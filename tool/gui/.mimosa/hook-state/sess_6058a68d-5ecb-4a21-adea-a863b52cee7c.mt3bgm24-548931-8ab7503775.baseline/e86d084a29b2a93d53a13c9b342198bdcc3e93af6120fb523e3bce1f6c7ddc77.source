"""E2.1+ Soft Autopilot whitelist hygiene tests."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.experience.soft_autopilot import (  # noqa: E402
    SoftFixBatch,
    apply_soft_fixes,
    evaluate_soft_fixes,
    restore_resources,
    snapshot_resources,
    summarize_soft_batch,
)


class _Adapter:
    def __init__(self) -> None:
        self.vocab = [
            {
                "id": "w1",
                "term": "  merhaba  ",
                "translation": "你好",
                "tags": ["a", "", "b"],
            },
            {"id": "w2", "term": "ev", "translation": "  house  ", "tags": []},
        ]
        self.expressions = [
            {
                "id": "e1",
                "term": " nasılsın ",
                "translation": "how are you",
                "tags": [""],
            },
        ]
        self._notified = 0

    def notify_resources_changed(self) -> None:
        self._notified += 1


class SoftAutopilotTest(unittest.TestCase):
    def test_evaluate_finds_trim_and_empty_tags(self) -> None:
        a = _Adapter()
        batch = evaluate_soft_fixes(a)
        rules = {f.rule_id for f in batch.fixes}
        self.assertIn("hygiene.trim_whitespace", rules)
        self.assertIn("hygiene.drop_empty_tags", rules)
        self.assertGreaterEqual(len(batch), 3)

    def test_strip_zero_width(self) -> None:
        """v4.62 P5: invisible ZWSP/BOM stripped from resource fields."""
        a = _Adapter()
        a.vocab[0]["term"] = "mer\u200bhaba"
        a.vocab[0]["translation"] = "你\ufeff好"
        batch = evaluate_soft_fixes(a)
        zws = [f for f in batch.fixes if f.rule_id == "hygiene.strip_zero_width"]
        self.assertGreaterEqual(len(zws), 1)
        apply_soft_fixes(a, batch)
        self.assertEqual(a.vocab[0]["term"], "merhaba")
        self.assertEqual(a.vocab[0]["translation"], "你好")

    def test_apply_mutates_and_notifies(self) -> None:
        a = _Adapter()
        batch = evaluate_soft_fixes(a)
        apply_soft_fixes(a, batch)
        self.assertEqual(a.vocab[0]["term"], "merhaba")
        self.assertEqual(a.vocab[1]["translation"], "house")
        self.assertEqual(a.vocab[0]["tags"], ["a", "b"])
        self.assertEqual(a.expressions[0]["term"], "nasılsın")
        self.assertEqual(a.expressions[0]["tags"], [])
        self.assertGreaterEqual(a._notified, 1)

    def test_snapshot_restore(self) -> None:
        a = _Adapter()
        snap = snapshot_resources(a)
        apply_soft_fixes(a)
        self.assertEqual(a.vocab[0]["term"], "merhaba")
        restore_resources(a, snap)
        self.assertEqual(a.vocab[0]["term"], "  merhaba  ")

    def test_soft_hygiene_command_undo(self) -> None:
        from PySide6.QtGui import QUndoStack

        from src.application.commands import SoftHygieneCommand
        from tests._qtapp import qt_app

        qt_app()
        a = _Adapter()
        stack = QUndoStack()
        batch = evaluate_soft_fixes(a)
        stack.push(SoftHygieneCommand(a, batch))
        self.assertEqual(a.vocab[0]["term"], "merhaba")
        stack.undo()
        self.assertEqual(a.vocab[0]["term"], "  merhaba  ")
        stack.redo()
        self.assertEqual(a.vocab[0]["term"], "merhaba")

    def test_no_id_changes(self) -> None:
        a = _Adapter()
        ids_before = {e["id"] for e in a.vocab + a.expressions}
        apply_soft_fixes(a)
        ids_after = {e["id"] for e in a.vocab + a.expressions}
        self.assertEqual(ids_before, ids_after)

    def test_evaluate_finds_collapse_and_quotes(self) -> None:
        a = _Adapter()
        # vocab[0] "  merhaba  " has no internal repeated whitespace and no
        # surrounding quotes — those rules must NOT fire on it.
        batch = evaluate_soft_fixes(a)
        rules = {f.rule_id for f in batch.fixes}
        # Existing fixture has neither collapse nor quote issues.
        self.assertNotIn("hygiene.collapse_repeated_spaces", rules)
        self.assertNotIn("hygiene.strip_surround_quotes", rules)

        # A dedicated fixture exercising the new rules.
        b = _CollapseQuoteAdapter()
        batch2 = evaluate_soft_fixes(b)
        rules2 = {f.rule_id for f in batch2.fixes}
        self.assertIn("hygiene.collapse_repeated_spaces", rules2)
        self.assertIn("hygiene.strip_surround_quotes", rules2)

    def test_collapse_applies_and_converges_with_trim(self) -> None:
        a = _CollapseQuoteAdapter()
        apply_soft_fixes(a)
        # "merhaba   dünya" → "merhaba dünya" (ends untouched; trim handles ends)
        self.assertEqual(a.vocab[0]["term"], "merhaba dünya")

    def test_strip_quotes_applies(self) -> None:
        a = _CollapseQuoteAdapter()
        apply_soft_fixes(a)
        # '"house"' → 'house'
        self.assertEqual(a.vocab[0]["translation"], "house")
        # 「你好」 → 你好
        self.assertEqual(a.expressions[0]["term"], "你好")

    def test_strip_quotes_does_not_misfire(self) -> None:
        # Escaped / unbalanced / empty-inner / inner-quote cases → no fix.
        a = _NoMisfireAdapter()
        batch = evaluate_soft_fixes(a)
        quote_fixes = [f for f in batch.fixes if f.rule_id == "hygiene.strip_surround_quotes"]
        self.assertEqual(quote_fixes, [])
        # And collapse must not fire on a single-space string.
        collapse = [f for f in batch.fixes if f.rule_id == "hygiene.collapse_repeated_spaces"]
        self.assertEqual(collapse, [])

    def test_collapse_undo(self) -> None:
        from PySide6.QtGui import QUndoStack

        from src.application.commands import SoftHygieneCommand
        from tests._qtapp import qt_app

        qt_app()
        a = _CollapseQuoteAdapter()
        stack = QUndoStack()
        before = a.vocab[0]["term"]
        batch = evaluate_soft_fixes(a)
        stack.push(SoftHygieneCommand(a, batch))
        self.assertEqual(a.vocab[0]["term"], "merhaba dünya")
        stack.undo()
        self.assertEqual(a.vocab[0]["term"], before)
        stack.redo()
        self.assertEqual(a.vocab[0]["term"], "merhaba dünya")

    def test_new_rules_keep_ids(self) -> None:
        a = _CollapseQuoteAdapter()
        ids_before = {e["id"] for e in a.vocab + a.expressions}
        apply_soft_fixes(a)
        ids_after = {e["id"] for e in a.vocab + a.expressions}
        self.assertEqual(ids_before, ids_after)

    def test_summarize_soft_batch(self) -> None:
        a = _Adapter()
        batch = evaluate_soft_fixes(a)
        self.assertGreater(len(batch), 0)
        text = summarize_soft_batch(batch)
        self.assertIn("规则规范化", text)
        self.assertIn(str(len(batch)), text)
        self.assertEqual(summarize_soft_batch(None), "")
        self.assertEqual(summarize_soft_batch(SoftFixBatch()), "")

    def test_all_fix_rule_ids_in_whitelist(self) -> None:
        # E1 gate G9 mirror: every produced rule_id is in the closed whitelist.
        from src.backend.experience.soft_autopilot import SOFT_RULE_IDS

        for a in (_Adapter(), _CollapseQuoteAdapter(), _NoMisfireAdapter()):
            batch = evaluate_soft_fixes(a)
            for f in batch.fixes:
                self.assertIn(f.rule_id, SOFT_RULE_IDS, f"non-whitelist rule {f.rule_id}")


class _CollapseQuoteAdapter:
    """Fixture exercising collapse_repeated_spaces + strip_surround_quotes."""

    def __init__(self) -> None:
        self.vocab = [
            {
                "id": "c1",
                "term": "merhaba   dünya",  # internal 3 spaces → collapse
                "translation": '"house"',  # ascii quotes → strip
                "tags": [],
            }
        ]
        self.expressions = [
            {
                "id": "c2",
                "term": "「你好」",  # CJK quotes → strip
                "translation": "good morning",
                "tags": [],
            }
        ]
        self._notified = 0

    def notify_resources_changed(self) -> None:
        self._notified += 1


class _NoMisfireAdapter:
    """Fixture where neither new rule should fire (guard against misfire)."""

    def __init__(self) -> None:
        self.vocab = [
            {
                "id": "n1",
                "term": 'a"b"c',  # inner quotes — must not strip
                "translation": "single space ok",  # no repeated ws — no collapse
                "tags": [],
            },
            {
                "id": "n2",
                "term": '"',  # unbalanced / too short — no strip
                "translation": '""',  # empty inner — no strip
                "tags": [],
            },
        ]
        self.expressions = []

    def notify_resources_changed(self) -> None:  # pragma: no cover
        pass


if __name__ == "__main__":
    unittest.main()
