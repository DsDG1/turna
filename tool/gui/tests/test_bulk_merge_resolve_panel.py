"""Tests for BulkMergeResolveDialog (connectplan D7 / P1-2)."""
from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))
from tests._course_samples import sample_section_from_chapter  # noqa: E402


from src.backend.course_adapter import CourseAdapter  # noqa: E402
from src.widgets.bulk_merge_resolve_panel import BulkMergeResolveDialog  # noqa: E402
from tests._qtapp import _App  # noqa: E402


def _plans(adapter: CourseAdapter, sids: list[str]):
    return [
        adapter.plan_section_merge(sid, sample_section_from_chapter(sid)) for sid in sids
    ]


class BulkMergeResolveDialogTest(unittest.TestCase):
    def setUp(self) -> None:
        _App.get()
        self.adapter = CourseAdapter()
        for sid in ("sec-a", "sec-b"):
            self.adapter.sections.append(sample_section_from_chapter(sid))
        self.plans = _plans(self.adapter, ["sec-a", "sec-b"])

    def test_rows_render_with_counts(self) -> None:
        dlg = BulkMergeResolveDialog(self.plans)
        self.assertEqual(dlg._table.rowCount(), 2)
        self.assertEqual(dlg._table.item(0, 0).text(), "sec-a")
        # Replace counts: 1 unit + 1 lesson per colliding section.
        self.assertEqual(dlg._table.item(0, 3).text(), "2")
        dlg.deleteLater()

    def test_default_decisions_merge_all(self) -> None:
        dlg = BulkMergeResolveDialog(self.plans)
        decisions = dlg.decisions()
        self.assertEqual(decisions, self.plans)
        dlg.deleteLater()

    def test_skip_one_row(self) -> None:
        dlg = BulkMergeResolveDialog(self.plans)
        dlg._combos[0].setCurrentIndex(1)  # 跳过
        decisions = dlg.decisions()
        self.assertIsNone(decisions[0])
        self.assertEqual(decisions[1], self.plans[1])
        dlg.deleteLater()

    def test_skip_all_button(self) -> None:
        dlg = BulkMergeResolveDialog(self.plans)
        dlg._set_all("skip")
        self.assertEqual(dlg.decisions(), [None, None])
        # Toggled back to merge-all restores plans.
        dlg._set_all("merge")
        self.assertEqual(dlg.decisions(), self.plans)
        dlg.deleteLater()

    def test_detail_opener_tunes_plan(self) -> None:
        tuned = self.plans[0]
        tuned.replaced_units = []  # simulate the user unchecking replacements
        dlg = BulkMergeResolveDialog(
            self.plans, detail_opener=lambda _plan: tuned
        )
        dlg._combos[0].setCurrentIndex(2)  # 细看…
        decisions = dlg.decisions()
        self.assertIs(decisions[0], tuned)
        self.assertEqual(decisions[0].replaced_units, [])
        self.assertEqual(dlg._combos[0].itemText(2), "已自定义 ✓")
        dlg.deleteLater()

    def test_detail_cancel_falls_back_to_merge(self) -> None:
        dlg = BulkMergeResolveDialog(self.plans, detail_opener=lambda _plan: None)
        dlg._combos[0].setCurrentIndex(2)  # 细看… → cancelled
        decisions = dlg.decisions()
        self.assertEqual(decisions[0], self.plans[0])
        # Combo bounced back to the plain merge entry.
        self.assertEqual(dlg._combos[0].currentIndex(), 0)
        dlg.deleteLater()


if __name__ == "__main__":
    unittest.main()
