"""C-18: local Context build stays inside the L-local latency budget."""
from __future__ import annotations

import shutil
import sys
import time
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.app import _validate_course_problems  # noqa: E402
from src.backend.experience.context_bus import (  # noqa: E402
    build_experience_context,
)
from tests._course_fixture import real_adapter_with_course  # noqa: E402

# L-local 预算（experienceai C-18）：实测 ~2ms，50ms 为慢机/CI 安全上限。
_BUDGET_MS = 50.0


class ContextBuildPerfTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.adapter, cls.tmp = real_adapter_with_course()

    @classmethod
    def tearDownClass(cls) -> None:
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def test_full_build_under_budget(self) -> None:
        t0 = time.perf_counter()
        ctx = build_experience_context(
            self.adapter, include_quality=True, include_hygiene=True
        )
        dt = (time.perf_counter() - t0) * 1000
        self.assertLess(dt, _BUDGET_MS, f"full build took {dt:.1f}ms")
        self.assertGreater(ctx.lesson_count, 0)
        # G2: quality on by default → P3 suggestion data actually present.
        self.assertTrue(ctx.quality_by_section)

    def test_cached_rebuild_under_budget(self) -> None:
        build_experience_context(
            self.adapter, include_quality=True, include_hygiene=True
        )
        t0 = time.perf_counter()
        ctx = build_experience_context(
            self.adapter, include_quality=True, include_hygiene=True
        )
        dt = (time.perf_counter() - t0) * 1000
        self.assertLess(dt, _BUDGET_MS, f"cached rebuild took {dt:.1f}ms")
        self.assertTrue(ctx.quality_by_section)

    def test_validate_course_problems_pure_fn(self) -> None:
        # G1: the shared pure function runs against a real course dir.
        problems = _validate_course_problems(self.adapter.course_dir)
        self.assertIsInstance(problems, list)
        for p in problems:
            self.assertIn("level", p)
            self.assertIn("message", p)


class FocusOnlyPerfTest(unittest.TestCase):
    """C-03: focus-only refresh must be cheap (no structure/hygiene/quality)."""

    @classmethod
    def setUpClass(cls) -> None:
        from tests._qtapp import qt_app

        qt_app()
        cls.adapter, cls.tmp = real_adapter_with_course()

    @classmethod
    def tearDownClass(cls) -> None:
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def test_focus_only_under_budget_and_skips_build(self) -> None:
        from src.application.experience_shell import ExperienceShell

        shell = ExperienceShell(debounce_ms=0)
        shell.set_adapter(self.adapter)
        # Warm a full build so a retained ctx exists.
        shell.set_selection(("lesson", "s1-l2"))
        shell.rebuild_now()
        import src.backend.experience.context_bus as cb

        original = cb.build_experience_context
        called = {"n": 0}

        def _boom(*a, **k):
            called["n"] += 1
            raise AssertionError("focus-only must not call build_experience_context")

        cb.build_experience_context = _boom
        try:
            t0 = time.perf_counter()
            shell.set_selection(("section", "section1"))
            shell.invalidate_focus()
            dt = (time.perf_counter() - t0) * 1000
        finally:
            cb.build_experience_context = original
        self.assertLess(dt, _BUDGET_MS, f"focus-only took {dt:.1f}ms")
        self.assertEqual(called["n"], 0)


if __name__ == "__main__":
    unittest.main()
