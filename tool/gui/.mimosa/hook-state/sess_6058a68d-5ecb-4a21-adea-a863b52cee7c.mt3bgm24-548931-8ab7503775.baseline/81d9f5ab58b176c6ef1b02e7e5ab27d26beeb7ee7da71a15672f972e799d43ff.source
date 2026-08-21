"""Tests for src.widgets.bulk_import_preview_panel (bookplan2 Phase 4)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path


_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))
from tests._qtapp import _App as _TestApp  # noqa: E402

from src.backend.import_strategy import SectionImportPreview
from src.widgets.bulk_import_preview_panel import (
    BulkImportPreviewPanel,
    action_label,
)


def _preview(
    *,
    title="Ch1",
    source_id="ch-1-1",
    target_id="ch-1-1",
    exists=False,
    action="append",
    new_words=1,
    new_expressions=0,
    new_grammar=0,
    duplicate_words=0,
    duplicate_expressions=0,
    duplicate_grammar=0,
    chapter_index=0,
) -> SectionImportPreview:
    return SectionImportPreview(
        chapter_index=chapter_index,
        title=title,
        source_id=source_id,
        target_id=target_id,
        exists=exists,
        action=action,
        word_count=new_words + duplicate_words,
        expression_count=new_expressions + duplicate_expressions,
        grammar_count=new_grammar + duplicate_grammar,
        new_words=new_words,
        new_expressions=new_expressions,
        new_grammar=new_grammar,
        duplicate_words=duplicate_words,
        duplicate_expressions=duplicate_expressions,
        duplicate_grammar=duplicate_grammar,
    )


class ActionLabelTest(unittest.TestCase):
    def test_known_actions_map_to_chinese(self) -> None:
        self.assertEqual(action_label("append"), "新增")
        self.assertEqual(action_label("merge"), "合并（交互）")
        self.assertEqual(action_label("skip"), "跳过")
        self.assertEqual(action_label("replace"), "覆盖")
        self.assertEqual(action_label("append_new"), "追加为新")

    def test_unknown_action_passthrough(self) -> None:
        self.assertEqual(action_label("weird"), "weird")


class BulkImportPreviewPanelTest(unittest.TestCase):
    def setUp(self) -> None:
        _TestApp.get()
        self.panel = BulkImportPreviewPanel()

    def _cell(self, row: int, col: int) -> str:
        return self.panel._table.item(row, col).text()

    def test_empty_panel_has_no_rows(self) -> None:
        self.assertEqual(self.panel._table.rowCount(), 0)

    def test_set_previews_rends_one_row_per_section(self) -> None:
        self.panel.set_previews([_preview(title="A"), _preview(title="B", source_id="ch-2-2")])
        self.assertEqual(self.panel._table.rowCount(), 2)
        self.assertEqual(self._cell(0, 0), "A")
        self.assertEqual(self._cell(1, 0), "B")

    def test_append_row_shows_new_resources_and_no_conflict(self) -> None:
        self.panel.set_previews(
            [_preview(new_words=2, new_expressions=1, new_grammar=0)]
        )
        self.assertEqual(self._cell(0, 2), "新增")
        self.assertEqual(self._cell(0, 3), "2 / 1 / 0")
        self.assertEqual(self._cell(0, 4), "0 / 0 / 0")
        self.assertEqual(self._cell(0, 5), "-")

    def test_merge_row_shows_conflict(self) -> None:
        self.panel.set_previews(
            [_preview(exists=True, action="merge", source_id="ch-1-1", target_id="ch-1-1")]
        )
        self.assertEqual(self._cell(0, 2), "合并（交互）")
        self.assertEqual(self._cell(0, 5), "是")

    def test_skip_row_labelled(self) -> None:
        self.panel.set_previews([_preview(exists=True, action="skip")])
        self.assertEqual(self._cell(0, 2), "跳过")

    def test_replace_row_labelled(self) -> None:
        self.panel.set_previews([_preview(exists=True, action="replace")])
        self.assertEqual(self._cell(0, 2), "覆盖")

    def test_append_new_shows_source_to_target_id(self) -> None:
        self.panel.set_previews(
            [
                _preview(
                    exists=True,
                    action="append_new",
                    source_id="ch-1-1",
                    target_id="ch-1-1-2",
                )
            ]
        )
        self.assertEqual(self._cell(0, 1), "ch-1-1 -> ch-1-1-2")
        self.assertEqual(self._cell(0, 2), "追加为新")

    def test_duplicate_resources_rendered(self) -> None:
        self.panel.set_previews(
            [_preview(new_words=1, duplicate_words=2, duplicate_expressions=1)]
        )
        self.assertEqual(self._cell(0, 3), "1 / 0 / 0")
        self.assertEqual(self._cell(0, 4), "2 / 1 / 0")

    def test_summary_aggregates_counts(self) -> None:
        self.panel.set_previews(
            [
                _preview(action="append", new_words=2),
                _preview(
                    action="merge", exists=True, new_words=0, duplicate_words=1
                ),
                _preview(action="skip", exists=True, new_words=0),
            ]
        )
        text = self.panel._summary.text()
        self.assertIn("共 3 个章节", text)
        self.assertIn("新增：1", text)
        self.assertIn("合并（交互）：1", text)
        self.assertIn("跳过：1", text)
        self.assertIn("新增资源 2 项", text)
        self.assertIn("重复资源 1 项", text)

    def test_empty_summary_message(self) -> None:
        self.panel.set_previews([])
        self.assertEqual(self.panel._summary.text(), "无可导入的章节。")

    def test_clear_empties_rows(self) -> None:
        self.panel.set_previews([_preview(), _preview()])
        self.panel.clear()
        self.assertEqual(self.panel._table.rowCount(), 0)
        self.assertEqual(self.panel._summary.text(), "")
        self.assertEqual(self.panel.previews, [])


if __name__ == "__main__":
    unittest.main()
