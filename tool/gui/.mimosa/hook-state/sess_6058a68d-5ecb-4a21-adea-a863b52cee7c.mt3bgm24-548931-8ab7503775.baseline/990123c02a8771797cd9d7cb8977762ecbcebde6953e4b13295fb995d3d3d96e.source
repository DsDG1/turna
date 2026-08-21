"""V-02 (v4.53): resource.batch_polish skill (pure + handler + collector + route).

Pure-module tests (L1 fast): the handler is driven through a fake host with
``safe_question`` patched and an inline fake AI worker, so no Qt application
object is constructed here.
"""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.experience.actions import (  # noqa: E402
    DANGEROUS_ACTION_IDS,
    get_action,
)
from src.backend.experience.intent_router import match_commands, route_intent  # noqa: E402
from src.backend.experience.pos_constants import POS_TAGS  # noqa: E402
from src.backend.experience.resource_batch_skill import (  # noqa: E402
    ACTION_ID,
    POLISH_FIELDS,
    build_batch_polish_messages,
    parse_batch_polish_reply,
    run_batch_polish,
)


def _entries():
    return [
        {
            "id": "w1",
            "kind": "vocab",
            "term": "merhaba",
            "translation": "",
            "pronunciation": "",
            "pos": "",
        },
        {
            "id": "e1",
            "kind": "expressions",
            "term": "nasilsin",
            "translation": "你好吗",
            "pronunciation": "",
            "pos": "",
        },
    ]


class BuildMessagesTest(unittest.TestCase):
    def test_system_user_and_whitelist_fields(self):
        msgs = build_batch_polish_messages(_entries())
        self.assertEqual(len(msgs), 2)
        self.assertEqual(msgs[0]["role"], "system")
        prompt = msgs[1]["content"]
        for f in POLISH_FIELDS:
            self.assertIn(f, prompt)
        for tag in POS_TAGS:
            self.assertIn(tag, prompt)  # pos 闭集列入 prompt
        self.assertIn("w1", prompt)
        self.assertIn("e1", prompt)

    def test_fields_filtered_to_whitelist(self):
        msgs = build_batch_polish_messages(
            _entries(), fields=("translation", "bogus", "id")
        )
        prompt = msgs[1]["content"]
        self.assertIn("translation", prompt)
        # 白名单外字段不进指令（id 只作为 JSON 键出现要求不变，检查指令句）
        self.assertNotIn("bogus", prompt)
        self.assertNotIn("pronunciation 给出", prompt)

    def test_entries_truncated(self):
        entries = _entries() + [
            {"id": "w3", "kind": "vocab", "term": "x",
             "translation": "", "pronunciation": "", "pos": ""}
        ]
        msgs = build_batch_polish_messages(entries, max_entries=2)
        prompt = msgs[1]["content"]
        self.assertIn("w1", prompt)
        self.assertNotIn("w3", prompt)

    def test_never_raises_on_garbage(self):
        msgs = build_batch_polish_messages([None, "junk", {"id": ""}])
        self.assertEqual(len(msgs), 2)


class ParseReplyTest(unittest.TestCase):
    def test_keeps_valid(self):
        out = parse_batch_polish_reply(
            {"entries": [
                {"id": "w1", "field": "translation", "value": "你好"},
                {"id": "w1", "field": "pos", "value": "Noun"},
                {"id": "e1", "field": "pronunciation", "value": "na-sil-sin"},
            ]},
            allowed_ids={"w1", "e1"},
            allowed_fields=POLISH_FIELDS,
        )
        self.assertEqual(
            out,
            {
                ("w1", "translation"): "你好",
                ("w1", "pos"): "noun",  # POS 闭集归一
                ("e1", "pronunciation"): "na-sil-sin",
            },
        )

    def test_drops_unknown_id_bad_field_empty_value(self):
        out = parse_batch_polish_reply(
            {"entries": [
                {"id": "w9", "field": "translation", "value": "x"},  # 未知 id
                {"id": "w1", "field": "term", "value": "hack"},  # 越界 field
                {"id": "w1", "field": "id", "value": "hack"},  # 越界 field
                {"id": "w1", "field": "translation", "value": "  "},  # 空 value
                {"id": "w1", "field": "pos", "value": "bogus"},  # POS 越界
                "junk",
            ]},
            allowed_ids={"w1"},
            allowed_fields=POLISH_FIELDS,
        )
        self.assertEqual(out, {})

    def test_allowed_fields_restricted(self):
        out = parse_batch_polish_reply(
            {"entries": [{"id": "w1", "field": "pos", "value": "noun"}]},
            allowed_ids={"w1"},
            allowed_fields=("translation", "pronunciation"),
        )
        self.assertEqual(out, {})

    def test_garbage_returns_empty(self):
        self.assertEqual(
            parse_batch_polish_reply("not json", allowed_ids=set(), allowed_fields=()), {}
        )
        self.assertEqual(
            parse_batch_polish_reply(None, allowed_ids=None, allowed_fields=None), {}
        )
        self.assertEqual(
            parse_batch_polish_reply("", allowed_ids={"w1"}, allowed_fields=POLISH_FIELDS), {}
        )
        self.assertEqual(
            parse_batch_polish_reply(
                {"entries": "junk"}, allowed_ids={"w1"}, allowed_fields=POLISH_FIELDS
            ),
            {},
        )

    def test_json_string_and_markdown_fence(self):
        raw = "```json\n" + json.dumps(
            {"entries": [{"id": "w1", "field": "translation", "value": "你好"}]},
            ensure_ascii=False,
        ) + "\n```"
        out = parse_batch_polish_reply(
            raw, allowed_ids={"w1"}, allowed_fields=POLISH_FIELDS
        )
        self.assertEqual(out, {("w1", "translation"): "你好"})


