"""Unit tests for ai_pedagogy prompt blocks (aiEnhance Phase 2 minimal)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.ai_generator import AiCourseSpec, build_prompt
from src.backend.ai_pedagogy import (
    distractor_rules_block,
    language_pack_block,
    level_guide_block,
    pedagogy_prompt_block,
    template_gradient_block,
)


class TestAiPedagogy(unittest.TestCase):
    def test_level_guide_differs(self) -> None:
        a1 = level_guide_block("A1")
        b2 = level_guide_block("B2")
        self.assertIn("A1", a1)
        self.assertIn("B2", b2)
        self.assertNotEqual(a1, b2)

    def test_level_normalize(self) -> None:
        self.assertIn("A1", level_guide_block("a1.1"))
        self.assertIn("A1", level_guide_block("unknown"))

    def test_turkish_pack(self) -> None:
        block = language_pack_block("Turkish")
        self.assertIn("元音和谐", block)
        self.assertIn("Turkish", block)

    def test_default_pack_for_other(self) -> None:
        block = language_pack_block("Swahili")
        self.assertIn("通用", block)

    def test_template_gradient(self) -> None:
        self.assertIn("listening", template_gradient_block("listening").lower())
        self.assertIn("intro", template_gradient_block("intro"))

    def test_distractor_rules(self) -> None:
        block = distractor_rules_block()
        self.assertIn("干扰项", block)
        self.assertIn("correctIndex", block)

    def test_full_pedagogy_block(self) -> None:
        block = pedagogy_prompt_block(level="A2", language="tr", template="practice")
        self.assertIn("教学法", block)
        self.assertIn("A2", block)
        self.assertIn("practice", block)
        self.assertIn("复现", block)

    def test_build_prompt_includes_pedagogy(self) -> None:
        prompt = build_prompt(
            AiCourseSpec(
                language="Turkish",
                topic="greetings",
                level="A1",
                template="intro",
            )
        )
        self.assertIn("教学法与质量约束", prompt)
        self.assertIn("CEFR A1", prompt)
        self.assertIn("干扰项", prompt)
        self.assertIn("先写 words", prompt)

    def test_build_prompt_grounded_order_rule(self) -> None:
        prompt = build_prompt(
            AiCourseSpec(
                language="Turkish",
                topic="x",
                level="A1",
                resource_pool=[
                    {
                        "id": "w-1",
                        "term": "a",
                        "translation": "b",
                        "_kind": "word",
                    }
                ],
            )
        )
        self.assertIn("grounded", prompt.lower())
        self.assertIn("new", prompt)
        self.assertIn("完整", prompt)


if __name__ == "__main__":
    unittest.main()
