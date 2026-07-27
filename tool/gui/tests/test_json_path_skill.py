"""Pure tests for the T-10 caret JSON-path skill (no Qt, never raises)."""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.experience.json_path_skill import explain_path, json_path_at  # noqa: E402

_DOC = {
    "id": "s1",
    "name": "章节",
    "units": [
        {
            "id": "u1",
            "name": "单元",
            "lessons": [
                {
                    "id": "l1",
                    "stages": [
                        {
                            "items": [
                                {
                                    "runtimeType": "multipleChoice",
                                    "prompt": 'say "hi"?',
                                    "options": ["a", "b"],
                                    "correctIndex": 0,
                                }
                            ]
                        }
                    ],
                }
            ],
        }
    ],
}
_TEXT = json.dumps(_DOC, ensure_ascii=False, indent=2)


def _off(sub: str, start: int = 0) -> int:
    return _TEXT.index(sub, start)


class TestJsonPathAt(unittest.TestCase):
    def test_nested_object_array_root(self) -> None:
        cases = {
            "root": (0, "$"),
            "top key": (_off('"id"'), "$.id"),
            "top value": (_off('"s1"'), "$.id"),
            "array key": (_off('"units"'), "$.units"),
            "nested name": (_off('"name"', _off('"units"')), "$.units[0].name"),
            "array element": (
                _off('"a",'),
                "$.units[0].lessons[0].stages[0].items[0].options[0]",
            ),
            "second element": (
                _off('"b"'),
                "$.units[0].lessons[0].stages[0].items[0].options[1]",
            ),
            "number value": (
                _off("0\n"),
                "$.units[0].lessons[0].stages[0].items[0].correctIndex",
            ),
            # Whitespace between keys → innermost enclosing container.
            "whitespace": (
                _off('"correctIndex"') - 2,
                "$.units[0].lessons[0].stages[0].items[0]",
            ),
        }
        for name, (offset, want) in cases.items():
            with self.subTest(case=name):
                self.assertEqual(json_path_at(_TEXT, offset), want)

    def test_string_with_escapes(self) -> None:
        # The escaped quote inside the prompt must not end the string early.
        offset = _off('"say \\"hi\\"?"') + 6
        self.assertEqual(
            json_path_at(_TEXT, offset),
            "$.units[0].lessons[0].stages[0].items[0].prompt",
        )

    def test_invalid_json_returns_none(self) -> None:
        cases = {
            "missing comma": ('{"a":1 "b":2}', 3),
            "unterminated": ('{"a": [1, 2', 5),
            "empty": ("", 0),
            "whitespace": ("   \n", 1),
            "negative offset": (_TEXT, -1),
            "past end": (_TEXT, len(_TEXT) + 10),
            "non-string": (None, 0),
        }
        for name, (text, offset) in cases.items():
            with self.subTest(case=name):
                self.assertIsNone(json_path_at(text, offset))


class TestExplainPath(unittest.TestCase):
    def test_known_fields(self) -> None:
        result = explain_path(_DOC, "$.units[0].name")
        self.assertTrue(result["known"])
        self.assertEqual(result["summary"], "名称")
        # Field inside an interaction item → INTERACTION_SCHEMA detail.
        schema = explain_path(
            _DOC, "$.units[0].lessons[0].stages[0].items[0].prompt"
        )
        self.assertTrue(schema["known"])
        self.assertEqual(schema["summary"], "题干")
        self.assertIn("multipleChoice", schema["detail"])
        self.assertIn("必填", schema["detail"])

    def test_unknown_path_fallback_never_raises(self) -> None:
        for path in ("$.zzz", "$.units[0].mystery", None, "", "not-a-path"):
            with self.subTest(path=path):
                result = explain_path(_DOC, path)
                self.assertFalse(result["known"])
                self.assertEqual(result["summary"], "未识别路径")
                self.assertIn("detail", result)
        # Path beyond the document reports absence, still no raise.
        missing = explain_path(_DOC, "$.units[5].name")
        self.assertIn("不存在", missing["detail"])
        # Garbage inputs must never raise.
        for obj in (None, 42, [], {"a": object()}):
            for path in (None, "$", "$.a[", 123):
                with self.subTest(obj=type(obj).__name__, path=path):
                    self.assertIn(explain_path(obj, path)["known"], (True, False))


if __name__ == "__main__":
    unittest.main()
