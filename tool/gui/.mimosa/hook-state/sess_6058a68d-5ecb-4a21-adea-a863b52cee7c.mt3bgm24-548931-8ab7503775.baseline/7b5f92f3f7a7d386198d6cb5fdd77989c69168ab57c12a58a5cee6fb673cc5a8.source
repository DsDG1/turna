"""K-21 (v4.43): resource.align_pos_tags skill (pos_skill + dispatch)."""
from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from tests._qtapp import qt_app  # noqa: E402

from src.backend.experience.actions import (  # noqa: E402
    DANGEROUS_ACTION_IDS,
    get_action,
)
from src.backend.experience.intent_router import match_commands, route_intent  # noqa: E402
from src.backend.experience.pos_constants import (  # noqa: E402
    POS_TAGS,
    normalize_pos,
)
from src.backend.experience.pos_skill import (  # noqa: E402
    ACTION_ID,
    build_pos_alignment_messages,
    evaluate_pos_alignment,
    parse_pos_alignment_reply,
    run_pos_alignment,
)


def _adapter(vocab):
    return SimpleNamespace(
        vocab=list(vocab),
        expressions=[],
        grammar_points=[],
        index={"language": "tr"},
        course_dir="/tmp/x",
    )


class PosConstantsTest(unittest.TestCase):
    def test_closed_set_10(self):
        self.assertEqual(len(POS_TAGS), 10)
        self.assertEqual(len(set(POS_TAGS)), 10)

    def test_normalize(self):
        self.assertEqual(normalize_pos(" Noun "), "noun")
        self.assertIsNone(normalize_pos("bogus"))
        self.assertIsNone(normalize_pos(""))
        self.assertIsNone(normalize_pos(None))


class EvaluateTest(unittest.TestCase):
    def test_missing_invalid_conflict_classification(self):
        a = _adapter(
            [
                {"id": "w1", "term": "merhaba", "pos": None, "tags": []},  # missing
                {"id": "w2", "term": "su", "pos": "noun", "tags": ["noun"]},  # ok
                {"id": "w3", "term": "kos", "pos": "verb", "tags": ["noun"]},  # conflict
                {"id": "w4", "term": "x", "pos": "bogus", "tags": []},  # invalid
                {"id": "w5", "term": "y", "pos": None, "tags": ["verb"]},  # healthy
            ]
        )
        r = evaluate_pos_alignment(a)
        issues = {m["word_id"]: m["issue"] for m in r["misaligned"]}
        self.assertEqual(issues, {"w1": "missing", "w3": "conflict", "w4": "invalid"})
        self.assertEqual(r["count"], 3)

    def test_healthy_returns_empty(self):
        a = _adapter([{"id": "w1", "term": "su", "pos": "noun", "tags": ["noun"]}])
        self.assertEqual(evaluate_pos_alignment(a), {"count": 0, "misaligned": []})

    def test_never_raises_on_bad_adapter(self):
        self.assertEqual(evaluate_pos_alignment(None), {"count": 0, "misaligned": []})
        self.assertEqual(evaluate_pos_alignment(SimpleNamespace(vocab=None)), {"count": 0, "misaligned": []})

    def test_closed_set_no_term_in_return(self):
        a = _adapter([{"id": "w1", "term": "secret-term", "pos": None, "tags": []}])
        r = evaluate_pos_alignment(a)
        blob = str(r)
        self.assertNotIn("secret-term", blob)
        self.assertIn("w1", blob)


class ParseReplyTest(unittest.TestCase):
    def test_keeps_valid_drops_invalid(self):
        out = parse_pos_alignment_reply(
            {"entries": [{"id": "w1", "pos": "noun"}, {"id": "w9", "pos": "bogus"}, {"id": "", "pos": "verb"}]}
        )
        self.assertEqual(out, {"w1": "noun"})

    def test_bad_json_returns_empty(self):
        self.assertEqual(parse_pos_alignment_reply("not json"), {})
        self.assertEqual(parse_pos_alignment_reply(None), {})
        self.assertEqual(parse_pos_alignment_reply(""), {})

    def test_raw_dict_passes(self):
        self.assertEqual(
            parse_pos_alignment_reply({"entries": [{"id": "w2", "pos": "verb"}]}),
            {"w2": "verb"},
        )