class RunSkillTest(unittest.TestCase):
    def test_runs_and_parses_completion_envelope(self):
        import src.backend.ai_generator as ai_gen

        body = {
            "choices": [
                {"message": {"content": json.dumps(
                    {"entries": [{"id": "w1", "field": "translation", "value": "你好"}]},
                    ensure_ascii=False,
                )}}
            ]
        }
        orig = ai_gen.request_chat
        ai_gen.request_chat = lambda *a, **k: body  # type: ignore[assignment]
        try:
            out = run_batch_polish(SimpleNamespace(is_complete=True), _entries())
        finally:
            ai_gen.request_chat = orig
        self.assertEqual(out, {("w1", "translation"): "你好"})

    def test_expressions_only_drops_pos_field(self):
        import src.backend.ai_generator as ai_gen

        body = {"entries": [
            {"id": "e1", "field": "pos", "value": "noun"},  # pos 不在白名单
            {"id": "e1", "field": "pronunciation", "value": "na-sil-sin"},
        ]}
        orig = ai_gen.request_chat
        ai_gen.request_chat = lambda *a, **k: body  # type: ignore[assignment]
        try:
            out = run_batch_polish(
                SimpleNamespace(is_complete=True), [_entries()[1]]
            )
        finally:
            ai_gen.request_chat = orig
        self.assertEqual(out, {("e1", "pronunciation"): "na-sil-sin"})

    def test_failure_returns_empty(self):
        import src.backend.ai_generator as ai_gen

        def boom(*a, **k):
            raise RuntimeError("net down")

        orig = ai_gen.request_chat
        ai_gen.request_chat = boom  # type: ignore[assignment]
        try:
            self.assertEqual(run_batch_polish(SimpleNamespace(), _entries()), {})
            self.assertEqual(run_batch_polish(SimpleNamespace(), []), {})
        finally:
            ai_gen.request_chat = orig


class CollectorTest(unittest.TestCase):
    """p2_resources: first surface-aware collector (surface=resources)."""

    def _ctx(self, surface, multi):
        from src.backend.experience.context_bus import ExperienceContext

        return ExperienceContext(
            surface=surface,
            multi_selection=list(multi),
            empty_lesson_count=0,
            validate_error_count=0,
            hygiene={"placeholder_count": 0, "needs_review_count": 0},
        )

    def test_resources_surface_multi_vocab_suggests(self):
        from src.backend.experience.context_bus import local_suggestions

        ctx = self._ctx("resources", [("vocab", "w1"), ("expressions", "e1")])
        sugs = [s for s in local_suggestions(ctx, limit=3)
                if s["action_id"] == ACTION_ID]
        self.assertEqual(len(sugs), 1)
        s = sugs[0]
        self.assertEqual(s["priority"], 2)
        self.assertIn("2", s["title"])
        self.assertEqual(
            s["scope"], {"count": 2, "entry_ids": ["vocab:w1", "expressions:e1"]}
        )

    def test_scope_closed_set_no_term(self):
        from src.backend.experience.context_bus import local_suggestions

        ctx = self._ctx("resources", [("vocab", "secret-id")])
        sugs = [s for s in local_suggestions(ctx, limit=3)
                if s["action_id"] == ACTION_ID]
        self.assertEqual(len(sugs), 1)
        self.assertEqual(set(sugs[0]["scope"].keys()), {"count", "entry_ids"})
        self.assertNotIn("term", str(sugs[0]["scope"]))

    def test_non_resources_surface_no_suggestion(self):
        from src.backend.experience.context_bus import local_suggestions

        ctx = self._ctx("tree", [("vocab", "w1"), ("vocab", "w2")])
        ids = [s["action_id"] for s in local_suggestions(ctx, limit=5)]
        self.assertNotIn(ACTION_ID, ids)

    def test_empty_multi_or_mixed_kinds_no_suggestion(self):
        from src.backend.experience.context_bus import local_suggestions

        ctx = self._ctx("resources", [])
        ids = [s["action_id"] for s in local_suggestions(ctx, limit=5)]
        self.assertNotIn(ACTION_ID, ids)
        ctx2 = self._ctx("resources", [("vocab", "w1"), ("lesson", "l1")])
        ids2 = [s["action_id"] for s in local_suggestions(ctx2, limit=5)]
        self.assertNotIn(ACTION_ID, ids2)


