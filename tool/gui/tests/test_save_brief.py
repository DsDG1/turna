"""O-10 local save brief pure helpers + pipeline wiring."""
from __future__ import annotations

import sys
import unittest
from dataclasses import dataclass, field
from pathlib import Path
from types import SimpleNamespace
from typing import Any

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.experience.save_brief import (  # noqa: E402
    build_local_save_brief,
    build_local_save_brief_from_context,
)
from src.application.save_pipeline import (  # noqa: E402
    REASON_MENU,
    SaveRequest,
    compose_status_message,
    run_save_pipeline,
)


@dataclass
class _FakeSaveResult:
    ok: bool
    message: str = ""
    errors: list[dict[str, Any]] = field(default_factory=list)


class SaveBriefPureTest(unittest.TestCase):
    def test_empty_defaults(self) -> None:
        self.assertEqual(build_local_save_brief(), "课程已保存")

    def test_counters(self) -> None:
        s = build_local_save_brief(
            lesson_count=12,
            empty_lesson_count=2,
            validate_error_count=1,
            placeholder_count=3,
            soft_count=4,
        )
        self.assertIn("12 课", s)
        self.assertIn("空课 2", s)
        self.assertIn("错 1", s)
        self.assertIn("待补 3", s)
        self.assertIn("规范化 4", s)

    def test_from_context(self) -> None:
        ctx = SimpleNamespace(
            lesson_count=5,
            empty_lesson_count=1,
            validate_error_count=0,
            validate_warning_count=2,
            hygiene={"placeholder_count": 1},
        )
        s = build_local_save_brief_from_context(ctx, soft_count=0)
        self.assertIn("5 课", s)
        self.assertIn("空课 1", s)
        self.assertIn("警 2", s)

    def test_from_none_context(self) -> None:
        self.assertEqual(
            build_local_save_brief_from_context(None),
            "课程已保存",
        )


class SaveBriefPipelineTest(unittest.TestCase):
    def test_brief_on_success_when_requested(self) -> None:
        outcome = run_save_pipeline(
            SaveRequest(reason=REASON_MENU, run_soft=False, want_ai_brief=True),
            do_save=lambda: _FakeSaveResult(ok=True, message="保存成功"),
            build_brief=lambda o: f"摘要 soft={o.soft_count}",
        )
        self.assertTrue(outcome.ok)
        self.assertEqual(outcome.brief, "摘要 soft=0")

    def test_brief_error_does_not_block_save(self) -> None:
        def boom(_o):
            raise RuntimeError("brief boom")

        outcome = run_save_pipeline(
            SaveRequest(reason=REASON_MENU, run_soft=False, want_ai_brief=True),
            do_save=lambda: _FakeSaveResult(ok=True, message="保存成功"),
            build_brief=boom,
        )
        self.assertTrue(outcome.ok)
        self.assertIsNone(outcome.brief)

    def test_brief_skipped_when_flag_off(self) -> None:
        called = []

        outcome = run_save_pipeline(
            SaveRequest(reason=REASON_MENU, run_soft=False, want_ai_brief=False),
            do_save=lambda: _FakeSaveResult(ok=True, message="保存成功"),
            build_brief=lambda o: called.append(1) or "x",
        )
        self.assertTrue(outcome.ok)
        self.assertIsNone(outcome.brief)
        self.assertEqual(called, [])

    def test_brief_not_on_failure(self) -> None:
        called = []
        outcome = run_save_pipeline(
            SaveRequest(reason=REASON_MENU, run_soft=False, want_ai_brief=True),
            do_save=lambda: _FakeSaveResult(
                ok=False, message="fail", errors=[{"level": "error"}]
            ),
            build_brief=lambda o: called.append(1) or "x",
        )
        self.assertFalse(outcome.ok)
        self.assertIsNone(outcome.brief)
        self.assertEqual(called, [])

    def test_compose_includes_brief(self) -> None:
        msg = compose_status_message(
            base="保存成功",
            soft_count=1,
            brief="12 课 · 空课 2",
        )
        self.assertIn("规则规范化 1 项", msg)
        self.assertIn("12 课", msg)


if __name__ == "__main__":
    unittest.main()
