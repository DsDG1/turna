"""Vocab ``pos`` column + grammar practiceItems carry (schema-sync P2).

Covers:
- course_cli CSV round-trip: vocab gains a pos column, expressions do not;
  export -> _build_entry keeps the value (G7 fix).
- course_cli.POS_TAGS mirrors the GUI single source of truth
  (experience/pos_constants.py) which mirrors lib/domain/course/pos_tag.dart.
- lint: non-empty pos outside the closed set is a warning, never an error.
- resource editor table columns: vocab gets pos, grammar gets the
  editor-only practiceItems column.
- resource pack JSON: practiceItems rides along with grammar entries.
"""
from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

_GUI = Path(__file__).resolve().parents[1]
_REPO = _GUI.parents[1]
for p in (str(_GUI), str(_REPO / "tool")):
    if p not in sys.path:
        sys.path.insert(0, p)

import course_cli  # noqa: E402
from src.backend.experience.pos_constants import POS_TAGS as GUI_POS_TAGS  # noqa: E402
from src.backend.experience import pos_constants  # noqa: E402


class CsvPosRoundTripTest(unittest.TestCase):
    def test_vocab_headers_include_pos(self) -> None:
        headers, _rows = course_cli.build_csv_rows("vocab", [])
        self.assertIn("pos", headers)

    def test_expressions_headers_exclude_pos(self) -> None:
        headers, _rows = course_cli.build_csv_rows("expressions", [])
        self.assertNotIn("pos", headers)

    def test_vocab_export_carries_pos(self) -> None:
        entries = [
            {"id": "w-1", "term": "merhaba", "translation": "你好", "pos": "noun"},
            {"id": "w-2", "term": "koş", "translation": "跑", "pos": None},
        ]
        _headers, rows = course_cli.build_csv_rows("vocab", entries)
        by_id = {r["id"]: r for r in rows}
        self.assertEqual(by_id["w-1"]["pos"], "noun")
        self.assertEqual(by_id["w-2"]["pos"], "")

    def test_build_entry_round_trips_pos(self) -> None:
        row = {
            "id": "w-1",
            "term": "merhaba",
            "translation": "你好",
            "pronunciation": "",
            "audioAsset": "",
            "tags": "",
            "pos": "Noun ",
        }
        entry = course_cli._build_entry(row, "vocab", {})
        self.assertEqual(entry["pos"], "noun")

    def test_build_entry_empty_pos_becomes_none(self) -> None:
        row = {
            "id": "w-1", "term": "a", "translation": "b",
            "pronunciation": "", "audioAsset": "", "tags": "", "pos": "",
        }
        entry = course_cli._build_entry(row, "vocab", {})
        self.assertIsNone(entry["pos"])

    def test_full_export_import_merge_keeps_pos(self) -> None:
        entries = [
            {"id": "w-1", "term": "merhaba", "translation": "你好", "pos": "noun",
             "pronunciation": None, "audioAsset": None, "tags": []},
        ]
        headers, rows = course_cli.build_csv_rows("vocab", entries)
        merged, problems = course_cli.merge_csv_rows("vocab", [], rows, set())
        self.assertEqual([p for p in problems if p.level == "error"], [])
        self.assertEqual(merged[0]["pos"], "noun")

    def test_grammar_build_entry_preserves_practice_items(self) -> None:
        existing = {
            "g-1": {
                "id": "g-1", "title": "T", "explanation": "",
                "exampleExpressionIds": [], "exampleSentenceIds": [],
                "practiceItems": [{"runtimeType": "ankiCard", "id": "a", "front": "f", "back": "b"}],
            }
        }
        row = {"id": "g-1", "title": "T2", "explanation": "x",
               "exampleExpressionIds": "", "exampleSentenceIds": ""}
        entry = course_cli._build_entry(row, "grammar_points", existing)
        self.assertEqual(len(entry["practiceItems"]), 1)
        self.assertEqual(entry["title"], "T2")


