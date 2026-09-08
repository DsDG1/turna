#!/usr/bin/env python3
"""One-command release builder for Turna.

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
import zipfile
from pathlib import Path

# The official-Anki cutover flags default ON, so every Android release
# artifact must embed the native core; an APK without it installs fine and
# then breaks official import/review at runtime (silent, CI-invisible).
NATIVE_SO_RELATIVE = "android/app/src/main/jniLibs/arm64-v8a/libturna_anki.so"
NATIVE_BUILD_SCRIPT = "native/turna_anki_core/build-android/build.sh"


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


def ensure_native_library(root: Path) -> None:
    so = root / NATIVE_SO_RELATIVE
    if so.exists():
        print(f"-> native core already present: {NATIVE_SO_RELATIVE}")
        return
    print(f"native core missing; building via {NATIVE_BUILD_SCRIPT}")
    run(["bash", NATIVE_BUILD_SCRIPT], cwd=root)
    if not so.exists():
        print(
            f"error: build script finished but {NATIVE_SO_RELATIVE} is missing",
            file=sys.stderr,
        )
        sys.exit(1)


def assert_native_in_artifact(artifact: Path) -> None:
    with zipfile.ZipFile(artifact) as zf:
        names = zf.namelist()
        embedded = [
            name
            for name in names
            if name.endswith("lib/arm64-v8a/libturna_anki.so")
        ]
        other_abis = sorted(
            {
                part
                for name in names
                for part in ("armeabi-v7a", "x86_64", "x86")
                if f"lib/{part}/" in name.replace("\\", "/")
            }
        )
    if not embedded:
        print(
            f"error: {artifact.name} does not embed lib/arm64-v8a/libturna_anki.so. "
            "The official-Anki cutover flags default on, so this artifact would "
            "break official import/review at runtime.",
            file=sys.stderr,
        )
        sys.exit(1)
    if other_abis:
        print(
            f"error: {artifact.name} contains extra JNI ABI dirs {other_abis} "
            "without a matching Official Anki .so policy (doc 34 §14.2: "
            "arm64-v8a only). Do not ship a fat APK that installs on ABIs "
            "where libturna_anki.so is missing.",
            file=sys.stderr,
        )
        sys.exit(1)
    print(f"-> {artifact.name} embeds {embedded[0]}")


def build_release(
    version: str,
    output_dir: Path,
    skip_web: bool,
    skip_content_validation: bool,
    skip_native: bool,
    skip_aab: bool = False,
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

    if skip_native:
        print(
            "warning: --skip-native: libturna_anki.so will NOT be built or "
            "verified inside the artifacts (never use for a real release)",
            file=sys.stderr,
        )
    else:
        ensure_native_library(root)

    run(
        [
            flutter,
            "build",
            "apk",
            "--release",
            "--split-per-abi",
            "--target-platform",
            "android-arm64",
        ],
        cwd=root,
    )
    apk_src = (
        root
        / "build"
        / "app"
        / "outputs"
        / "flutter-apk"
        / "app-arm64-v8a-release.apk"
    )
    apk_dst = output_dir / f"turna-v{version}-release.apk"
    copy_artifact(apk_src, apk_dst)
    if not skip_native:
        assert_native_in_artifact(apk_dst)
    artifacts.append(apk_dst)

    if skip_aab:
        print("-> skipping appbundle (--skip-aab)")
    else:
        run(
            [
                flutter,
                "build",
                "appbundle",
                "--release",
                "--target-platform",
                "android-arm64",
            ],
            cwd=root,
        )
        aab_src = (
            root / "build" / "app" / "outputs" / "bundle" / "release" / "app-release.aab"
        )
        aab_dst = output_dir / f"turna-v{version}-release.aab"
        copy_artifact(aab_src, aab_dst)
        if not skip_native:
            assert_native_in_artifact(aab_dst)
        artifacts.append(aab_dst)

    if not skip_web:
        run([flutter, "build", "web", "--release"], cwd=root)
        web_src = root / "build" / "web"
        web_dst = output_dir / f"turna-v{version}-web"
        copy_tree(web_src, web_dst)
        artifacts.append(web_dst)

    run([sys.executable, "tool/export_content_inventory.py"], cwd=root)
    inventory_src = root / "docs" / "content_inventory_current.md"
    inventory_dst = root / "docs" / f"content_inventory_v{version}.md"
    copy_artifact(inventory_src, inventory_dst)
    artifacts.append(inventory_dst)

    return artifacts


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Build a Turna release.")
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
    parser.add_argument(
        "--skip-native",
        action="store_true",
        help=(
            "Skip building/verifying libturna_anki.so in the artifacts "
            "(CI smoke only; never use for a real release)."
        ),
    )
    parser.add_argument(
        "--skip-aab",
        action="store_true",
        help="Skip the flutter build appbundle step (APK-only distribution).",
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
        skip_native=args.skip_native,
        skip_aab=args.skip_aab,
    )

    print("\nRelease build complete:")
    for artifact in artifacts:
        print(f"  {artifact}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
