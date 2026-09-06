"""External Git course library backend.

Connects to a remote git repository that stores Turna course directories,
lets the editor clone/pull/push them, and can copy a cloned course into the
app's bundled ``assets/courses/<lang>/`` directory so it ships with the Flutter
app.

Pure Python — shells out to the system ``git`` via ``subprocess`` (no new
dependency). All network operations are explicit (never automatic) and raise
``RuntimeError`` with the git stderr on failure.
"""
from __future__ import annotations

import collections
import os
from datetime import datetime
import http.server
import re
import shutil
import subprocess
import threading
import urllib.parse
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from src.backend.course_adapter import CourseAdapter, _REPO_ROOT

_DEFAULT_TIMEOUT = 60.0
# Bound for the per-request git RPC subprocess (info/refs + upload/receive-pack).
# A hung git process must not pin a handler thread forever.
_GIT_RPC_TIMEOUT = 120.0


class GitHTTPRequestHandler(http.server.BaseHTTPRequestHandler):
    """Minimal Git Smart HTTP protocol handler with diagnostic logging.

    Security config (auth_token, read_only, allow_ips) is read from the
    ``GitHTTPServer`` instance so each server can have independent settings.
    """

    def log_message(self, format: str, *args: Any) -> None:
        # Suppress writing standard HTTP server logs to stderr,
        # but parse it and add it to our server's queue.
        client_ip = self.client_address[0]
        msg = format % args
        now = datetime.now().strftime("%H:%M:%S")
        self.server.log_queue.append(f"[{now}] {client_ip} - {msg}")

    def _client_allowed(self) -> bool:
        allow_ips = getattr(self.server, "allow_ips", [])
        if allow_ips and self.client_address[0] not in allow_ips:
            return False
        return True

    def _auth_ok(self) -> bool:
        auth_token = getattr(self.server, "auth_token", "")
        if not auth_token:
            return True
        header = self.headers.get("Authorization", "")
        if header.startswith("Bearer "):
            return header[len("Bearer "):].strip() == auth_token
        return False

    def _is_read_only(self) -> bool:
        return getattr(self.server, "read_only", False)

    def _reject(self, code: int, message: str) -> None:
        self.send_error(code, message)
        self.server.log_queue.append(
            f"[{datetime.now():%H:%M:%S}] {self.client_address[0]} - ❌ {message}"
        )

    def _record_peer(self) -> None:
        """Track the client IP as a connected peer (for presence list)."""
        ip = self.client_address[0]
        peers = getattr(self.server, "connected_peers", None)
        if peers is not None:
            peers[ip] = datetime.now().timestamp()

    def _read_body(self) -> bytes:
        """Read the POST body, decoding chunked transfer-encoding when used.

        git-receive-pack / git-upload-pack POSTs are commonly streamed with
        ``Transfer-Encoding: chunked`` (no ``Content-Length``); reading by
        ``Content-Length`` alone yields an empty body and a failed push.
        """
        if self.headers.get("Transfer-Encoding", "").lower() == "chunked":
            chunks: list[bytes] = []
            # Guard against infinite loops on malformed input (e.g. a closed
            # socket where readline() returns b"" forever, or a peer that
            # spuriously interleaves empty lines). Cap consecutive empties
            # and total iterations. (B7)
            empty_streak = 0
            max_empty_streak = 8
            total_iterations = 0
            max_iterations = 1_000_000
            while True:
                total_iterations += 1
                if total_iterations > max_iterations:
                    break
                size_line = self.rfile.readline().strip()
                if not size_line:
                    empty_streak += 1
                    if empty_streak > max_empty_streak:
                        break
                    continue
                empty_streak = 0
                try:
                    size = int(size_line, 16)
                except ValueError:
                    break
                if size == 0:
                    # Trailing CRLF after the terminating 0-size chunk.
                    self.rfile.readline()
                    break
                chunks.append(self.rfile.read(size))
                self.rfile.readline()  # consume CRLF after each chunk
            return b"".join(chunks)
        length = int(self.headers.get("Content-Length", 0))
        return self.rfile.read(length)

    def do_GET(self) -> None:
        if not self._client_allowed():
            self._reject(403, "IP not allowed")
            return
        if not self._auth_ok():
            self._reject(401, "Unauthorized")
            return
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        if path.endswith("/info/refs"):
            query = urllib.parse.parse_qs(parsed.query)
            service = query.get("service", [None])[0]
            if service in ["git-upload-pack", "git-receive-pack"]:
                if service == "git-receive-pack" and self._is_read_only():
                    self._reject(403, "Read-only server: push not allowed")
                    return
                self._record_peer()
                # Write service header packet line
                service_line = f"# service={service}\n"
                l = len(service_line) + 4
                header = f"{l:04x}{service_line}0000".encode("utf-8")

                # Run git command
                git_cmd = service.replace("git-", "")
                cmd = ["git", git_cmd, "--stateless-rpc", "--advertise-refs", "."]
                try:
                    proc = subprocess.run(
                        cmd,
                        cwd=str(self.server.repo_path),
                        capture_output=True,
                        check=False,
                        timeout=_GIT_RPC_TIMEOUT,
                    )
                except subprocess.TimeoutExpired:
                    self.server.log_queue.append(
                        f"[{datetime.now():%H:%M:%S}] {self.client_address[0]} - "
                        f"⏱ GET {service} 超时"
                    )
                    self.send_error(504, "git timeout")
                    return

                content = header + proc.stdout

                self.send_response(200)
                self.send_header("Content-Type", f"application/x-{service}-advertisement")
                self.send_header("Cache-Control", "no-cache, max-age=0, must-revalidate")
                self.send_header("Pragma", "no-cache")
                self.send_header("Content-Length", str(len(content)))
                self.send_header("Connection", "close")
                self.end_headers()

                self.wfile.write(content)

                # Diagnostic logging
                now = datetime.now().strftime("%H:%M:%S")
                client_ip = self.client_address[0]
                if proc.returncode != 0:
                    err_msg = (proc.stderr or b"").decode("utf-8", errors="replace").strip()
                    self.server.log_queue.append(f"[{now}] {client_ip} - ❌ GET {service} 失败 (代码 {proc.returncode}): {err_msg[:200]}")
                else:
                    self.server.log_queue.append(f"[{now}] {client_ip} - ✅ GET {service} 成功")
                return

        self.send_error(404, "Not Found")

    def do_POST(self) -> None:
        if not self._client_allowed():
            self._reject(403, "IP not allowed")
            return
        if not self._auth_ok():
            self._reject(401, "Unauthorized")
            return
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        service = path.split("/")[-1]
        if service == "git-receive-pack" and self._is_read_only():
            self._reject(403, "Read-only server: push not allowed")
            return
        if service in ["git-upload-pack", "git-receive-pack"]:
            self._record_peer()
            post_data = self._read_body()

            git_cmd = service.replace("git-", "")
            cmd = ["git", git_cmd, "--stateless-rpc", "."]
            try:
                proc = subprocess.run(
                    cmd,
                    cwd=str(self.server.repo_path),
                    input=post_data,
                    capture_output=True,
                    check=False,
                    timeout=_GIT_RPC_TIMEOUT,
                )
            except subprocess.TimeoutExpired:
                self.server.log_queue.append(
                    f"[{datetime.now():%H:%M:%S}] {self.client_address[0]} - "
                    f"⏱ POST {service} 超时"
                )
                self.send_error(504, "git timeout")
                return

            content = proc.stdout

            self.send_response(200)
            self.send_header("Content-Type", f"application/x-{service}-result")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Content-Length", str(len(content)))
            self.send_header("Connection", "close")
            self.end_headers()

            self.wfile.write(content)

            # Diagnostic logging
            now = datetime.now().strftime("%H:%M:%S")
            client_ip = self.client_address[0]
            if proc.returncode != 0:
                err_msg = (proc.stderr or b"").decode("utf-8", errors="replace").strip()
                self.server.log_queue.append(f"[{now}] {client_ip} - ❌ POST {service} 失败 (代码 {proc.returncode}): {err_msg[:200]}")
            else:
                self.server.log_queue.append(f"[{now}] {client_ip} - ✅ POST {service} 成功")
            return

        self.send_error(404, "Not Found")


