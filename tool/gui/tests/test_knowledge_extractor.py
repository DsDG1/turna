"""Tests for knowledge_prompt + knowledge_extractor's pure parsing logic.

No monkeypatching of request_chat, no network. Covers:
- build_extraction_messages: system/user shape, language + chapter content, truncation.
- build_correction_prompt: error list text.
- _collect_errors: JSON parse + coerce success/failure paths.
"""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.knowledge_extractor import _collect_errors  # noqa: E402
from src.backend.knowledge_prompt import (  # noqa: E402
    _MAX_CHAPTER_CHARS,
    KnowledgePromptLibrary,
    KnowledgePromptTemplates,
    build_correction_prompt,
    build_extraction_messages,
    _truncate_markdown,
)
from src.backend.markdown_chopper import split_chapters  # noqa: E402


def _chapter(title: str = "1 Merhaba", body: str = "merhaba means hello\n") -> "object":
    md = f"## {title}\n{body}"
    return split_chapters(md)[0]


# --------------------------------------------------------------------------- #
# build_extraction_messages
# --------------------------------------------------------------------------- #


class BuildExtractionMessagesTest(unittest.TestCase):
    def test_system_and_user_roles(self) -> None:
        msgs = build_extraction_messages("Turkish", "Chinese", _chapter())
        self.assertEqual([m["role"] for m in msgs], ["system", "user"])

    def test_system_enforces_json_only(self) -> None:
        msgs = build_extraction_messages("Turkish", "Chinese", _chapter())
        self.assertIn("JSON", msgs[0]["content"])

    def test_user_contains_languages_and_chapter(self) -> None:
        ch = _chapter(title="2 Aile", body="aile means family\n")
        msgs = build_extraction_messages("Turkish", "Chinese", ch)
        user = msgs[1]["content"]
        self.assertIn("Turkish", user)
        self.assertIn("Chinese", user)
        self.assertIn("2 Aile", user)
        self.assertIn("aile means family", user)

    def test_user_contains_schema_shape(self) -> None:
        user = build_extraction_messages("Turkish", "Chinese", _chapter())[1]["content"]
        for key in ("words", "expressions", "grammarPoints"):
            self.assertIn(f'"{key}"', user)
        for field in ("term", "translation", "title", "explanation"):
            self.assertIn(field, user)

    def test_user_does_not_request_units(self) -> None:
        user = build_extraction_messages("Turkish", "Chinese", _chapter())[1]["content"]
        # We deliberately avoid the units-bearing shape parse_completion requires.
        self.assertNotIn('"units"', user)

    def test_short_markdown_preserved_intact(self) -> None:
        body = "merhaba means hello\ngünaydın means good morning\n"
        ch = _chapter(body=body)
        user = build_extraction_messages("Turkish", "Chinese", ch)[1]["content"]
        self.assertIn(body.rstrip(), user)
        self.assertNotIn("已截断", user)

    def test_long_markdown_truncated_with_notice(self) -> None:
        body = "x" * (_MAX_CHAPTER_CHARS + 500) + "\n"
        ch = _chapter(body=body)
        user = build_extraction_messages("Turkish", "Chinese", ch)[1]["content"]
        self.assertIn("已截断", user)
        # The full oversized body must NOT be present verbatim.
        self.assertNotIn(body.rstrip(), user)


# --------------------------------------------------------------------------- #
# build_correction_prompt
# --------------------------------------------------------------------------- #


class BuildCorrectionPromptTest(unittest.TestCase):
    def test_lists_each_error(self) -> None:
        prompt = build_correction_prompt(["缺 term", "缺 title"])
        self.assertIn("缺 term", prompt)
        self.assertIn("缺 title", prompt)
        self.assertIn("完整的修正 JSON", prompt)

    def test_empty_errors_still_builds(self) -> None:
        # Defensive: should not crash on an empty list.
        prompt = build_correction_prompt([])
        self.assertIn("JSON", prompt)


# --------------------------------------------------------------------------- #
# _collect_errors (parse + coerce, no network)
# --------------------------------------------------------------------------- #


