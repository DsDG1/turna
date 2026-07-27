"""V-06 (v4.52): resource.resolve_term_conflicts skill (evaluate + handler).

Pure-module tests (L1 fast): the handler is driven through a fake host with
``safe_question`` patched, so no Qt application object is constructed here.
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
from src.backend.experience.term_conflict_skill import (  # noqa: E402
    ACTION_ID,
    build_term_conflict_messages,
    evaluate_term_conflicts,
    parse_term_conflict_reply,
)


def _adapter(vocab, expressions):
    return SimpleNamespace(
        vocab=list(vocab),
        expressions=list(expressions),
        grammar_points=[],
        sections=[],
    )


class EvaluateTest(unittest.TestCase):
    def test_conflict_detected(self):
        a = _adapter(
            [{"id": "w1", "term": "merhaba", "translation": "你好"}],
            [{"id": "e1", "term": "merhaba", "translation": "哈喽"}],
        )
        r = evaluate_term_conflicts(a)
        self.assertEqual(r["count"], 1)
        self.assertEqual(
            r["conflicts"][0],
            {"vocab_id": "w1", "expression_id": "e1", "issue": "translation_mismatch"},
        )

    def test_same_translation_skipped(self):
        # 同 term 同 translation → K-20 duplicate 领域，这里不报冲突。
        a = _adapter(
            [{"id": "w1", "term": "merhaba", "translation": "你好"}],
            [{"id": "e1", "term": "merhaba", "translation": " 你好 "}],
        )
        self.assertEqual(evaluate_term_conflicts(a), {"count": 0, "conflicts": []})

    def test_empty_term_skipped(self):
        a = _adapter(
            [{"id": "w1", "term": " ", "translation": "你好"}],
            [{"id": "e1", "term": "", "translation": "哈喽"}],
        )
        self.assertEqual(evaluate_term_conflicts(a), {"count": 0, "conflicts": []})

    def test_case_and_whitespace_normalized(self):
        a = _adapter(
            [{"id": "w1", "term": " Merhaba ", "translation": "你好"}],
            [{"id": "e1", "term": "merhaba", "translation": " 你好  "}],
        )
        # 归一化后 term 相同、translation 也相同 → 不算冲突
        self.assertEqual(evaluate_term_conflicts(a)["count"], 0)
        a.expressions[0]["translation"] = "您好"
        self.assertEqual(evaluate_term_conflicts(a)["count"], 1)

    def test_term_source_fallback(self):
        a = _adapter(
            [{"id": "w1", "source": "su", "translation": "水"}],
            [{"id": "e1", "source": "su", "translation": "开水"}],
        )
        self.assertEqual(evaluate_term_conflicts(a)["count"], 1)

    def test_never_raises_on_bad_adapter(self):
        self.assertEqual(evaluate_term_conflicts(None), {"count": 0, "conflicts": []})
        bad = SimpleNamespace(vocab=None, expressions="junk")
        self.assertEqual(evaluate_term_conflicts(bad), {"count": 0, "conflicts": []})
        weird = _adapter([{"term": "x"}, "junk"], [{"id": None}])
        self.assertEqual(evaluate_term_conflicts(weird), {"count": 0, "conflicts": []})

    def test_multiple_pairs_count(self):
        a = _adapter(
            [
                {"id": "w1", "term": "a", "translation": "1"},
                {"id": "w2", "term": "b", "translation": "2"},
            ],
            [
                {"id": "e1", "term": "a", "translation": "x"},
                {"id": "e2", "term": "b", "translation": "y"},
                {"id": "e3", "term": "c", "translation": "z"},
            ],
        )
        r = evaluate_term_conflicts(a)
        self.assertEqual(r["count"], 2)
        self.assertEqual(
            {(c["vocab_id"], c["expression_id"]) for c in r["conflicts"]},
            {("w1", "e1"), ("w2", "e2")},
        )

    def test_closed_set_no_term_or_translation_in_return(self):
        a = _adapter(
            [{"id": "w1", "term": "secret-term", "translation": "secret-trans"}],
            [{"id": "e1", "term": "secret-term", "translation": "other"}],
        )
        blob = str(evaluate_term_conflicts(a))
        self.assertNotIn("secret-term", blob)
        self.assertNotIn("secret-trans", blob)
        self.assertIn("w1", blob)
        self.assertIn("e1", blob)


class LlmInterfaceTest(unittest.TestCase):
    """v1 预留接口：build/parse 存在且永不抛（handler 零 LLM）。"""

    def test_build_messages_lists_pairs(self):
        a = _adapter(
            [{"id": "w1", "term": "merhaba", "translation": "你好"}],
            [{"id": "e1", "term": "merhaba", "translation": "哈喽"}],
        )
        msgs, terms = build_term_conflict_messages(SimpleNamespace(), a)
        self.assertEqual(len(msgs), 2)
        self.assertIn("w1", msgs[1]["content"])
        self.assertEqual(terms["w1"], "merhaba")

    def test_parse_reply_robust(self):
        out = parse_term_conflict_reply(
            {"entries": [{"vocab_id": "w1", "expression_id": "e1", "translation": "你好"},
                          {"vocab_id": "", "expression_id": "e2", "translation": "x"}]}
        )
        self.assertEqual(out, {"w1|e1": "你好"})
        self.assertEqual(parse_term_conflict_reply("not json"), {})
        self.assertEqual(parse_term_conflict_reply(None), {})
        self.assertEqual(parse_term_conflict_reply(json.dumps({"entries": []})), {})


class _Status:
    def __init__(self, host):
        self._host = host

    def showMessage(self, msg, _ms=0):  # noqa: N802
        self._host._status.append(msg)


def _make_host(vocab, expressions):
    from src.backend.experience.metrics import ExperienceMetrics

    class Host:
        def __init__(self) -> None:
            self.adapter = _adapter(vocab, expressions)
            self.experience_metrics = ExperienceMetrics()
            self.undo_stack = MagicMock()
            self._status: list[str] = []
            self._events: list = []

        def statusBar(self):  # noqa: N802
            return _Status(self)

        def _record_experience_event(self, *a, **k):
            self._events.append((a, k))

        def _refresh_validate_after_ai(self):
            pass

        def _on_ai_edit_applied(self):
            pass

    return Host()


class ResolveConflictsHandlerTest(unittest.TestCase):
    def _call(self, host, answers):
        from src.application.experience_handlers.resources import (
            handle_resolve_term_conflicts,
        )

        with patch(
            "src.application.experience_handlers.resources.safe_question",
            side_effect=list(answers),
        ) as q:
            handle_resolve_term_conflicts(host, {})
        return q

    def test_unify_to_vocab_apply_and_undo(self):
        host = _make_host(
            [{"id": "w1", "term": "merhaba", "translation": "你好"}],
            [{"id": "e1", "term": "merhaba", "translation": "哈喽"}],
        )
        self._call(host, [True])  # 第一问即选 vocab 方向
        self.assertEqual(host.undo_stack.push.call_count, 1)
        cmd = host.undo_stack.push.call_args[0][0]
        expr = host.adapter.expressions[0]
        cmd.redo()
        self.assertEqual(expr["translation"], "你好")
        self.assertEqual(expr["id"], "e1")  # 保 id
        cmd.undo()
        self.assertEqual(expr["translation"], "哈喽")
        # timeline 闭集 scope：只有 count，无 term/translation
        args, kwargs = host._events[-1]
        self.assertEqual(kwargs.get("action_id"), ACTION_ID)
        self.assertEqual(kwargs.get("scope"), {"count": 1})
        self.assertNotIn("merhaba", str(host._events))
        self.assertNotIn("哈喽", str(host._events))
        by_action = host.experience_metrics.snapshot().get("suggestion_by_action", {})
        self.assertEqual(by_action.get(ACTION_ID, {}).get("applied"), 1)

    def test_unify_to_expression_apply_and_undo(self):
        host = _make_host(
            [{"id": "w1", "term": "merhaba", "translation": "你好"}],
            [{"id": "e1", "term": "merhaba", "translation": "哈喽"}],
        )
        self._call(host, [False, True])  # 否 vocab → 选 expression
        self.assertEqual(host.undo_stack.push.call_count, 1)
        cmd = host.undo_stack.push.call_args[0][0]
        word = host.adapter.vocab[0]
        cmd.redo()
        self.assertEqual(word["translation"], "哈喽")
        self.assertEqual(word["id"], "w1")
        cmd.undo()
        self.assertEqual(word["translation"], "你好")

    def test_no_conflicts_status_only(self):
        host = _make_host(
            [{"id": "w1", "term": "merhaba", "translation": "你好"}],
            [{"id": "e1", "term": "merhaba", "translation": "你好"}],
        )
        q = self._call(host, [])
        self.assertEqual(q.call_count, 0)  # 无冲突不弹确认
        self.assertTrue(any("无词条冲突" in m for m in host._status))
        self.assertEqual(host.undo_stack.push.call_count, 0)

    def test_reject_both_directions_counts_rejected(self):
        host = _make_host(
            [{"id": "w1", "term": "merhaba", "translation": "你好"}],
            [{"id": "e1", "term": "merhaba", "translation": "哈喽"}],
        )
        self._call(host, [False, False])
        self.assertEqual(host.undo_stack.push.call_count, 0)
        by_action = host.experience_metrics.snapshot().get("suggestion_by_action", {})
        self.assertEqual(by_action.get(ACTION_ID, {}).get("rejected"), 1)


class SuggestionAndRoutingTest(unittest.TestCase):
    def test_hygiene_conflict_count_and_p2_suggestion(self):
        from src.backend.experience.context_bus import (
            ExperienceContext,
            _course_hygiene,
            local_suggestions,
        )

        a = _adapter(
            [{"id": "w1", "term": "merhaba", "translation": "你好"}],
            [{"id": "e1", "term": "merhaba", "translation": "哈喽"}],
        )
        h = _course_hygiene(a)
        self.assertEqual(h["conflict_count"], 1)
        ctx = ExperienceContext(
            hygiene={"conflict_count": 2, "placeholder_count": 0,
                     "needs_review_count": 0},
            empty_lesson_count=0,
            validate_error_count=0,
        )
        sugs = local_suggestions(ctx, limit=3)
        mine = [s for s in sugs if s["action_id"] == ACTION_ID]
        self.assertEqual(len(mine), 1)
        self.assertEqual(mine[0]["scope"], {"count": 2})
        self.assertIn("2", mine[0]["title"])

    def test_action_registered_write_not_dangerous(self):
        spec = get_action(ACTION_ID)
        self.assertIsNotNone(spec)
        self.assertTrue(spec.needs_confirm)  # 写操作：预览 + 确认 + Undo
        self.assertFalse(spec.dangerous)
        self.assertNotIn(ACTION_ID, DANGEROUS_ACTION_IDS)
        from src.application.experience_handlers.registry import HANDLERS

        self.assertIn(ACTION_ID, HANDLERS)

    def test_slash_keyword_and_golden(self):
        self.assertEqual(route_intent("/conflicts").action_id, ACTION_ID)
        for kw in ("词条冲突", "释义冲突", "冲突仲裁"):
            self.assertEqual(route_intent(kw).action_id, ACTION_ID, kw)
        self.assertEqual(
            [i.action_id for i in match_commands("/conflicts")], [ACTION_ID]
        )
        path = Path(__file__).resolve().parent / "ai_goldens" / "intent_routes.json"
        rows = json.loads(path.read_text(encoding="utf-8"))
        self.assertTrue(any(r.get("text") == "/conflicts" for r in rows))


if __name__ == "__main__":
    unittest.main()
