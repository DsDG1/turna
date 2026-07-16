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
    AddItemCommand,
    AddListeningPhaseCommand,
    AddStageCommand,
    AddSubLessonCommand,
    AiEditLessonCommand,
    AiEditSectionCommand,
    AiEditUnitCommand,
    AppendLessonCommand,
    DeleteItemCommand,
    DeleteListeningPhaseCommand,
    DeleteLessonCommand,
    DeleteSectionCommand,
    DeleteStageCommand,
    DeleteSubLessonCommand,
    DeleteUnitCommand,
    ImportAiSectionCommand,
    MergeAiSectionCommand,
    MoveItemCommand,
    MoveLessonCommand,
    MoveListeningPhaseCommand,
    MoveSectionCommand,
    MoveStageCommand,
    MoveSubLessonCommand,
    MoveUnitCommand,
    NewLessonCommand,
    NewUnitCommand,
    RenameListeningPhaseCommand,
    RenameStageCommand,
    RenameSubLessonCommand,
    ReplaceItemCommand,
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

    def test_move_section_undo(self) -> None:
        ids = [s["id"] for s in self.adapter.sections]
        self.assertGreaterEqual(len(ids), 2)
        cmd = MoveSectionCommand(self.adapter, 0, 1)
        self.stack.push(cmd)
        moved = [s["id"] for s in self.adapter.sections]
        self.assertEqual(moved, [ids[1], ids[0]] + ids[2:])
        self.stack.undo()
        self.assertEqual([s["id"] for s in self.adapter.sections], ids)

    def test_move_section_bounds_noop(self) -> None:
        ids = [s["id"] for s in self.adapter.sections]
        # to_idx out of range — move_within returns False, list unchanged.
        cmd = MoveSectionCommand(self.adapter, 0, len(ids))
        self.stack.push(cmd)
        self.assertEqual([s["id"] for s in self.adapter.sections], ids)

    def test_move_lesson_undo(self) -> None:
        section = self.adapter.sections[0]
        unit = section["units"][0]
        ids = [l["id"] for l in unit["lessons"]]
        self.assertGreaterEqual(len(ids), 2)
        cmd = MoveLessonCommand(self.adapter, unit["id"], 0, 1)
        self.stack.push(cmd)
        moved = [l["id"] for l in unit["lessons"]]
        self.assertEqual(moved, [ids[1], ids[0]])
        self.stack.undo()
        self.assertEqual([l["id"] for l in unit["lessons"]], ids)

    def test_move_unit_undo(self) -> None:
        section = self.adapter.sections[0]
        # The seeded course has one unit per section; add a second so we can
        # reorder units within the same parent section.
        self.stack.push(NewUnitCommand(self.adapter, section["id"], "Temp unit"))
        units = section["units"]
        ids = [u["id"] for u in units]
        self.assertGreaterEqual(len(ids), 2)
        cmd = MoveUnitCommand(self.adapter, section["id"], 0, 1)
        self.stack.push(cmd)
        moved = [u["id"] for u in section["units"]]
        self.assertEqual(moved, [ids[1], ids[0]])
        self.stack.undo()
        self.assertEqual([u["id"] for u in section["units"]], ids)

    def test_move_lesson_keeps_hierarchy(self) -> None:
        """A lesson move reorders within its parent unit only — the unit's
        membership and the section structure are untouched."""
        section = self.adapter.sections[0]
        unit = section["units"][0]
        lesson_ids_before = [l["id"] for l in unit["lessons"]]
        unit_ids_before = [u["id"] for u in section["units"]]
        cmd = MoveLessonCommand(self.adapter, unit["id"], 0, 1)
        self.stack.push(cmd)
        # Same lessons, just reordered; same units.
        self.assertEqual(
            sorted(l["id"] for l in unit["lessons"]),
            sorted(lesson_ids_before),
        )
        self.assertEqual([u["id"] for u in section["units"]], unit_ids_before)


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


