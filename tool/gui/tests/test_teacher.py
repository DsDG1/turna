"""Tests for teacher-view pure functions + the vocab delete guard.

Covers T.2 (intro lesson generation round-trips through validate), T.7
(error path parsing / humanization) and T16 (deleting a vocab entry
confirms and surfaces lesson references first).
"""
from __future__ import annotations

import os
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))
from tests._course_fixture import copy_turkish_course, real_adapter_with_course
from tests._qtapp import _App

from PySide6.QtCore import Qt

from src.backend.course_adapter import CourseAdapter
from src.teacher.error_mapper import (
    humanize_problem,
    parse_path,
    problem_to_node_ref,
)
from src.backend.lesson_content import build_intro_lesson


class LessonWizardTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="turna_wizard_"))
        self.course_dir = self.tmp / "turkish"
        copy_turkish_course(self.course_dir)

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_build_intro_lesson_structure(self) -> None:
        words = [
            {"id": "w-a", "term": "A", "translation": "甲"},
            {"id": "w-b", "term": "B", "translation": "乙"},
        ]
        lesson = build_intro_lesson("测试课", "desc", words)
        self.assertEqual(lesson["template"], "intro")
        self.assertEqual(lesson["type"], "normal")
        subs = lesson["content"]["subLessons"]
        self.assertEqual(len(subs), 2)
        for sl in subs:
            stages = sl["stages"]
            self.assertEqual(len(stages), 3)
            rts = [st["items"][0]["runtimeType"] for st in stages]
            self.assertEqual(rts, ["showWord", "translateSentence", "fillBlank"])

    def test_generated_intro_lesson_validates(self) -> None:
        """The wizard output must pass course_cli validate after save (§15.13)."""
        adapter = CourseAdapter()
        adapter.load(self.course_dir)
        words = adapter.vocab[:2]
        lesson = build_intro_lesson("向导课", "向导生成", words)
        adapter.sections[0]["units"][0]["lessons"].append(lesson)
        result = adapter.save()
        self.assertTrue(result.ok, f"save failed: {result.message} errors={result.errors}")


class ErrorMapperTest(unittest.TestCase):
    def test_parse_path_full(self) -> None:
        parts = parse_path("section:section4/unit:u-1/lesson:l-1")
        self.assertEqual(parts["section"], "section4")
        self.assertEqual(parts["unit"], "u-1")
        self.assertEqual(parts["lesson"], "l-1")

    def test_parse_path_section_only(self) -> None:
        parts = parse_path("section:section2")
        self.assertEqual(parts["section"], "section2")
        self.assertEqual(parts["unit"], "")

    def test_parse_path_empty(self) -> None:
        self.assertEqual(parse_path(""), {"section": "", "unit": "", "lesson": ""})

    def test_humanize_dangling_word(self) -> None:
        msg = humanize_problem(
            {"message": "ShowWord sw-1 references missing wordId w-x", "path": ""}
        )
        self.assertIn("引用了不存在的词", msg)

    def test_humanize_duplicate(self) -> None:
        msg = humanize_problem({"message": "Duplicate lesson id: s1-l1", "path": ""})
        self.assertIn("重复", msg)

    def test_problem_to_node_ref_lesson(self) -> None:
        ref = problem_to_node_ref(
            {"path": "section:section1/unit:u-1/lesson:s1-l2"}, []
        )
        self.assertEqual(ref, ("lesson", "s1-l2"))

    def test_problem_to_node_ref_none_for_empty_path(self) -> None:
        self.assertIsNone(problem_to_node_ref({"path": ""}, []))


class VocabDeleteConfirmTest(unittest.TestCase):
    """T16: deleting a vocab entry must confirm and report lesson references.

    The teacher path used to delete immediately with neither a confirm nor a
    reference check, so a word still used by a lesson vanished on click.
    """

    @classmethod
    def setUpClass(cls) -> None:
        os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
        _App.get()

    def setUp(self) -> None:
        self.adapter, self.tmp = real_adapter_with_course("turna_vocab_del_")
        # Two dedicated entries we control: one we point a lesson at (so the
        # reference count is exact), one the course never references.
        # Every shipped turkish vocab entry is referenced, so both are new.
        self.used = self._blank_entry("deneme", "试词")
        self._reference_vocab(self.used)
        self.clean = self._blank_entry("kullanilmaz", "未用词")

    def _blank_entry(self, term: str, translation: str) -> str:
        new_id = self.adapter.add_resource_entry("vocab")
        for entry in self.adapter.vocab:
            if entry["id"] == new_id:
                entry["term"] = term
                entry["translation"] = translation
        return new_id

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _reference_vocab(self, vocab_id: str) -> None:
        """Point a lesson item at *vocab_id* so find_resource_refs sees it."""
        section = self.adapter.sections[0]
        lesson = section["units"][0]["lessons"][0]
        content = lesson.setdefault("content", {})
        stages = content.setdefault("stages", [])
        if not stages:
            stages.append({"id": "st-test", "items": []})
        stages[0].setdefault("items", []).append(
            {"id": "i-ref", "runtimeType": "showWord", "wordId": vocab_id}
        )

    def _table_on_row(self, vocab_id: str):
        from src.teacher.vocab_table import VocabTableWidget

        table = VocabTableWidget(self.adapter)
        self.addCleanup(table.deleteLater)
        for row in range(table.table.rowCount()):
            if table.table.item(row, 0).data(Qt.ItemDataRole.UserRole) == vocab_id:
                table.table.setCurrentCell(row, 0)
                return table
        self.fail(f"vocab row {vocab_id} not found")

    def _deleted(self, vocab_id: str) -> bool:
        return all(v.get("id") != vocab_id for v in self.adapter.vocab)

    def test_declined_delete_keeps_the_entry(self) -> None:
        table = self._table_on_row(self.used)
        with patch("src.application.ui_guard.safe_question", return_value=False) as ask:
            table._on_del()
        ask.assert_called_once()
        self.assertFalse(self._deleted(self.used))
        self.assertFalse(table.is_dirty())

    def test_confirm_text_reports_the_live_references(self) -> None:
        table = self._table_on_row(self.used)
        with patch("src.application.ui_guard.safe_question", return_value=False) as ask:
            table._on_del()
        text = ask.call_args.args[2]
        self.assertIn("1 处引用", text)
        self.assertIn("i-ref", text)

    def test_accepted_delete_removes_the_entry(self) -> None:
        table = self._table_on_row(self.used)
        with patch("src.application.ui_guard.safe_question", return_value=True):
            table._on_del()
        self.assertTrue(self._deleted(self.used))
        self.assertTrue(table.is_dirty())

    def test_unreferenced_entry_still_confirms_and_says_so(self) -> None:
        table = self._table_on_row(self.clean)
        with patch("src.application.ui_guard.safe_question", return_value=False) as ask:
            table._on_del()
        self.assertIn("未发现引用", ask.call_args.args[2])
        self.assertFalse(self._deleted(self.clean))

    def test_delete_is_safe_by_default(self) -> None:
        # default_yes=False: an accidental/headless Yes must not delete.
        table = self._table_on_row(self.used)
        with patch("src.application.ui_guard.safe_question", return_value=False) as ask:
            table._on_del()
        self.assertFalse(ask.call_args.kwargs.get("default_yes", True))


if __name__ == "__main__":
    unittest.main()