class GitHTTPServer(http.server.ThreadingHTTPServer):
    """Threaded HTTP server that tracks the repository path it serves and
    maintains a log queue.

    ThreadingHTTPServer handles each request on its own thread so a slow
    git-receive-pack push cannot block a concurrent info/refs (clone) request.
    """
    def __init__(
        self,
        server_address: tuple[str, int],
        RequestHandlerClass,
        repo_path: Path,
        auth_token: str = "",
        read_only: bool = False,
        allow_ips: list[str] | None = None,
    ) -> None:
        self.repo_path = repo_path
        self.log_queue = collections.deque(maxlen=100)
        self.auth_token = auth_token
        self.read_only = read_only
        self.allow_ips = allow_ips or []
        self.connected_peers: dict[str, float] = {}  # ip -> last-seen timestamp
        super().__init__(server_address, RequestHandlerClass)


class GitServerThread(threading.Thread):
    """Thread for running the Git HTTP server in the background."""

    def __init__(
        self,
        repo_path: Path,
        host: str = "0.0.0.0",
        port: int = 5000,
        auth_token: str = "",
        read_only: bool = False,
        allow_ips: list[str] | None = None,
    ) -> None:
        super().__init__()
        self.repo_path = repo_path
        self.host = host
        self.port = port
        self.auth_token = auth_token
        self.read_only = read_only
        self.allow_ips = allow_ips or []
        # Bind the server synchronously so we know if it succeeded
        self.server = GitHTTPServer(
            (self.host, self.port),
            GitHTTPRequestHandler,
            self.repo_path,
            auth_token=self.auth_token,
            read_only=self.read_only,
            allow_ips=self.allow_ips,
        )
        self.daemon = True

    def run(self) -> None:
        if self.server:
            self.server.serve_forever()

    def stop(self) -> None:
        if self.server:
            self.server.shutdown()
            self.server.server_close()


