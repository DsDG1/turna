"""Milestone 2 integration: new lesson per template + save round-trip via CLI."""
from __future__ import annotations

import shutil
import sys
import tempfile
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.course_adapter import CourseAdapter  # noqa: E402
from src.backend.lesson_content import (  # noqa: E402
    INTERACTION_SCHEMA,
    add_item,
    add_listening_phase,
    add_stage,
    move_item,
    move_stage,
    new_lesson_from_template,
    normalize_item,
    rename_stage,
    rename_sub_lesson,
    switch_runtime_type,
)


_REPO = _GUI.parents[1]
COURSE_SRC = _REPO / "assets" / "courses" / "turkish"


class NewLessonRoundTripTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="varnamala_m2_"))
        self.course_dir = self.tmp / "turkish"
        shutil.copytree(COURSE_SRC, self.course_dir)

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _adapter(self) -> CourseAdapter:
        a = CourseAdapter()
        a.load(self.course_dir)
        return a

    def test_new_intro_lesson_with_items_saves(self) -> None:
        a = self._adapter()
        section = a.sections[0]
        unit = section["units"][0]
        lesson = new_lesson_from_template("intro", unit)
        sub = lesson["content"]["subLessons"][0]
        stage = sub["stages"][0]
        for item in stage["items"]:
            if item.get("runtimeType") == "showWord":
                item["wordId"] = "w-merhaba"
        add_item(stage, "translateSentence")
        result = a.save()
        self.assertTrue(result.ok, f"{result.message} errors={result.errors}")

    def test_new_mastery_lesson_single_stage_saves(self) -> None:
        a = self._adapter()
        section = a.sections[0]
        unit = section["units"][0]
        lesson = new_lesson_from_template("mastery", unit)
        stage = lesson["content"]["stages"][0]
        add_item(stage, "multipleChoice")
        result = a.save()
        self.assertTrue(result.ok, f"{result.message} errors={result.errors}")

    def test_new_listening_lesson_with_phases_saves(self) -> None:
        a = self._adapter()
        section = a.sections[0]
        unit = section["units"][0]
        lesson = new_lesson_from_template("listening", unit)
        word_phase = lesson["content"]["listeningPhases"][0]
        add_item(word_phase, "listenAndPick")["audioAsset"] = "sounds/example/test.mp3"
        result = a.save()
        self.assertTrue(result.ok, f"{result.message} errors={result.errors}")

    def test_new_reading_lesson_with_passage_saves(self) -> None:
        a = self._adapter()
        section = a.sections[0]
        unit = section["units"][0]
        lesson = new_lesson_from_template("reading", unit)
        lesson["content"]["readingPassage"]["title"] = "Test passage"
        lesson["content"]["readingPassage"]["paragraphs"] = ["One.", "Two."]
        stage = lesson["content"]["stages"][0]
        add_item(stage, "readingMcq")
        add_item(stage, "readingTrueFalse")
        result = a.save()
        self.assertTrue(result.ok, f"{result.message} errors={result.errors}")

    def test_delete_lesson_saves(self) -> None:
        a = self._adapter()
        section = a.sections[0]
        unit = section["units"][0]
        before = len(unit["lessons"])
        lid = unit["lessons"][0]["id"]
        a.delete_lesson(lid)
        result = a.save()
        self.assertTrue(result.ok, f"{result.message} errors={result.errors}")
        self.assertEqual(len(unit["lessons"]), before - 1)

    def test_teacher_mode_intro_crud_saves(self) -> None:
        a = self._adapter()
        unit = a.sections[0]["units"][0]
        lesson = new_lesson_from_template("intro", unit)
        sub = lesson["content"]["subLessons"][0]
        stage = sub["stages"][0]

        for item in stage["items"]:
            if item.get("runtimeType") == "showWord":
                item["wordId"] = "w-merhaba"

        rename_sub_lesson(sub, "Renamed sub")
        rename_stage(stage, "Renamed stage")
        item = add_item(stage, "multipleChoice")
        item["prompt"] = "Q1"
        item["options"] = ["A", "B"]
        item["correctIndex"] = 0

        new_stage = add_stage(sub, "Extra stage")
        add_item(new_stage, "fillBlank")

        move_item(stage, 0, 1)
        move_stage(sub, 1, 0)

        result = a.save()
        self.assertTrue(result.ok, f"{result.message} errors={result.errors}")

    def test_teacher_mode_switch_item_type_saves(self) -> None:
        a = self._adapter()
        unit = a.sections[0]["units"][0]
        lesson = new_lesson_from_template("mastery", unit)
        stage = lesson["content"]["stages"][0]
        item = add_item(stage, "multipleChoice")
        item["prompt"] = "Translate this"
        item["options"] = ["A", "B"]
        item["correctIndex"] = 0

        idx = stage["items"].index(item)
        stage["items"][idx] = switch_runtime_type(item, "translateSentence")
        stage["items"][idx]["expected"] = "translated"

        result = a.save()
        self.assertTrue(result.ok, f"{result.message} errors={result.errors}")

    def test_teacher_mode_listening_crud_saves(self) -> None:
        a = self._adapter()
        unit = a.sections[0]["units"][0]
        lesson = new_lesson_from_template("listening", unit)
        phase = add_listening_phase(lesson, "dialogue", "D")
        phase["audioAsset"] = "sounds/example/d.mp3"
        phase["transcript"] = "A: hello"
        item = add_item(phase, "listenAndPick")
        item["audioAsset"] = "sounds/example/q.mp3"
        item["prompt"] = "What?"
        item["options"] = ["A", "B"]
        item["correctIndex"] = 0

        result = a.save()
        self.assertTrue(result.ok, f"{result.message} errors={result.errors}")

    def test_teacher_mode_reading_crud_saves(self) -> None:
        a = self._adapter()
        unit = a.sections[0]["units"][0]
        lesson = new_lesson_from_template("reading", unit)
        lesson["content"]["readingPassage"]["title"] = "Title"
        lesson["content"]["readingPassage"]["paragraphs"] = ["P1", "P2"]
        stage = lesson["content"]["stages"][0]
        item = add_item(stage, "readingMcq")
        item["prompt"] = "What?"
        item["options"] = ["A", "B"]
        item["correctIndex"] = 0

        result = a.save()
        self.assertTrue(result.ok, f"{result.message} errors={result.errors}")


class InteractionSchemaConsistencyTest(unittest.TestCase):
    def test_every_schema_field_round_trips(self) -> None:
        for rt, specs in INTERACTION_SCHEMA.items():
            item = normalize_item({"runtimeType": rt})
            for spec in specs:
                self.assertIn(spec.name, item, f"{rt} missing {spec.name}")
            self.assertEqual(item["runtimeType"], rt)


if __name__ == "__main__":
    unittest.main()