class ContentCommandsUndoTest(unittest.TestCase):
    """Undo round-trips for lesson content commands (sub-lesson/stage/item)."""

    def _sample_content(self) -> dict:
        return {
            "subLessons": [
                {
                    "id": "sl-1",
                    "name": "SL1",
                    "stages": [
                        {
                            "id": "st-1",
                            "name": "Stage 1",
                            "items": [
                                {
                                    "runtimeType": "multipleChoice",
                                    "id": "i-1",
                                    "prompt": "Q1",
                                    "options": ["A", "B"],
                                    "correctIndex": 0,
                                    "imageAsset": "",
                                    "grammarPointId": "",
                                }
                            ],
                        }
                    ],
                }
            ]
        }

    def test_add_sub_lesson_undo(self) -> None:
        content = {"subLessons": []}
        stack = QUndoStack()
        cmd = AddSubLessonCommand(content, "New SL")
        cmd.signals.changed.connect(lambda: None)
        stack.push(cmd)
        self.assertEqual(len(content["subLessons"]), 1)
        stack.undo()
        self.assertEqual(len(content["subLessons"]), 0)

    def test_delete_sub_lesson_undo(self) -> None:
        content = self._sample_content()
        sl = content["subLessons"][0]
        stack = QUndoStack()
        cmd = DeleteSubLessonCommand(content, sl)
        cmd.signals.changed.connect(lambda: None)
        stack.push(cmd)
        self.assertEqual(len(content["subLessons"]), 0)
        stack.undo()
        self.assertEqual(len(content["subLessons"]), 1)
        self.assertEqual(content["subLessons"][0]["id"], "sl-1")

    def test_rename_sub_lesson_undo(self) -> None:
        content = self._sample_content()
        sl = content["subLessons"][0]
        stack = QUndoStack()
        cmd = RenameSubLessonCommand(sl, "Renamed")
        cmd.signals.changed.connect(lambda: None)
        stack.push(cmd)
        self.assertEqual(sl["name"], "Renamed")
        stack.undo()
        self.assertEqual(sl["name"], "SL1")

    def test_move_sub_lesson_undo(self) -> None:
        content = {
            "subLessons": [
                {"id": "sl-1", "name": "A", "stages": []},
                {"id": "sl-2", "name": "B", "stages": []},
            ]
        }
        stack = QUndoStack()
        cmd = MoveSubLessonCommand(content, 0, 1)
        cmd.signals.changed.connect(lambda: None)
        stack.push(cmd)
        self.assertEqual([sl["id"] for sl in content["subLessons"]], ["sl-2", "sl-1"])
        stack.undo()
        self.assertEqual([sl["id"] for sl in content["subLessons"]], ["sl-1", "sl-2"])

    def test_add_stage_undo(self) -> None:
        content = self._sample_content()
        sl = content["subLessons"][0]
        stack = QUndoStack()
        cmd = AddStageCommand(sl, "New Stage")
        cmd.signals.changed.connect(lambda: None)
        stack.push(cmd)
        self.assertEqual(len(sl["stages"]), 2)
        stack.undo()
        self.assertEqual(len(sl["stages"]), 1)

    def test_delete_stage_undo(self) -> None:
        content = self._sample_content()
        sl = content["subLessons"][0]
        stage = sl["stages"][0]
        stack = QUndoStack()
        cmd = DeleteStageCommand(sl, stage)
        cmd.signals.changed.connect(lambda: None)
        stack.push(cmd)
        self.assertEqual(len(sl["stages"]), 0)
        stack.undo()
        self.assertEqual(len(sl["stages"]), 1)
        self.assertEqual(sl["stages"][0]["id"], "st-1")

    def test_rename_stage_undo(self) -> None:
        content = self._sample_content()
        stage = content["subLessons"][0]["stages"][0]
        stack = QUndoStack()
        cmd = RenameStageCommand(stage, "Renamed")
        cmd.signals.changed.connect(lambda: None)
        stack.push(cmd)
        self.assertEqual(stage["name"], "Renamed")
        stack.undo()
        self.assertEqual(stage["name"], "Stage 1")

    def test_move_stage_undo(self) -> None:
        sl = {
            "id": "sl-1",
            "name": "SL",
            "stages": [
                {"id": "st-1", "name": "A", "items": []},
                {"id": "st-2", "name": "B", "items": []},
            ],
        }
        stack = QUndoStack()
        cmd = MoveStageCommand(sl, 0, 1)
        cmd.signals.changed.connect(lambda: None)
        stack.push(cmd)
        self.assertEqual([st["id"] for st in sl["stages"]], ["st-2", "st-1"])
        stack.undo()
        self.assertEqual([st["id"] for st in sl["stages"]], ["st-1", "st-2"])

    def test_add_item_undo(self) -> None:
        content = self._sample_content()
        stage = content["subLessons"][0]["stages"][0]
        stack = QUndoStack()
        cmd = AddItemCommand(stage, "multipleChoice")
        cmd.signals.changed.connect(lambda: None)
        stack.push(cmd)
        self.assertEqual(len(stage["items"]), 2)
        stack.undo()
        self.assertEqual(len(stage["items"]), 1)

    def test_delete_item_undo(self) -> None:
        content = self._sample_content()
        stage = content["subLessons"][0]["stages"][0]
        item = stage["items"][0]
        stack = QUndoStack()
        cmd = DeleteItemCommand(stage, item)
        cmd.signals.changed.connect(lambda: None)
        stack.push(cmd)
        self.assertEqual(len(stage["items"]), 0)
        stack.undo()
        self.assertEqual(len(stage["items"]), 1)
        self.assertEqual(stage["items"][0]["id"], "i-1")

    def test_replace_item_undo(self) -> None:
        content = self._sample_content()
        stage = content["subLessons"][0]["stages"][0]
        new_item = dict(stage["items"][0])
        new_item["prompt"] = "Replaced"
        stack = QUndoStack()
        cmd = ReplaceItemCommand(stage, "i-1", new_item)
        cmd.signals.changed.connect(lambda: None)
        stack.push(cmd)
        self.assertEqual(stage["items"][0]["prompt"], "Replaced")
        stack.undo()
        self.assertEqual(stage["items"][0]["prompt"], "Q1")

    def test_move_item_undo(self) -> None:
        stage = {
            "id": "st-1",
            "name": "Stage",
            "items": [
                {"runtimeType": "multipleChoice", "id": "i-1"},
                {"runtimeType": "multipleChoice", "id": "i-2"},
            ],
        }
        stack = QUndoStack()
        cmd = MoveItemCommand(stage, 0, 1)
        cmd.signals.changed.connect(lambda: None)
        stack.push(cmd)
        self.assertEqual([it["id"] for it in stage["items"]], ["i-2", "i-1"])
        stack.undo()
        self.assertEqual([it["id"] for it in stage["items"]], ["i-1", "i-2"])


class AppendLessonCommandTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="varnamala_cmd_"))
        self.adapter = _load_adapter(self.tmp)
        self.stack = QUndoStack()

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_append_lesson_undo_removes(self) -> None:
        section = self.adapter.sections[0]
        unit = section["units"][0]
        uid = unit["id"]
        before = len(unit.get("lessons", []))
        lesson = {
            "id": "appended-l1",
            "name": "Appended",
            "description": "",
            "type": "normal",
            "template": "intro",
            "prerequisiteLessonIds": [],
            "content": {"subLessons": []},
        }
        cmd = AppendLessonCommand(self.adapter, uid, lesson)
        cmd.signals.changed.connect(lambda: None)
        self.stack.push(cmd)
        self.assertEqual(len(unit["lessons"]), before + 1)
        self.stack.undo()
        ids = {l.get("id") for l in unit["lessons"]}
        self.assertNotIn("appended-l1", ids)


class ListeningPhaseCommandsTest(unittest.TestCase):
    def setUp(self) -> None:
        self.lesson: dict[str, Any] = {
            "id": "l-listen",
            "template": "listening",
            "content": {"listeningPhases": []},
        }
        self.stack = QUndoStack()

    def test_add_listening_phase_undo(self) -> None:
        cmd = AddListeningPhaseCommand(self.lesson, "wordPairing", "Phase 1")
        cmd.signals.changed.connect(lambda: None)
        self.stack.push(cmd)
        self.assertEqual(len(self.lesson["content"]["listeningPhases"]), 1)
        self.stack.undo()
        self.assertEqual(len(self.lesson["content"]["listeningPhases"]), 0)

    def test_delete_listening_phase_undo(self) -> None:
        phase = {"id": "lp-1", "name": "P1", "type": "wordPairing", "items": []}
        self.lesson["content"]["listeningPhases"].append(phase)
        cmd = DeleteListeningPhaseCommand(self.lesson, phase)
        cmd.signals.changed.connect(lambda: None)
        self.stack.push(cmd)
        self.assertEqual(len(self.lesson["content"]["listeningPhases"]), 0)
        self.stack.undo()
        self.assertEqual(len(self.lesson["content"]["listeningPhases"]), 1)
        self.assertEqual(self.lesson["content"]["listeningPhases"][0]["id"], "lp-1")

    def test_move_listening_phase_undo(self) -> None:
        self.lesson["content"]["listeningPhases"] = [
            {"id": "lp-1", "name": "A", "type": "wordPairing"},
            {"id": "lp-2", "name": "B", "type": "wordPairing"},
        ]
        cmd = MoveListeningPhaseCommand(self.lesson, 0, 1)
        cmd.signals.changed.connect(lambda: None)
        self.stack.push(cmd)
        ids = [p["id"] for p in self.lesson["content"]["listeningPhases"]]
        self.assertEqual(ids, ["lp-2", "lp-1"])
        self.stack.undo()
        ids = [p["id"] for p in self.lesson["content"]["listeningPhases"]]
        self.assertEqual(ids, ["lp-1", "lp-2"])

    def test_rename_listening_phase_undo(self) -> None:
        phase = {"id": "lp-1", "name": "Old", "type": "wordPairing"}
        self.lesson["content"]["listeningPhases"].append(phase)
        cmd = RenameListeningPhaseCommand(phase, "New")
        cmd.signals.changed.connect(lambda: None)
        self.stack.push(cmd)
        self.assertEqual(phase["name"], "New")
        self.stack.undo()
        self.assertEqual(phase["name"], "Old")


class AiResourceRollbackTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="varnamala_cmd_"))
        self.adapter = _load_adapter(self.tmp)
        self.stack = QUndoStack()

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_import_ai_section_undo_rolls_back_resources(self) -> None:
        section_json = {
            "id": "ai-res-imp",
            "name": "AI Import",
            "description": "",
            "prerequisiteSectionIds": [],
            "words": [
                {"id": "w-ai-1", "term": "AI", "translation": "人工智能", "tags": []}
            ],
            "expressions": [
                {"id": "e-ai-1", "term": "hello", "translation": "你好", "tags": []}
            ],
            "grammarPoints": [
                {"id": "g-ai-1", "title": "AI grammar", "explanation": ""}
            ],
            "units": [],
        }
        before_vocab = len(self.adapter.vocab)
        before_expr = len(self.adapter.expressions)
        before_grammar = len(self.adapter.grammar_points)

        cmd = ImportAiSectionCommand(self.adapter, section_json)
        cmd.signals.changed.connect(lambda: None)
        self.stack.push(cmd)
        self.assertIn("ai-res-imp", {s.get("id") for s in self.adapter.sections})
        self.assertIn("w-ai-1", {w.get("id") for w in self.adapter.vocab})
        self.assertIn("e-ai-1", {e.get("id") for e in self.adapter.expressions})
        self.assertIn("g-ai-1", {g.get("id") for g in self.adapter.grammar_points})

        self.stack.undo()
        self.assertNotIn("ai-res-imp", {s.get("id") for s in self.adapter.sections})
        self.assertEqual(len(self.adapter.vocab), before_vocab)
        self.assertEqual(len(self.adapter.expressions), before_expr)
        self.assertEqual(len(self.adapter.grammar_points), before_grammar)

    def test_ai_edit_section_undo_rolls_back_resources(self) -> None:
        section = self.adapter.sections[0]
        sid = section["id"]
        resource_section = {
            "id": sid,
            "name": "Edited",
            "words": [
                {"id": "w-edit-1", "term": "T", "translation": "翻译", "tags": []}
            ],
            "expressions": [],
            "grammarPoints": [],
            "units": [],
        }
        before_vocab = len(self.adapter.vocab)
        cmd = AiEditSectionCommand(
            self.adapter, sid, resource_section, resource_section=resource_section
        )
        cmd.signals.changed.connect(lambda: None)
        self.stack.push(cmd)
        self.assertIn("w-edit-1", {w.get("id") for w in self.adapter.vocab})
        self.stack.undo()
        self.assertEqual(len(self.adapter.vocab), before_vocab)

    def test_ai_edit_unit_undo_rolls_back_resources(self) -> None:
        section = self.adapter.sections[0]
        unit = section["units"][0]
        uid = unit["id"]
        new_unit = dict(unit)
        new_unit["name"] = "Edited Unit"
        resource_section = {
            "id": section["id"],
            "name": section["name"],
            "words": [
                {"id": "w-unit-edit", "term": "U", "translation": "单元", "tags": []}
            ],
            "expressions": [],
            "grammarPoints": [],
            "units": [new_unit],
        }
        before_vocab = len(self.adapter.vocab)
        cmd = AiEditUnitCommand(
            self.adapter, section["id"], uid, new_unit, resource_section=resource_section
        )
        cmd.signals.changed.connect(lambda: None)
        self.stack.push(cmd)
        self.assertIn("w-unit-edit", {w.get("id") for w in self.adapter.vocab})
        self.stack.undo()
        self.assertEqual(len(self.adapter.vocab), before_vocab)

    def test_ai_edit_lesson_undo_rolls_back_resources(self) -> None:
        section = self.adapter.sections[0]
        unit = section["units"][0]
        lesson = unit["lessons"][0]
        lid = lesson["id"]
        new_lesson = dict(lesson)
        new_lesson["name"] = "Edited Lesson"
        resource_section = {
            "id": section["id"],
            "name": section["name"],
            "words": [
                {"id": "w-lesson-edit", "term": "L", "translation": "课", "tags": []}
            ],
            "expressions": [],
            "grammarPoints": [],
            "units": [
                {
                    "id": unit["id"],
                    "name": unit["name"],
                    "lessons": [new_lesson],
                }
            ],
        }
        before_vocab = len(self.adapter.vocab)
        cmd = AiEditLessonCommand(
            self.adapter, lid, new_lesson, resource_section=resource_section
        )
        cmd.signals.changed.connect(lambda: None)
        self.stack.push(cmd)
        self.assertIn("w-lesson-edit", {w.get("id") for w in self.adapter.vocab})
        self.stack.undo()
        self.assertEqual(len(self.adapter.vocab), before_vocab)


class MergeAiSectionCommandTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="varnamala_merge_"))
        self.adapter = _load_adapter(self.tmp)
        self.stack = QUndoStack()

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _make_plan(self, target_sid: str | None, incoming: dict) -> "SectionMergePlan":
        from src.backend.course_adapter import SectionMergePlan

        return self.adapter.plan_section_merge(target_sid, incoming)

    def test_merge_replaces_existing_unit_and_appends_new_unit(self) -> None:
        target = self.adapter.sections[0]
        existing_unit = target["units"][0]
        existing_lesson = existing_unit["lessons"][0]
        original_unit_name = existing_unit["name"]
        incoming = {
            "id": target["id"],
            "name": target["name"],
            "words": [],
            "expressions": [],
            "grammarPoints": [],
            "units": [
                {
                    "id": existing_unit["id"],
                    "name": "Updated unit",
                    "lessons": [
                        {
                            "id": existing_lesson["id"],
                            "name": "Updated lesson",
                            "template": "intro",
                            "content": {"subLessons": []},
                        }
                    ],
                },
                {
                    "id": "ai-new-unit",
                    "name": "New unit",
                    "lessons": [
                        {
                            "id": "ai-new-lesson",
                            "name": "New lesson",
                            "template": "intro",
                            "content": {"subLessons": []},
                        }
                    ],
                },
            ],
        }
        plan = self._make_plan(target["id"], incoming)
        before_unit_count = len(target["units"])
        cmd = MergeAiSectionCommand(self.adapter, plan)
        cmd.signals.changed.connect(lambda: None)
        self.stack.push(cmd)

        target_after = self.adapter.find_section(target["id"])
        self.assertEqual(target_after["units"][0]["name"], "Updated unit")
        self.assertEqual(len(target_after["units"]), before_unit_count + 1)
        self.assertTrue(any(u.get("id") == "ai-new-unit" for u in target_after["units"]))

        self.stack.undo()
        target_after_undo = self.adapter.find_section(target["id"])
        self.assertEqual(target_after_undo["units"][0]["name"], original_unit_name)
        self.assertEqual(len(target_after_undo["units"]), before_unit_count)

    def test_merge_appends_lesson_to_existing_unit(self) -> None:
        target = self.adapter.sections[0]
        existing_unit = target["units"][0]
        existing_lesson = existing_unit["lessons"][0]
        original_lesson_count = len(existing_unit["lessons"])
        incoming = {
            "id": target["id"],
            "name": target["name"],
            "words": [],
            "expressions": [],
            "grammarPoints": [],
            "units": [
                {
                    "id": existing_unit["id"],
                    "name": existing_unit["name"],
                    "lessons": [
                        dict(existing_lesson),
                        {
                            "id": "ai-appended-lesson",
                            "name": "Appended lesson",
                            "template": "intro",
                            "content": {"subLessons": []},
                        },
                    ],
                }
            ],
        }
        plan = self._make_plan(target["id"], incoming)
        cmd = MergeAiSectionCommand(self.adapter, plan)
        cmd.signals.changed.connect(lambda: None)
        self.stack.push(cmd)

        unit_after = self.adapter.find_section(target["id"])["units"][0]
        self.assertEqual(len(unit_after["lessons"]), original_lesson_count + 1)
        self.assertTrue(
            any(l.get("id") == "ai-appended-lesson" for l in unit_after["lessons"])
        )

        self.stack.undo()
        unit_after_undo = self.adapter.find_section(target["id"])["units"][0]
        self.assertEqual(len(unit_after_undo["lessons"]), original_lesson_count)

    def test_merge_rolls_back_added_resources(self) -> None:
        target = self.adapter.sections[0]
        existing_unit = target["units"][0]
        incoming = {
            "id": target["id"],
            "name": target["name"],
            "words": [
                {"id": "w-merge-new", "term": "New", "translation": "新", "tags": []}
            ],
            "expressions": [],
            "grammarPoints": [],
            "units": [
                {
                    "id": existing_unit["id"],
                    "name": existing_unit["name"],
                    "lessons": list(existing_unit["lessons"]),
                }
            ],
        }
        plan = self._make_plan(target["id"], incoming)
        before_vocab = len(self.adapter.vocab)
        cmd = MergeAiSectionCommand(self.adapter, plan)
        cmd.signals.changed.connect(lambda: None)
        self.stack.push(cmd)
        self.assertIn("w-merge-new", {w.get("id") for w in self.adapter.vocab})

        self.stack.undo()
        self.assertEqual(len(self.adapter.vocab), before_vocab)


if __name__ == "__main__":
    unittest.main()