class CollectErrorsTest(unittest.TestCase):
    def test_valid_extraction_returns_kp_no_errors(self) -> None:
        content = json.dumps(
            {
                "words": [{"term": "merhaba", "translation": "hello"}],
                "expressions": [{"term": "Selam!", "translation": "Hi!"}],
                "grammarPoints": [{"title": "Greetings", "explanation": "hi"}],
            },
            ensure_ascii=False,
        )
        errors, kp = _collect_errors(content, id_prefix="ch-1-merhaba-")
        self.assertEqual(errors, [])
        self.assertIsNotNone(kp)
        assert kp is not None  # for type checker
        self.assertEqual(kp.words[0]["id"], "ch-1-merhaba-w-merhaba")
        self.assertEqual(len(kp.expressions), 1)
        self.assertEqual(len(kp.grammarPoints), 1)

    def test_strips_markdown_fences(self) -> None:
        content = (
            "```json\n"
            + json.dumps({"words": [{"term": "ev", "translation": "house"}]})
            + "\n```"
        )
        errors, kp = _collect_errors(content, id_prefix="")
        self.assertEqual(errors, [])
        self.assertIsNotNone(kp)

    def test_empty_content_is_error(self) -> None:
        errors, kp = _collect_errors("   ", id_prefix="")
        self.assertTrue(errors)
        self.assertIsNone(kp)

    def test_non_json_content_is_error(self) -> None:
        errors, kp = _collect_errors("this is not json at all", id_prefix="")
        self.assertTrue(errors)
        self.assertIsNone(kp)

    def test_word_missing_term_is_error(self) -> None:
        # coerce raises ValueError on word without term -> surfaced as error.
        content = json.dumps({"words": [{"translation": "x"}]})
        errors, kp = _collect_errors(content, id_prefix="")
        self.assertTrue(errors)
        self.assertIsNone(kp)

    def test_grammar_point_missing_title_is_error(self) -> None:
        content = json.dumps({"grammarPoints": [{"explanation": "no title"}]})
        errors, kp = _collect_errors(content, id_prefix="")
        self.assertTrue(errors)
        self.assertIsNone(kp)

    def test_empty_extraction_is_not_error(self) -> None:
        # An all-empty-but-valid object coerces to empty groups; the GUI marks
        # empty chapters to skip. This is success, not an error.
        content = json.dumps({"words": [], "expressions": [], "grammarPoints": []})
        errors, kp = _collect_errors(content, id_prefix="")
        self.assertEqual(errors, [])
        self.assertIsNotNone(kp)
        assert kp is not None
        self.assertEqual(kp.words, [])


# --------------------------------------------------------------------------- #
# paragraph-aware truncation (bookplan2 Phase 5)
# --------------------------------------------------------------------------- #


class TruncationTest(unittest.TestCase):
    def test_short_markdown_unchanged(self) -> None:
        self.assertEqual(_truncate_markdown("short text", 100), "short text")

    def test_hard_cut_when_no_paragraph_boundary(self) -> None:
        body = "x" * 500
        out = _truncate_markdown(body, 100)
        self.assertIn("已截断", out)
        self.assertNotIn("x" * 500, out)
        # Falls back to a hard cut at the cap (no paragraph boundary to honour).
        self.assertTrue(out.startswith("x" * 100))

    def test_cuts_at_paragraph_boundary(self) -> None:
        # Two paragraphs; the boundary sits inside the back half of the window.
        para_a = "a" * 60
        para_b = "b" * 60
        md = f"{para_a}\n\n{para_b}"
        out = _truncate_markdown(md, 80)
        self.assertIn("已截断", out)
        # The first paragraph is preserved intact; the second is dropped at the
        # boundary rather than mid-word.
        self.assertIn(para_a, out)
        self.assertNotIn(para_b, out)

    def test_max_chars_param_overrides_default(self) -> None:
        body = "x" * 1000
        out = _truncate_markdown(body, 200)
        # Hard cut (no boundary) -> 200 chars then notice.
        self.assertTrue(out.startswith("x" * 200))


# --------------------------------------------------------------------------- #
# KnowledgePromptLibrary (bookplan2 Phase 5)
# --------------------------------------------------------------------------- #


class KnowledgePromptLibraryTest(unittest.TestCase):
    def test_default_templates_used_for_unknown_pair(self) -> None:
        lib = KnowledgePromptLibrary()
        tpl = lib.templates_for("Turkish", "Chinese")
        self.assertIn("JSON", tpl.system)
        self.assertIn("words", tpl.schema_block)

    def test_register_override_is_returned_for_pair(self) -> None:
        lib = KnowledgePromptLibrary()
        custom = KnowledgePromptTemplates(system="CUSTOM SYSTEM")
        lib.register("Spanish", "English", custom)
        self.assertEqual(lib.templates_for("Spanish", "English").system, "CUSTOM SYSTEM")
        # Other pairs keep the default.
        self.assertNotEqual(
            lib.templates_for("Turkish", "Chinese").system, "CUSTOM SYSTEM"
        )

    def test_register_is_case_insensitive(self) -> None:
        lib = KnowledgePromptLibrary()
        custom = KnowledgePromptTemplates(intro="Hola")
        lib.register("spanish", "english", custom)
        self.assertEqual(lib.templates_for("Spanish", "English").intro, "Hola")

    def test_override_flows_into_extraction_messages(self) -> None:
        lib = KnowledgePromptLibrary()
        lib.register(
            "Turkish",
            "Chinese",
            KnowledgePromptTemplates(system="TURKISH-ONLY SYSTEM"),
        )
        ch = _chapter()
        msgs = build_extraction_messages("Turkish", "Chinese", ch, library=lib)
        self.assertEqual(msgs[0]["content"], "TURKISH-ONLY SYSTEM")

    def test_max_chars_param_threads_into_truncation(self) -> None:
        body = "y" * 1000
        ch = _chapter(body=body)
        user = build_extraction_messages("Turkish", "Chinese", ch, max_chars=150)[
            1
        ]["content"]
        self.assertIn("已截断", user)

    def test_clear_removes_overrides(self) -> None:
        lib = KnowledgePromptLibrary()
        lib.register("Spanish", "English", KnowledgePromptTemplates(system="X"))
        lib.clear()
        self.assertNotEqual(lib.templates_for("Spanish", "English").system, "X")


if __name__ == "__main__":
    unittest.main()