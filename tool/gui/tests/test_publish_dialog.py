"""Tests for the merged PublishDialog (expert vs teacher_friendly modes).

Locks in that ``teacher_friendly=True`` hides the engineering sections
(id-set diff, per-file bump checkboxes, raw lint warnings) and humanizes
validate errors, while the expert path keeps the full release-engineer
checklist. The async paths (report fetch / publish save on a worker) are
covered by the busy-state + settle tests at the bottom.
"""
from __future__ import annotations

import sys
import time
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

from PySide6.QtCore import QThread
from PySide6.QtWidgets import QApplication, QDialog

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.widgets.publish_dialog import PublishDialog
from tests._qtapp import _App


def _adapter_with_report(*, ok: bool = True, errors=None):
    adapter = MagicMock()
    adapter.release_report.return_value = {
        "changes": {
            "index": True,
            "sections": False,
            "vocab": True,
            "expressions": False,
            "grammar_points": False,
        },
        "version_bump": {"index": (1, 2)},
        "audio_manifest": [
            {"asset_id": "a1", "status": "ok"},
            {"asset_id": "a2", "status": "missing"},
        ],
        "diff": {
            "vocab": {"added": ["w1"], "removed": [], "unchanged_count": 3},
            "expressions": {"added": [], "removed": [], "unchanged_count": 0},
            "grammar_points": {"added": [], "removed": [], "unchanged_count": 0},
            "sections": {"added": [], "removed": [], "unchanged_count": 1},
        },
        "validation": {"ok": ok, "errors": errors or [], "warnings": []},
    }
    adapter.save.return_value = MagicMock(ok=True, message="saved")
    return adapter


def _spin_until(condition, timeout: float = 5.0) -> bool:
    """Process events until ``condition()`` is true (worker signal delivery)."""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        QApplication.processEvents()
        if condition():
            return True
        QThread.msleep(10)
    QApplication.processEvents()
    return bool(condition())


class PublishDialogModeTest(unittest.TestCase):
    def setUp(self) -> None:
        _App.get()

    def _make_dlg(self, adapter, *, teacher_friendly: bool) -> PublishDialog:
        # Deterministic synchronous render for mode assertions; the async
        # path has its own tests below.
        return PublishDialog(
            adapter, None, teacher_friendly=teacher_friendly, load_async=False
        )

    def _ok_text(self, dlg: PublishDialog) -> str:
        return dlg.ok_btn.text()

    def _ok_enabled(self, dlg: PublishDialog) -> bool:
        return dlg.ok_btn.isEnabled()

    def test_expert_mode_shows_full_checklist(self) -> None:
        dlg = self._make_dlg(_adapter_with_report(), teacher_friendly=False)
        self.assertIsNotNone(dlg.diff_group)
        self.assertIsNotNone(dlg.bump_group)
        self.assertEqual(self._ok_text(dlg), "确认发布")
        # Expert changes label lists all five categories including sections.
        self.assertIn("section 内容", dlg.changes_label.text())

    def test_teacher_mode_hides_engineering_sections(self) -> None:
        dlg = self._make_dlg(_adapter_with_report(), teacher_friendly=True)
        self.assertFalse(hasattr(dlg, "diff_group"))
        self.assertFalse(hasattr(dlg, "bump_group"))
        self.assertEqual(self._ok_text(dlg), "发布")
        # Teacher changes label hides the raw "sections" category.
        self.assertNotIn("section 内容", dlg.changes_label.text())
        # Version shown as an auto-update line (no raw filename).
        self.assertIn("自动更新", dlg.version_label.text())

    def test_teacher_mode_humanizes_validation_failure(self) -> None:
        adapter = _adapter_with_report(ok=False, errors=[
            {"message": "vocab[0].id references missing word w_missing",
             "path": "section:section1/unit:u-1/lesson:s1-l1"}
        ])
        dlg = self._make_dlg(adapter, teacher_friendly=True)
        self.assertFalse(self._ok_enabled(dlg))
        # Raw engineering message is not shown verbatim; humanized text is.
        self.assertNotIn("vocab[0].id", dlg.validation_label.text())
        self.assertIn("引用了不存在的词", dlg.validation_label.text())

    def test_expert_mode_shows_raw_error_tooltip(self) -> None:
        adapter = _adapter_with_report(ok=False, errors=[
            {"message": "raw error string", "path": ""}
        ])
        dlg = self._make_dlg(adapter, teacher_friendly=False)
        self.assertFalse(self._ok_enabled(dlg))
        self.assertIn("raw error string", dlg.validation_label.toolTip())


class PublishDialogAsyncTest(unittest.TestCase):
    def setUp(self) -> None:
        _App.get()

    def test_async_load_shows_busy_state_then_renders(self) -> None:
        dlg = PublishDialog(_adapter_with_report(), None, teacher_friendly=False)
        # Busy state is visible immediately: hint text + disabled actions.
        self.assertIn("正在生成", dlg.changes_label.text())
        self.assertFalse(dlg.ok_btn.isEnabled())
        self.assertFalse(dlg.export_btn.isEnabled())
        self.assertTrue(
            _spin_until(lambda: dlg._load_worker is None and bool(dlg._report))
        )
        # Report rendered; buttons reflect the (passing) validation.
        self.assertTrue(dlg.ok_btn.isEnabled())
        self.assertTrue(dlg.export_btn.isEnabled())
        self.assertIn("结构", dlg.changes_label.text())

    def test_async_publish_runs_on_worker_and_accepts(self) -> None:
        adapter = _adapter_with_report()
        dlg = PublishDialog(
            adapter, None, teacher_friendly=False, load_async=False
        )
        with patch("src.widgets.publish_dialog.QMessageBox"):
            dlg._on_publish()
            # Busy immediately: publishing flag set, actions disabled.
            self.assertTrue(dlg._publishing)
            self.assertFalse(dlg.ok_btn.isEnabled())
            self.assertFalse(dlg.cancel_btn.isEnabled())
            self.assertEqual(dlg.ok_btn.text(), "发布中…")
            # Esc / close must not tear the dialog down mid-save.
            with patch.object(QDialog, "reject") as super_reject:
                dlg.reject()
                super_reject.assert_not_called()
            self.assertTrue(_spin_until(lambda: dlg._publish_worker is None))
        self.assertFalse(dlg._publishing)
        self.assertEqual(dlg.result(), QDialog.DialogCode.Accepted)
        adapter.apply_version_bump.assert_called_once()
        adapter.save.assert_called_once()

    def test_async_publish_failure_keeps_dialog_open(self) -> None:
        adapter = _adapter_with_report()
        adapter.save.return_value = MagicMock(ok=False, message="boom")
        dlg = PublishDialog(
            adapter, None, teacher_friendly=False, load_async=False
        )
        with patch("src.widgets.publish_dialog.QMessageBox") as msg_box:
            dlg._on_publish()
            self.assertTrue(_spin_until(lambda: dlg._publish_worker is None))
            msg_box.critical.assert_called_once()
        self.assertFalse(dlg._publishing)
        self.assertTrue(dlg.ok_btn.isEnabled())
        self.assertEqual(dlg.result(), 0)  # not accepted


if __name__ == "__main__":
    unittest.main()
