"""Tests for the Git library backend (clone/pull/push/save_to_assets).

Uses a local bare git repo as the "remote" so no network is required. Skips
gracefully if ``git`` is not installed.
"""
from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))
from tests._course_fixture import copy_turkish_course  # noqa: E402

from src.backend.course_adapter import CourseAdapter  # noqa: E402
from src.backend.git_library import GitLibrary  # noqa: E402


def _git_available() -> bool:
    try:
        subprocess.run(["git", "--version"], capture_output=True, check=True)
    except (FileNotFoundError, subprocess.CalledProcessError):
        return False
    return True


@unittest.skipUnless(_git_available(), "git not installed")
class GitLibraryTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="varnamala_git_"))
        # Create a bare "remote".
        self.remote = self.tmp / "remote.git"
        subprocess.run(
            ["git", "init", "--bare", str(self.remote)],
            capture_output=True,
            check=True,
        )
        # Seed an initial commit in a working repo, then push to the remote.
        seed = self.tmp / "seed"
        copy_turkish_course(seed)
        # Remove any nested .git from the source (shouldn't be one, but be safe).
        nested = seed / ".git"
        if nested.exists():
            shutil.rmtree(nested, ignore_errors=True)
        self._commit_all(seed, "initial", remote=str(self.remote))
        self.lib = GitLibrary()
        self.clone_dir = self.tmp / "clone"

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _commit_all(self, repo: Path, msg: str, remote: str | None = None) -> None:
        env = {
            "GIT_AUTHOR_NAME": "t",
            "GIT_AUTHOR_EMAIL": "t@t",
            "GIT_COMMITTER_NAME": "t",
            "GIT_COMMITTER_EMAIL": "t@t",
        }
        import os

        full_env = {**os.environ, **env}
        subprocess.run(["git", "init"], cwd=str(repo), capture_output=True, check=True, env=full_env)
        subprocess.run(
            ["git", "branch", "-M", "main"], cwd=str(repo), capture_output=True, check=True, env=full_env
        )
        subprocess.run(["git", "add", "-A"], cwd=str(repo), capture_output=True, check=True, env=full_env)
        subprocess.run(
            ["git", "commit", "-m", msg], cwd=str(repo), capture_output=True, check=True, env=full_env
        )
        if remote:
            subprocess.run(
                ["git", "remote", "add", "origin", remote],
                cwd=str(repo),
                capture_output=True,
                check=True,
                env=full_env,
            )
            subprocess.run(
                ["git", "push", "-u", "origin", "main"],
                cwd=str(repo),
                capture_output=True,
                check=True,
                env=full_env,
            )
            # Point the bare remote's HEAD at main so a plain clone checks out
            # files (otherwise HEAD defaults to master and clone warns + checks
            # out nothing).
            subprocess.run(
                ["git", "--git-dir", remote, "symbolic-ref", "HEAD", "refs/heads/main"],
                capture_output=True,
                check=True,
            )

    def test_clone_pulls_existing(self) -> None:
        self.lib.clone(str(self.remote), self.clone_dir)
        self.assertTrue((self.clone_dir / ".git").is_dir())
        self.assertTrue((self.clone_dir / "index.json").is_file())
        # Cloning again into the same dir should pull (not fail).
        self.lib.clone(str(self.remote), self.clone_dir)

    def test_commit_and_push_roundtrip(self) -> None:
        self.lib.clone(str(self.remote), self.clone_dir)
        # Edit a file, push, then verify on a fresh clone.
        idx_path = self.clone_dir / "index.json"
        data = json.loads(idx_path.read_text(encoding="utf-8"))
        data["displayName"] = "Turkish (edited)"
        idx_path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
        self.lib.commit_and_push(self.clone_dir, "edit display name")

        fresh = self.tmp / "fresh"
        self.lib.clone(str(self.remote), fresh)
        fresh_data = json.loads((fresh / "index.json").read_text(encoding="utf-8"))
        self.assertEqual(fresh_data["displayName"], "Turkish (edited)")

    def test_status_reports_dirty(self) -> None:
        self.lib.clone(str(self.remote), self.clone_dir)
        st = self.lib.status(self.clone_dir)
        self.assertFalse(st.dirty)
        (self.clone_dir / "index.json").write_text("{}", encoding="utf-8")
        st = self.lib.status(self.clone_dir)
        self.assertTrue(st.dirty)

    def test_save_to_assets_copies_course(self) -> None:
        self.lib.clone(str(self.remote), self.clone_dir)
        assets_root = self.tmp / "assets" / "courses"
        target = self.lib.save_to_assets(self.clone_dir, "tr", repo_root=self.tmp)
        self.assertEqual(target, self.tmp / "assets" / "courses" / "tr")
        self.assertTrue((target / "index.json").is_file())
        # Should be a valid course dir.
        self.assertTrue(CourseAdapter.is_course_dir(target))

    def test_save_to_assets_refuses_overwrite(self) -> None:
        self.lib.clone(str(self.remote), self.clone_dir)
        # First copy succeeds.
        self.lib.save_to_assets(self.clone_dir, "tr", repo_root=self.tmp)
        # Second copy without overwrite flag should raise FileExistsError.
        with self.assertRaises(FileExistsError):
            self.lib.save_to_assets(self.clone_dir, "tr", repo_root=self.tmp)
        # With overwrite flag it merges.
        target = self.lib.save_to_assets(
            self.clone_dir, "tr", repo_root=self.tmp, overwrite=True
        )
        self.assertTrue((target / "index.json").is_file())

    def test_save_to_assets_rejects_non_course(self) -> None:
        bogus = self.tmp / "bogus"
        bogus.mkdir()
        with self.assertRaises(RuntimeError):
            self.lib.save_to_assets(bogus, "tr", repo_root=self.tmp)

    def test_get_history_handles_author_with_pipe(self) -> None:
        """An author name containing '|' must not misalign the history columns
        (the field separator is 0x1f, not '|')."""
        self.lib.clone(str(self.remote), self.clone_dir)
        # Make a commit whose author name contains a literal '|'.
        env_pipe = {
            "GIT_AUTHOR_NAME": "A|B Team",
            "GIT_AUTHOR_EMAIL": "ab@t",
            "GIT_COMMITTER_NAME": "A|B Team",
            "GIT_COMMITTER_EMAIL": "ab@t",
        }
        import os
        full_env = {**os.environ, **env_pipe}
        (self.clone_dir / "marker.txt").write_text("m", encoding="utf-8")
        subprocess.run(["git", "add", "-A"], cwd=str(self.clone_dir),
                       capture_output=True, check=True, env=full_env)
        subprocess.run(["git", "commit", "-m", "msg|with|pipes"],
                       cwd=str(self.clone_dir), capture_output=True,
                       check=True, env=full_env)
        history = self.lib.get_history(self.clone_dir, count=1)
        self.assertEqual(len(history), 1)
        self.assertEqual(history[0]["author"], "A|B Team")
        self.assertEqual(history[0]["message"], "msg|with|pipes")
        # date is a short YYYY-MM-DD form, not a fragment of the author.
        import datetime as _dt
        self.assertRegex(history[0]["date"], r"^\d{4}-\d{2}-\d{2}$")

    def test_lan_collaboration_server(self) -> None:
        # Clone repo to create a working repo
        self.lib.clone(str(self.remote), self.clone_dir)

        # Start server thread
        from src.backend.git_library import GitServerThread
        import socket
        sock = socket.socket()
        sock.bind(('127.0.0.1', 0))
        port = sock.getsockname()[1]
        sock.close()

        self.lib.enable_lan_write(self.clone_dir)

        thread = GitServerThread(self.clone_dir, host="127.0.0.1", port=port)
        thread.start()
        try:
            server_url = f"http://127.0.0.1:{port}/"
            client_dir = self.tmp / "client_clone"
            self.lib.clone(server_url, client_dir)
            self.assertTrue((client_dir / "index.json").is_file())

            # Edit a file in client, commit and push to server
            idx_path = client_dir / "index.json"
            data = json.loads(idx_path.read_text(encoding="utf-8"))
            data["displayName"] = "Turkish (edited via LAN)"
            idx_path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")

            self.lib.commit_and_push(client_dir, "lan push")

            # Verify server repo got updated
            server_data = json.loads((self.clone_dir / "index.json").read_text(encoding="utf-8"))
            self.assertEqual(server_data["displayName"], "Turkish (edited via LAN)")

            # Test get_history
            history = self.lib.get_history(client_dir, count=2)
            self.assertEqual(len(history), 2)
            self.assertEqual(history[0]["message"], "lan push")

            # Test server log queue
            logs = list(thread.server.log_queue)
            self.assertTrue(any("GET" in log or "info/refs" in log for log in logs))
            self.assertTrue(any("POST" in log or "git-receive-pack" in log for log in logs))
            self.assertTrue(any("✅" in log or "成功" in log for log in logs))

        finally:
            thread.stop()
            thread.join(timeout=2.0)

    def test_list_branches_and_current(self) -> None:
        self.lib.clone(str(self.remote), self.clone_dir)
        branches = self.lib.list_branches(self.clone_dir)
        self.assertIn("main", branches)
        self.assertEqual(self.lib.current_branch(self.clone_dir), "main")

    def test_create_and_switch_branch(self) -> None:
        self.lib.clone(str(self.remote), self.clone_dir)
        self.lib.create_branch(self.clone_dir, "feature")
        self.assertEqual(self.lib.current_branch(self.clone_dir), "feature")
        self.assertIn("feature", self.lib.list_branches(self.clone_dir))
        self.lib.switch_branch(self.clone_dir, "main")
        self.assertEqual(self.lib.current_branch(self.clone_dir), "main")

    def test_delete_branch(self) -> None:
        self.lib.clone(str(self.remote), self.clone_dir)
        self.lib.create_branch(self.clone_dir, "temp")
        self.lib.switch_branch(self.clone_dir, "main")
        self.lib.delete_branch(self.clone_dir, "temp")
        self.assertNotIn("temp", self.lib.list_branches(self.clone_dir))

    def test_list_remotes_all(self) -> None:
        self.lib.clone(str(self.remote), self.clone_dir)
        remotes = self.lib.list_remotes_all(self.clone_dir)
        self.assertTrue(any(r["name"] == "origin" for r in remotes))

    def test_add_and_remove_remote(self) -> None:
        self.lib.clone(str(self.remote), self.clone_dir)
        self.lib.add_remote(self.clone_dir, "upstream", str(self.remote))
        remotes = self.lib.list_remotes_all(self.clone_dir)
        self.assertTrue(any(r["name"] == "upstream" for r in remotes))
        self.lib.remove_remote(self.clone_dir, "upstream")
        remotes = self.lib.list_remotes_all(self.clone_dir)
        self.assertFalse(any(r["name"] == "upstream" for r in remotes))

    def test_diff_working_vs_head(self) -> None:
        self.lib.clone(str(self.remote), self.clone_dir)
        # No changes -> empty diff.
        self.assertEqual(self.lib.diff_working_vs_head(self.clone_dir).strip(), "")
        # Make a change.
        (self.clone_dir / "index.json").write_text("{}", encoding="utf-8")
        diff = self.lib.diff_working_vs_head(self.clone_dir)
        self.assertIn("index.json", diff)

    def test_list_files(self) -> None:
        self.lib.clone(str(self.remote), self.clone_dir)
        files = self.lib.list_files(self.clone_dir)
        self.assertIn("index.json", files)

    def test_read_file_at_ref(self) -> None:
        self.lib.clone(str(self.remote), self.clone_dir)
        content = self.lib.read_file_at_ref(self.clone_dir, "HEAD", "index.json")
        data = json.loads(content)
        self.assertIn("language", data)

    def test_log_since(self) -> None:
        self.lib.clone(str(self.remote), self.clone_dir)
        logs = self.lib.log_since(self.clone_dir, ref="-n 5")
        # Should return at least 1 commit.
        self.assertGreaterEqual(len(logs), 1)

    def test_has_conflicts_false_on_clean(self) -> None:
        self.lib.clone(str(self.remote), self.clone_dir)
        self.assertFalse(self.lib.has_conflicts(self.clone_dir))

    def test_stash_and_pop(self) -> None:
        self.lib.clone(str(self.remote), self.clone_dir)
        (self.clone_dir / "new.txt").write_text("stash me", encoding="utf-8")
        self.lib.stash(self.clone_dir)
        self.assertFalse((self.clone_dir / "new.txt").exists())
        self.lib.stash_pop(self.clone_dir)
        self.assertTrue((self.clone_dir / "new.txt").exists())

    def test_git_library_accepts_config(self) -> None:
        lib = GitLibrary(git_bin="git", timeout=30.0, token="", ssh_key_path="")
        self.assertEqual(lib._git, "git")
        self.assertEqual(lib._timeout, 30.0)

    def test_lan_server_with_token_auth(self) -> None:
        """Token-protected LAN server rejects requests without auth."""
        self.lib.clone(str(self.remote), self.clone_dir)
        from src.backend.git_library import GitServerThread
        import socket
        import urllib.request

        sock = socket.socket()
        sock.bind(('127.0.0.1', 0))
        port = sock.getsockname()[1]
        sock.close()

        self.lib.enable_lan_write(self.clone_dir)
        thread = GitServerThread(
            self.clone_dir, host="127.0.0.1", port=port,
            auth_token="secret-token",
        )
        thread.start()
        try:
            # Request without token -> 401.
            try:
                urllib.request.urlopen(
                    f"http://127.0.0.1:{port}/info/refs?service=git-upload-pack"
                )
                auth_failed = False
            except urllib.error.HTTPError as e:
                auth_failed = e.code == 401
            self.assertTrue(auth_failed)
        finally:
            thread.stop()
            thread.join(timeout=2.0)

    def test_lan_server_read_only_rejects_push(self) -> None:
        """Read-only LAN server rejects git-receive-pack (push)."""
        self.lib.clone(str(self.remote), self.clone_dir)
        from src.backend.git_library import GitServerThread
        import socket
        import urllib.request

        sock = socket.socket()
        sock.bind(('127.0.0.1', 0))
        port = sock.getsockname()[1]
        sock.close()

        thread = GitServerThread(
            self.clone_dir, host="127.0.0.1", port=port,
            read_only=True,
        )
        thread.start()
        try:
            # Attempt receive-pack info/refs -> 403.
            try:
                urllib.request.urlopen(
                    f"http://127.0.0.1:{port}/info/refs?service=git-receive-pack"
                )
                rejected = False
            except urllib.error.HTTPError as e:
                rejected = e.code == 403
            self.assertTrue(rejected)
        finally:
            thread.stop()
            thread.join(timeout=2.0)

    def test_lan_server_ip_allow_list(self) -> None:
        """IP allow-list blocks disallowed clients."""
        self.lib.clone(str(self.remote), self.clone_dir)
        from src.backend.git_library import GitServerThread
        import socket
        import urllib.request

        sock = socket.socket()
        sock.bind(('127.0.0.1', 0))
        port = sock.getsockname()[1]
        sock.close()

        # Allow only 1.2.3.4 (not 127.0.0.1).
        thread = GitServerThread(
            self.clone_dir, host="127.0.0.1", port=port,
            allow_ips=["1.2.3.4"],
        )
        thread.start()
        try:
            try:
                urllib.request.urlopen(
                    f"http://127.0.0.1:{port}/info/refs?service=git-upload-pack"
                )
                blocked = False
            except urllib.error.HTTPError as e:
                blocked = e.code == 403
            self.assertTrue(blocked)
        finally:
            thread.stop()
            thread.join(timeout=2.0)


