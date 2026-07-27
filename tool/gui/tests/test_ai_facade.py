"""Tests for src.backend.ai.facade (M2 generate_course entry)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest import mock

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.ai.config import AiApiConfig, AiCourseSpec, ChatMessage  # noqa: E402
from src.backend.ai.facade import (  # noqa: E402
    GenerateResult,
    PipelineOptions,
    generate_course,
    normalize_generation_mode,
)
from src.backend.ai_pipeline import PipelineState, PipelineStep  # noqa: E402


class NormalizeModeTest(unittest.TestCase):
    def test_aliases(self) -> None:
        self.assertEqual(normalize_generation_mode("fast"), "fast")
        self.assertEqual(normalize_generation_mode("refine"), "refine")
        self.assertEqual(normalize_generation_mode("phased"), "refine")
        self.assertEqual(normalize_generation_mode("PHASED"), "refine")
        self.assertEqual(normalize_generation_mode(None), "fast")
        self.assertEqual(normalize_generation_mode(""), "fast")


class GenerateCourseDispatchTest(unittest.TestCase):
    def _cfg(self) -> AiApiConfig:
        return AiApiConfig(base_url="http://x", api_key="k", model="m")

    def _spec(self) -> AiCourseSpec:
        return AiCourseSpec(topic="问候", language="Turkish", source_language="Chinese")

    def test_chat_path_uses_generate_from_chat(self) -> None:
        draft = {"id": "s1", "units": []}
        with mock.patch(
            "src.backend.ai.facade.generate_from_chat", return_value=draft
        ) as m:
            result = generate_course(
                self._cfg(),
                self._spec(),
                mode="refine",
                chat_history=[ChatMessage(role="user", content="hi")],
            )
        self.assertIsInstance(result, GenerateResult)
        self.assertEqual(result.draft, draft)
        self.assertIsNone(result.pipeline_state)
        m.assert_called_once()

    def test_fast_path_uses_retry_not_pipeline(self) -> None:
        draft = {"id": "s1", "units": []}
        with mock.patch(
            "src.backend.ai.facade.request_course_with_retry", return_value=draft
        ) as m_req, mock.patch(
            "src.backend.ai_pipeline.run_pipeline"
        ) as m_pipe:
            result = generate_course(
                self._cfg(),
                self._spec(),
                mode="fast",
                validator=lambda _s: [],
            )
        self.assertEqual(result.mode, "fast")
        self.assertEqual(result.draft, draft)
        m_req.assert_called_once()
        m_pipe.assert_not_called()

    def test_refine_alias_phased_runs_pipeline(self) -> None:
        state = PipelineState(
            step=PipelineStep.READY_IMPORT,
            mode="refine",
            draft={"id": "s1", "units": []},
            explanation="ok",
        )
        with mock.patch(
            "src.backend.ai_pipeline.run_pipeline", return_value=state
        ) as m_pipe:
            result = generate_course(
                self._cfg(),
                self._spec(),
                mode="phased",
                validator=lambda _s: [],
                pipeline_options=PipelineOptions(skip_steps=("fix",)),
            )
        self.assertEqual(result.mode, "refine")
        self.assertIs(result.pipeline_state, state)
        self.assertEqual(result.draft, state.draft)
        self.assertEqual(result.explanation, "ok")
        m_pipe.assert_called_once()
        self.assertEqual(m_pipe.call_args.kwargs["mode"], "refine")
        self.assertEqual(m_pipe.call_args.kwargs["skip_steps"], ("fix",))


if __name__ == "__main__":
    unittest.main()
