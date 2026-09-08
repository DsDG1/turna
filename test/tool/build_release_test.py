#!/usr/bin/env python3
"""Unit tests for tool/build_release.py.

These tests mock out subprocess and filesystem side effects. They verify that
build_release.py invokes the expected Flutter toolchain commands and produces
correctly named artifact paths for a given version.
"""

from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

# tool/ is not a package; import the module by path.
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "tool"))

import build_release  # noqa: E402


class BuildReleaseTests(unittest.TestCase):
    def setUp(self) -> None:
        self.root = build_release.project_root()
        self.output_dir = self.root / "build" / "releases" / "test-version"

    def _run_build(
        self,
        version: str = "0.4.0-test",
        skip_web: bool = False,
        skip_content_validation: bool = True,
        skip_native: bool = True,
        skip_aab: bool = False,
        ensure_native_mock: MagicMock | None = None,
    ) -> tuple[list[str], list[tuple[Path, Path]]]:
        """Run build_release.build_release with mocked subprocess/shutil.

        Returns (subprocess commands as joined strings, copy2 calls).
        """
        commands: list[list[str]] = []
        copies: list[tuple[Path, Path]] = []

        def fake_run(cmd: list[str], cwd: Path, check: bool = True) -> MagicMock:
            commands.append(cmd)
            # Create expected artifact files/directories on disk so real
            # Path.exists() checks in build_release succeed.
            # cmd[0] is the flutter executable path (possibly absolute).
            if cmd[1:4] == ["build", "apk", "--release"]:
                apk = cwd / "build" / "app" / "outputs" / "flutter-apk" / "app-arm64-v8a-release.apk"
                apk.parent.mkdir(parents=True, exist_ok=True)
                apk.write_text("apk", encoding="utf-8")
            elif cmd[1:4] == ["build", "appbundle", "--release"]:
                aab = cwd / "build" / "app" / "outputs" / "bundle" / "release" / "app-release.aab"
                aab.parent.mkdir(parents=True, exist_ok=True)
                aab.write_text("aab", encoding="utf-8")
            elif cmd[1:4] == ["build", "web", "--release"]:
                web = cwd / "build" / "web" / "index.html"
                web.parent.mkdir(parents=True, exist_ok=True)
                web.write_text("html", encoding="utf-8")
            elif cmd[0] == sys.executable and "export_content_inventory" in cmd[1]:
                inventory = cwd / "docs" / "content_inventory_current.md"
                if not inventory.exists():
                    inventory.parent.mkdir(parents=True, exist_ok=True)
                    inventory.write_text("inventory", encoding="utf-8")
            return MagicMock(returncode=0)

        def fake_copy2(src: os.PathLike[str], dst: os.PathLike[str], *args: object, **kwargs: object) -> None:
            copies.append((Path(src), Path(dst)))

        def fake_copytree(src: os.PathLike[str], dst: os.PathLike[str], *args: object, **kwargs: object) -> None:
            copies.append((Path(src), Path(dst)))

        def fake_rmtree(path: os.PathLike[str]) -> None:
            pass

        native_patch = (
            patch("build_release.ensure_native_library", new=ensure_native_mock)
            if ensure_native_mock is not None
            else patch("build_release.ensure_native_library")
        )

        with patch("build_release.subprocess.run", side_effect=fake_run), \
             patch("build_release.shutil.which", return_value="/flutter"), \
             patch("build_release.shutil.copy2", side_effect=fake_copy2), \
             patch("build_release.shutil.copytree", side_effect=fake_copytree), \
             patch("build_release.shutil.rmtree", side_effect=fake_rmtree), \
             patch("build_release.assert_native_in_artifact"), \
             native_patch:
            artifacts = build_release.build_release(
                version=version,
                output_dir=self.output_dir,
                skip_web=skip_web,
                skip_content_validation=skip_content_validation,
                skip_native=skip_native,
                skip_aab=skip_aab,
            )

        joined_commands = [" ".join(c) for c in commands]
        return joined_commands, copies

    @staticmethod
    def _has_command(commands: list[str], needle: str) -> bool:
        return any(needle in c for c in commands)

    def test_build_commands_include_pub_get_and_build_runner(self) -> None:
        commands, _ = self._run_build()
        self.assertTrue(self._has_command(commands, "flutter pub get"))
        self.assertTrue(
            self._has_command(
                commands,
                "flutter pub run build_runner build --delete-conflicting-outputs",
            )
        )

    def test_build_commands_include_apk_and_appbundle(self) -> None:
        commands, copies = self._run_build()
        self.assertTrue(self._has_command(commands, "flutter build apk --release"))
        self.assertTrue(self._has_command(commands, "flutter build appbundle --release"))
        dst_names = [dst.name for _, dst in copies]
        self.assertIn("turna-v0.4.0-test-release.apk", dst_names)
        self.assertIn("turna-v0.4.0-test-release.aab", dst_names)

    def test_aab_build_is_skipped_with_flag(self) -> None:
        commands, copies = self._run_build(skip_aab=True)
        self.assertFalse(self._has_command(commands, "flutter build appbundle --release"))
        dst_names = [dst.name for _, dst in copies]
        self.assertNotIn("turna-v0.4.0-test-release.aab", dst_names)
        self.assertIn("turna-v0.4.0-test-release.apk", dst_names)

    def test_web_build_is_skipped_with_flag(self) -> None:
        commands, copies = self._run_build(skip_web=True)
        self.assertFalse(self._has_command(commands, "flutter build web --release"))
        dst_names = [dst.name for _, dst in copies]
        self.assertNotIn("turna-v0.4.0-test-web", dst_names)

    def test_web_build_is_included_by_default(self) -> None:
        commands, copies = self._run_build(skip_web=False)
        self.assertTrue(self._has_command(commands, "flutter build web --release"))
        dst_names = [dst.name for _, dst in copies]
        self.assertIn("turna-v0.4.0-test-web", dst_names)

    def test_native_build_is_skipped_with_flag(self) -> None:
        mock_ensure = MagicMock()
        self._run_build(skip_native=True, ensure_native_mock=mock_ensure)
        mock_ensure.assert_not_called()

    def test_native_build_when_not_skipped(self) -> None:
        mock_ensure = MagicMock()
        self._run_build(skip_native=False, ensure_native_mock=mock_ensure)
        mock_ensure.assert_called_once()

    def test_content_validation_commands_when_not_skipped(self) -> None:
        commands, _ = self._run_build(skip_content_validation=False)
        self.assertTrue(self._has_command(commands, f"{sys.executable} tool/course_cli.py validate"))
        self.assertTrue(self._has_command(commands, f"{sys.executable} tool/course_cli.py lint"))

    def test_inventory_is_copied_to_versioned_file(self) -> None:
        _, copies = self._run_build()
        inventory_copies = [
            (src, dst) for src, dst in copies
            if dst.name == "content_inventory_v0.4.0-test.md"
        ]
        self.assertEqual(len(inventory_copies), 1)
        src, dst = inventory_copies[0]
        self.assertEqual(src.name, "content_inventory_current.md")

    def test_validate_version_rejects_bad_characters(self) -> None:
        for bad in ["", "a/b", "a\\b"]:
            with self.assertRaises(SystemExit):
                build_release.validate_version(bad)


if __name__ == "__main__":
    unittest.main()