class BuildMessagesTest(unittest.TestCase):
    def test_messages_have_system_and_user(self):
        a = _adapter([{"id": "w1", "term": "su", "pos": None, "tags": []}])
        msgs, terms = build_pos_alignment_messages(
            SimpleNamespace(is_complete=True), a
        )
        self.assertEqual(len(msgs), 2)
        self.assertEqual(msgs[0]["role"], "system")
        self.assertIn("pos", msgs[1]["content"])
        # terms map carries term for confirmation UI (client-side, not telemetry)
        self.assertEqual(terms, {"w1": "su"})
        # allowed closed set listed in prompt
        for tag in POS_TAGS:
            self.assertIn(tag, msgs[1]["content"])


class RunSkillTest(unittest.TestCase):
    def test_runs_and_parses(self):
        import src.backend.ai_generator as ai_gen

        a = _adapter([{"id": "w1", "term": "su", "pos": None, "tags": []}])
        orig = ai_gen.request_chat
        ai_gen.request_chat = lambda *args, **k: {  # type: ignore[assignment]
            "entries": [{"id": "w1", "pos": "noun"}]
        }
        try:
            out = run_pos_alignment(SimpleNamespace(is_complete=True), a)
        finally:
            ai_gen.request_chat = orig
        self.assertEqual(out, {"w1": "noun"})

    def test_failure_returns_empty(self):
        import src.backend.ai_generator as ai_gen

        a = _adapter([{"id": "w1", "term": "su", "pos": None, "tags": []}])

        def boom(*args, **k):
            raise RuntimeError("net down")

        orig = ai_gen.request_chat
        ai_gen.request_chat = boom  # type: ignore[assignment]
        try:
            self.assertEqual(run_pos_alignment(SimpleNamespace(), a), {})
        finally:
            ai_gen.request_chat = orig


class ActionRegistryTest(unittest.TestCase):
    def test_registered_write_not_dangerous(self):
        spec = get_action(ACTION_ID)
        self.assertIsNotNone(spec)
        self.assertTrue(spec.needs_confirm)  # write op: preview + confirm + undo
        self.assertFalse(spec.dangerous)
        self.assertNotIn(ACTION_ID, DANGEROUS_ACTION_IDS)


class RoutingTest(unittest.TestCase):
    def test_slash_exact(self):
        self.assertEqual(route_intent("/pos-align").action_id, ACTION_ID)

    def test_keyword(self):
        self.assertEqual(route_intent("词性对齐").action_id, ACTION_ID)
        self.assertEqual(route_intent("POS 对齐").action_id, ACTION_ID)

    def test_match_commands_prefix(self):
        self.assertEqual([i.action_id for i in match_commands("/pos-align")], [ACTION_ID])

    def test_golden_has_pos_align(self):
        import json

        path = Path(__file__).resolve().parent / "ai_goldens" / "intent_routes.json"
        rows = json.loads(path.read_text(encoding="utf-8"))
        self.assertTrue(any(r.get("text") == "/pos-align" for r in rows))


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


class AlignPosDispatchTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        qt_app()

    def _make_host(self, vocab, *, ai_complete=True, mapping=None, reject=False):
        from src.backend.experience.job_registry import JobRegistry
        from src.backend.experience.metrics import ExperienceMetrics

        class Host:
            def __init__(self) -> None:
                self.adapter = _adapter(vocab)
                self._ai_config = SimpleNamespace(is_complete=ai_complete)
                self._settings_obj = SimpleNamespace()
                self.job_tray = JobRegistry()
                self.experience_metrics = ExperienceMetrics()
                self.undo_stack = MagicMock()
                self._status: list[str] = []
                self._events: list = []
                self._experience_worker = None
                self._deny = False
                self._make_ai_worker = _fake_worker_factory()
                self.experience = SimpleNamespace(invalidate=lambda: None)

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

        # v4.46+: confirm goes through ui_guard.safe_question imported into
        # the resources handler namespace (offscreen default = reject).
        self._qbox = patch(
            "src.application.experience_handlers.resources.safe_question",
            return_value=not reject,
        )
        self._qbox.start()
        self.addCleanup(self._qbox.stop)

        # Patch run_pos_alignment to return mapping (avoid real LLM).
        target = mapping if mapping is not None else {"w1": "noun"}
        self._runpatch = patch(
            "src.backend.experience.pos_skill.run_pos_alignment",
            return_value=target,
        )
        self._runpatch.start()
        self.addCleanup(self._runpatch.stop)
        return host

    def _call(self, host):
        from src.application.experience_skills_mixin import ExperienceSkillsMixin

        ExperienceSkillsMixin._experience_align_pos(host, {})

    def test_healthy_no_op(self):
        host = self._make_host([{"id": "w1", "term": "su", "pos": "noun", "tags": ["noun"]}])
        self._call(host)
        self.assertTrue(any("已对齐" in m for m in host._status))
        self.assertEqual(host.undo_stack.push.call_count, 0)

    def test_rejected_counts_rejected(self):
        host = self._make_host(
            [{"id": "w1", "term": "su", "pos": None, "tags": []}], reject=True
        )
        self._call(host)
        self.assertEqual(host.undo_stack.push.call_count, 0)
        by_action = host.experience_metrics.snapshot().get("suggestion_by_action", {})
        self.assertEqual(by_action.get(ACTION_ID, {}).get("rejected"), 1)

    def test_no_config_status(self):
        host = self._make_host(
            [{"id": "w1", "term": "su", "pos": None, "tags": []}], ai_complete=False
        )
        self._call(host)
        self.assertTrue(any("配置不完整" in m for m in host._status))
        self.assertEqual(host.undo_stack.push.call_count, 0)

    def test_success_pushes_batch_patch(self):
        host = self._make_host(
            [
                {"id": "w1", "term": "su", "pos": None, "tags": []},
                {"id": "w2", "term": "x", "pos": "bogus", "tags": []},
            ],
            mapping={"w1": "noun", "w2": "verb"},
        )
        self._call(host)
        # One ApplyBatchPatchCommand pushed onto undo stack.
        self.assertEqual(host.undo_stack.push.call_count, 1)
        cmd = host.undo_stack.push.call_args[0][0]
        self.assertEqual(cmd.text(), "对齐词性（POS）（2 词）")
        # metrics applied + timeline closed-set scope (count only, no term).
        self.assertTrue(host._events)
        args, kwargs = host._events[-1]
        self.assertEqual(kwargs.get("action_id"), ACTION_ID)
        self.assertEqual(kwargs.get("scope"), {"count": 2})
        self.assertNotIn("su", str(host._events))
        self.assertNotIn("bogus", str(host._events))

    def test_empty_mapping_status(self):
        host = self._make_host(
            [{"id": "w1", "term": "su", "pos": None, "tags": []}], mapping={}
        )
        self._call(host)
        self.assertEqual(host.undo_stack.push.call_count, 0)
        self.assertTrue(any("未给出可用建议" in m for m in host._status))

    def test_deny_budget_blocks(self):
        # _deny_ai_write_if_blocked returns True -> skill aborts before worker.
        host = self._make_host(
            [{"id": "w1", "term": "su", "pos": None, "tags": []}]
        )
        host._deny = True
        self._call(host)
        self.assertEqual(host.undo_stack.push.call_count, 0)


class CrossStackAlignmentTest(unittest.TestCase):
    """GUI POS closed set must match Flutter enum (lib/domain/course/pos_tag.dart)."""

    def test_flutter_pos_tag_file_exists_and_matches(self):
        flutter_path = _GUI.parents[1] / "lib" / "domain" / "course" / "pos_tag.dart"
        if not flutter_path.exists():
            self.skipTest("Flutter pos_tag.dart not yet created (C step pending)")
        text = flutter_path.read_text(encoding="utf-8")
        for tag in POS_TAGS:
            self.assertIn(tag, text, f"Flutter enum missing POS tag '{tag}'")


if __name__ == "__main__":
    unittest.main()