@dataclass
class GitStatus:
    """Summary of a local clone's relation to its remote + working tree."""

    dirty: bool  # uncommitted changes in the working tree
    ahead: int  # commits not yet pushed
    behind: int  # commits on the remote not yet pulled
    branch: str  # current branch name (empty if detached)


class GitLibrary:
    """Thin wrapper over the system ``git`` CLI for course repositories."""

    def __init__(
        self,
        git_bin: str = "git",
        timeout: float = _DEFAULT_TIMEOUT,
        token: str = "",
        ssh_key_path: str = "",
    ) -> None:
        self._git = git_bin or "git"
        self._timeout = timeout
        self._token = token
        self._ssh_key_path = ssh_key_path

    def _env_for(self, cwd: Path) -> dict[str, str]:
        """Build the environment for a git subprocess, injecting auth if set."""
        env = dict(os.environ)
        # Prevent git from blocking on interactive credentials in background/test execution
        env["GIT_TERMINAL_PROMPT"] = "0"
        # SSH key override
        if self._ssh_key_path:
            key = os.path.expanduser(self._ssh_key_path)
            env["GIT_SSH_COMMAND"] = (
                f"ssh -i {key} -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
            )
        elif "GIT_SSH_COMMAND" not in env:
            env["GIT_SSH_COMMAND"] = "ssh -o BatchMode=yes"
        return env

    def _extra_args_for_https(self, url: str | None = None) -> list[str]:
        """Return URL-scoped -c http.<base>.extraheader args for HTTPS token auth.

        Previously this injected a global ``http.extraheader`` that applied
        to every HTTP request git made — including submodules, LFS, and
        redirect targets — so a malicious repo could redirect
        ``git-upload-pack`` to a third-party host and capture the bearer
        token. It also fired for plain ``http://`` (non-TLS) URLs, leaking
        the token in cleartext. (B13)

        Now the header is URL-scoped to the *base* of the requested remote
        (``http.<scheme>://<host>/.extraheader``), and only emitted for
        ``https://`` URLs. SSH (``git@``) and non-HTTPS URLs are left alone.
        """
        if not self._token:
            return []
        if not url:
            return []
        if url.startswith("git@"):
            return []  # SSH URL, token doesn't apply
        if not url.startswith("https://"):
            return []  # Don't leak token over cleartext http:// or unknown schemes
        # Derive the http.<base>.extraheader scope. Git matches the longest
        # prefix, so the scheme://host/ form covers all paths under that host
        # without matching other hosts. Strip a trailing slash to match git's
        # own config-key normalization.
        from urllib.parse import urlparse

        parsed = urlparse(url)
        if not parsed.scheme or not parsed.netloc:
            return []
        base = f"{parsed.scheme}://{parsed.netloc}/"
        return ["-c", f"http.{base}.extraheader=Authorization: Bearer {self._token}"]

    # --- low-level helper ------------------------------------------------

    def _run(
        self,
        args: list[str],
        cwd: Path,
        timeout: float | None = None,
        check: bool = True,
        url: str | None = None,
    ) -> subprocess.CompletedProcess[str]:
        cmd = [self._git]
        cmd.extend(self._extra_args_for_https(url))
        cmd.extend(args)
        env = self._env_for(cwd)
        effective_timeout = timeout if timeout is not None else self._timeout
        try:
            proc = subprocess.run(  # noqa: S603 - git path is fixed/configurable
                cmd,
                cwd=str(cwd),
                capture_output=True,
                text=True,
                timeout=effective_timeout,
                check=False,
                env=env,
            )
        except FileNotFoundError as exc:
            raise RuntimeError(f"找不到 git 可执行文件：{self._git}") from exc
        except subprocess.TimeoutExpired as exc:
            raise RuntimeError(f"git 命令超时：{' '.join(args)}") from exc
        if check and proc.returncode != 0:
            detail = (proc.stderr or proc.stdout or "").strip()[:500]
            raise RuntimeError(f"git {' '.join(args)} 失败：{detail}")
        return proc

    # --- public API ------------------------------------------------------

    def clone(self, remote_url: str, local_dir: Path) -> Path:
        """Clone ``remote_url`` into ``local_dir``.

        If ``local_dir`` already exists and is a git repo, pull instead.
        Returns the local directory path.
        """
        local_dir = Path(local_dir)
        if (local_dir / ".git").is_dir():
            self._run(["pull", "--ff-only"], cwd=local_dir, url=remote_url)
            return local_dir
        local_dir.mkdir(parents=True, exist_ok=True)
        # "--" keeps a pasted URL starting with "-" from being read as an option.
        self._run(["clone", "--", remote_url, str(local_dir)], cwd=local_dir.parent, url=remote_url)
        return local_dir

    def pull(self, local_dir: Path) -> None:
        """Fast-forward pull from the tracked remote."""
        self._run(["pull", "--ff-only"], cwd=Path(local_dir))

    def commit_and_push(self, local_dir: Path, message: str) -> None:
        """Stage all changes, commit, and push to the tracked remote."""
        local_dir = Path(local_dir)
        self._run(["add", "-A"], cwd=local_dir)
        # Commit only if there is something to commit.
        status = self._run(["status", "--porcelain"], cwd=local_dir, check=False)
        if status.stdout.strip():
            self._run(["commit", "-m", message], cwd=local_dir)
        self._run(["push"], cwd=local_dir)

    def commit_and_push_file(self, local_dir: Path, filename: str, message: str) -> None:
        """Stage only a single file, commit, and push to remote."""
        local_dir = Path(local_dir)
        self._run(["add", filename], cwd=local_dir)
        status = self._run(["status", "--porcelain", filename], cwd=local_dir, check=False)
        if status.stdout.strip():
            self._run(["commit", "-m", message], cwd=local_dir)
        self._run(["push"], cwd=local_dir)

    def status(self, local_dir: Path) -> GitStatus:
        """Return a compact status summary for the clone."""
        local_dir = Path(local_dir)
        branch_proc = self._run(
            ["rev-parse", "--abbrev-ref", "HEAD"], cwd=local_dir, check=False
        )
        branch = branch_proc.stdout.strip()
        if branch == "HEAD":  # detached
            branch = ""

        dirty_proc = self._run(
            ["status", "--porcelain"], cwd=local_dir, check=False
        )
        dirty = bool(dirty_proc.stdout.strip())

        ahead = behind = 0
        up_proc = self._run(
            ["rev-parse", "--abbrev-ref", "@{upstream}"],
            cwd=local_dir,
            check=False,
        )
        if up_proc.returncode == 0:
            upstream = up_proc.stdout.strip()
            counts = self._run(
                ["rev-list", "--left-right", "--count", f"{upstream}...HEAD"],
                cwd=local_dir,
                check=False,
            )
            if counts.returncode == 0:
                parts = counts.stdout.split()
                if len(parts) == 2:
                    behind = int(parts[0]) if parts[0].isdigit() else 0
                    ahead = int(parts[1]) if parts[1].isdigit() else 0
        return GitStatus(dirty=dirty, ahead=ahead, behind=behind, branch=branch)

    def fetch(self, local_dir: Path) -> None:
        """Fetch updates from the tracked remote."""
        self._run(["fetch"], cwd=Path(local_dir))

    def pull_rebase(self, local_dir: Path) -> None:
        """Fetch + rebase local commits on top of the tracked remote.

        Used before pushing a collaboration memo so a teammate's earlier push
        does not cause a non-fast-forward rejection.
        """
        self._run(["pull", "--rebase"], cwd=Path(local_dir))

    def enable_lan_write(self, local_dir: Path) -> None:
        """Configure the repository to allow pushing to the currently checked out branch."""
        self._run(["config", "receive.denyCurrentBranch", "updateInstead"], cwd=Path(local_dir))

    # --- branch & remote management -------------------------------------

    def list_branches(self, local_dir: Path) -> list[str]:
        """Return local branch names (without remote prefixes)."""
        proc = self._run(["branch", "--format=%(refname:short)"], cwd=Path(local_dir), check=False)
        return [line.strip() for line in proc.stdout.splitlines() if line.strip()]

    def current_branch(self, local_dir: Path) -> str:
        """Return the current branch name (empty if detached HEAD)."""
        proc = self._run(["rev-parse", "--abbrev-ref", "HEAD"], cwd=Path(local_dir), check=False)
        branch = proc.stdout.strip()
        return "" if branch == "HEAD" else branch

    def create_branch(self, local_dir: Path, name: str) -> None:
        """Create and checkout a new branch."""
        self._run(["checkout", "-b", name], cwd=Path(local_dir))

    def switch_branch(self, local_dir: Path, name: str) -> None:
        """Checkout an existing branch."""
        self._run(["checkout", name], cwd=Path(local_dir))

    def delete_branch(self, local_dir: Path, name: str) -> None:
        """Delete a local branch (-d, safe)."""
        self._run(["branch", "-d", name], cwd=Path(local_dir))

    def list_remotes_all(self, local_dir: Path) -> list[dict[str, str]]:
        """Return [{name, url, type}] for all configured remotes."""
        local_dir = Path(local_dir)
        proc = self._run(["remote", "-v"], cwd=local_dir, check=False)
        remotes: list[dict[str, str]] = []
        for line in proc.stdout.splitlines():
            parts = line.split()
            if len(parts) >= 3:
                remotes.append({"name": parts[0], "url": parts[1], "type": parts[2]})
        return remotes

    def add_remote(self, local_dir: Path, name: str, url: str) -> None:
        """Add a new named remote."""
        self._run(["remote", "add", name, url], cwd=Path(local_dir))

    def remove_remote(self, local_dir: Path, name: str) -> None:
        """Remove a named remote."""
        self._run(["remote", "remove", name], cwd=Path(local_dir))

    def push_to(self, local_dir: Path, remote: str, branch: str) -> None:
        """Push to a specific remote and branch."""
        self._run(["push", remote, branch], cwd=Path(local_dir))

    def pull_from(self, local_dir: Path, remote: str, branch: str) -> None:
        """Pull from a specific remote and branch (ff-only)."""
        self._run(["pull", "--ff-only", remote, branch], cwd=Path(local_dir))

    # --- conflict resolution & history manipulation ---------------------

    def merge(self, local_dir: Path, ref: str) -> str:
        """Merge ``ref`` into the current branch. Return merge output or conflict info."""
        proc = self._run(["merge", ref], cwd=Path(local_dir), check=False)
        return proc.stdout + proc.stderr

    def merge_abort(self, local_dir: Path) -> None:
        """Abort an in-progress merge."""
        self._run(["merge", "--abort"], cwd=Path(local_dir))

    def stash(self, local_dir: Path) -> None:
        """Stash working tree changes."""
        self._run(["stash", "push", "-u"], cwd=Path(local_dir))

    def stash_pop(self, local_dir: Path) -> None:
        """Pop the most recent stash."""
        self._run(["stash", "pop"], cwd=Path(local_dir))

    def reset_to(self, local_dir: Path, ref: str, mode: str = "hard") -> None:
        """Reset HEAD to ``ref``. ``mode`` is 'hard' | 'soft' | 'mixed'."""
        if mode not in ("hard", "soft", "mixed"):
            raise ValueError(f"invalid reset mode: {mode}")
        self._run(["reset", f"--{mode}", ref], cwd=Path(local_dir))

    def revert(self, local_dir: Path, ref: str) -> None:
        """Revert the commit at ``ref`` (creates a new commit)."""
        self._run(["revert", "--no-edit", ref], cwd=Path(local_dir))

    def has_conflicts(self, local_dir: Path) -> bool:
        """Return True if the working tree has unresolved merge conflicts."""
        proc = self._run(["diff", "--name-only", "--diff-filter=U"], cwd=Path(local_dir), check=False)
        return bool(proc.stdout.strip())

    # --- diff & file browsing -------------------------------------------

    def diff_working_vs_head(self, local_dir: Path, stat: bool = False) -> str:
        """Return the diff of the working tree against HEAD."""
        args = ["diff", "HEAD"]
        if stat:
            args.append("--stat")
        proc = self._run(args, cwd=Path(local_dir), check=False)
        return proc.stdout

    def diff_commits(self, local_dir: Path, ref_a: str, ref_b: str, stat: bool = False) -> str:
        """Return the diff between two refs."""
        args = ["diff", f"{ref_a}..{ref_b}"]
        if stat:
            args.append("--stat")
        proc = self._run(args, cwd=Path(local_dir), check=False)
        return proc.stdout

    def list_files(self, local_dir: Path, ref: str = "HEAD") -> list[str]:
        """List all tracked files at ``ref`` (default HEAD)."""
        proc = self._run(["ls-tree", "-r", "--name-only", ref], cwd=Path(local_dir), check=False)
        return [line.strip() for line in proc.stdout.splitlines() if line.strip()]

    def read_file_at_ref(self, local_dir: Path, ref: str, file_path: str) -> str:
        """Return the content of ``file_path`` at ``ref``."""
        proc = self._run(["show", f"{ref}:{file_path}"], cwd=Path(local_dir), check=False)
        return proc.stdout

    def log_since(self, local_dir: Path, ref: str = "@{1}") -> list[dict[str, str]]:
        """Return commits since ``ref`` (default last pulled position)."""
        local_dir = Path(local_dir)
        sep = "\x1f"
        cmd = ["log", f"--pretty=format:%h%x1f%an%x1f%ad%x1f%s", "--date=short"]
        # @{1} may fail if no upstream; fall back to last 10.
        proc = self._run(cmd + [ref], cwd=local_dir, check=False)
        if proc.returncode != 0:
            proc = self._run(cmd + ["-n", "10"], cwd=local_dir, check=False)
        commits = []
        if proc.stdout.strip():
            for line in proc.stdout.strip().split("\n"):
                parts = line.split(sep, 3)
                if len(parts) == 4:
                    commits.append({
                        "hash": parts[0],
                        "author": parts[1],
                        "date": parts[2],
                        "message": parts[3],
                    })
        return commits

    def get_history(self, local_dir: Path, count: int = 5) -> list[dict[str, str]]:
        """Get the recent commit history as a list of dicts."""
        local_dir = Path(local_dir)
        # Unit-separator (0x1f) — %an / %s can contain '|', which would misalign
        # the columns when split on '|'. 0x1f cannot appear in these fields and
        # is safe to pass to subprocess (unlike %x00, which embeds a NUL byte
        # in the argument list and is rejected by Popen).
        sep = "\x1f"
        cmd = ["log", f"--pretty=format:%h%x1f%an%x1f%ad%x1f%s", "--date=short", "-n", str(count)]
        proc = self._run(cmd, cwd=local_dir, check=False)
        commits = []
        if proc.returncode == 0 and proc.stdout.strip():
            for line in proc.stdout.strip().split("\n"):
                parts = line.split(sep, 3)
                if len(parts) == 4:
                    commits.append({
                        "hash": parts[0],
                        "author": parts[1],
                        "date": parts[2],
                        "message": parts[3],
                    })
        return commits

    @staticmethod
    def save_to_assets(
        course_dir: Path,
        lang_code: str,
        repo_root: Path = _REPO_ROOT,
        overwrite: bool = False,
    ) -> Path:
        """Copy a course directory into ``<repo_root>/assets/courses/<lang_code>``.

        The source must look like a course directory (contain ``index.json``).
        If the target already exists and ``overwrite`` is False, raises
        ``FileExistsError`` listing the file count that would be overwritten.
        Returns the target directory path.
        """
        course_dir = Path(course_dir)
        if not CourseAdapter.is_course_dir(course_dir):
            raise RuntimeError(f"源目录不是有效课程仓库：{course_dir}")
        if not lang_code:
            raise RuntimeError("缺少语言代码，无法确定 assets 目标目录。")
        if re.fullmatch(r"[A-Za-z0-9_-]+", lang_code) is None:
            raise RuntimeError(f"非法语言代码：{lang_code!r}（只允许字母、数字、-、_）")

        target = Path(repo_root) / "assets" / "courses" / lang_code
        if target.exists() and any(target.iterdir()):
            if not overwrite:
                file_count = sum(1 for _ in target.rglob("*") if _.is_file())
                raise FileExistsError(
                    f"目标目录已存在且非空：{target}（{file_count} 个文件）。"
                    "请显式确认覆盖后再复制。"
                )
            # dirs_exist_ok=True merges/overwrites per-file below.
        target.mkdir(parents=True, exist_ok=True)

        def _ignore_git(directory: str, names: list[str]) -> list[str]:
            # Never copy the clone's .git metadata into the bundled assets.
            ignored: list[str] = []
            if Path(directory) == course_dir and ".git" in names:
                ignored.append(".git")
            return ignored

        shutil.copytree(course_dir, target, dirs_exist_ok=True, ignore=_ignore_git)
        return target