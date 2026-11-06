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

from PySide6.QtCore import QObject, Signal
from PySide6.QtWidgets import QDialog, QMessageBox

from src.application.course_plan_service import CoursePlanService
from src.application.course_preview_service import (
    apply_publication_state,
    feedback_to_problem,
    section_hash,
)
from src.dialogs.ai.design_controller import DesignController
from src.widgets.course_preview_dialog import CoursePreviewDialog
from tests._qtapp import _App


def _section() -> dict:
    return {
        "id": "s",
        "name": "草稿",
        "units": [
            {
                "id": "u",
                "name": "单元",
                "lessons": [
                    {
                        "id": "l",
                        "name": "课",
                        "content": {
                            "stages": [
                                {
                                    "id": "st",
                                    "items": [
                                        {
                                            "id": "q",
                                            "runtimeType": "multipleChoice",
                                            "prompt": "选一",
                                            "options": ["A", "B"],
                                            "correctIndex": 0,
                                        }
                                    ],
                                }
                            ]
                        },
                    }
                ],
            }
        ],
    }


def _entry() -> dict:
    return {
        "id": "feedback-one",
        "revision": 1,
        "item_key": "section:s/unit:u/lesson:l/stages:st/item:q",
        "category": "answer",
        "reviewer": "老师",
        "message": "第二个选项也对，请修改。",
        "question": {
            "location": "单元 › 课 › 第 1 项",
            "prompt": "选一",
            "answer": "A",
        },
    }


class _FakeWorker(QObject):
    result_ready = Signal(object)
    error_occurred = Signal(str)
    completed = Signal()

    def __init__(self, target, *args, parent=None, **kwargs):
        super().__init__(parent)
        self.target = target
        self.args = args
        self.kwargs = kwargs

    def start(self) -> None:
        try:
            result = self.target(*self.args, **self.kwargs)
        except Exception as exc:
            self.error_occurred.emit(str(exc))
        else:
            self.result_ready.emit(result)
        finally:
            self.completed.emit()


class _FakeService:
    def __init__(self) -> None:
        self.publish_calls = []
        self.feedback_entries = [_entry()]

    def publish(self, section, preview_id=""):
        self.publish_calls.append((section, preview_id))
        revision = len(self.publish_calls)
        return {
            "preview_id": "a" * 22,
            "url": f"https://example.test/p/{'a' * 22}/",
            "current_revision": revision,
            "current_hash": section_hash(section),
            "updated_at": "2026-11-06T00:00:00+00:00",
        }

    def feedback(self, preview_id):
        return list(self.feedback_entries)


class _AcceptedDiffView:
    def __init__(self, *args, **kwargs):
        pass

    def exec(self):
        return QDialog.DialogCode.Accepted


class _RejectedDiffView(_AcceptedDiffView):
    def exec(self):
        return QDialog.DialogCode.Rejected


