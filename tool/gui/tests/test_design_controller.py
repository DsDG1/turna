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


def _section() -> dict:
    return {
        "id": "greetings",
        "name": "Greetings",
        "units": [
            {
                "id": "random-u",
                "name": "U1",
                "lessons": [
                    {
                        "id": "random-l",
                        "name": "L1",
                        "template": "intro",
                        "content": {"subLessons": []},
                    }
                ],
            }
        ],
        "words": [{"id": "w-1", "term": "merhaba", "translation": "hello"}],
    }


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
        ctrl = self._controller(_section())
        self.assertFalse(ctrl.generate())
        self.assertIn("主题", self.errors[-1])


class DesignControllerGenerateTest(unittest.TestCase):
    def test_generate_from_chat_rewrites_ids_deterministically(self) -> None:
        drafts: list[dict] = []
        records: list = []
        ctrl = DesignController(
            ai_config_fn=_config,
            worker_factory=_factory(records, _section()),
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
        gen_worker = records[-1]
        self.assertIs(gen_worker.target, generate_from_chat)

    def test_generate_without_chat_uses_one_shot_path(self) -> None:
        records: list = []
        drafts: list = []
        ctrl = DesignController(
            ai_config_fn=_config,
            worker_factory=_factory(records, _section()),
            on_draft_ready=drafts.append,
        )
        ctrl.set_params(topic="旅行")
        self.assertTrue(ctrl.generate())
        from src.backend.ai_generator import request_course_with_retry

        self.assertIs(records[-1].target, request_course_with_retry)
        self.assertEqual(len(drafts), 1)

    def test_grounded_spec_carries_pool_and_brief(self) -> None:
        records: list = []
        ctrl = DesignController(
            ai_config_fn=_config,
            worker_factory=_factory(records, _section()),
        )
        ctrl.set_resource_pool(
            [{"id": "w-1", "term": "merhaba", "translation": "hello"}]
        )
        ctrl.set_params(topic="问候", design_brief="两单元 intro")
        self.assertTrue(ctrl.generate())
        spec = records[-1].args[1]
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
        ctrl._on_draft_generated(_section())

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
            worker_factory=_factory(records, _section()),
            on_usage_update=usages.append,
        )
        ctrl.set_params(topic="问候")
        ctrl.generate()
        worker = records[-1]
        worker.usage_ready.emit(
            {"prompt_tokens": 10, "completion_tokens": 5, "total_tokens": 15}
        )
        self.assertEqual(usages[-1]["total_tokens"], 15)
        self.assertEqual(ctrl.usage["prompt_tokens"], 10)


if __name__ == "__main__":
    unittest.main()
