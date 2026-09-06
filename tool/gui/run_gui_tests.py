#!/usr/bin/env python3
"""Layered GUI test runner (L0 gate / L1 fast / L2 full / affected).

Usage (from repo root or tool/gui)::

    python run_gui_tests.py gate
    python run_gui_tests.py fast              # sequential L1 fast
    python run_gui_tests.py fast -j 4         # parallel L1 fast (4 workers)
    python run_gui_tests.py affected          # run only tests affected by git diff
    python run_gui_tests.py affected -j 4     # parallel affected tests
    python run_gui_tests.py list-affected     # print affected test modules
    python run_gui_tests.py ci                # gate+fast (PR default)
    python run_gui_tests.py ci -j 4           # gate+parallel fast
    python run_gui_tests.py full              # unittest discover tests/test_*.py
    python run_gui_tests.py clean-cache
    python run_gui_tests.py list-fast         # print L1 modules

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
import time
import unittest
from concurrent.futures import ThreadPoolExecutor, as_completed
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
    | \bUnifiedWorkspaceWidget\b
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
    os.environ.setdefault("PYTHONUTF8", "1")
    os.environ.setdefault("PYTHONIOENCODING", "utf-8")
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    if hasattr(sys.stderr, "reconfigure"):
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")


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


def cmd_e1() -> int:
    _ensure_path()
    script = TESTS_DIR / "experience_e1_gate_smoke.py"
    if not script.is_file():
        print(f"error: missing {script}", file=sys.stderr)
        return 1
    return subprocess.call([sys.executable, str(script)], cwd=str(GUI_DIR))


def cmd_e2() -> int:
    _ensure_path()
    script = TESTS_DIR / "experience_e2_gate_smoke.py"
    if not script.is_file():
        print(f"error: missing {script}", file=sys.stderr)
        return 1
    return subprocess.call([sys.executable, str(script)], cwd=str(GUI_DIR))


def cmd_gate() -> int:
    _ensure_path()
    code1 = cmd_e1()
    if code1 != 0:
        return code1
    print("\n", flush=True)
    return cmd_e2()


def run_modules_parallel(paths: list[Path], jobs: int = 4) -> int:
    _ensure_path()
    if not paths:
        print("No test modules to run.")
        return 0

    # Slowest-first heuristic to minimize idle worker waiting tail
    def _priority(p: Path) -> int:
        name = p.name
        if "git_library" in name:
            return 0
        if "course_adapter" in name or "lesson_round_trip" in name:
            return 1
        return 2

    sorted_paths = sorted(paths, key=_priority)
    names = [f"tests.{p.stem}" for p in sorted_paths]
    print(f"Parallel execution: {len(names)} modules across {jobs} workers", flush=True)

    def _run_mod(mod_name: str) -> tuple[str, int, float, str]:
        t0 = time.perf_counter()
        env = dict(os.environ)
        env["QT_QPA_PLATFORM"] = "offscreen"
        env["PYTHONUTF8"] = "1"
        res = subprocess.run(
            [sys.executable, "-m", "unittest", mod_name],
            cwd=str(GUI_DIR),
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            env=env,
        )
        dt = time.perf_counter() - t0
        output = (res.stdout + "\n" + res.stderr).strip()
        return mod_name, res.returncode, dt, output

    t_start = time.perf_counter()
    passed = 0
    failed_modules: list[tuple[str, str]] = []

    with ThreadPoolExecutor(max_workers=jobs) as ex:
        futures = {ex.submit(_run_mod, name): name for name in names}
        for fut in as_completed(futures):
            mod_name, code, dt, output = fut.result()
            if code == 0:
                passed += 1
                print(f"  ✓ {mod_name} ({dt:.2f}s)", flush=True)
            else:
                failed_modules.append((mod_name, output))
                print(f"  ✗ {mod_name} FAILED ({dt:.2f}s)", flush=True)

    total_dt = time.perf_counter() - t_start
    print(
        f"\nParallel summary: ran={len(names)} passed={passed} "
        f"failed={len(failed_modules)} in {total_dt:.2f}s",
        flush=True,
    )

    if failed_modules:
        print("\n=== Failures Summary ===", flush=True)
        for mod, out in failed_modules:
            print(f"\n--- {mod} ---", flush=True)
            print(out, flush=True)
        return 1

    return 0


def find_affected_tests() -> list[Path]:
    """Find test files affected by current git working tree modifications."""
    repo_dir = GUI_DIR
    try:
        p1 = subprocess.run(
            ["git", "diff", "--name-only", "HEAD"],
            cwd=str(repo_dir),
            capture_output=True,
            text=True,
        )
        p2 = subprocess.run(
            ["git", "status", "--porcelain"],
            cwd=str(repo_dir),
            capture_output=True,
            text=True,
        )
    except Exception as e:
        print(f"warning: git detection failed: {e}", file=sys.stderr)
        return []

    changed = set(p1.stdout.splitlines())
    for line in p2.stdout.splitlines():
        parts = line.strip().split(maxsplit=1)
        if len(parts) == 2:
            changed.add(parts[1])

    affected: set[Path] = set()
    all_tests = list_test_modules()
    test_texts = {t: t.read_text(encoding="utf-8", errors="replace") for t in all_tests}

    for rel in changed:
        norm = rel.replace("\\", "/")
        if norm.startswith("tool/gui/"):
            norm = norm[len("tool/gui/"):]
        if norm.startswith("tests/test_") and norm.endswith(".py"):
            p = TESTS_DIR / Path(norm).name
            if p.is_file():
                affected.add(p)
        elif norm.startswith("src/"):
            stem = Path(norm).stem
            direct = TESTS_DIR / f"test_{stem}.py"
            if direct.is_file():
                affected.add(direct)
            if stem.endswith("_controller"):
                alt = TESTS_DIR / f"test_{stem[:-11]}.py"
                if alt.is_file():
                    affected.add(alt)
            pattern = re.compile(rf"\b(from|import)\s+[^\n]*\b{re.escape(stem)}\b")
            for t, text in test_texts.items():
                if t not in affected and pattern.search(text):
                    affected.add(t)

    return sorted(affected)


def cmd_affected(jobs: int = 1) -> int:
    _ensure_path()
    affected = find_affected_tests()
    if not affected:
        print("No affected test modules detected for current git changes.")
        return 0
    print(f"Detected {len(affected)} affected test module(s):")
    for p in affected:
        print(f"  • {p.name}")
    print(flush=True)
    if jobs > 1:
        return run_modules_parallel(affected, jobs=jobs)

    loader = unittest.TestLoader()
    suite = unittest.TestSuite()
    for path in affected:
        mod_name = f"tests.{path.stem}"
        try:
            suite.addTests(loader.loadTestsFromName(mod_name))
        except Exception as exc:
            print(f"error: failed to load {mod_name}: {exc}", file=sys.stderr)
            return 1
    result = unittest.TextTestRunner(verbosity=1).run(suite)
    print(
        f"\nAffected summary: ran={result.testsRun} "
        f"failures={len(result.failures)} errors={len(result.errors)} "
        f"skipped={len(result.skipped)}",
        flush=True,
    )
    return 0 if result.wasSuccessful() else 1


def cmd_list_affected() -> int:
    affected = find_affected_tests()
    print(f"Affected test modules: {len(affected)}")
    for p in affected:
        print(p.name)
    return 0


def cmd_fast(jobs: int = 1) -> int:
    _ensure_path()
    pure = pure_modules()
    if not pure:
        print("error: no pure modules classified", file=sys.stderr)
        return 1
    if jobs > 1:
        return run_modules_parallel(pure, jobs=jobs)

    # Sequential in-process execution (classic default)
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
    print(f"L1 fast: {len(names)} modules (sequential)", flush=True)
    result = unittest.TextTestRunner(verbosity=1).run(suite)
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


def cmd_usability() -> int:
    """T.9 headless teacher-path smoke (offline; not part of ci default)."""
    script = TESTS_DIR / "usability_smoke.py"
    print(f"=== T.9 usability smoke: {script.name} ===", flush=True)
    return subprocess.call([sys.executable, str(script)], cwd=str(GUI_DIR))


def cmd_ci(jobs: int = 1) -> int:
    """PR / pre-commit default: L0 gate then L1 fast (not full UI suite)."""
    print("=== CI tier: L0 gate + L1 fast ===", flush=True)
    code = cmd_gate()
    if code != 0:
        return code
    return cmd_fast(jobs=jobs)


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
        choices=(
            "gate", "e1", "e2", "fast", "ci", "full", "usability",
            "clean-cache", "list-fast", "affected", "list-affected",
        ),
        help="Which tier / maintenance action to run",
    )
    parser.add_argument(
        "-j", "--jobs",
        type=int,
        default=1,
        help="Number of concurrent worker processes for fast / affected tiers (default: 1)",
    )
    args = parser.parse_args(argv)
    if args.tier == "gate":
        return cmd_gate()
    if args.tier == "e1":
        return cmd_e1()
    if args.tier == "e2":
        return cmd_e2()
    if args.tier == "fast":
        return cmd_fast(jobs=args.jobs)
    if args.tier == "ci":
        return cmd_ci(jobs=args.jobs)
    if args.tier == "affected":
        return cmd_affected(jobs=args.jobs)
    if args.tier == "list-affected":
        return cmd_list_affected()
    if args.tier == "full":
        return cmd_full()
    if args.tier == "usability":
        return cmd_usability()
    if args.tier == "clean-cache":
        return cmd_clean_cache()
    if args.tier == "list-fast":
        return cmd_list_fast()
    return 2


if __name__ == "__main__":
    sys.exit(main())
