#!/usr/bin/env python3
from __future__ import annotations

import contextlib
import io
import json
import re
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT / "tool"))

from course_cli import _validate_course, _validate_interaction, cmd_validate  # type: ignore


class Args:
    def __init__(self, course_dir: Path) -> None:
        self.course_dir = course_dir
        self.format = "text"


def valid_items() -> dict[str, dict]:
    return {
        "showWord": {"id": "i", "wordId": "w-1"},
        "multipleChoice": {
            "id": "i",
            "prompt": "Choose",
            "options": ["A", "B"],
            "correctIndex": 1,
        },
        "multiSelect": {
            "id": "i",
            "prompt": "Choose",
            "options": ["A", "B", "C"],
            "correctIndices": [0, 2],
            "minSelections": 1,
            "maxSelections": 2,
        },
        "fillBlank": {"id": "i", "sentence": "___", "answer": "A"},
        "translateSentence": {"id": "i", "source": "A", "expected": "B"},
        "listenAndPick": {
            "id": "i",
            "audioAsset": "a",
            "prompt": "Choose",
            "options": ["A", "B"],
            "correctIndex": 0,
        },
        "typeTheWord": {"id": "i", "audioAsset": "a", "prompt": "Type", "expected": "A"},
        "listenOnly": {"id": "i", "transcript": "A"},
        "reorderSentence": {"id": "i", "scrambled": ["B", "A"], "correct": ["A", "B"]},
        "readingMcq": {
            "id": "i",
            "prompt": "Choose",
            "options": ["A", "B"],
            "correctIndex": 0,
        },
        "readingTrueFalse": {"id": "i", "statement": "A", "answer": True},
        "readingShortAnswer": {"id": "i", "prompt": "Answer", "expectedAnswer": "A"},
        "ankiCard": {"id": "i", "front": "A", "back": "B"},
        "ankiHtmlCard": {
            "id": "i",
            "frontHtml": "A",
            "backHtml": "B",
            "css": "",
            "mediaBasePath": "",
        },
        "imageRecall": {"id": "i", "imageAssets": ["a.png"], "answerText": "A"},
        "dictation": {"id": "i", "audioAssets": ["a.mp3"], "expected": "A"},
        "readAloud": {"id": "i", "targetText": "A"},
    }


class InteractionSchemaValidationTest(unittest.TestCase):
    def validate(self, item: dict) -> list:
        problems = []
        _validate_interaction("lesson", "stage", item, problems)
        return problems

    def test_all_dart_runtime_types_accept_valid_items(self) -> None:
        for runtime_type, item in valid_items().items():
            with self.subTest(runtime_type=runtime_type):
                self.assertEqual(self.validate({"runtimeType": runtime_type, **item}), [])

    def test_unknown_runtime_type_fails(self) -> None:
        problems = self.validate({"runtimeType": "futureType", "id": "i"})
        self.assertTrue(any("Unknown runtimeType" in p.message for p in problems))

    def test_document_correct_answer_fails_instead_of_becoming_placeholder(self) -> None:
        item = valid_items()["multipleChoice"]
        item["correctAnswer"] = item.pop("correctIndex")
        problems = self.validate({"runtimeType": "multipleChoice", **item})
        messages = "\n".join(p.message for p in problems)
        self.assertIn("correctIndex", messages)
        self.assertIn("correctAnswer", messages)

    def test_choice_index_and_options_are_checked(self) -> None:
        cases = []
        item = valid_items()["multipleChoice"]
        item["correctIndex"] = 2
        cases.append(("multipleChoice", item))
        item = valid_items()["multipleChoice"]
        item["options"] = ["A", "A"]
        cases.append(("multipleChoice", item))
        item = valid_items()["readingMcq"]
        item["correctIndex"] = True
        cases.append(("readingMcq", item))
        for runtime_type, value in cases:
            with self.subTest(runtime_type=runtime_type, value=value):
                self.assertTrue(
                    self.validate({"runtimeType": runtime_type, **value})
                )

    def test_multi_select_indices_and_selection_bounds_are_checked(self) -> None:
        item = {"runtimeType": "multiSelect", **valid_items()["multiSelect"]}
        item["correctIndices"] = [0, 0]
        self.assertTrue(self.validate(item))
        item = {"runtimeType": "multiSelect", **valid_items()["multiSelect"]}
        item["minSelections"] = 3
        self.assertTrue(self.validate(item))

    def test_accepted_answers_are_typed_and_reorders_keep_the_token_set(self) -> None:
        valid = {
            "runtimeType": "reorderSentence",
            "id": "i",
            "scrambled": ["B", "A"],
            "correct": ["A", "B"],
            "acceptedAnswers": ["B A"],
        }
        self.assertEqual(self.validate(valid), [])
        with_decoy = dict(valid, scrambled=["B", "decoy", "A"])
        self.assertEqual(self.validate(with_decoy), [])
        invalid = dict(valid, acceptedAnswers=["A"])
        self.assertTrue(self.validate(invalid))
        invalid = dict(valid, acceptedAnswers="B A")
        self.assertTrue(self.validate(invalid))

    def test_required_types_and_non_empty_values_are_checked(self) -> None:
        cases = [
            {"runtimeType": "showWord", "id": "i", "wordId": ""},
            {"runtimeType": "translateSentence", "id": "i", "source": "A"},
            {"runtimeType": "readingTrueFalse", "id": "i", "statement": "A", "answer": 1},
            {"runtimeType": "reorderSentence", "id": "i", "scrambled": ["A"], "correct": ["B"]},
            {"runtimeType": "dictation", "id": "i", "audioAssets": "a.mp3", "expected": "A"},
        ]
        for item in cases:
            with self.subTest(item=item):
                self.assertTrue(self.validate(item))


