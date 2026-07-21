"""Tests for the generation pipeline state machine (aiEnhance Phase 5).

All LLM-touching helpers are patched at the ``src.backend.ai_pipeline``
namespace so the state transitions run offline with mock responses, mirroring
``test_ai_phased.py`` / ``test_ai_generator.py``.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest.mock import patch

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from tests._course_samples import sample_section  # noqa: E402

from src.backend.ai_generator import AiApiConfig, AiCourseSpec  # noqa: E402
from src.backend.ai_pipeline import (  # noqa: E402
    PipelineState,
    PipelineStep,
    STATUS_DONE,
    STATUS_FAILED,
    STATUS_SKIPPED,
    run_pipeline,
)


def _config() -> AiApiConfig:
    return AiApiConfig(base_url="http://x", api_key="k", model="m")


def _spec() -> AiCourseSpec:
    return AiCourseSpec(topic="问候", level="A1", unit_count=1, lessons_per_unit=2)


def _section() -> dict:
    return sample_section(unit_id="u1", lesson_id="u1-l1")


def _outline() -> dict:
    return {
        "id": "greetings",
        "name": "Greetings",
        "words": [{"id": "w-a", "term": "Merhaba", "translation": "你好"}],
        "expressions": [],
        "grammarPoints": [],
        "units": [
            {
                "id": "u1",
                "name": "U1",
                "lessons": [
                    {"id": "u1-l1", "name": "Hello", "template": "intro",
                     "targetWordIds": ["w-a"]},
                ],
            }
        ],
    }


def _usage_emit(kwargs: dict, total: int = 10) -> None:
    cb = kwargs.get("usage_callback")
    if cb:
        cb({"prompt_tokens": total - 4, "completion_tokens": 4, "total_tokens": total})


class PipelineFastModeTest(unittest.TestCase):
    def test_fast_happy_path(self) -> None:
        progresses: list[str] = []

        def fake_generate(config, spec, validator, **kwargs):
            _usage_emit(kwargs, 10)
            return _section()

        with patch("src.backend.ai_pipeline.request_course_with_retry",
                   side_effect=fake_generate) as gen, \
             patch("src.backend.ai_pipeline.explain_course",
                   return_value="这门课先学问候。"):
            state = run_pipeline(
                _config(), _spec(), mode="fast",
                validator=lambda _s: [],
                on_progress=lambda s: progresses.append(s.step),
            )
        gen.assert_called_once()
        self.assertTrue(state.ready_for_import)
        self.assertEqual(state.step, PipelineStep.READY_IMPORT)
        self.assertEqual(state.step_statuses[PipelineStep.OUTLINE], STATUS_SKIPPED)
        # No structural errors -> Fix skipped in fast mode.
        self.assertEqual(state.step_statuses[PipelineStep.FIX], STATUS_SKIPPED)
        self.assertEqual(state.step_statuses[PipelineStep.EXPLAIN], STATUS_DONE)
        self.assertEqual(state.explanation, "这门课先学问候。")
        self.assertIn(PipelineStep.EXTRACT, state.skipped_steps)
        self.assertIsNotNone(state.quality)
        self.assertIn("mean", state.quality)
        self.assertEqual(state.usage_total["total_tokens"], 10)
        self.assertEqual(state.errors, [])
        self.assertTrue(progresses)

    def test_fast_generate_failure_recorded_not_raised(self) -> None:
        with patch("src.backend.ai_pipeline.request_course_with_retry",
                   side_effect=ValueError("boom")):
            state = run_pipeline(_config(), _spec(), mode="fast",
                                 validator=lambda _s: [])
        self.assertEqual(state.step_statuses[PipelineStep.GENERATE], STATUS_FAILED)
        self.assertTrue(any("boom" in e for e in state.errors))
        self.assertFalse(state.ready_for_import)


class PipelineRefineModeTest(unittest.TestCase):
    def _run_refine(self, **kwargs):
        def fake_outline(config, spec, **kw):
            _usage_emit(kw, 6)
            return _outline()

        def fake_fill(config, spec, outline, **kw):
            _usage_emit(kw, 20)
            # lesson progress callback fires on_progress
            cb = kw.get("on_lesson_done")
            if cb:
                cb("u1-l1", 1, 1)
            return _section()

        with patch("src.backend.ai_pipeline.request_outline",
                   side_effect=fake_outline), \
             patch("src.backend.ai_pipeline.fill_lessons_from_outline",
                   side_effect=fake_fill), \
             patch("src.backend.ai_pipeline.explain_course",
                   return_value="解释"):
            return run_pipeline(_config(), _spec(), mode="refine",
                                validator=lambda _s: [], **kwargs)

    def test_refine_happy_path_uses_phased_components(self) -> None:
        progresses: list[PipelineState] = []
        state = self._run_refine(on_progress=progresses.append)
        self.assertTrue(state.ready_for_import)
        self.assertEqual(state.step_statuses[PipelineStep.PLAN], STATUS_DONE)
        self.assertEqual(state.step_statuses[PipelineStep.OUTLINE], STATUS_DONE)
        self.assertEqual(state.step_statuses[PipelineStep.GENERATE], STATUS_DONE)
        self.assertEqual(state.step_statuses[PipelineStep.VALIDATE], STATUS_DONE)
        self.assertEqual(state.step_statuses[PipelineStep.QUALITY], STATUS_DONE)
        # Refine Fix runs its rule-based pass (no LLM loop without errors).
        self.assertEqual(state.step_statuses[PipelineStep.FIX], STATUS_DONE)
        self.assertEqual(state.step_statuses[PipelineStep.EXPLAIN], STATUS_DONE)
        self.assertIsNotNone(state.outline)
        self.assertEqual(state.usage_total["total_tokens"], 26)
        # on_progress fired at least once per step + lesson progress.
        self.assertGreaterEqual(len(progresses), len(state.step_statuses))

    def test_skip_fix_and_explain(self) -> None:
        state = self._run_refine(skip_steps=(PipelineStep.FIX, PipelineStep.EXPLAIN))
        self.assertEqual(state.step_statuses[PipelineStep.FIX], STATUS_SKIPPED)
        self.assertEqual(state.step_statuses[PipelineStep.EXPLAIN], STATUS_SKIPPED)
        self.assertIn(PipelineStep.FIX, state.skipped_steps)
        self.assertIn(PipelineStep.EXPLAIN, state.skipped_steps)
        self.assertEqual(state.explanation, "")
        self.assertTrue(state.ready_for_import)

    def test_resume_reuses_outline_and_draft(self) -> None:
        resume = PipelineState(outline=_outline(), draft=_section())
        with patch("src.backend.ai_pipeline.request_outline") as ol, \
             patch("src.backend.ai_pipeline.fill_lessons_from_outline") as fill, \
             patch("src.backend.ai_pipeline.explain_course", return_value="x"):
            state = run_pipeline(
                _config(), _spec(), mode="refine",
                validator=lambda _s: [],
                skip_steps=(PipelineStep.EXPLAIN,),
                resume_state=resume,
            )
        ol.assert_not_called()
        fill.assert_not_called()
        self.assertEqual(state.step_statuses[PipelineStep.OUTLINE], STATUS_DONE)
        self.assertEqual(state.step_statuses[PipelineStep.GENERATE], STATUS_DONE)
        self.assertTrue(state.ready_for_import)


class PipelineCancelTest(unittest.TestCase):
    def test_cancel_before_first_step(self) -> None:
        state = run_pipeline(
            _config(), _spec(), mode="refine",
            validator=lambda _s: [],
            cancel_check=lambda: True,
        )
        self.assertTrue(state.cancelled)
        self.assertEqual(state.step_statuses[PipelineStep.PLAN], STATUS_FAILED)
        self.assertTrue(any("取消" in e for e in state.errors))
        self.assertIsNone(state.draft)

    def test_cancel_stops_gracefully_mid_pipeline(self) -> None:
        calls = {"n": 0}

        def cancel_check() -> bool:
            calls["n"] += 1
            # Allow plan + outline, cancel when generate is about to run.
            return calls["n"] > 2

        with patch("src.backend.ai_pipeline.request_outline",
                   return_value=_outline()), \
             patch("src.backend.ai_pipeline.fill_lessons_from_outline") as fill:
            state = run_pipeline(
                _config(), _spec(), mode="refine",
                validator=lambda _s: [],
                cancel_check=cancel_check,
            )
        fill.assert_not_called()
        self.assertTrue(state.cancelled)
        self.assertEqual(state.step_statuses[PipelineStep.OUTLINE], STATUS_DONE)
        self.assertEqual(state.step_statuses[PipelineStep.GENERATE], STATUS_FAILED)
        # Partial state (outline) survives for resume.
        self.assertIsNotNone(state.outline)


class PipelineFixTest(unittest.TestCase):
    def test_llm_fix_only_gets_remaining_errors(self) -> None:
        section = _section()
        error = {"level": "error", "path": "units[0]", "message": "坏掉了"}
        warning = {"level": "warning", "message": "只是提醒"}
        validations = {"n": 0}

        def validator(_s):
            validations["n"] += 1
            # First two validations (Validate step + rule-fix re-check) report
            # the error; after the LLM fix the section is clean.
            return [warning] + ([] if validations["n"] > 2 else [error])

        def fake_correction(config, prompt, **kwargs):
            _usage_emit(kwargs, 5)
            return section

        with patch("src.backend.ai_pipeline.request_outline",
                   return_value=_outline()), \
             patch("src.backend.ai_pipeline.fill_lessons_from_outline",
                   return_value=section), \
             patch("src.backend.ai_pipeline.request_correction",
                   side_effect=fake_correction) as fix, \
             patch("src.backend.ai_pipeline.explain_course", return_value="x"):
            state = run_pipeline(
                _config(), _spec(), mode="refine", validator=validator,
                skip_steps=(PipelineStep.EXPLAIN,),
            )
        fix.assert_called_once()
        prompt = fix.call_args.args[1]
        self.assertIn("坏掉了", prompt)
        self.assertNotIn("只是提醒", prompt)  # warnings are not re-fed
        self.assertEqual(state.step_statuses[PipelineStep.FIX], STATUS_DONE)
        self.assertEqual(state.errors, [])
        self.assertTrue(state.ready_for_import)

    def test_fix_rolls_back_when_ids_would_be_removed(self) -> None:
        section = _section()
        existing = _section()
        error = {"level": "error", "message": "bad"}

        def fake_correction(config, prompt, **kwargs):
            fixed = _section()
            fixed["units"] = []  # would silently drop the unit id
            return fixed

        with patch("src.backend.ai_pipeline.request_outline",
                   return_value=_outline()), \
             patch("src.backend.ai_pipeline.fill_lessons_from_outline",
                   return_value=section), \
             patch("src.backend.ai_pipeline.request_correction",
                   side_effect=fake_correction), \
             patch("src.backend.ai_pipeline.explain_course", return_value="x"):
            state = run_pipeline(
                _config(), _spec(), mode="refine",
                validator=lambda _s: [error],
                existing_section=existing,
                skip_steps=(PipelineStep.EXPLAIN,),
            )
        self.assertTrue(any("回滚" in e for e in state.errors))
        # Pre-fix draft kept (unit intact).
        self.assertTrue(state.draft["units"])
        self.assertTrue(state.ready_for_import)

    def test_fix_loop_bounded_by_max_fix_loops(self) -> None:
        error = {"level": "error", "message": "still bad"}

        with patch("src.backend.ai_pipeline.request_outline",
                   return_value=_outline()), \
             patch("src.backend.ai_pipeline.fill_lessons_from_outline",
                   return_value=_section()), \
             patch("src.backend.ai_pipeline.request_correction",
                   return_value=_section()) as fix, \
             patch("src.backend.ai_pipeline.explain_course", return_value="x"):
            state = run_pipeline(
                _config(), _spec(), mode="refine",
                validator=lambda _s: [error],
                max_fix_loops=2,
                skip_steps=(PipelineStep.EXPLAIN,),
            )
        self.assertEqual(fix.call_count, 2)
        self.assertEqual(state.step_statuses[PipelineStep.FIX], STATUS_DONE)
        # Remaining errors are surfaced in problems, not raised.
        self.assertTrue(state.problems)


if __name__ == "__main__":
    unittest.main()