class _Status:
    def __init__(self, host):
        self._host = host

    def showMessage(self, msg, _ms=0):  # noqa: N802
        self._host._status.append(msg)


def _make_signal():
    sig = MagicMock()
    sig._handlers = []

    def connect(handler):
        sig._handlers.append(handler)

    sig.connect = connect
    return sig


def _fake_worker_factory():
    def factory(target, *args, **kwargs):
        w = SimpleNamespace()
        w.result_ready = _make_signal()
        w.error_occurred = _make_signal()

        def start(*a, **k):
            try:
                result = target(*args, **kwargs)
            except Exception as exc:  # noqa: BLE001
                for cb in list(w.error_occurred._handlers):
                    cb(str(exc))
            else:
                for cb in list(w.result_ready._handlers):
                    cb(result)

        w.start = start
        return w

    return factory


class BatchPolishHandlerTest(unittest.TestCase):
    def _make_host(self, vocab, expressions, *, ai_complete=True, mapping=None):
        from src.backend.experience.job_registry import JobRegistry
        from src.backend.experience.metrics import ExperienceMetrics

        class Host:
            def __init__(self) -> None:
                self.adapter = SimpleNamespace(
                    vocab=list(vocab),
                    expressions=list(expressions),
                    grammar_points=[],
                    index={"language": "tr"},
                )
                self._ai_config = SimpleNamespace(is_complete=ai_complete)
                self.job_tray = JobRegistry()
                self.experience_metrics = ExperienceMetrics()
                self.undo_stack = MagicMock()
                self._status: list[str] = []
                self._events: list = []
                self._experience_worker = None
                self._deny = False
                self._make_ai_worker = _fake_worker_factory()
                self.experience = SimpleNamespace(
                    context=SimpleNamespace(multi_selection=[])
                )

            def statusBar(self):  # noqa: N802
                return _Status(self)

            def _record_experience_event(self, *a, **k):
                self._events.append((a, k))

            def _refresh_experience(self, *a, **k):
                pass

            def _refresh_validate_after_ai(self):
                pass

            def _on_ai_edit_applied(self):
                pass

            def _deny_ai_write_if_blocked(self, *, label="AI"):
                return self._deny

        host = Host()
        target = mapping if mapping is not None else {}
        self._runpatch = patch(
            "src.backend.experience.resource_batch_skill.run_batch_polish",
            return_value=target,
        )
        self._runpatch.start()
        self.addCleanup(self._runpatch.stop)
        return host

    def _call(self, host, scope, *, confirm=True):
        from src.application.experience_handlers.resources import handle_batch_polish

        with patch(
            "src.application.experience_handlers.resources.safe_question",
            return_value=confirm,
        ):
            handle_batch_polish(host, scope)

    _VOCAB = [{"id": "w1", "term": "merhaba", "translation": "", "pos": None}]
    _EXPR = [{"id": "e1", "term": "nasilsin", "translation": "你好吗"}]
    _SCOPE = {"entries": [("vocab", "w1"), ("expressions", "e1")]}

    def test_no_selection_status(self):
        host = self._make_host(self._VOCAB, self._EXPR)
        self._call(host, {})
        self.assertTrue(any("请先" in m and "多选" in m for m in host._status))
        self.assertEqual(host.undo_stack.push.call_count, 0)

    def test_ctx_multi_selection_fallback(self):
        host = self._make_host(self._VOCAB, self._EXPR)
        host.experience.context = SimpleNamespace(
            multi_selection=[("vocab", "w1"), ("lesson", "l9"), ("vocab", "w1")]
        )
        self._call(host, {}, confirm=False)
        # lesson 被过滤、w1 去重后仍有选中 -> 走确认（拒绝计 rejected）
        by_action = host.experience_metrics.snapshot().get("suggestion_by_action", {})
        self.assertEqual(by_action.get(ACTION_ID, {}).get("rejected"), 1)

    def test_confirm_runs_worker_apply_undo(self):
        host = self._make_host(
            self._VOCAB,
            self._EXPR,
            mapping={
                ("w1", "translation"): "你好",
                ("w1", "pos"): "interjection",
                ("e1", "pronunciation"): "na-sil-sin",
                ("w9", "translation"): "ghost",  # 未选中 -> 丢
            },
        )
        self._call(host, self._SCOPE)
        self.assertEqual(host.undo_stack.push.call_count, 1)
        cmd = host.undo_stack.push.call_args[0][0]
        self.assertEqual(cmd.text(), "批量润色词条（3 处）")
        word = host.adapter.vocab[0]
        expr = host.adapter.expressions[0]
        cmd.redo()
        self.assertEqual(word["translation"], "你好")
        self.assertEqual(word["pos"], "interjection")
        self.assertEqual(expr["pronunciation"], "na-sil-sin")
        self.assertEqual(word["id"], "w1")  # 保 id
        cmd.undo()
        self.assertEqual(word["translation"], "")
        self.assertIsNone(word["pos"])
        self.assertIsNone(expr.get("pronunciation"))  # undo 回写旧值 None
        # timeline 闭集 scope：只有 count，无 term/原文
        args, kwargs = host._events[-1]
        self.assertEqual(kwargs.get("action_id"), ACTION_ID)
        self.assertEqual(kwargs.get("scope"), {"count": 3})
        self.assertNotIn("merhaba", str(host._events))
        self.assertNotIn("nasilsin", str(host._events))
        by_action = host.experience_metrics.snapshot().get("suggestion_by_action", {})
        self.assertEqual(by_action.get(ACTION_ID, {}).get("applied"), 1)

    def test_expressions_pos_patch_dropped(self):
        host = self._make_host(
            [],
            self._EXPR,
            mapping={("e1", "pos"): "noun", ("e1", "translation"): "你好吗呀"},
        )
        self._call(host, {"entries": [("expressions", "e1")]})
        self.assertEqual(host.undo_stack.push.call_count, 1)
        cmd = host.undo_stack.push.call_args[0][0]
        self.assertEqual(cmd.text(), "批量润色词条（1 处）")  # pos 补丁被丢
        cmd.redo()
        self.assertEqual(host.adapter.expressions[0]["translation"], "你好吗呀")
        self.assertNotIn("pos", host.adapter.expressions[0])

    def test_rejected_counts_rejected(self):
        host = self._make_host(self._VOCAB, self._EXPR)
        self._call(host, self._SCOPE, confirm=False)
        self.assertEqual(host.undo_stack.push.call_count, 0)
        by_action = host.experience_metrics.snapshot().get("suggestion_by_action", {})
        self.assertEqual(by_action.get(ACTION_ID, {}).get("rejected"), 1)

    def test_no_config_status(self):
        host = self._make_host(self._VOCAB, self._EXPR, ai_complete=False)
        self._call(host, self._SCOPE)
        self.assertTrue(any("配置不完整" in m for m in host._status))
        self.assertEqual(host.undo_stack.push.call_count, 0)

    def test_budget_denied_blocks(self):
        host = self._make_host(self._VOCAB, self._EXPR)
        host._deny = True
        self._call(host, self._SCOPE)
        self.assertEqual(host.undo_stack.push.call_count, 0)

    def test_empty_mapping_status(self):
        host = self._make_host(self._VOCAB, self._EXPR, mapping={})
        self._call(host, self._SCOPE)
        self.assertEqual(host.undo_stack.push.call_count, 0)
        self.assertTrue(any("未给出可用建议" in m for m in host._status))


class ContractAndRoutingTest(unittest.TestCase):
    def test_action_registered_write_not_dangerous(self):
        spec = get_action(ACTION_ID)
        self.assertIsNotNone(spec)
        self.assertTrue(spec.needs_confirm)  # 写操作：预览 + 确认 + Undo
        self.assertFalse(spec.dangerous)
        self.assertNotIn(ACTION_ID, DANGEROUS_ACTION_IDS)
        from src.application.experience_handlers.registry import HANDLERS

        self.assertIn(ACTION_ID, HANDLERS)

    def test_slash_keyword_match_and_golden(self):
        self.assertEqual(route_intent("/polish").action_id, ACTION_ID)
        for kw in ("批量润色", "润色词条", "补全发音"):
            self.assertEqual(route_intent(kw).action_id, ACTION_ID, kw)
        self.assertEqual(
            [i.action_id for i in match_commands("/polish")], [ACTION_ID]
        )
        path = Path(__file__).resolve().parent / "ai_goldens" / "intent_routes.json"
        rows = json.loads(path.read_text(encoding="utf-8"))
        self.assertTrue(any(r.get("text") == "/polish" for r in rows))


if __name__ == "__main__":
    unittest.main()
