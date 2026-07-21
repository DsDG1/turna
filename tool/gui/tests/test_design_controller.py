"""Tests for DesignController (connectplan P3-2).

Fake workers make the whole chat → generate → persist cycle testable without
threads, network, or a QApplication.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))
from tests._course_samples import sample_section  # noqa: E402

from src.backend.ai_generator import AiApiConfig, generate_from_chat  # noqa: E402
from src.dialogs.ai.design_controller import DesignController  # noqa: E402


class _FakeSignal:
    def __init__(self) -> None:
        self._callbacks: list = []

    def connect(self, callback) -> None:
        self._callbacks.append(callback)

    def emit(self, *args) -> None:
        for cb in self._callbacks:
            cb(*args)


class _FakeWorker:
    """Records the target/args; emits the canned result on start()."""

    def __init__(self, target, *args, result=None, **kwargs):
        self.target = target
        self.args = args
        self.kwargs = kwargs
        self.result = result
        self.result_ready = _FakeSignal()
        self.error_occurred = _FakeSignal()
        self.chunk_ready = _FakeSignal()
        self.usage_ready = _FakeSignal()
        self.cancelled = False

    def start(self) -> None:
        self.result_ready.emit(self.result)

    def cancel(self) -> None:
        self.cancelled = True


def _factory(records: list, result):
    def factory(target, *args, **kwargs):
        worker = _FakeWorker(target, *args, result=result, **kwargs)
        records.append(worker)
        return worker

    return factory


def _config() -> AiApiConfig:
    return AiApiConfig(base_url="http://localhost", api_key="k", model="m")


class DesignControllerChatTest(unittest.TestCase):
    def setUp(self) -> None:
        self.records: list = []
        self.errors: list[str] = []
        self.busy: list[tuple[bool, str]] = []

    def _controller(self, result, **kwargs) -> DesignController:
        return DesignController(
            ai_config_fn=_config,
            worker_factory=_factory(self.records, result),
            on_error=self.errors.append,
            on_busy_changed=lambda b, s: self.busy.append((b, s)),
            **kwargs,
        )

    def test_send_chat_appends_and_replies(self) -> None:
        ctrl = self._controller("好的，建议先做问候主题。")
        self.assertTrue(ctrl.send_chat("我想做土耳其语问候课"))
        self.assertEqual([m.role for m in ctrl.chat], ["user", "assistant"])
        self.assertEqual(ctrl.chat[1].content, "好的，建议先做问候主题。")
        # Topic anchored to the latest user message.
        self.assertEqual(ctrl.params["topic"], "我想做土耳其语问候课")
        self.assertEqual(self.busy[0], (True, "对话中…"))
        self.assertEqual(self.busy[-1], (False, ""))

    def test_send_chat_requires_api_config(self) -> None:
        ctrl = DesignController(
            ai_config_fn=lambda: AiApiConfig(),
            worker_factory=_factory(self.records, "x"),
            on_error=self.errors.append,
        )
        self.assertFalse(ctrl.send_chat("hello"))
        self.assertTrue(self.errors)
        self.assertEqual(len(ctrl.chat), 0)

    def test_generate_without_topic_errors(self) -> None:
        ctrl = self._controller(sample_section(unit_id="random-u", lesson_id="random-l"))
        self.assertFalse(ctrl.generate())
        self.assertIn("主题", self.errors[-1])


class DesignControllerGenerateTest(unittest.TestCase):
    def test_generate_from_chat_rewrites_ids_deterministically(self) -> None:
        drafts: list[dict] = []
        records: list = []
        ctrl = DesignController(
            ai_config_fn=_config,
            worker_factory=_factory(records, sample_section(unit_id="random-u", lesson_id="random-l")),
            on_draft_ready=drafts.append,
        )
        ctrl.send_chat("做问候课")  # first worker: alignment reply
        self.assertTrue(ctrl.generate())
        self.assertEqual(len(drafts), 1)
        draft = drafts[0]
        # Structural ids rewritten from the section id, not random.
        self.assertEqual(draft["units"][0]["id"], "greetings-u1")
        self.assertEqual(draft["units"][0]["lessons"][0]["id"], "greetings-u1-l1")
        # The chat path was used (chat history present) with draft slot.
        # (records[-1] is the auto-chained explain worker, so filter by target.)
        gen_worker = [r for r in records if r.target is generate_from_chat][-1]
        self.assertIs(gen_worker.target, generate_from_chat)

    def test_generate_without_chat_uses_one_shot_path(self) -> None:
        records: list = []
        drafts: list = []
        ctrl = DesignController(
            ai_config_fn=_config,
            worker_factory=_factory(records, sample_section(unit_id="random-u", lesson_id="random-l")),
            on_draft_ready=drafts.append,
        )
        ctrl.set_params(topic="旅行")
        self.assertTrue(ctrl.generate())
        from src.backend.ai_phased import request_course

        gen_workers = [r for r in records if r.target is request_course]
        self.assertEqual(len(gen_workers), 1)
        self.assertEqual(len(drafts), 1)

    def test_grounded_spec_carries_pool_and_brief(self) -> None:
        records: list = []
        ctrl = DesignController(
            ai_config_fn=_config,
            worker_factory=_factory(records, sample_section(unit_id="random-u", lesson_id="random-l")),
        )
        ctrl.set_resource_pool(
            [{"id": "w-1", "term": "merhaba", "translation": "hello"}]
        )
        ctrl.set_params(topic="问候", design_brief="两单元 intro")
        self.assertTrue(ctrl.generate())
        from src.backend.ai_phased import request_course

        spec = [r for r in records if r.target is request_course][-1].args[1]
        self.assertEqual(spec.resource_pool[0]["id"], "w-1")
        self.assertEqual(spec.design_brief, "两单元 intro")

    def test_busy_guard_blocks_parallel_requests(self) -> None:
        class _HangingWorker(_FakeWorker):
            def start(self) -> None:  # never finishes
                pass

        records: list = []

        def factory(target, *args, **kwargs):
            worker = _HangingWorker(target, *args, **kwargs)
            records.append(worker)
            return worker

        ctrl = DesignController(
            ai_config_fn=_config, worker_factory=factory
        )
        ctrl.set_params(topic="问候")
        self.assertTrue(ctrl.generate())
        self.assertTrue(ctrl.is_busy)
        self.assertFalse(ctrl.generate())
        self.assertFalse(ctrl.send_chat("再来一次"))
        ctrl.cancel()
        self.assertTrue(records[-1].cancelled)


class DesignControllerPersistenceTest(unittest.TestCase):
    def test_design_dict_round_trip(self) -> None:
        ctrl = DesignController(
            ai_config_fn=_config,
            worker_factory=_factory([], "回复"),
        )
        ctrl.set_params(topic="问候", unit_count=2, design_brief="brief")
        ctrl.send_chat("做问候课")
        ctrl._on_draft_generated(sample_section(unit_id="random-u", lesson_id="random-l"))

        data = ctrl.to_design_dict()
        self.assertEqual(len(data["chat_history"]), 2)
        # send_chat anchors the topic to the latest user message.
        self.assertEqual(data["params"]["topic"], "做问候课")
        self.assertEqual(data["params"]["design_brief"], "brief")
        self.assertEqual(len(data["draft_sections"]), 1)

        restored = DesignController(
            ai_config_fn=_config, worker_factory=_factory([], None)
        )
        restored.apply_design_dict(data)
        self.assertEqual([m.role for m in restored.chat], ["user", "assistant"])
        self.assertEqual(restored.params["topic"], "做问候课")
        self.assertEqual(restored.draft["id"], "greetings")

    def test_apply_empty_dict_is_noop(self) -> None:
        restored = DesignController(
            ai_config_fn=_config, worker_factory=_factory([], None)
        )
        restored.apply_design_dict(None)
        self.assertEqual(restored.chat, [])
        self.assertIsNone(restored.draft)

    def test_usage_accumulates(self) -> None:
        usages: list[dict] = []
        records: list = []
        ctrl = DesignController(
            ai_config_fn=_config,
            worker_factory=_factory(records, sample_section(unit_id="random-u", lesson_id="random-l")),
            on_usage_update=usages.append,
        )
        ctrl.set_params(topic="问候")
        ctrl.generate()
        from src.backend.ai_phased import request_course

        worker = [r for r in records if r.target is request_course][-1]
        # Real workers emit usage mid-flight (before the result); the fake
        # already delivered its result synchronously in start(), so re-mark
        # it as the active worker — usage from non-active workers is dropped.
        ctrl._worker = worker
        worker.usage_ready.emit(
            {"prompt_tokens": 10, "completion_tokens": 5, "total_tokens": 15}
        )
        self.assertEqual(usages[-1]["total_tokens"], 15)
        self.assertEqual(ctrl.usage["prompt_tokens"], 10)


class DesignControllerPhaseCTest(unittest.TestCase):
    """Phase C: attachments, explain chain, settings injection, genre, sanitize."""

    def test_send_chat_with_attachments_builds_content_pieces(self) -> None:
        records: list = []
        ctrl = DesignController(
            ai_config_fn=_config,
            worker_factory=_factory(records, "好的"),
        )

        class _Rec:
            def __init__(self, content):
                self.content = content

        ok = ctrl.send_chat(
            "参考这张图做课",
            [
                _Rec({"type": "image_url", "image_url": {"url": "data:..."}}),
                _Rec({"type": "text", "text": "extracted text"}),
            ],
        )
        self.assertTrue(ok)
        content = ctrl.chat[0].content
        self.assertIsInstance(content, list)
        self.assertEqual(content[0], {"type": "text", "text": "参考这张图做课"})
        self.assertEqual(content[1]["type"], "image_url")
        self.assertEqual(content[2]["text"], "extracted text")

    def test_explain_chain_runs_after_draft(self) -> None:
        from src.backend.ai_generator import explain_course

        records: list = []
        explanations: list[str] = []
        ctrl = DesignController(
            ai_config_fn=_config,
            worker_factory=_factory(records, sample_section(unit_id="random-u", lesson_id="random-l")),
            on_explanation=explanations.append,
        )
        ctrl.set_params(topic="问候")
        self.assertTrue(ctrl.generate())
        explain_workers = [r for r in records if r.target is explain_course]
        self.assertEqual(len(explain_workers), 1)
        # explain args: (config, spec, section)
        self.assertEqual(explain_workers[0].args[2]["id"], "greetings")
        # The canned result doubles as the explanation text.
        self.assertTrue(explanations)
        self.assertEqual(ctrl.explanation, explanations[-1])
        self.assertEqual(ctrl.to_design_dict()["explanation"], explanations[-1])

    def test_explain_error_routes_off_popup_channel(self) -> None:
        from src.backend.ai_generator import explain_course

        class _ErrorWorker(_FakeWorker):
            def start(self) -> None:
                self.error_occurred.emit("boom")

        records: list = []
        explain_errors: list[str] = []
        errors: list[str] = []

        def factory(target, *args, **kwargs):
            if target is explain_course:
                worker = _ErrorWorker(target, *args, **kwargs)
            else:
                worker = _FakeWorker(target, *args, result=sample_section(unit_id="random-u", lesson_id="random-l"), **kwargs)
            records.append(worker)
            return worker

        ctrl = DesignController(
            ai_config_fn=_config,
            worker_factory=factory,
            on_error=errors.append,
            on_explanation_error=explain_errors.append,
        )
        ctrl.set_params(topic="问候")
        ctrl.generate()
        self.assertEqual(explain_errors, ["boom"])
        self.assertEqual(errors, [])

    def test_settings_injected_into_worker_kwargs(self) -> None:
        from src.backend.ai_phased import request_course

        class _Settings:
            ai_timeout = 33.0
            ai_temperature = 0.5
            ai_retry_max = 4

        records: list = []
        ctrl = DesignController(
            ai_config_fn=_config,
            worker_factory=_factory(records, sample_section(unit_id="random-u", lesson_id="random-l")),
            settings_fn=_Settings,
        )
        ctrl.set_params(topic="问候")
        ctrl.generate()
        worker = [r for r in records if r.target is request_course][-1]
        self.assertEqual(worker.kwargs["timeout"], 33.0)
        self.assertEqual(worker.kwargs["temperature"], 0.5)
        self.assertEqual(worker.kwargs["max_retries"], 4)

    def test_genre_batch_replaces_template(self) -> None:
        from src.backend.ai_phased import request_course

        records: list = []
        ctrl = DesignController(
            ai_config_fn=_config,
            worker_factory=_factory(records, sample_section(unit_id="random-u", lesson_id="random-l")),
        )
        ctrl.set_params(topic="[listening] 机场对话", use_genre_batch=True)
        spec = ctrl.build_spec()
        self.assertEqual(spec.template, "listening")
        ctrl.generate()
        sent = [r for r in records if r.target is request_course][-1].args[1]
        self.assertEqual(sent.template, "listening")

    def test_design_dict_sanitizes_image_content(self) -> None:
        ctrl = DesignController(
            ai_config_fn=_config,
            worker_factory=_factory([], "好的"),
        )

        class _Rec:
            content = {"type": "image_url", "image_url": {"url": "data:base64..."}}

        ctrl.send_chat("看图做课", [_Rec()])
        data = ctrl.to_design_dict()
        content = data["chat_history"][0]["content"]
        # base64 本体不落盘 — image pieces degrade to a placeholder.
        texts = [p["text"] for p in content if p["type"] == "text"]
        self.assertIn("[图片附件]", texts)
        self.assertNotIn("data:base64...", str(data))

    def test_explanation_restored_from_design_dict(self) -> None:
        explanations: list[str] = []
        restored = DesignController(
            ai_config_fn=_config,
            worker_factory=_factory([], None),
            on_explanation=explanations.append,
        )
        restored.apply_design_dict({"explanation": "这门课先学问候。"})
        self.assertEqual(restored.explanation, "这门课先学问候。")
        self.assertEqual(explanations, ["这门课先学问候。"])


class DesignControllerLocalRegenTest(unittest.TestCase):
    def test_regenerate_lesson_requires_draft(self) -> None:
        errors: list[str] = []
        ctrl = DesignController(
            ai_config_fn=_config,
            worker_factory=_factory([], None),
            on_error=errors.append,
        )
        self.assertFalse(ctrl.regenerate_lesson("l1"))
        self.assertTrue(errors)

    def test_regenerate_lesson_starts_worker(self) -> None:
        from src.backend.ai_generator import regenerate_lesson_in_section

        records: list = []
        section = sample_section(unit_id="random-u", lesson_id="random-l")
        ctrl = DesignController(
            ai_config_fn=_config,
            worker_factory=_factory(records, section),
        )
        ctrl.set_draft(section)
        self.assertTrue(ctrl.regenerate_lesson("random-l"))
        # Fake worker completes immediately → explain chain may spawn a 2nd worker.
        self.assertGreaterEqual(len(records), 1)
        self.assertIs(records[0].target, regenerate_lesson_in_section)
        self.assertIsNotNone(ctrl._draft_checkpoint)

    def test_restore_draft_checkpoint(self) -> None:
        drafts: list = []
        ctrl = DesignController(
            ai_config_fn=_config,
            worker_factory=_factory([], None),
            on_draft_ready=drafts.append,
        )
        original = sample_section(unit_id="random-u", lesson_id="random-l")
        ctrl.set_draft(original)
        ctrl._draft_checkpoint = original
        ctrl.set_draft({"id": "other", "units": [], "words": []})
        self.assertTrue(ctrl.restore_draft_checkpoint())
        self.assertEqual(ctrl.draft["id"], "greetings")
        self.assertTrue(drafts)


class DesignControllerPipelineTest(unittest.TestCase):
    """Phase 5 (批次②): refine mode runs the ai_pipeline state machine."""

    def _pipeline_state(self, **kwargs) -> "PipelineState":
        from src.backend.ai_pipeline import PipelineState, PipelineStep

        kwargs.setdefault("step", PipelineStep.READY_IMPORT)
        return PipelineState(**kwargs)

    def test_refine_mode_dispatches_run_pipeline(self) -> None:
        from src.backend.ai_generator import explain_course
        from src.backend.ai_pipeline import run_pipeline

        records: list = []
        drafts: list = []
        explanations: list[str] = []
        state = self._pipeline_state(
            draft=sample_section(unit_id="random-u", lesson_id="random-l"),
            explanation="这门课先学问候。",
        )
        ctrl = DesignController(
            ai_config_fn=_config,
            worker_factory=_factory(records, state),
            on_draft_ready=drafts.append,
            on_explanation=explanations.append,
        )
        ctrl.set_params(topic="问候", generation_mode="phased")
        self.assertTrue(ctrl.generate())
        gen = [r for r in records if r.target is run_pipeline]
        self.assertEqual(len(gen), 1)
        self.assertEqual(gen[0].kwargs["mode"], "refine")
        self.assertEqual(gen[0].args[1].topic, "问候")
        # Draft landed through the normal ready channel; explanation came
        # from the pipeline, so no separate explain worker was chained.
        self.assertEqual(len(drafts), 1)
        self.assertEqual(drafts[0]["units"][0]["id"], "greetings-u1")
        self.assertEqual(explanations, ["这门课先学问候。"])
        self.assertFalse([r for r in records if r.target is explain_course])
        # Clean completion clears the resume snapshot.
        self.assertIsNone(ctrl.pipeline_state)
        self.assertNotIn("pipeline", ctrl.to_design_dict())

    def test_refine_skip_switches_map_to_skip_steps(self) -> None:
        from src.backend.ai_pipeline import run_pipeline

        records: list = []
        ctrl = DesignController(
            ai_config_fn=_config,
            worker_factory=_factory(records, self._pipeline_state()),
        )
        ctrl.set_params(
            topic="问候",
            generation_mode="phased",
            pipeline_skip_fix=True,
            pipeline_skip_explain=True,
        )
        self.assertTrue(ctrl.generate())
        worker = [r for r in records if r.target is run_pipeline][-1]
        self.assertEqual(worker.kwargs["skip_steps"], ("fix", "explain"))

    def test_cancelled_pipeline_keeps_snapshot_for_resume(self) -> None:
        from src.backend.ai_pipeline import PipelineStep

        outline = {"id": "greetings", "units": []}
        state = self._pipeline_state(
            step=PipelineStep.GENERATE,
            outline=outline,
            cancelled=True,
            errors=["请求已取消。"],
        )
        records: list = []
        errors: list[str] = []
        ctrl = DesignController(
            ai_config_fn=_config,
            worker_factory=_factory(records, state),
            on_error=errors.append,
        )
        ctrl.set_params(topic="问候", generation_mode="phased")
        self.assertTrue(ctrl.generate())
        # Graceful cancel: no blocking error, snapshot persisted.
        self.assertEqual(errors, [])
        self.assertIsNotNone(ctrl.pipeline_state)
        saved = ctrl.to_design_dict()
        self.assertEqual(saved["pipeline"]["outline"], outline)
        self.assertTrue(saved["pipeline"]["cancelled"])

        # Reopen: the restored snapshot is offered as resume_state.
        restored_records: list = []
        restored = DesignController(
            ai_config_fn=_config,
            worker_factory=_factory(restored_records, self._pipeline_state()),
        )
        restored.apply_design_dict(saved)
        self.assertIsNotNone(restored.pipeline_state)
        restored.set_params(topic="问候", generation_mode="phased")
        self.assertTrue(restored.generate())
        from src.backend.ai_pipeline import run_pipeline

        worker = [r for r in restored_records if r.target is run_pipeline][-1]
        self.assertIsNotNone(worker.kwargs["resume_state"])
        self.assertEqual(worker.kwargs["resume_state"].outline, outline)

    def test_pipeline_failure_without_draft_surfaces_error(self) -> None:
        state = self._pipeline_state(errors=["outline: 大纲仍无效：缺少 id"])
        records: list = []
        errors: list[str] = []
        ctrl = DesignController(
            ai_config_fn=_config,
            worker_factory=_factory(records, state),
            on_error=errors.append,
        )
        ctrl.set_params(topic="问候", generation_mode="phased")
        self.assertTrue(ctrl.generate())
        self.assertTrue(errors)
        self.assertIn("大纲", errors[-1])

    def test_pipeline_progress_finalizes_cancel_without_result(self) -> None:
        """Real workers drop the result on cancel; progress must finalize."""
        from src.backend.ai_pipeline import PipelineStep

        records: list = []
        busy: list[tuple[bool, str]] = []

        class _HangingWorker(_FakeWorker):
            def start(self) -> None:  # never emits a result
                pass

        def factory(target, *args, **kwargs):
            worker = _HangingWorker(target, *args, **kwargs)
            records.append(worker)
            return worker

        ctrl = DesignController(
            ai_config_fn=_config,
            worker_factory=factory,
            on_busy_changed=lambda b, s: busy.append((b, s)),
        )
        ctrl.set_params(topic="问候", generation_mode="phased")
        self.assertTrue(ctrl.generate())
        self.assertTrue(ctrl.is_busy)
        cancelled = self._pipeline_state(
            step=PipelineStep.GENERATE, cancelled=True, errors=["请求已取消。"]
        )
        ctrl._on_pipeline_progress(cancelled)
        self.assertFalse(ctrl.is_busy)
        self.assertEqual(busy[-1], (False, ""))
        self.assertIs(ctrl.pipeline_state, cancelled)


if __name__ == "__main__":
    unittest.main()
