"""E5-D palette_controller + K-25 help.fix pure/host tests."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from typing import Any
from unittest.mock import MagicMock

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.application.palette_controller import (  # noqa: E402
    LOW_CONFIDENCE_THRESHOLD,
    dispatch_palette_payload,
    empty_lessons_from_host,
    enrich_fill_empty_scope,
    history_rows_from_timeline,
    should_confirm_scope,
    show_help_tour,
)
from src.backend.experience.intent_router import Intent  # noqa: E402
from src.backend.experience.timeline import ExperienceTimeline  # noqa: E402
from src.widgets.command_palette import CommandPalette  # noqa: E402
from tests._qtapp import qt_app  # noqa: E402


class PureHelpersTest(unittest.TestCase):
    def test_history_rows_confidence_is_s04_armed(self) -> None:
        """F2: history replay conf 0.6 so write actions get scope confirm."""
        from types import SimpleNamespace

        from src.application.palette_controller import (
            history_rows_from_timeline,
            should_confirm_scope,
        )

        tl = SimpleNamespace(
            replayable=lambda n: [
                SimpleNamespace(
                    action_id="lesson.fill_empty",
                    summary="填空",
                    scope={"first_lesson_id": "l1"},
                )
            ]
        )
        rows = history_rows_from_timeline(tl, n=3)
        self.assertEqual(rows[0]["confidence"], 0.6)
        self.assertTrue(
            should_confirm_scope(
                "lesson.fill_empty",
                rows[0]["confidence"],
                needs_confirm=True,
            )
        )

    def test_history_rows_from_timeline(self) -> None:
        tl = ExperienceTimeline(maxlen=20)
        tl.record("x", "批修", action_id="validate.open_and_fix", scope={"n": 1})
        tl.record("x", "保存", action_id="app.save")  # app.* skipped by replayable
        tl.record("x", "清待补", action_id="resource.fill_stubs")
        rows = history_rows_from_timeline(tl, 3)
        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[0]["action_id"], "validate.open_and_fix")
        self.assertIn("最近", rows[0]["label"])
        self.assertEqual(rows[0]["scope"], {"n": 1})

    def test_history_rows_none_timeline(self) -> None:
        self.assertEqual(history_rows_from_timeline(None), [])

    def test_should_confirm_scope_matrix(self) -> None:
        self.assertFalse(
            should_confirm_scope("lesson.fill_empty", 1.0, needs_confirm=True)
        )
        self.assertFalse(
            should_confirm_scope("app.save", 0.6, needs_confirm=False)
        )
        self.assertFalse(
            should_confirm_scope("resource.open_hygiene", 0.6, needs_confirm=False)
        )
        self.assertTrue(
            should_confirm_scope("lesson.fill_empty", 0.6, needs_confirm=True)
        )
        self.assertLess(0.6, LOW_CONFIDENCE_THRESHOLD)

    def test_enrich_fill_empty_scope(self) -> None:
        self.assertEqual(
            enrich_fill_empty_scope({}, ["l1", "l2"])["first_lesson_id"],
            "l1",
        )
        self.assertEqual(
            enrich_fill_empty_scope({"first_lesson_id": "keep"}, ["l1"])[
                "first_lesson_id"
            ],
            "keep",
        )
        self.assertEqual(enrich_fill_empty_scope({}, []), {})


class DispatchHostTest(unittest.TestCase):
    def setUp(self) -> None:
        self.saves: list[str] = []
        self.suggests: list[dict] = []
        self.confirms: list[tuple] = []
        self.why = 0
        self.pin = 0
        self.events: list[tuple] = []
        self.host = SimpleNamespace(
            experience=SimpleNamespace(
                context=SimpleNamespace(empty_lessons=["empty-1"])
            ),
            undo_stack=MagicMock(),
            _on_save=lambda reason="menu": self.saves.append(reason),
            _on_experience_suggestion=lambda p: self.suggests.append(dict(p)),
            _confirm_scope_for_low_confidence=lambda *a: (
                self.confirms.append(a) or True
            ),
            _experience_why_current=lambda: setattr(self, "why", self.why + 1),
            _on_experience_pin_toggled=lambda: setattr(self, "pin", self.pin + 1),
            _record_experience_event=lambda *a, **k: self.events.append((a, k)),
            _palette_help_non_modal=True,
        )

    def test_dispatch_save(self) -> None:
        dispatch_palette_payload(
            self.host, {"action_id": "app.save", "confidence": 1.0}
        )
        self.assertEqual(self.saves, ["palette"])

    def test_dispatch_undo(self) -> None:
        dispatch_palette_payload(self.host, {"action_id": "app.undo"})
        self.host.undo_stack.undo.assert_called_once()

    def test_dispatch_why_pin(self) -> None:
        dispatch_palette_payload(self.host, {"action_id": "app.why"})
        dispatch_palette_payload(self.host, {"action_id": "app.pin"})
        self.assertEqual(self.why, 1)
        self.assertEqual(self.pin, 1)

    def test_dispatch_skill_enrich_fill(self) -> None:
        dispatch_palette_payload(
            self.host,
            {
                "action_id": "lesson.fill_empty",
                "label": "填充空课",
                "confidence": 1.0,
                "scope": {},
            },
        )
        self.assertEqual(len(self.suggests), 1)
        self.assertEqual(self.suggests[0]["action_id"], "lesson.fill_empty")
        self.assertEqual(self.suggests[0]["scope"]["first_lesson_id"], "empty-1")
        self.assertEqual(self.confirms, [])

    def test_low_confidence_confirm_cancel(self) -> None:
        self.host._confirm_scope_for_low_confidence = lambda *a: False
        dispatch_palette_payload(
            self.host,
            {
                "action_id": "lesson.fill_empty",
                "confidence": 0.6,
                "label": "填充",
                "scope": {},
            },
        )
        self.assertEqual(self.suggests, [])

    def test_low_confidence_confirm_ok(self) -> None:
        dispatch_palette_payload(
            self.host,
            {
                "action_id": "lesson.fill_empty",
                "confidence": 0.6,
                "label": "填充",
                "scope": {},
            },
        )
        self.assertEqual(len(self.confirms), 1)
        self.assertEqual(len(self.suggests), 1)

    def test_empty_action_noop(self) -> None:
        dispatch_palette_payload(self.host, {"action_id": ""})
        self.assertEqual(self.suggests, [])

    def test_empty_lessons_from_host(self) -> None:
        self.assertEqual(empty_lessons_from_host(self.host), ["empty-1"])
        self.assertEqual(empty_lessons_from_host(SimpleNamespace()), [])


class HelpFixAndAsyncTest(unittest.TestCase):
    def setUp(self) -> None:
        qt_app()

    def test_help_tour_click_dispatches_validate(self) -> None:
        suggests: list[dict] = []
        host = SimpleNamespace(
            _on_experience_suggestion=lambda p: suggests.append(dict(p)),
            _record_experience_event=lambda *a, **k: None,
            _palette_help_non_modal=True,
            experience=None,
            undo_stack=MagicMock(),
        )
        from PySide6.QtWidgets import QListWidget

        show_help_tour(host)
        dlg = host._last_help_dialog
        self.assertIsNotNone(dlg)
        # First row should be /validate (app.help skipped in list).
        list_w = dlg.findChild(QListWidget)
        self.assertIsNotNone(list_w)
        self.assertGreater(list_w.count(), 0)
        item = list_w.item(0)
        list_w.itemClicked.emit(item)
        self.assertEqual(len(suggests), 1)
        self.assertEqual(suggests[0]["action_id"], "validate.open_and_fix")

    def test_async_hook_called_when_no_local_match(self) -> None:
        calls: list[str] = []
        pal = CommandPalette()
        pal.set_async_candidate_hook(lambda t: calls.append(t))
        # setText already fires textChanged; do not emit a second time.
        pal.input.setText("zzzzz不存在的查询词")
        self.assertEqual(calls, ["zzzzz不存在的查询词"])
        self.assertTrue(pal._loading_async)
    def test_apply_async_candidates_merges(self) -> None:
        pal = CommandPalette()
        pal.input.setText("mystery phrase")
        pal.input.textChanged.emit("mystery phrase")
        # No local match → empty intents (unless hook sets loading).
        pal.apply_async_candidates(
            "mystery phrase",
            [
                Intent(
                    action_id="app.why",
                    label="LLM: 解释",
                    confidence=0.7,
                )
            ],
        )
        self.assertEqual(len(pal._intents), 1)
        self.assertEqual(pal._intents[0].action_id, "app.why")

    def test_apply_async_stale_ignored(self) -> None:
        pal = CommandPalette()
        pal.input.setText("current")
        pal.apply_async_candidates(
            "old query",
            [Intent(action_id="app.save", label="save", confidence=0.7)],
        )
        # Stale must not inject intents over current local match for "current".
        # "current" has no match → empty; stale still ignored so still empty.
        self.assertEqual(pal._intents, [])

    def test_async_hook_not_called_when_local_match(self) -> None:
        calls: list[str] = []
        pal = CommandPalette()
        pal.set_async_candidate_hook(lambda t: calls.append(t))
        pal.input.setText("/validate")
        self.assertEqual(calls, [])
        self.assertGreaterEqual(len(pal._intents), 1)

if __name__ == "__main__":
    unittest.main()
