#!/usr/bin/env python3
"""Build the Turna GUI into a single-file executable (guiplan §9 M5.2).

Wraps PyInstaller with the bundled `turna_gui.spec`. Intended for local
host builds -- PyInstaller (like PySide6) cannot be pip-installed in the TRAE
sandbox, so the produced exe must be verified on the developer's machine.

Usage:
    python tool/gui/build_gui.py            # build onefile exe
    python tool/gui/build_gui.py --clean    # remove build/ dist/ first
    python tool/gui/build_gui.py --onedir   # onedir instead of onefile
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
SPEC = ROOT / "tool" / "gui" / "turna_gui.spec"


def require_pyinstaller() -> str:
    pi = shutil.which("pyinstaller")
    if pi is None:
        try:
            import PyInstaller  # noqa: F401

            return sys.executable
        except ImportError:
            print(
                "error: PyInstaller not found. Install with: pip install pyinstaller",
                file=sys.stderr,
            )
            sys.exit(1)
    return pi


def build(clean: bool, onedir: bool) -> int:
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
    parser.add_argument("--onedir", action="store_true", help="Build onedir instead of onefile.")
    args = parser.parse_args(argv)
    require_pyinstaller()
    return build(clean=args.clean, onedir=args.onedir)


if __name__ == "__main__":
    sys.exit(main())
