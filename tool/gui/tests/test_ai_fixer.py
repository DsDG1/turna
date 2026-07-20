"""Tests for AI correction prompt building and JSON extraction."""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.ai_fixer import build_correction_prompt, extract_json_object  # noqa: E402


class AiFixerTest(unittest.TestCase):
    def test_build_correction_prompt_contains_problems_and_node(self) -> None:
        problems = [
            {"level": "error", "message": "missing wordId", "path": "unit:u1/lesson:l1"},
        ]
        node = {"id": "l1", "name": "Lesson 1"}
        context = {"node_kind": "lesson", "language": "en"}
        prompt = build_correction_prompt(problems, node, context)
        self.assertIn("missing wordId", prompt)
        self.assertIn("\"id\": \"l1\"", prompt)
        self.assertIn("node_kind", prompt)
        self.assertIn("保持所有 id 不变", prompt)

    def test_build_correction_prompt_contains_user_hint(self) -> None:
        problems = [
            {"level": "error", "message": "missing wordId", "path": "unit:u1/lesson:l1"},
        ]
        node = {"id": "l1", "name": "Lesson 1"}
        context = {"node_kind": "lesson", "language": "en"}
        prompt = build_correction_prompt(problems, node, context, user_hint="强制修改翻译")
        self.assertIn("## 额外用户指引 (优先级高)", prompt)
        self.assertIn("强制修改翻译", prompt)

    def test_extract_json_object_strips_markdown_fence(self) -> None:
        text = "```json\n{\"id\": \"x\"}\n```"
        result = extract_json_object(text)
        self.assertEqual(result, {"id": "x"})

    def test_extract_json_object_finds_first_object(self) -> None:
        text = "Here is the fix: {\"id\": \"x\", \"name\": \"y\"} thanks."
        result = extract_json_object(text)
        self.assertEqual(result, {"id": "x", "name": "y"})

    def test_extract_json_object_raises_on_invalid(self) -> None:
        with self.assertRaises(ValueError):
            extract_json_object("no json here")


if __name__ == "__main__":
    unittest.main()
