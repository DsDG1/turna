"""Tests for the merged PublishDialog (expert vs teacher_friendly modes).

Locks in that ``teacher_friendly=True`` hides the engineering sections
(id-set diff, per-file bump checkboxes, raw lint warnings) and humanizes
validate errors, while the expert path keeps the full release-engineer
checklist.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from PySide6.QtWidgets import QDialogButtonBox

from src.widgets.publish_dialog import PublishDialog
from tests._qtapp import _App  # noqa: E402


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
    return adapter


class PublishDialogModeTest(unittest.TestCase):
    def setUp(self) -> None:
        _App.get()

    def _ok_text(self, dlg: PublishDialog) -> str:
        return dlg.buttons.button(QDialogButtonBox.StandardButton.Ok).text()

    def _ok_enabled(self, dlg: PublishDialog) -> bool:
        return dlg.buttons.button(QDialogButtonBox.StandardButton.Ok).isEnabled()

    def test_expert_mode_shows_full_checklist(self) -> None:
        dlg = PublishDialog(_adapter_with_report(), None, teacher_friendly=False)
        self.assertIsNotNone(dlg.diff_group)
        self.assertIsNotNone(dlg.bump_group)
        self.assertEqual(self._ok_text(dlg), "确认发布")
        # Expert changes label lists all five categories including sections.
        self.assertIn("section 内容", dlg.changes_label.text())

    def test_teacher_mode_hides_engineering_sections(self) -> None:
        dlg = PublishDialog(_adapter_with_report(), None, teacher_friendly=True)
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
        dlg = PublishDialog(adapter, None, teacher_friendly=True)
        self.assertFalse(self._ok_enabled(dlg))
        # Raw engineering message is not shown verbatim; humanized text is.
        self.assertNotIn("vocab[0].id", dlg.validation_label.text())
        self.assertIn("引用了不存在的词", dlg.validation_label.text())

    def test_expert_mode_shows_raw_error_tooltip(self) -> None:
        adapter = _adapter_with_report(ok=False, errors=[
            {"message": "raw error string", "path": ""}
        ])
        dlg = PublishDialog(adapter, None, teacher_friendly=False)
        self.assertFalse(self._ok_enabled(dlg))
        self.assertIn("raw error string", dlg.validation_label.toolTip())


if __name__ == "__main__":
    unittest.main()