class AuthoringExampleValidationTest(unittest.TestCase):
    def test_every_executable_lesson_template_validates(self) -> None:
        template_dir = PROJECT_ROOT / "docs" / "authoring" / "templates"
        for template_path in sorted(template_dir.glob("*.json")):
            with self.subTest(template=template_path.name), tempfile.TemporaryDirectory() as tmp:
                course_dir = Path(tmp) / "course"
                shutil.copytree(
                    PROJECT_ROOT / "test" / "fixtures" / "turkish_course", course_dir
                )
                section_path = course_dir / "sections" / "section1.json"
                section = json.loads(section_path.read_text(encoding="utf-8"))
                lesson = json.loads(template_path.read_text(encoding="utf-8"))
                section["units"][0]["lessons"].append(lesson)
                section_path.write_text(
                    json.dumps(section, ensure_ascii=False), encoding="utf-8"
                )
                self.assertEqual(_validate_course(course_dir), [])

    def test_inline_json_interactions_match_the_schema(self) -> None:
        docs = [
            PROJECT_ROOT / "docs" / "authoring" / "lesson-type-templates.md",
            PROJECT_ROOT / "docs" / "authoring" / "listening-show-format.md",
        ]

        def walk(value: object, label: str) -> None:
            if isinstance(value, dict):
                if "runtimeType" in value:
                    problems = []
                    _validate_interaction("doc", "example", value, problems)
                    self.assertEqual(problems, [], msg=f"{label}: {value}")
                for child in value.values():
                    walk(child, label)
            elif isinstance(value, list):
                for child in value:
                    walk(child, label)

        for path in docs:
            text = path.read_text(encoding="utf-8")
            for index, block in enumerate(re.findall(r"```json\s*(.*?)```", text, re.S)):
                with self.subTest(document=path.name, block=index):
                    walk(json.loads(block), f"{path.name} block {index}")


class DocumentStyleCourseRegressionTest(unittest.TestCase):
    def test_real_course_rejects_document_style_field_through_cli(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            course_dir = Path(tmp) / "course"
            shutil.copytree(
                PROJECT_ROOT / "assets" / "courses" / "nouveau-turkish",
                course_dir,
            )
            section_path = course_dir / "sections" / "section1.json"
            section = json.loads(section_path.read_text(encoding="utf-8"))
            item = section["units"][0]["lessons"][0]["content"]["subLessons"][0]["stages"][0]["items"][1]
            item["correctAnswer"] = item.pop("correctIndex")
            section_path.write_text(json.dumps(section, ensure_ascii=False), encoding="utf-8")
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                result = cmd_validate(Args(course_dir))
            self.assertEqual(result, 1)
            self.assertIn("correctIndex", output.getvalue())
            self.assertIn("mc-turkce", output.getvalue())


if __name__ == "__main__":
    unittest.main()
