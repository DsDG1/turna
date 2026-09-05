"""Tests for domain schema constants and StrEnum behavior."""

from __future__ import annotations

import json
import unittest

from src.backend.schema_constants import (
    KEY_EXPRESSIONS,
    KEY_GRAMMAR,
    KEY_ITEMS,
    KEY_LISTENING_PHASES,
    KEY_READING_PASSAGE,
    KEY_RUNTIME_TYPE,
    KEY_STAGES,
    KEY_SUB_LESSONS,
    KEY_VOCAB,
    ContentKey,
    CourseKey,
    InteractionType,
    ItemKey,
    ListeningPhaseType,
    ResourceKey,
    TemplateType,
)


class TestSchemaConstants(unittest.TestCase):
    """Verify that schema constants behave transparently as strings and match domain rules."""

    def test_str_enum_is_instance_of_str(self) -> None:
        """Every StrEnum member must literally be an instance of str."""
        self.assertIsInstance(ContentKey.STAGES, str)
        self.assertIsInstance(ResourceKey.VOCAB, str)
        self.assertIsInstance(ItemKey.RUNTIME_TYPE, str)
        self.assertIsInstance(CourseKey.COURSE, str)
        self.assertIsInstance(TemplateType.INTRO, str)
        self.assertIsInstance(InteractionType.MULTIPLE_CHOICE, str)
        self.assertIsInstance(ListeningPhaseType.WORD_PAIRING, str)

    def test_string_equality(self) -> None:
        """StrEnum values must equal raw string literals."""
        self.assertEqual(ContentKey.STAGES, "stages")
        self.assertEqual(ContentKey.SUB_LESSONS, "subLessons")
        self.assertEqual(ContentKey.LISTENING_PHASES, "listeningPhases")
        self.assertEqual(ContentKey.READING_PASSAGE, "readingPassage")
        self.assertEqual(ContentKey.ITEMS, "items")

        self.assertEqual(ResourceKey.VOCAB, "vocab")
        self.assertEqual(ResourceKey.EXPRESSIONS, "expressions")
        self.assertEqual(ResourceKey.GRAMMAR, "grammar")

        self.assertEqual(ItemKey.RUNTIME_TYPE, "runtimeType")
        self.assertEqual(ItemKey.PROMPT, "prompt")
        self.assertEqual(ItemKey.OPTIONS, "options")
        self.assertEqual(ItemKey.CORRECT_INDEX, "correctIndex")

    def test_dictionary_interchangeability(self) -> None:
        """Dict keyed by string can be accessed by StrEnum and vice-versa."""
        raw_dict = {"stages": [1, 2], "vocab": {"word_1": {}}}
        self.assertEqual(raw_dict[ContentKey.STAGES], [1, 2])
        self.assertEqual(raw_dict[KEY_STAGES], [1, 2])
        self.assertEqual(raw_dict[ResourceKey.VOCAB], {"word_1": {}})
        self.assertEqual(raw_dict[KEY_VOCAB], {"word_1": {}})

        enum_keyed_dict: dict[str, str] = {
            ContentKey.STAGES: "active",
            ResourceKey.GRAMMAR: "present",
        }
        self.assertEqual(enum_keyed_dict["stages"], "active")
        self.assertEqual(enum_keyed_dict["grammar"], "present")

    def test_json_serialization_without_custom_encoder(self) -> None:
        """StrEnum keys and values must serialize seamlessly to JSON."""
        data = {
            ContentKey.STAGES: [
                {
                    ItemKey.RUNTIME_TYPE: InteractionType.MULTIPLE_CHOICE,
                    ItemKey.PROMPT: "Test prompt",
                }
            ],
            CourseKey.METADATA: {
                CourseKey.TEMPLATE: TemplateType.PRACTICE,
            },
        }
        encoded = json.dumps(data)
        decoded = json.loads(encoded)
        self.assertIn("stages", decoded)
        self.assertEqual(decoded["stages"][0]["runtimeType"], "multipleChoice")
        self.assertEqual(decoded["stages"][0]["prompt"], "Test prompt")
        self.assertEqual(decoded["metadata"]["template"], "practice")

    def test_set_and_tuple_membership(self) -> None:
        """StrEnum members work transparently in set lookups."""
        raw_set = {"stages", "subLessons"}
        self.assertIn(ContentKey.STAGES, raw_set)
        self.assertIn(KEY_STAGES, raw_set)
        self.assertIn("stages", {ContentKey.STAGES, ContentKey.SUB_LESSONS})

    def test_shorthand_aliases(self) -> None:
        """Module-level shorthand aliases map correctly to StrEnum members."""
        self.assertIs(KEY_STAGES, ContentKey.STAGES)
        self.assertIs(KEY_SUB_LESSONS, ContentKey.SUB_LESSONS)
        self.assertIs(KEY_LISTENING_PHASES, ContentKey.LISTENING_PHASES)
        self.assertIs(KEY_READING_PASSAGE, ContentKey.READING_PASSAGE)
        self.assertIs(KEY_ITEMS, ContentKey.ITEMS)
        self.assertIs(KEY_VOCAB, ResourceKey.VOCAB)
        self.assertIs(KEY_EXPRESSIONS, ResourceKey.EXPRESSIONS)
        self.assertIs(KEY_GRAMMAR, ResourceKey.GRAMMAR)
        self.assertIs(KEY_RUNTIME_TYPE, ItemKey.RUNTIME_TYPE)

    def test_interaction_type_matches_lesson_content(self) -> None:
        """Ensure all 14 interaction types match ALLOWED_RUNTIME_TYPES in lesson_content."""
        from src.backend.lesson_content import ALLOWED_RUNTIME_TYPES

        enum_values = tuple(member.value for member in InteractionType)
        self.assertEqual(len(enum_values), 14)
        self.assertEqual(enum_values, ALLOWED_RUNTIME_TYPES)

    def test_template_type_matches_lesson_content(self) -> None:
        """Ensure all 7 template types match CONTENT_BY_TEMPLATE keys."""
        from src.backend.lesson_content import CONTENT_BY_TEMPLATE

        enum_values = set(member.value for member in TemplateType)
        self.assertEqual(len(enum_values), 7)
        self.assertEqual(enum_values, set(CONTENT_BY_TEMPLATE.keys()))


if __name__ == "__main__":
    unittest.main()