class CoursePreviewDialogTest(unittest.TestCase):
    def setUp(self) -> None:
        _App.get()
        self.draft = _section()
        self.service = _FakeService()
        self.states = []
        self.dialog = CoursePreviewDialog(
            draft_fn=lambda: self.draft,
            preview_state={},
            on_state_changed=self.states.append,
            on_apply_revision=self._apply,
            validate=lambda _draft: [],
            ai_config=SimpleNamespace(is_complete=True),
            course_context={"node_kind": "section", "node_id": "s"},
            service_factory=lambda _target: self.service,
            worker_factory=_FakeWorker,
            revision_fn=self._revise,
        )
        self.addCleanup(self.dialog.deleteLater)

    def _apply(self, corrected) -> None:
        self.draft = corrected

    def _revise(self, *args, **kwargs):
        corrected = _section()
        corrected["name"] = "根据反馈修订"
        return corrected

    def test_publish_persists_link_revision_and_closes_pending_feedback(self) -> None:
        self.dialog._state["pending_feedback_ids"] = ["old-feedback"]

        self.dialog._start_publish()

        self.assertEqual(len(self.service.publish_calls), 1)
        self.assertEqual(self.dialog._state["published_revision"], 1)
        self.assertEqual(self.dialog._state["handled_feedback_ids"], ["old-feedback"])
        self.assertEqual(self.dialog._state["pending_feedback_ids"], [])
        self.assertTrue(self.dialog.url_edit.text().startswith("https://example.test/"))
        self.assertTrue(self.states)

    def test_feedback_revision_applies_and_marks_only_after_publish(self) -> None:
        initial = self.draft
        self.dialog._state.update(
            {"preview_id": "a" * 22, "published_revision": 1, "published_hash": section_hash(initial)}
        )
        self.dialog._start_feedback()
        with patch("src.widgets.course_preview_dialog.SectionDiffView", _AcceptedDiffView):
            self.dialog._on_revise()

        self.assertEqual(self.draft["name"], "根据反馈修订")
        self.assertEqual(len(self.service.publish_calls), 1)
        self.assertEqual(self.dialog._state["handled_feedback_ids"], ["feedback-one"])
        self.assertEqual(self.dialog.feedback_list.count(), 0)

    def test_validation_failure_preserves_draft_and_feedback(self) -> None:
        self.dialog._state.update({"preview_id": "a" * 22, "published_revision": 1})
        self.dialog._validate = lambda _draft: [{"level": "error", "message": "坏题"}]
        self.dialog._start_feedback()
        with patch("src.widgets.course_preview_dialog.SectionDiffView", _AcceptedDiffView), patch.object(QMessageBox, "warning") as warning:
            self.dialog._on_revise()

        self.assertEqual(self.draft["name"], "草稿")
        self.assertEqual(self.service.publish_calls, [])
        self.assertEqual(self.dialog._state["handled_feedback_ids"], [])
        warning.assert_called_once()

    def test_rejected_diff_preserves_draft_and_feedback(self) -> None:
        self.dialog._state.update({"preview_id": "a" * 22, "published_revision": 1})
        self.dialog._start_feedback()
        with patch("src.widgets.course_preview_dialog.SectionDiffView", _RejectedDiffView):
            self.dialog._on_revise()

        self.assertEqual(self.draft["name"], "草稿")
        self.assertEqual(self.service.publish_calls, [])
        self.assertEqual(self.dialog._state["handled_feedback_ids"], [])

    def test_publish_failure_does_not_close_pending_feedback(self) -> None:
        self.dialog._state["pending_feedback_ids"] = ["old-feedback"]

        def fail(_section, preview_id=""):
            raise RuntimeError("ssh unavailable")

        self.service.publish = fail
        with patch.object(QMessageBox, "warning"):
            self.dialog._start_publish()

        self.assertEqual(self.dialog._state["handled_feedback_ids"], [])
        self.assertEqual(self.dialog._state["pending_feedback_ids"], ["old-feedback"])


class PreviewStateAndPromptTest(unittest.TestCase):
    def test_feedback_problem_contains_old_revision_and_snapshot(self) -> None:
        problem = feedback_to_problem(_entry(), current_revision=2)

        self.assertIn("旧修订 r1", problem["message"])
        self.assertIn("第二个选项也对", problem["message"])
        self.assertIn("提交时参考答案：A", problem["message"])
        self.assertEqual(problem["feedback_id"], "feedback-one")

    def test_publication_requires_preview_id(self) -> None:
        with self.assertRaises(ValueError):
            apply_publication_state({}, {}, set())

    def test_design_controller_web_preview_roundtrip(self) -> None:
        controller = DesignController(ai_config_fn=lambda: SimpleNamespace())
        state = {"preview_id": "a" * 22, "published_revision": 4}
        controller.set_web_preview_state(state)
        restored = DesignController(ai_config_fn=lambda: SimpleNamespace())

        restored.apply_design_dict(controller.to_design_dict())

        self.assertEqual(restored.web_preview_state, state)
        self.assertIsNot(restored.web_preview_state, controller.web_preview_state)

    def test_course_plan_preview_state_uses_progress_and_saves(self) -> None:
        store = MagicMock()
        service = CoursePlanService(SimpleNamespace(), store=store)
        plan = SimpleNamespace(progress={})

        service.set_preview_state(plan, "sec-1", {"preview_id": "a" * 22})

        self.assertEqual(service.preview_state(plan, "sec-1")["preview_id"], "a" * 22)
        store.save_plan.assert_called_once_with(plan)


if __name__ == "__main__":
    unittest.main()
