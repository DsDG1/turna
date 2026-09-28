"""T8: AiMergePreviewDialog shows both sides and defaults to skip."""
from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from PySide6.QtCore import Qt
from PySide6.QtWidgets import QTreeWidget

from src.backend.course_adapter import CourseAdapter
from src.dialogs.ai.ai_merge_preview_dialog import AiMergePreviewDialog
from tests._course_samples import sample_section_from_chapter
from tests._qtapp import _App


def _plan_with_collision():
    adapter = CourseAdapter()
    adapter.sections.append(sample_section_from_chapter("sec-x"))
    return adapter.plan_section_merge(
        "sec-x", sample_section_from_chapter("sec-x")
    )


class AiMergePreviewDialogTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        _App.get()

    def test_replaced_rows_default_to_skip_with_existing_summary(self) -> None:
        plan = _plan_with_collision()
        dlg = AiMergePreviewDialog(plan)
        tree = dlg.findChild(QTreeWidget)
        # The replaced unit row: unchecked by default (overwrite is opt-in)…
        unit_item = tree.topLevelItem(0).child(0)
        self.assertEqual(unit_item.checkState(0), Qt.CheckState.Unchecked)
        self.assertEqual(plan.replaced_units[0].action, "skip")
        # …and its tooltip shows what would be overwritten (the existing
        # side, not just the incoming one).
        tip = unit_item.toolTip(0)
        self.assertIn("覆盖现有", tip)
        self.assertIn("个课时", tip)
        # Same default for the replaced lesson row.
        lesson_item = unit_item.child(0)
        self.assertEqual(lesson_item.checkState(0), Qt.CheckState.Unchecked)
        unit_id = next(iter(plan.replaced_lessons_by_unit))
        self.assertEqual(
            plan.replaced_lessons_by_unit[unit_id][0].action, "skip"
        )
        self.assertIn("将覆盖现有课时", lesson_item.toolTip(0))
        dlg.deleteLater()

    def test_checking_unit_restores_children_after_uncheck(self) -> None:
        """T8 recheck fix: uncheck cascades skip; REcheck restores children."""
        plan = _plan_with_collision()
        dlg = AiMergePreviewDialog(plan)
        tree = dlg.findChild(QTreeWidget)
        unit_item = tree.topLevelItem(0).child(0)
        lesson_item = unit_item.child(0)

        # Opt in (check) the unit → children restore to their original action.
        unit_item.setCheckState(0, Qt.CheckState.Checked)
        self.assertEqual(plan.replaced_units[0].action, "replace")
        unit_id = next(iter(plan.replaced_lessons_by_unit))
        lesson_action = plan.replaced_lessons_by_unit[unit_id][0]
        self.assertEqual(lesson_action.action, "replace")
        self.assertEqual(lesson_item.checkState(0), Qt.CheckState.Checked)

        # Uncheck → cascade skip…
        unit_item.setCheckState(0, Qt.CheckState.Unchecked)
        self.assertEqual(lesson_action.action, "skip")
        self.assertEqual(lesson_item.checkState(0), Qt.CheckState.Unchecked)

        # …and recheck brings the children back (the old bug left them
        # skipped forever).
        unit_item.setCheckState(0, Qt.CheckState.Checked)
        self.assertEqual(lesson_action.action, "replace")
        self.assertEqual(lesson_item.checkState(0), Qt.CheckState.Checked)
        dlg.deleteLater()


if __name__ == "__main__":
    unittest.main()
