"""Tests for src.widgets.resource_review_table."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

from PySide6.QtWidgets import QApplication

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.extraction_quality import QualityIssue
from src.widgets.resource_review_table import ResourceReviewTable, ResourceRow


class _TestApp:
    _app: QApplication | None = None

    @classmethod
    def get(cls) -> QApplication:
        if cls._app is None:
            cls._app = QApplication.instance() or QApplication([])
        return cls._app


class ResourceReviewTableTest(unittest.TestCase):
    def setUp(self) -> None:
        _TestApp.get()
        self.table = ResourceReviewTable()
        self.table.set_rows(
            [
                ResourceRow(
                    chapter_index=0,
                    resource_type="word",
                    entry={"term": "merhaba", "translation": "hello", "tags": ["greeting"]},
                ),
                ResourceRow(
                    chapter_index=0,
                    resource_type="word",
                    entry={"term": "aile", "translation": "family", "tags": ["noun"]},
                ),
                ResourceRow(
                    chapter_index=1,
                    resource_type="expression",
                    entry={"term": "Selam!", "translation": "Hi!", "tags": ["greeting"]},
                    issues=[QualityIssue("warning", "lang_check", "empty tag", 1)],
                ),
            ]
        )

    def test_kept_rows_returns_checked_entries(self) -> None:
        self.table.set_checked_by_term("merhaba", False)
        kept = self.table.kept_rows()
        terms = [e["term"] for _ci, _rtype, e in kept]
        self.assertNotIn("merhaba", terms)
        self.assertIn("aile", terms)
        self.assertIn("Selam!", terms)

    def test_filter_by_chapter(self) -> None:
        self.table.set_chapter_filter(0)
        self.assertEqual(self.table.row_count(), 2)
        self.table.set_chapter_filter(None)
        self.assertEqual(self.table.row_count(), 3)

    def test_filter_by_tag(self) -> None:
        # Simulate tag selection.
        self.table._tag_filter = "greeting"
        self.table._refresh_table()
        self.assertEqual(self.table.row_count(), 2)

    def test_filter_by_search(self) -> None:
        self.table._search_text = "fam"
        self.table._refresh_table()
        self.assertEqual(self.table.row_count(), 1)
        self.assertEqual(
            self.table._visible_rows()[0].display_term(), "aile"
        )

    def test_batch_delete(self) -> None:
        self.table.set_checked_by_term("merhaba", True)
        self.table.set_checked_by_term("aile", False)
        self.table.set_checked_by_term("Selam!", False)
        self.table._delete_selected()
        self.assertEqual(self.table.row_count(), 2)

    def test_edit_round_trips(self) -> None:
        # Simulate inline edit in the Qt table and read it back via kept_rows.
        self.table._table.item(0, 4).setText("hi")
        kept = self.table.kept_rows()
        self.assertEqual(kept[0][2]["translation"], "hi")


class ReviewTablePerfTest(unittest.TestCase):
    """bookplan2 Phase 6: 50 chapters x 50 words must not lag the Review page."""

    def setUp(self) -> None:
        _TestApp.get()
        self.table = ResourceReviewTable()
        self.rows = [
            ResourceRow(
                chapter_index=ci,
                resource_type="word",
                entry={
                    "term": f"w{ci}_{w}",
                    "translation": f"t{w}",
                    "tags": ["greeting" if w % 2 else "noun"],
                },
            )
            for ci in range(50)
            for w in range(50)
        ]
        self.table.set_rows(self.rows)
        self.assertEqual(self.table.row_count(), 2500)

    def _timed(self, fn) -> float:
        import time

        t0 = time.perf_counter()
        fn()
        return time.perf_counter() - t0

    def test_single_chapter_filter_is_fast(self) -> None:
        elapsed = self._timed(lambda: self.table.set_chapter_filter(0))
        self.assertEqual(self.table.row_count(), 50)
        # Offscreen, generous threshold to absorb CI jitter; was dominated by
        # per-refresh resizeColumnsToContents before the Phase 6 fix.
        self.assertLess(elapsed, 0.5)

    def test_full_refresh_is_fast(self) -> None:
        # Clear filter -> full 2500-row rebuild.
        elapsed = self._timed(lambda: self.table.set_chapter_filter(None))
        self.assertEqual(self.table.row_count(), 2500)
        self.assertLess(elapsed, 1.5)

    def test_search_refresh_is_fast(self) -> None:
        self.table._search_text = "w0_"
        elapsed = self._timed(self.table._refresh_table)
        self.assertLess(elapsed, 0.5)
        # "w0_" matches w0_0..w0_9 and w10_0.. etc. — just assert it filters.
        self.assertLess(self.table.row_count(), 2500)

    def test_kept_rows_over_2500_rows(self) -> None:
        # End-to-end: building kept_rows over the full set must stay cheap and
        # correct (all checked by default).
        kept = self.table.kept_rows()
        self.assertEqual(len(kept), 2500)


if __name__ == "__main__":
    unittest.main()
