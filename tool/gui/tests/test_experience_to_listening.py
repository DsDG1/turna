"""v4.39 K-13 item.to_listening tests (deterministic migrate + patch + undo)."""
from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from tests._qtapp import qt_app  # noqa: E402


def _stage_item(*, iid="q1", rt="multipleChoice"):
    return {"id": iid, "runtimeType": rt, "prompt": "merhaba", "expected": "hello",
            "options": ["hello", "x"]}


def _lesson_with_item(*, iid="q1", rt="multipleChoice"):
    item = _stage_item(iid=iid, rt=rt)
    return {
        "id": "l1", "template": "practice",
        "content": {"stages": [{"id": "st1", "items": [item]}]},
    }


class SwitchRuntimeTypeTest(unittest.TestCase):
    def test_to_listen_preserves_id_and_type(self) -> None:
        from src.backend.lesson_content import switch_runtime_type

        new = switch_runtime_type(_stage_item(), "listenAndPick")
        self.assertEqual(new["id"], "q1")
        self.assertEqual(new["runtimeType"], "listenAndPick")
        self.assertIn("audioAsset", new)

    def test_id_never_changes(self) -> None:
        from src.backend.lesson_content import switch_runtime_type

        for target in ("listenAndPick", "typeTheWord", "fillBlank"):
            new = switch_runtime_type(_stage_item(), target)
            self.assertEqual(new["id"], "q1")


class _CmdSignals:
    def __init__(self) -> None:
        self.changed = self

    def connect(self, _cb) -> None:
        pass


class _FakeApplyItemPatchCommand:
    def __init__(self, stage, patch) -> None:
        self.stage = stage
        self.patch = patch
        self.signals = _CmdSignals()
        self.pushed = True
        # simulate redo: replace item in stage
        from src.backend.experience.patch import apply_item_patch
        apply_item_patch(stage, patch)


class _UndoStack:
    def __init__(self) -> None:
        self.commands: list = []

    def push(self, cmd) -> None:
        self.commands.append(cmd)


class _Adapter:
    def __init__(self, lesson: dict) -> None:
        self.section = {"id": "s1", "units": [{"id": "u1", "lessons": [lesson]}]}

    def find_lesson(self, lesson_id: str):
        if lesson_id != "l1":
            raise KeyError(lesson_id)
        return self.section, self.section["units"][0], self.section["units"][0]["lessons"][0]


class ToListeningSkillTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        qt_app()

    def _make_window(self, lesson: dict, *, current=("lesson", "l1")):
        from PySide6.QtWidgets import QWidget
        from src.application.experience_skills_mixin import ExperienceSkillsMixin
        from src.backend.experience.conflict_guard import ConflictGuard

        win = QWidget()
        self.addCleanup(win.deleteLater)
        win.course_dir = "/tmp/course"
        win._current_node_ref = current
        win.adapter = _Adapter(lesson)
        win.undo_stack = _UndoStack()
        win.experience_metrics = _Metrics()
        win._messages: list[str] = []
        win.statusBar = lambda: SimpleNamespace(
            showMessage=lambda m, ms=0: win._messages.append(m)
        )
        win._on_ai_edit_applied = lambda *a: None
        win._record_experience_event = lambda *a, **k: None
        win._refresh_validate_after_ai = lambda msg: None
        return win

    def test_no_selection_status(self) -> None:
        from src.application.experience_skills_mixin import ExperienceSkillsMixin

        win = self._make_window(_lesson_with_item(), current=("tree", "x"))
        ExperienceSkillsMixin._experience_to_listening(win, {})
        self.assertTrue(any("选中要迁的题" in m for m in win._messages))
        self.assertEqual(len(win.undo_stack.commands), 0)

    def test_already_listening_status(self) -> None:
        from src.application.experience_skills_mixin import ExperienceSkillsMixin

        lesson = _lesson_with_item(rt="listenAndPick")
        win = self._make_window(lesson)
        ExperienceSkillsMixin._experience_to_listening(win, {"item_id": "q1", "lesson_id": "l1"})
        self.assertTrue(any("已是听力题" in m for m in win._messages))
        self.assertEqual(len(win.undo_stack.commands), 0)

    def test_confirm_applies_patch_preserves_id(self) -> None:
        from src.application.experience_skills_mixin import ExperienceSkillsMixin

        lesson = _lesson_with_item(rt="multipleChoice")
        win = self._make_window(lesson)
        # v4.46+: confirm goes through ui_guard.safe_question imported into
        # the memory_nav handler namespace.
        with patch(
            "src.application.experience_handlers.memory_nav.safe_question",
            return_value=True,
        ), patch(
            "src.application.commands.ApplyItemPatchCommand",
            _FakeApplyItemPatchCommand,
        ):
            ExperienceSkillsMixin._experience_to_listening(
                win, {"item_id": "q1", "lesson_id": "l1"}
            )
        self.assertEqual(len(win.undo_stack.commands), 1)
        item = lesson["content"]["stages"][0]["items"][0]
        self.assertEqual(item["id"], "q1")  # id preserved
        self.assertEqual(item["runtimeType"], "listenAndPick")
        m = win.experience_metrics.counts
        self.assertEqual(m.get(("suggestion", "item.to_listening", "applied")), 1)

    def test_decline_records_rejected_no_patch(self) -> None:
        from src.application.experience_skills_mixin import ExperienceSkillsMixin

        lesson = _lesson_with_item(rt="multipleChoice")
        win = self._make_window(lesson)
        with patch(
            "src.application.experience_handlers.memory_nav.safe_question",
            return_value=False,
        ):
            ExperienceSkillsMixin._experience_to_listening(
                win, {"item_id": "q1", "lesson_id": "l1"}
            )
        self.assertEqual(len(win.undo_stack.commands), 0)
        m = win.experience_metrics.counts
        self.assertEqual(m.get(("suggestion", "item.to_listening", "rejected")), 1)

    def test_no_course_dir_status(self) -> None:
        from src.application.experience_skills_mixin import ExperienceSkillsMixin

        win = self._make_window(_lesson_with_item())
        win.course_dir = ""
        with patch("src.application.experience_skills_mixin.QMessageBox") as mb:
            mb.StandardButton = __import__(
                "PySide6.QtWidgets", fromlist=["QMessageBox"]
            ).QMessageBox.StandardButton
            ExperienceSkillsMixin._experience_to_listening(win, {"item_id": "q1"})
        self.assertIsNone(getattr(win, "_applied", None))


class _Metrics:
    def __init__(self) -> None:
        self.counts: dict[tuple, int] = {}

    def _inc(self, key: tuple) -> None:
        self.counts[key] = self.counts.get(key, 0) + 1

    def inc_suggestion(self, action_id: str, stage: str) -> None:
        self._inc(("suggestion", action_id, stage))


class RoutingContractTest(unittest.TestCase):
    def test_slash_exact(self) -> None:
        from src.backend.experience.intent_router import route_intent

        i = route_intent("/to-listening")
        self.assertEqual(i.action_id, "item.to_listening")
        self.assertEqual(i.confidence, 1.0)

    def test_keyword_not_shadowed_by_fill_gaps(self) -> None:
        from src.backend.experience.intent_router import route_intent

        # 迁为听力 contains 听力 but should route to K-13, not listening.fill_gaps
        self.assertEqual(route_intent("迁为听力").action_id, "item.to_listening")
        self.assertEqual(route_intent("听力缺口").action_id, "listening.fill_gaps")

    def test_action_spec_needs_confirm_not_dangerous(self) -> None:
        from src.backend.experience import get_action
        from src.backend.experience.actions import DANGEROUS_ACTION_IDS

        spec = get_action("item.to_listening")
        self.assertTrue(spec.needs_confirm)
        self.assertFalse(spec.dangerous)
        self.assertNotIn("item.to_listening", DANGEROUS_ACTION_IDS)


if __name__ == "__main__":
    unittest.main()