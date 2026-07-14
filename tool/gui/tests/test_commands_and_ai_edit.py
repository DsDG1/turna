"""Tests for tree-level undo commands, section deletion, and AI edit prompt.

Uses a copy of the real Turkish course as the working directory so the
CourseAdapter has realistic sections/units/lessons to mutate.
"""
from __future__ import annotations

import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from PySide6.QtGui import QUndoStack  # noqa: E402

from src.application.commands import (  # noqa: E402
    AiEditLessonCommand,
    AiEditSectionCommand,
    AiEditUnitCommand,
    DeleteLessonCommand,
    DeleteSectionCommand,
    DeleteUnitCommand,
    ImportAiSectionCommand,
    NewLessonCommand,
    NewUnitCommand,
    UpdateLessonMetaCommand,
    UpdateSectionMetaCommand,
    UpdateSectionPrereqsCommand,
    UpdateUnitMetaCommand,
)
from src.backend.ai_generator import (  # noqa: E402
    AiApiConfig,
    AiCourseSpec,
    build_edit_prompt,
    generate_edit,
)
from src.backend.course_adapter import CourseAdapter  # noqa: E402

_REPO = _GUI.parents[1]
COURSE_SRC = _REPO / "assets" / "courses" / "turkish"


def _load_adapter(tmp: Path) -> CourseAdapter:
    course_dir = tmp / "turkish"
    shutil.copytree(COURSE_SRC, course_dir)
    adapter = CourseAdapter()
    adapter.load(course_dir)
    return adapter


class _FakeChatBody:
    """Minimal OpenAI-compatible response body for parse_completion."""

    def __init__(self, payload: dict) -> None:
        self._payload = payload

    def get(self, key, default=None):
        return self._payload.get(key, default)


class SectionDeleteTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="varnamala_cmd_"))
        self.adapter = _load_adapter(self.tmp)

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_section_is_referenced_detects_dependency(self) -> None:
        first = self.adapter.sections[0]
        first_id = first["id"]
        # Add a second section depending on the first if none does.
        if not self.adapter.section_is_referenced(first_id):
            self.adapter.sections.append(
                {
                    "id": "dep-1",
                    "name": "Dep",
                    "prerequisiteSectionIds": [first_id],
                    "units": [],
                }
            )
        refs = self.adapter.section_is_referenced(first_id)
        self.assertTrue(refs, "expected at least one section to reference first_id")
        self.assertIn(first_id, [s.get("id") for s in self.adapter.sections])

    def test_delete_section_removes_from_sections_and_index(self) -> None:
        sid = self.adapter.sections[0]["id"]
        # Clear any references so deletion is allowed.
        for s in self.adapter.sections:
            s["prerequisiteSectionIds"] = [
                p for p in s.get("prerequisiteSectionIds", []) if p != sid
            ]
        self.adapter.delete_section(sid)
        ids = {s.get("id") for s in self.adapter.sections}
        self.assertNotIn(sid, ids)
        index_ids = {e.get("id") for e in self.adapter.index.get("sections", [])}
        self.assertNotIn(sid, index_ids)

    def test_delete_section_raises_on_unknown(self) -> None:
        with self.assertRaises(KeyError):
            self.adapter.delete_section("does-not-exist")


class TreeCommandsUndoTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="varnamala_cmd_"))
        self.adapter = _load_adapter(self.tmp)
        self.stack = QUndoStack()

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_new_unit_undo_removes(self) -> None:
        section = self.adapter.sections[0]
        before = len(section.get("units", []))
        cmd = NewUnitCommand(self.adapter, section["id"])
        self.stack.push(cmd)
        self.assertEqual(len(section["units"]), before + 1)
        new_id = cmd.unit_id
        self.assertIsNotNone(new_id)
        self.stack.undo()
        self.assertEqual(len(section["units"]), before)
        ids = {u.get("id") for u in section["units"]}
        self.assertNotIn(new_id, ids)

    def test_delete_unit_undo_restores(self) -> None:
        section = self.adapter.sections[0]
        unit = section["units"][0]
        uid = unit["id"]
        cmd = DeleteUnitCommand(self.adapter, uid)
        self.stack.push(cmd)
        ids = {u.get("id") for u in section["units"]}
        self.assertNotIn(uid, ids)
        self.stack.undo()
        ids = {u.get("id") for u in section["units"]}
        self.assertIn(uid, ids)

    def test_new_lesson_undo_removes(self) -> None:
        section = self.adapter.sections[0]
        unit = section["units"][0]
        before = len(unit.get("lessons", []))
        cmd = NewLessonCommand(self.adapter, unit["id"], "intro", "L")
        self.stack.push(cmd)
        self.assertEqual(len(unit["lessons"]), before + 1)
        lid = cmd.lesson_id
        self.stack.undo()
        ids = {l.get("id") for l in unit["lessons"]}
        self.assertNotIn(lid, ids)

    def test_delete_lesson_undo_restores(self) -> None:
        section = self.adapter.sections[0]
        unit = section["units"][0]
        lesson = unit["lessons"][0]
        lid = lesson["id"]
        cmd = DeleteLessonCommand(self.adapter, lid)
        self.stack.push(cmd)
        ids = {l.get("id") for l in unit["lessons"]}
        self.assertNotIn(lid, ids)
        self.stack.undo()
        ids = {l.get("id") for l in unit["lessons"]}
        self.assertIn(lid, ids)

    def test_delete_section_undo_restores(self) -> None:
        sid = self.adapter.sections[0]["id"]
        for s in self.adapter.sections:
            s["prerequisiteSectionIds"] = [
                p for p in s.get("prerequisiteSectionIds", []) if p != sid
            ]
        cmd = DeleteSectionCommand(self.adapter, sid)
        self.stack.push(cmd)
        self.assertNotIn(sid, {s.get("id") for s in self.adapter.sections})
        self.stack.undo()
        self.assertIn(sid, {s.get("id") for s in self.adapter.sections})
        self.assertIn(sid, {e.get("id") for e in self.adapter.index["sections"]})


class MetadataCommandsUndoTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="varnamala_cmd_"))
        self.adapter = _load_adapter(self.tmp)
        self.stack = QUndoStack()

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_update_section_meta_undo(self) -> None:
        section = self.adapter.sections[0]
        sid = section["id"]
        old_name = section["name"]
        cmd = UpdateSectionMetaCommand(self.adapter, sid, "新名称", "新描述")
        self.stack.push(cmd)
        self.assertEqual(self.adapter.find_section(sid)["name"], "新名称")
        entry = next(e for e in self.adapter.index["sections"] if e["id"] == sid)
        self.assertEqual(entry["name"], "新名称")
        self.stack.undo()
        self.assertEqual(self.adapter.find_section(sid)["name"], old_name)

    def test_update_unit_meta_undo(self) -> None:
        section = self.adapter.sections[0]
        unit = section["units"][0]
        uid = unit["id"]
        old_name = unit["name"]
        cmd = UpdateUnitMetaCommand(self.adapter, uid, "Unit-X", "desc")
        self.stack.push(cmd)
        self.assertEqual(self.adapter.find_unit(uid)[1]["name"], "Unit-X")
        self.stack.undo()
        self.assertEqual(self.adapter.find_unit(uid)[1]["name"], old_name)

    def test_update_lesson_meta_undo(self) -> None:
        section = self.adapter.sections[0]
        unit = section["units"][0]
        lesson = unit["lessons"][0]
        lid = lesson["id"]
        cmd = UpdateLessonMetaCommand(self.adapter, lid, "L-X", "d")
        self.stack.push(cmd)
        self.assertEqual(self.adapter.find_lesson(lid)[2]["name"], "L-X")
        self.stack.undo()
        # original name restored
        self.assertNotEqual(self.adapter.find_lesson(lid)[2]["name"], "L-X")

    def test_update_section_prereqs_undo(self) -> None:
        section = self.adapter.sections[0]
        sid = section["id"]
        section["prerequisiteSectionIds"] = []
        # pick another section as prereq
        other = self.adapter.sections[1]["id"]
        cmd = UpdateSectionPrereqsCommand(self.adapter, sid, [other])
        self.stack.push(cmd)
        self.assertEqual(
            self.adapter.find_section(sid)["prerequisiteSectionIds"], [other]
        )
        self.stack.undo()
        self.assertEqual(
            self.adapter.find_section(sid)["prerequisiteSectionIds"], []
        )


class AiEditCommandsTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="varnamala_cmd_"))
        self.adapter = _load_adapter(self.tmp)
        self.stack = QUndoStack()

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_import_ai_section_undo(self) -> None:
        section_json = {
            "id": "ai-test-imp",
            "name": "AI Import",
            "description": "",
            "prerequisiteSectionIds": [],
            "words": [],
            "expressions": [],
            "grammarPoints": [],
            "units": [
                {
                    "id": "ai-test-imp-u1",
                    "name": "U1",
                    "description": "",
                    "prerequisiteUnitIds": [],
                    "lessons": [],
                }
            ],
        }
        cmd = ImportAiSectionCommand(self.adapter, section_json)
        self.stack.push(cmd)
        self.assertIn("ai-test-imp", {s.get("id") for s in self.adapter.sections})
        self.stack.undo()
        self.assertNotIn("ai-test-imp", {s.get("id") for s in self.adapter.sections})

    def test_ai_edit_section_undo(self) -> None:
        section = self.adapter.sections[0]
        sid = section["id"]
        original_name = section["name"]
        new_section = dict(section)
        new_section["name"] = "AI Edited Name"
        cmd = AiEditSectionCommand(self.adapter, sid, new_section)
        self.stack.push(cmd)
        self.assertEqual(self.adapter.find_section(sid)["name"], "AI Edited Name")
        self.stack.undo()
        self.assertEqual(self.adapter.find_section(sid)["name"], original_name)

    def test_ai_edit_unit_undo(self) -> None:
        section = self.adapter.sections[0]
        unit = section["units"][0]
        uid = unit["id"]
        original_name = unit["name"]
        new_unit = dict(unit)
        new_unit["name"] = "AI Unit Edited"
        cmd = AiEditUnitCommand(self.adapter, section["id"], uid, new_unit)
        self.stack.push(cmd)
        self.assertEqual(self.adapter.find_unit(uid)[1]["name"], "AI Unit Edited")
        self.stack.undo()
        self.assertEqual(self.adapter.find_unit(uid)[1]["name"], original_name)

    def test_ai_edit_lesson_undo(self) -> None:
        section = self.adapter.sections[0]
        unit = section["units"][0]
        lesson = unit["lessons"][0]
        lid = lesson["id"]
        original_name = lesson["name"]
        new_lesson = dict(lesson)
        new_lesson["name"] = "AI Lesson Edited"
        cmd = AiEditLessonCommand(self.adapter, lid, new_lesson)
        self.stack.push(cmd)
        self.assertEqual(self.adapter.find_lesson(lid)[2]["name"], "AI Lesson Edited")
        self.stack.undo()
        self.assertEqual(self.adapter.find_lesson(lid)[2]["name"], original_name)


class AiEditPromptTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="varnamala_cmd_"))
        self.adapter = _load_adapter(self.tmp)

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_build_edit_prompt_contains_existing_unit_and_vocab(self) -> None:
        section = self.adapter.sections[0]
        # attach some vocab to the section dict for the prompt summary
        section["words"] = [
            {"id": "w-test", "term": "merhaba", "translation": "你好"}
        ]
        spec = AiCourseSpec(topic="add practice lessons", language="Turkish")
        prompt = build_edit_prompt(spec, section, "unit", section["units"][0]["id"])
        self.assertIn(section["units"][0]["id"], prompt)
        self.assertIn("merhaba", prompt)
        self.assertIn(section["id"], prompt)

    def test_generate_edit_keeps_section_id_and_uses_chat(self) -> None:
        # Use a small self-consistent section so the resource self-check passes.
        section = {
            "id": "synth-1",
            "name": "Synth",
            "description": "",
            "prerequisiteSectionIds": [],
            "words": [
                {"id": "w-hi", "term": "Merhaba", "translation": "你好",
                 "pronunciation": None, "audioAsset": None, "tags": []}
            ],
            "expressions": [],
            "grammarPoints": [],
            "units": [
                {
                    "id": "synth-1-u1",
                    "name": "U1",
                    "description": "",
                    "prerequisiteUnitIds": [],
                    "lessons": [
                        {
                            "id": "synth-1-u1-l1",
                            "name": "L1",
                            "description": "",
                            "type": "normal",
                            "template": "intro",
                            "prerequisiteLessonIds": [],
                            "content": {
                                "subLessons": [
                                    {
                                        "id": "synth-1-u1-l1-sl1",
                                        "name": "sl1",
                                        "stages": [
                                            {
                                                "id": "synth-1-u1-l1-sl1-st1",
                                                "name": "st1",
                                                "items": [
                                                    {
                                                        "runtimeType": "showWord",
                                                        "id": "sw1",
                                                        "wordId": "w-hi",
                                                        "context": "hi",
                                                    }
                                                ],
                                            }
                                        ],
                                    }
                                ]
                            },
                        }
                    ],
                }
            ],
        }
        sid = section["id"]
        spec = AiCourseSpec(topic="tweak", language="Turkish")
        returned = dict(section)
        returned["name"] = "Edited by AI"

        with patch(
            "src.backend.ai_generator.request_chat",
            return_value={
                "choices": [
                    {"message": {"content": json.dumps(returned, ensure_ascii=False)}}
                ]
            },
        ) as mock_chat:
            result = generate_edit(
                AiApiConfig(base_url="https://x", api_key="k", model="m"),
                spec,
                section,
                "section",
                "",
            )
        self.assertEqual(result["id"], sid)
        self.assertEqual(result["name"], "Edited by AI")
        mock_chat.assert_called_once()


if __name__ == "__main__":
    unittest.main()