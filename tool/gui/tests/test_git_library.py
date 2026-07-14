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

from src.backend.course_adapter import CourseAdapter  # noqa: E402
from src.backend.git_library import GitLibrary  # noqa: E402

_REPO = _GUI.parents[1]
COURSE_SRC = _REPO / "assets" / "courses" / "turkish"


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
        shutil.copytree(COURSE_SRC, seed)
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


if __name__ == "__main__":
    unittest.main()