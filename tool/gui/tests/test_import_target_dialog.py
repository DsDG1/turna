"""Tests for ImportTargetDialog (workshop import target selection)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from PySide6.QtWidgets import QDialog

from src.dialogs.import_target_dialog import ImportTargetDialog
from tests._qtapp import _App  # noqa: E402


def _mock_adapter():
    adapter = MagicMock()
    adapter.sections = [
        {
            "id": "s1",
            "name": "Section 1",
            "units": [
                {"id": "u1", "name": "Unit 1", "lessons": []},
                {"id": "u2", "name": "Unit 2", "lessons": []},
            ],
        },
        {
            "id": "s2",
            "name": "Section 2",
            "units": [
                {"id": "u3", "name": "Unit 3", "lessons": []},
            ],
        },
    ]
    return adapter


class ImportTargetDialogTest(unittest.TestCase):
    def setUp(self) -> None:
        _App.get()
        self.adapter = _mock_adapter()

    def test_new_section_default(self) -> None:
        dlg = ImportTargetDialog(self.adapter)
        with patch.object(QDialog, "exec", return_value=QDialog.DialogCode.Accepted):
            target = dlg.select()
        self.assertIsNotNone(target)
        self.assertEqual(target.mode, "new_section")

    def test_into_section_returns_section_id(self) -> None:
        dlg = ImportTargetDialog(self.adapter)
        dlg._into_section_radio.setChecked(True)
        dlg._section_combo.setCurrentIndex(1)  # s2
        with patch.object(QDialog, "exec", return_value=QDialog.DialogCode.Accepted):
            target = dlg.select()
        self.assertEqual(target.mode, "into_section")
        self.assertEqual(target.section_id, "s2")

    def test_into_unit_returns_unit_id(self) -> None:
        dlg = ImportTargetDialog(self.adapter)
        dlg._into_unit_radio.setChecked(True)
        dlg._section_combo.setCurrentIndex(0)  # s1
        dlg._unit_combo.setCurrentIndex(1)  # u2
        with patch.object(QDialog, "exec", return_value=QDialog.DialogCode.Accepted):
            target = dlg.select()
        self.assertEqual(target.mode, "into_unit")
        self.assertEqual(target.unit_id, "u2")

    def test_cancel_returns_none(self) -> None:
        dlg = ImportTargetDialog(self.adapter)
        with patch.object(QDialog, "exec", return_value=QDialog.DialogCode.Rejected):
            target = dlg.select()
        self.assertIsNone(target)

    def test_unit_combo_refreshes_on_section_change(self) -> None:
        dlg = ImportTargetDialog(self.adapter)
        dlg._section_combo.setCurrentIndex(1)  # s2
        unit_ids = [dlg._unit_combo.itemData(i) for i in range(dlg._unit_combo.count())]
        self.assertEqual(unit_ids, ["u3"])


if __name__ == "__main__":
    unittest.main()
