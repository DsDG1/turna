"""A3 follow-up (v4.67): AiFixDialog embeds PreviewHost for the diff preview.

Scope B - the bespoke section-tree / side-by-side JSON diff is replaced by the
shared PreviewHost component. The modal shell, correction flow, worker-identity
guard, and the ``exec()`` / ``corrected_node()`` caller contract are preserved.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock

from PySide6.QtCore import QObject, Signal
from PySide6.QtWidgets import QDialog

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from tests._qtapp import qt_app  # noqa: E402


class _FakeWorker(QObject):
    result_ready = Signal(object)
    error_occurred = Signal(str)
    completed = Signal()

    def __init__(self, target, *args, parent=None, **kwargs) -> None:
        super().__init__(parent)
        self._target = target
        self._args = args
        self._kwargs = kwargs

    def cancel(self) -> None:  # noqa: D401
        pass

    def isRunning(self) -> bool:  # noqa: N802
        return False

    def start(self, *args, **kwargs) -> None:  # noqa: D401
        pass


class AiFixDialogPreviewHostTest(unittest.TestCase):
    def setUp(self) -> None:
        qt_app()

    def _make_dialog(self, *, node_json, course_context):
        from src.dialogs.ai_fix_dialog import AiFixDialog

        problems = [{"level": "error", "path": "u", "message": "bad"}]
        config = MagicMock()
        config.is_complete = True
        with unittest.mock.patch(
            "src.dialogs.ai_fix_dialog.AiRequestWorker", _FakeWorker
        ):
            dlg = AiFixDialog(problems, node_json, course_context, config)
        return dlg

    def test_result_offers_via_preview_host(self) -> None:
        dlg = self._make_dialog(
            node_json={"id": "w1", "term": "merhaba", "translation": "hello"},
            course_context={"node_kind": "word"},
        )
        dlg._on_result(dlg._worker, {"id": "w1", "term": "merhaba", "translation": "hi"})
        # PreviewHost now has a pending apply action with summary + details.
        self.assertIsNotNone(dlg.preview_host._apply_fn)
        self.assertTrue(dlg.preview_host._summary.text().strip())
        # Success page is current.
        self.assertEqual(dlg.right_stack.currentIndex(), 1)
        # corrected_node returns the AI result.
        self.assertEqual(dlg.corrected_node()["translation"], "hi")

    def test_apply_accepts_dialog(self) -> None:
        dlg = self._make_dialog(
            node_json={"id": "w1", "term": "a", "translation": "x"},
            course_context={"node_kind": "word"},
        )
        dlg._on_result(dlg._worker, {"id": "w1", "term": "a", "translation": "y"})
        # Apply via the PreviewHost apply_fn -> dialog accepts.
        dlg.preview_host._apply_fn()
        self.assertEqual(dlg.result(), QDialog.DialogCode.Accepted)
        self.assertEqual(dlg.corrected_node()["translation"], "y")

    def test_discard_rejects_dialog(self) -> None:
        dlg = self._make_dialog(
            node_json={"id": "w1", "term": "a", "translation": "x"},
            course_context={"node_kind": "word"},
        )
        dlg._on_result(dlg._worker, {"id": "w1", "term": "a", "translation": "y"})
        dlg.preview_host._discard_fn()
        self.assertEqual(dlg.result(), QDialog.DialogCode.Rejected)

    def test_non_section_diff_details_per_field(self) -> None:
        dlg = self._make_dialog(
            node_json={"id": "w1", "term": "merhaba", "translation": "hello"},
            course_context={"node_kind": "word"},
        )
        summary, details = dlg._diff_preview(
            {"id": "w1", "term": "merhaba", "translation": "hello"},
            {"id": "w1", "term": "merhaba", "translation": "hi"},
        )
        self.assertIn("1", summary)  # 1 处字段变更
        # Per-field line for the changed translation.
        self.assertTrue(any("translation" in line and "hello" in line and "hi" in line for line in details))

    def test_section_diff_returns_summary_and_lines(self) -> None:
        dlg = self._make_dialog(
            node_json={"id": "s1", "units": []},
            course_context={"node_kind": "section"},
        )
        before = {"id": "s1", "units": []}
        after = {"id": "s1", "units": [{"id": "u1", "lessons": []}]}
        summary, details = dlg._diff_preview(before, after)
        self.assertIsInstance(summary, str)
        self.assertIsInstance(details, list)
        # Either structural changes counted or a no-change marker.
        self.assertTrue(summary)

    def test_diff_preview_never_crashes_on_garbage(self) -> None:
        dlg = self._make_dialog(
            node_json={"id": "s1", "units": []},
            course_context={"node_kind": "section"},
        )
        summary, details = dlg._diff_preview({}, "not-a-dict")  # type: ignore[arg-type]
        self.assertIsInstance(summary, str)
        self.assertEqual(details, [])


if __name__ == "__main__":
    unittest.main()
