"""v4.65 B1+B2: resource.fill_stubs_batch skill (selector + handler + routing).

FieldPatch-based global「清待补」: selects stub entries via the stub predicate
(``select_stub_entries`` over the adapter's global pools) and reuses
``run_batch_polish`` for the LLM fill; stub tags are stripped via their own
Undo-able FieldPatch. Pure-module tests (L1 fast): the handler is driven
through a fake host with ``safe_question`` patched and an inline fake AI
worker, so no Qt application object is constructed here.
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
from src.backend.experience.resource_stub_select import (  # noqa: E402
    ACTION_ID,
    is_stub_grammar_entry,
    is_stub_vocab_entry,
    select_stub_entries,
    strip_stub_tags,
    without_stub_tags,
)


class SelectorTest(unittest.TestCase):
    """resource_stub_select: pure stub predicate + pool scan (never raises)."""

    def test_is_stub_vocab_empty_and_placeholder(self):
        self.assertTrue(is_stub_vocab_entry({"id": "w1", "translation": ""}))
        self.assertTrue(is_stub_vocab_entry({"id": "w1", "translation": "[待补]"}))
        self.assertTrue(is_stub_vocab_entry({"id": "w1", "translation": "  "}))
        self.assertFalse(is_stub_vocab_entry({"id": "w1", "translation": "你好"}))

    def test_is_stub_vocab_tags(self):
        self.assertTrue(
            is_stub_vocab_entry({"id": "w1", "translation": "你好", "tags": ["needs-review"]})
        )
        self.assertTrue(is_stub_vocab_entry({"id": "w1", "tags": ["auto-fix"]}))
        self.assertFalse(is_stub_vocab_entry({"id": "w1", "translation": "你好", "tags": ["a1"]}))
        self.assertFalse(is_stub_vocab_entry("junk"))
        self.assertFalse(is_stub_vocab_entry(None))

    def test_is_stub_grammar(self):
        self.assertTrue(is_stub_grammar_entry({"id": "g1", "explanation": ""}))
        self.assertTrue(is_stub_grammar_entry({"id": "g1", "explanation": "x", "tags": ["needs-review"]}))
        self.assertFalse(is_stub_grammar_entry({"id": "g1", "explanation": "规则"}))
        self.assertFalse(is_stub_grammar_entry(None))

    def test_select_scans_pools_excludes_grammar_by_default(self):
        vocab = [
            {"id": "w1", "term": "merhaba", "translation": ""},
            {"id": "w2", "term": "kedi", "translation": "猫"},
        ]
        exprs = [{"id": "e1", "term": "nasilsin", "translation": "[待补]"}]
        grammar = [{"id": "g1", "title": "Vowel", "explanation": ""}]
        out = select_stub_entries(vocab, exprs, grammar)
        ids = {(s["id"], s["kind"]) for s in out}
        self.assertEqual(ids, {("w1", "vocab"), ("e1", "expressions")})
        # grammar excluded by default
        with_grammar = select_stub_entries(vocab, exprs, grammar, include_grammar=True)
        self.assertIn(("g1", "grammar"), {(s["id"], s["kind"]) for s in with_grammar})

    def test_select_shapes_for_run_batch_polish(self):
        vocab = [{"id": "w1", "term": "merhaba", "translation": "", "pos": "interjection"}]
        out = select_stub_entries(vocab, [], [])
        self.assertEqual(len(out), 1)
        s = out[0]
        self.assertEqual(
            set(s.keys()), {"id", "kind", "term", "translation", "pronunciation", "pos"}
        )
        self.assertEqual(s["pos"], "interjection")
        # expressions carry no pos
        eout = select_stub_entries([], [{"id": "e1", "term": "x", "translation": ""}], [])
        self.assertEqual(eout[0]["pos"], "")

    def test_select_never_raises_and_skips_no_id(self):
        self.assertEqual(select_stub_entries(None, None), [])
        self.assertEqual(select_stub_entries("junk", {"x": 1}), [])
        # entry without id is dropped
        self.assertEqual(select_stub_entries([{"term": "x", "translation": ""}], []), [])

    def test_strip_stub_tags_only_stub_tags(self):
        e = {"id": "w1", "tags": ["needs-review", "a1", "auto-fix"]}
        self.assertTrue(strip_stub_tags(e))
        self.assertEqual(e["tags"], ["a1"])
        # nothing to strip -> False, list untouched
        e2 = {"id": "w2", "tags": ["a1"]}
        self.assertFalse(strip_stub_tags(e2))
        self.assertEqual(e2["tags"], ["a1"])
        self.assertFalse(strip_stub_tags({"id": "w3"}))
        self.assertFalse(strip_stub_tags(None))

    def test_without_stub_tags_pure_no_mutation(self):
        # 红线: without_stub_tags must NOT mutate (field_patch captures pre-strip
        # old tags so the removal is Undo-able).
        e = {"id": "w1", "tags": ["needs-review", "a1"]}
        self.assertEqual(without_stub_tags(e), ["a1"])
        self.assertEqual(e["tags"], ["needs-review", "a1"])  # untouched
        # no stub tag -> None (skip no-op patch)
        self.assertIsNone(without_stub_tags({"id": "w2", "tags": ["a1"]}))
        self.assertIsNone(without_stub_tags({"id": "w3"}))
        self.assertIsNone(without_stub_tags(None))


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


class FillStubsBatchHandlerTest(unittest.TestCase):
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

    def _call(self, host, scope=None, *, confirm=True):
        from src.application.experience_handlers.resources import (
            handle_fill_stubs_batch,
        )

        with patch(
            "src.application.experience_handlers.resources.safe_question",
            return_value=confirm,
        ):
            handle_fill_stubs_batch(host, scope or {})

    _VOCAB = [
        {"id": "w1", "term": "merhaba", "translation": "", "tags": ["needs-review"]},
        {"id": "w2", "term": "kedi", "translation": "猫"},
    ]
    _EXPR = [{"id": "e1", "term": "nasilsin", "translation": "[待补]"}]

    def test_no_stubs_status_no_llm(self):
        host = self._make_host([{"id": "w9", "term": "x", "translation": "成稿"}], [])
        self._call(host)
        self.assertTrue(any("没有待补词条" in m for m in host._status))
        self.assertEqual(host.undo_stack.push.call_count, 0)

    def test_no_adapter_status(self):
        host = self._make_host(self._VOCAB, self._EXPR)
        host.adapter = None
        self._call(host)
        self.assertTrue(any("请先打开课程" in m for m in host._status))

    def test_rejected_counts_rejected(self):
        host = self._make_host(self._VOCAB, self._EXPR)
        self._call(host, confirm=False)
        self.assertEqual(host.undo_stack.push.call_count, 0)
        by_action = host.experience_metrics.snapshot().get("suggestion_by_action", {})
        self.assertEqual(by_action.get(ACTION_ID, {}).get("rejected"), 1)

    def test_no_config_status(self):
        host = self._make_host(self._VOCAB, self._EXPR, ai_complete=False)
        self._call(host)
        self.assertTrue(any("配置不完整" in m for m in host._status))
        self.assertEqual(host.undo_stack.push.call_count, 0)

    def test_budget_denied_blocks(self):
        host = self._make_host(self._VOCAB, self._EXPR)
        host._deny = True
        self._call(host)
        self.assertEqual(host.undo_stack.push.call_count, 0)

    def test_confirm_fills_and_strips_tags_undo(self):
        host = self._make_host(
            self._VOCAB,
            self._EXPR,
            mapping={
                ("w1", "translation"): "你好",
                ("e1", "translation"): "你好吗",
                ("w9", "translation"): "ghost",  # 未知 id -> 丢
            },
        )
        self._call(host)
        self.assertEqual(host.undo_stack.push.call_count, 1)
        cmd = host.undo_stack.push.call_args[0][0]
        word = host.adapter.vocab[0]
        expr = host.adapter.expressions[0]
        cmd.redo()
        self.assertEqual(word["translation"], "你好")
        self.assertEqual(expr["translation"], "你好吗")
        self.assertEqual(word["id"], "w1")  # 保 id
        # stub tags stripped on the filled vocab entry
        self.assertNotIn("needs-review", word.get("tags") or [])
        cmd.undo()
        self.assertEqual(word["translation"], "")
        self.assertIn("needs-review", word.get("tags") or [])
        # timeline 闭集 scope：只有 count，无 term/原文
        args, kwargs = host._events[-1]
        self.assertEqual(kwargs.get("action_id"), ACTION_ID)
        self.assertIn("count", kwargs.get("scope", {}))
        self.assertNotIn("merhaba", str(host._events))
        self.assertNotIn("nasilsin", str(host._events))
        by_action = host.experience_metrics.snapshot().get("suggestion_by_action", {})
        self.assertEqual(by_action.get(ACTION_ID, {}).get("applied"), 1)

    def test_expressions_pos_patch_dropped(self):
        host = self._make_host(
            [],
            self._EXPR,
            mapping={("e1", "pos"): "noun", ("e1", "translation"): "你好吗"},
        )
        self._call(host)
        self.assertEqual(host.undo_stack.push.call_count, 1)
        cmd = host.undo_stack.push.call_args[0][0]
        cmd.redo()
        self.assertEqual(host.adapter.expressions[0]["translation"], "你好吗")
        self.assertNotIn("pos", host.adapter.expressions[0])

    def test_empty_mapping_status(self):
        host = self._make_host(self._VOCAB, self._EXPR, mapping={})
        self._call(host)
        self.assertEqual(host.undo_stack.push.call_count, 0)
        self.assertTrue(any("未给出可用建议" in m for m in host._status))

    def test_uses_new_action_id_not_batch_polish(self):
        # 红线：metrics/events must use fill_stubs_batch, never resource.batch_polish.
        host = self._make_host(
            self._VOCAB, [], mapping={("w1", "translation"): "你好"}
        )
        self._call(host)
        by_action = host.experience_metrics.snapshot().get("suggestion_by_action", {})
        self.assertIn(ACTION_ID, by_action)
        self.assertNotIn("resource.batch_polish", by_action)
        for _args, kwargs in host._events:
            self.assertNotEqual(kwargs.get("action_id"), "resource.batch_polish")


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
        self.assertEqual(route_intent("/fill-stubs").action_id, ACTION_ID)
        for kw in ("批量补齐资源", "全局补齐资源", "fill stubs"):
            self.assertEqual(route_intent(kw).action_id, ACTION_ID, kw)
        # broad 待补 / 补全词条 still route to the whole-section variant.
        self.assertEqual(route_intent("待补").action_id, "resource.fill_stubs")
        self.assertEqual(route_intent("补全词条").action_id, "resource.fill_stubs")
        self.assertEqual(
            [i.action_id for i in match_commands("/fill-stubs")], [ACTION_ID]
        )
        path = Path(__file__).resolve().parent / "ai_goldens" / "intent_routes.json"
        rows = json.loads(path.read_text(encoding="utf-8"))
        self.assertTrue(any(r.get("text") == "/fill-stubs" for r in rows))


if __name__ == "__main__":
    unittest.main()