class HttpsTokenScopeTest(unittest.TestCase):
    """Unit tests for the URL-scoped git token auth (B13).

    These don't shell out to git; they just check the extra-args builder.
    """

    def test_no_token_yields_no_args(self) -> None:
        lib = GitLibrary()
        self.assertEqual(lib._extra_args_for_https("https://example.com/x.git"), [])

    def test_https_url_is_url_scoped(self) -> None:
        lib = GitLibrary(token="tkn")
        args = lib._extra_args_for_https("https://example.com/x.git")
        self.assertEqual(len(args), 2)
        self.assertTrue(args[1].startswith("http.https://example.com/.extraheader="))
        self.assertIn("Bearer tkn", args[1])

    def test_cleartext_http_url_gets_no_token(self) -> None:
        lib = GitLibrary(token="tkn")
        self.assertEqual(lib._extra_args_for_https("http://example.com/x.git"), [])

    def test_ssh_url_gets_no_token(self) -> None:
        lib = GitLibrary(token="tkn")
        self.assertEqual(lib._extra_args_for_https("git@example.com:x.git"), [])

    def test_scope_is_host_specific_not_global(self) -> None:
        lib = GitLibrary(token="tkn")
        args = lib._extra_args_for_https("https://good.example.com/x.git")
        # Must NOT be the unscaled http.extraheader form (which would leak to
        # redirect/submodule hosts).
        self.assertNotEqual(args[1].split("=", 1)[0], "http.extraheader")
        self.assertIn("good.example.com", args[1])

    def test_malformed_url_yields_no_args(self) -> None:
        lib = GitLibrary(token="tkn")
        self.assertEqual(lib._extra_args_for_https("not-a-url"), [])


if __name__ == "__main__":
    unittest.main()