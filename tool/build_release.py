#!/usr/bin/env python3
"""One-command release builder for Varnamala.

Produces versioned release artifacts (APK, AAB, optional web) and a matching
content inventory report. Intended for local release builds and CI smoke tests.

Examples:
    python tool/build_release.py --version 0.4.0-future4
    python tool/build_release.py --version 0.4.0-future4 --skip-web
    python tool/build_release.py --version 0.4.0-future4 --output-dir ./dist
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path


def project_root() -> Path:
    return Path(__file__).resolve().parent.parent


def require_flutter() -> str:
    flutter = shutil.which("flutter")
    if flutter is None:
        print("error: flutter not found in PATH", file=sys.stderr)
        sys.exit(1)
    return flutter


def run(cmd: list[str], cwd: Path) -> None:
    print(f"$ {' '.join(cmd)}")
    subprocess.run(cmd, cwd=cwd, check=True)


def validate_version(version: str) -> str:
    if not version or "/" in version or "\\" in version:
        print(f"error: invalid version string: {version!r}", file=sys.stderr)
        sys.exit(1)
    return version


def copy_artifact(src: Path, dst: Path) -> None:
    if not src.exists():
        print(f"error: expected artifact not found: {src}", file=sys.stderr)
        sys.exit(1)
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)
    print(f"-> {dst}")


def copy_tree(src: Path, dst: Path) -> None:
    """Copy a directory tree to ``dst``.

    Uses ``dirs_exist_ok=True`` so the destination is merged in place rather
    than removed-then-recreated — the old ``rmtree`` + ``copytree`` sequence
    left no tree at all if the process was interrupted between the two calls
    (M18).
    """
    if not src.exists():
        print(f"error: expected artifact directory not found: {src}", file=sys.stderr)
        sys.exit(1)
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(src, dst, dirs_exist_ok=True)
    print(f"-> {dst}")


def build_release(
    version: str,
    output_dir: Path,
    skip_web: bool,
    skip_content_validation: bool,
) -> list[Path]:
    root = project_root()
    flutter = require_flutter()
    artifacts: list[Path] = []

    run([flutter, "pub", "get"], cwd=root)
    run(
        [flutter, "pub", "run", "build_runner", "build", "--delete-conflicting-outputs"],
        cwd=root,
    )

    if not skip_content_validation:
        run([sys.executable, "tool/course_cli.py", "validate"], cwd=root)
        run([sys.executable, "tool/course_cli.py", "lint"], cwd=root)

    run([flutter, "build", "apk", "--release"], cwd=root)
    apk_src = root / "build" / "app" / "outputs" / "flutter-apk" / "app-release.apk"
    apk_dst = output_dir / f"varnamala-v{version}-release.apk"
    copy_artifact(apk_src, apk_dst)
    artifacts.append(apk_dst)

    run([flutter, "build", "appbundle", "--release"], cwd=root)
    aab_src = root / "build" / "app" / "outputs" / "bundle" / "release" / "app-release.aab"
    aab_dst = output_dir / f"varnamala-v{version}-release.aab"
    copy_artifact(aab_src, aab_dst)
    artifacts.append(aab_dst)

    if not skip_web:
        run([flutter, "build", "web", "--release"], cwd=root)
        web_src = root / "build" / "web"
        web_dst = output_dir / f"varnamala-v{version}-web"
        copy_tree(web_src, web_dst)
        artifacts.append(web_dst)

    run([sys.executable, "tool/export_content_inventory.py"], cwd=root)
    inventory_src = root / "docs" / "content_inventory_current.md"
    inventory_dst = root / "docs" / f"content_inventory_v{version}.md"
    copy_artifact(inventory_src, inventory_dst)
    artifacts.append(inventory_dst)

    return artifacts


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Build a Varnamala release.")
    parser.add_argument(
        "--version",
        required=True,
        help="Release version string used in artifact names (e.g., 0.4.0-future4).",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        help="Directory for release artifacts. Defaults to build/releases/<version>.",
    )
    parser.add_argument(
        "--skip-web",
        action="store_true",
        help="Skip the flutter build web step.",
    )
    parser.add_argument(
        "--skip-content-validation",
        action="store_true",
        help="Skip course content validate/lint (useful for CI smoke).",
    )
    args = parser.parse_args(argv)

    version = validate_version(args.version)
    root = project_root()
    output_dir = args.output_dir or (root / "build" / "releases" / version)
    output_dir.mkdir(parents=True, exist_ok=True)

    artifacts = build_release(
        version=version,
        output_dir=output_dir,
        skip_web=args.skip_web,
        skip_content_validation=args.skip_content_validation,
    )

    print("\nRelease build complete:")
    for artifact in artifacts:
        print(f"  {artifact}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
