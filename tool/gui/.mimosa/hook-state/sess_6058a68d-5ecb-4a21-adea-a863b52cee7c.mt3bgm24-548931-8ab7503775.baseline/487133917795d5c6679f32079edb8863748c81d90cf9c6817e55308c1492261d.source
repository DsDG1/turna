#!/usr/bin/env python3
"""Layered GUI test runner (L0 gate / L1 fast / L2 full).

Usage (from repo root or tool/gui)::

    QT_QPA_PLATFORM=offscreen python3 tool/gui/run_gui_tests.py gate
    QT_QPA_PLATFORM=offscreen python3 tool/gui/run_gui_tests.py fast
    QT_QPA_PLATFORM=offscreen python3 tool/gui/run_gui_tests.py ci     # gate+fast (PR default)
    QT_QPA_PLATFORM=offscreen python3 tool/gui/run_gui_tests.py full
    python3 tool/gui/run_gui_tests.py clean-cache
    python3 tool/gui/run_gui_tests.py list-fast   # print L1 modules

Tiers
-----
L0 gate  — experience_e1_gate_smoke.py (Experience OS contract smoke)
L1 fast  — test modules whose source does not reference heavy Qt/widget APIs
L0+L1 ci — **default for PR / pre-commit** (seconds–tens of seconds)
L2 full  — unittest discover tests/test_*.py (BASELINE; release / UI changes / nightly)

Classification is heuristic (source scan). Prefer pure backend tests for L1;
widget construction belongs in L2. See tests/BASELINE.md.
"""
from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import unittest
from pathlib import Path

GUI_DIR = Path(__file__).resolve().parent
TESTS_DIR = GUI_DIR / "tests"

# Heavy Qt / widget markers → exclude from L1 fast.
_QT_HEAVY = re.compile(
    r"""
    PySide6\.(QtWidgets|QtGui|QtTest)
    | from\s+PySide6\s+import
    | \bQApplication\b
    | \bqt_app\s*\(
    | \bQMainWindow\b
    | \bQDialog\b
    | \bQWidget\b
    | \bQTest\b
    | \bprocessEvents\s*\(
    """,
    re.VERBOSE,
)


def _ensure_path() -> None:
    gui = str(GUI_DIR)
    if gui not in sys.path:
        sys.path.insert(0, gui)
    os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")


def list_test_modules() -> list[Path]:
    return sorted(TESTS_DIR.glob("test_*.py"))


def is_pure_module(path: Path) -> bool:
    text = path.read_text(encoding="utf-8", errors="replace")
    return _QT_HEAVY.search(text) is None


def pure_modules() -> list[Path]:
    return [p for p in list_test_modules() if is_pure_module(p)]


def qtish_modules() -> list[Path]:
    return [p for p in list_test_modules() if not is_pure_module(p)]


def cmd_list_fast() -> int:
    pure = pure_modules()
    qtish = qtish_modules()
    print(f"L1 pure: {len(pure)}  L2-only qtish: {len(qtish)}  total: {len(pure) + len(qtish)}")
    print("--- L1 pure ---")
    for p in pure:
        print(p.name)
    print("--- L2 qtish ---")
    for p in qtish:
        print(p.name)
    return 0


def cmd_gate() -> int:
    _ensure_path()
    script = TESTS_DIR / "experience_e1_gate_smoke.py"
    if not script.is_file():
        print(f"error: missing {script}", file=sys.stderr)
        return 1
    return subprocess.call([sys.executable, str(script)], cwd=str(GUI_DIR))


def cmd_fast() -> int:
    _ensure_path()
    pure = pure_modules()
    if not pure:
        print("error: no pure modules classified", file=sys.stderr)
        return 1
    # Load as tests.test_foo so relative imports (tests._qtapp) work.
    loader = unittest.TestLoader()
    suite = unittest.TestSuite()
    names: list[str] = []
    for path in pure:
        mod_name = f"tests.{path.stem}"
        names.append(mod_name)
        try:
            suite.addTests(loader.loadTestsFromName(mod_name))
        except Exception as exc:  # noqa: BLE001 — report and continue? fail hard.
            print(f"error: failed to load {mod_name}: {exc}", file=sys.stderr)
            return 1
    print(f"L1 fast: {len(names)} modules", flush=True)
    result = unittest.TextTestRunner(verbosity=1).run(suite)
    # Match discover-style summary for BASELINE mental model
    print(
        f"\nL1 summary: ran={result.testsRun} "
        f"failures={len(result.failures)} errors={len(result.errors)} "
        f"skipped={len(result.skipped)}",
        flush=True,
    )
    return 0 if result.wasSuccessful() else 1


def cmd_full() -> int:
    _ensure_path()
    # Same as documented discover command.
    return subprocess.call(
        [
            sys.executable,
            "-m",
            "unittest",
            "discover",
            "-s",
            str(TESTS_DIR),
            "-p",
            "test_*.py",
        ],
        cwd=str(GUI_DIR),
    )


def cmd_ci() -> int:
    """PR / pre-commit default: L0 gate then L1 fast (not full UI suite)."""
    print("=== CI tier: L0 gate + L1 fast ===", flush=True)
    code = cmd_gate()
    if code != 0:
        return code
    return cmd_fast()


def cmd_clean_cache() -> int:
    removed = 0
    for root, dirs, _files in os.walk(GUI_DIR):
        if "__pycache__" in dirs:
            p = Path(root) / "__pycache__"
            shutil.rmtree(p, ignore_errors=True)
            removed += 1
            dirs.remove("__pycache__")
    # pytest cache if present
    for extra in (GUI_DIR / ".pytest_cache", GUI_DIR / "tests" / ".pytest_cache"):
        if extra.exists():
            shutil.rmtree(extra, ignore_errors=True)
            removed += 1
    print(f"removed {removed} cache dir(s) under {GUI_DIR}")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "tier",
        choices=("gate", "fast", "ci", "full", "clean-cache", "list-fast"),
        help="Which tier / maintenance action to run",
    )
    args = parser.parse_args(argv)
    if args.tier == "gate":
        return cmd_gate()
    if args.tier == "fast":
        return cmd_fast()
    if args.tier == "ci":
        return cmd_ci()
    if args.tier == "full":
        return cmd_full()
    if args.tier == "clean-cache":
        return cmd_clean_cache()
    if args.tier == "list-fast":
        return cmd_list_fast()
    return 2


if __name__ == "__main__":
    sys.exit(main())