class PosClosedSetMirrorTest(unittest.TestCase):
    def test_course_cli_pos_tags_mirror_gui_constants(self) -> None:
        self.assertEqual(frozenset(course_cli.POS_TAGS), frozenset(GUI_POS_TAGS))

    def test_normalize_pos_accepts_closed_set(self) -> None:
        for tag in GUI_POS_TAGS:
            self.assertTrue(pos_constants.is_valid_pos(tag))
        self.assertFalse(pos_constants.is_valid_pos("verbish"))
        self.assertFalse(pos_constants.is_valid_pos(""))
        self.assertIsNone(pos_constants.normalize_pos(None))


class LintPosTest(unittest.TestCase):
    def _problems(self, entries):
        problems = []
        course_cli._lint_entries(entries, "word", set(), problems)
        return problems

    def test_unknown_pos_is_warning(self) -> None:
        entries = [{"id": "w-1", "term": "a", "translation": "b",
                    "tags": [], "pos": "verbish"}]
        problems = self._problems(entries)
        pos_problems = [p for p in problems if "pos" in p.message]
        self.assertEqual(len(pos_problems), 1)
        self.assertEqual(pos_problems[0].level, "warning")

    def test_valid_and_empty_pos_are_clean(self) -> None:
        entries = [
            {"id": "w-1", "term": "a", "translation": "b", "tags": [], "pos": "verb"},
            {"id": "w-2", "term": "c", "translation": "d", "tags": []},
        ]
        problems = self._problems(entries)
        self.assertEqual([p for p in problems if "pos" in p.message], [])


class ResourceEditorColumnsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        from tests._qtapp import qt_app
        qt_app()

    def test_vocab_table_has_pos_column(self) -> None:
        from src.widgets.resource_editor import _columns
        self.assertIn("pos", _columns("vocab"))

    def test_grammar_table_has_practice_items_column(self) -> None:
        from src.widgets.resource_editor import _columns
        cols = _columns("grammar_points")
        self.assertIn("practiceItems", cols)
        # Editor-only column must NOT leak into the CSV headers.
        headers, _ = course_cli.build_csv_rows("grammar_points", [])
        self.assertNotIn("practiceItems", headers)

    def test_pos_delegate_maps_labels_to_enums(self) -> None:
        from PySide6.QtCore import Qt
        from src.widgets.resource_editor import _PosDelegate
        from src.widgets.resource_editor import POS_LABELS

        delegate = _PosDelegate(None)
        editor = delegate.createEditor(None, None, None)
        # Every combo entry stores the English enum; label text is Chinese.
        datas = [editor.itemData(i) for i in range(editor.count())]
        self.assertEqual(datas[0], "")
        for value in GUI_POS_TAGS:
            self.assertIn(value, datas)
        pos = editor.findData("noun")
        editor.setCurrentIndex(pos)
        self.assertEqual(editor.currentText(), POS_LABELS["noun"])


class ResourcePackPracticeItemsTest(unittest.TestCase):
    def test_practice_items_survive_adapter_resource_pack(self) -> None:
        import tempfile

        from src.backend.course_adapter import CourseAdapter
        with tempfile.TemporaryDirectory() as tmp:
            course_dir = Path(tmp) / "turkish"
            from tests._course_fixture import copy_turkish_course
            copy_turkish_course(course_dir)
            adapter = CourseAdapter()
            adapter.load(course_dir)
            adapter.grammar_points[0]["practiceItems"] = [
                {"runtimeType": "ankiCard", "id": "ak-1",
                 "front": "f", "back": "b", "audioAssets": [],
                 "imageAssets": [], "hint": "", "sourceNoteId": "9"},
            ]
            pack_path = Path(tmp) / "pack.json"
            adapter.export_resource_pack(pack_path)

            other = CourseAdapter()
            other.load(course_dir)
            other.grammar_points[0].pop("practiceItems", None)
            counts = other.import_resource_pack(pack_path, replace=True)
            self.assertGreaterEqual(counts.get("grammar_points", 0), 1)
            items = other.grammar_points[0].get("practiceItems") or []
            # replace=True rebuilds from the pack; practiceItems must ride.
            self.assertEqual(
                len(items), 1,
                "practiceItems must survive resource pack export/import",
            )


if __name__ == "__main__":
    unittest.main()
