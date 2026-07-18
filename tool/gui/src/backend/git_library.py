"""External Git course library backend.

Connects to a remote git repository that stores Varnamala course directories,
lets the editor clone/pull/push them, and can copy a cloned course into the
app's bundled ``assets/courses/<lang>/`` directory so it ships with the Flutter
app.

Pure Python — shells out to the system ``git`` via ``subprocess`` (no new
dependency). All network operations are explicit (never automatic) and raise
``RuntimeError`` with the git stderr on failure.
"""
from __future__ import annotations

import re
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path

from src.backend.course_adapter import CourseAdapter, _REPO_ROOT

_DEFAULT_TIMEOUT = 60.0


@dataclass
class GitStatus:
    """Summary of a local clone's relation to its remote + working tree."""

    dirty: bool  # uncommitted changes in the working tree
    ahead: int  # commits not yet pushed
    behind: int  # commits on the remote not yet pulled
    branch: str  # current branch name (empty if detached)


class GitLibrary:
    """Thin wrapper over the system ``git`` CLI for course repositories."""

    def __init__(self, git_bin: str = "git") -> None:
        self._git = git_bin

    # --- low-level helper ------------------------------------------------

    def _run(
        self,
        args: list[str],
        cwd: Path,
        timeout: float = _DEFAULT_TIMEOUT,
        check: bool = True,
    ) -> subprocess.CompletedProcess[str]:
        cmd = [self._git, *args]
        try:
            proc = subprocess.run(  # noqa: S603 — git path is fixed/configurable
                cmd,
                cwd=str(cwd),
                capture_output=True,
                text=True,
                timeout=timeout,
                check=False,
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
            self._run(["pull", "--ff-only"], cwd=local_dir)
            return local_dir
        local_dir.mkdir(parents=True, exist_ok=True)
        # "--" keeps a pasted URL starting with "-" from being read as an option.
        self._run(["clone", "--", remote_url, str(local_dir)], cwd=local_dir.parent)
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