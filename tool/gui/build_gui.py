#!/usr/bin/env python3
"""Build the Turna GUI into a single-file executable (guiplan §9 M5.2).

Wraps PyInstaller with the bundled `turna_gui.spec`. Intended for local
host builds -- PyInstaller (like PySide6) cannot be pip-installed in the TRAE
sandbox, so the produced exe must be verified on the developer's machine.

The exe's version comes from ``tool/gui/pyproject.toml`` (the single source
read by ``turna_gui.spec``). Without ``--version`` the file is left alone,
which is what a local scratch build wants; the release workflow stamps the
version first so the shipped exe reports something other than 0.0.0.

Usage:
    python tool/gui/build_gui.py                    # build onefile exe
    python tool/gui/build_gui.py --clean            # remove build/ dist/ first
    python tool/gui/build_gui.py --version 0.9.2    # stamp the version first
"""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
SPEC = ROOT / "tool" / "gui" / "turna_gui.spec"
PYPROJECT = ROOT / "tool" / "gui" / "pyproject.toml"

_VERSION_RE = re.compile(r'(?m)^version\s*=\s*"([^"]+)"')


def read_version() -> str:
    match = _VERSION_RE.search(PYPROJECT.read_text(encoding="utf-8"))
    return match.group(1) if match else "0.0.0"


def stamp_version(version: str) -> None:
    """Write *version* into pyproject.toml (the exe's version source)."""
    text = PYPROJECT.read_text(encoding="utf-8")
    if not _VERSION_RE.search(text):
        raise SystemExit(
            f"error: no version line in {PYPROJECT} — refusing to guess the format"
        )
    PYPROJECT.write_text(
        _VERSION_RE.sub(f'version = "{version}"', text, count=1), encoding="utf-8"
    )
    print(f"stamped version {version} into {PYPROJECT.name}")


def require_pyinstaller() -> str:
    pi = shutil.which("pyinstaller")
    if pi is None:
        try:
            import PyInstaller

            return sys.executable
        except ImportError:
            print(
                "error: PyInstaller not found. Install with: pip install pyinstaller",
                file=sys.stderr,
            )
            sys.exit(1)
    return pi


def build(clean: bool) -> int:
    if not SPEC.exists():
        print(f"error: spec not found: {SPEC}", file=sys.stderr)
        return 1

    if clean:
        for d in (ROOT / "build", ROOT / "dist"):
            if d.exists():
                shutil.rmtree(d)
                print(f"cleaned {d}")

    cmd = [sys.executable, "-m", "PyInstaller", str(SPEC), "--noconfirm"]
    cmd.extend(["--distpath", str(ROOT / "dist"), "--workpath", str(ROOT / "build")])

    print(f"$ {' '.join(cmd)}")
    return subprocess.run(cmd, cwd=ROOT).returncode


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Build the Turna GUI exe.")
    parser.add_argument("--clean", action="store_true", help="Remove build/ and dist/ first.")
    parser.add_argument(
        "--version",
        help="Stamp this version into pyproject.toml before building "
        "(the exe reads its version from there).",
    )
    args = parser.parse_args(argv)
    if args.version:
        stamp_version(args.version)
    else:
        print(f"version: {read_version()}")
    require_pyinstaller()
    return build(clean=args.clean)


if __name__ == "__main__":
    sys.exit(main())
