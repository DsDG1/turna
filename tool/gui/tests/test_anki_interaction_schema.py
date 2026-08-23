"""Schema-sync plan P0: ankiCard / ankiHtmlCard interaction schemas.

Covers the schema whitelist additions, lossless round-trips through
``normalize_item`` (the save path rebuilds items from the schema), and
runtimeType switching semantics (front/back join the prompt/answer groups
while ids stay immutable — design constraint #3).
"""
from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.lesson_content import (  # noqa: E402
    ALLOWED_RUNTIME_TYPES,
    INTERACTION_SCHEMA,
    default_interaction,
    normalize_item,
    switch_runtime_type,
    switch_template,
    new_lesson_from_template,
)


def _field_names(rt: str) -> set[str]:
    return {spec.name for spec in INTERACTION_SCHEMA[rt]}


class AnkiSchemaShapeTest(unittest.TestCase):
    def test_anki_types_registered(self) -> None:
        self.assertIn("ankiCard", ALLOWED_RUNTIME_TYPES)
        self.assertIn("ankiHtmlCard", ALLOWED_RUNTIME_TYPES)
        # Appended at the end — existing order untouched.
        self.assertEqual(ALLOWED_RUNTIME_TYPES[-2:], ("ankiCard", "ankiHtmlCard"))

    def test_anki_card_field_set(self) -> None:
        self.assertEqual(
            _field_names("ankiCard"),
            {
                "id", "front", "back", "audioAssets", "imageAssets",
                "hint", "sourceNoteId",
            },
        )
        required = {spec.name for spec in INTERACTION_SCHEMA["ankiCard"] if spec.required}
        self.assertEqual(required, {"front", "back"})

    def test_anki_html_card_field_set(self) -> None:
        self.assertEqual(
            _field_names("ankiHtmlCard"),
            {
                "id", "frontHtml", "backHtml", "css", "mediaBasePath",
                "allowJs", "audioAssets", "sourceNoteId", "sourceCardId",
                "wordId",
            },
        )
        required = {
            spec.name for spec in INTERACTION_SCHEMA["ankiHtmlCard"] if spec.required
        }
        self.assertEqual(required, {"frontHtml", "backHtml"})
        # The synthetic anki word id must NOT be a ref_word dropdown.
        word_id_spec = next(s for s in INTERACTION_SCHEMA["ankiHtmlCard"] if s.name == "wordId")
        self.assertEqual(word_id_spec.kind, "string")

    def test_default_interaction_allow_js_off(self) -> None:
        item = default_interaction("ankiHtmlCard")
        self.assertIs(item["allowJs"], False)
        self.assertEqual(item["css"], "")
        self.assertEqual(item["audioAssets"], [])


class AnkiRoundTripTest(unittest.TestCase):
    def test_anki_card_normalize_lossless(self) -> None:
        raw = {
            "runtimeType": "ankiCard",
            "id": "anki-imp1-n42-c0",
            "front": "merhaba",
            "back": "你好",
            "audioAssets": ["anki://imp1/a.mp3"],
            "imageAssets": ["anki://imp1/i.png"],
            "hint": "greeting",
            "sourceNoteId": "42",
        }
        out = normalize_item(raw)
        self.assertEqual(out, raw)

    def test_anki_html_card_normalize_lossless(self) -> None:
        raw = {
            "runtimeType": "ankiHtmlCard",
            "id": "anki-imp1-n42-c1",
            "frontHtml": "<div>merhaba</div>",
            "backHtml": "<div>你好</div>",
            "css": ".card { color: red; }",
            "mediaBasePath": "anki-imports/imp1",
            "allowJs": True,
            "audioAssets": ["anki://imp1/a.mp3"],
            "sourceNoteId": "42",
            "sourceCardId": "1700000001",
            "wordId": "anki-imp1-c1700000001",
        }
        out = normalize_item(raw)
        self.assertEqual(out, raw)

    def test_normalize_fills_missing_optionals(self) -> None:
        out = normalize_item(
            {"runtimeType": "ankiCard", "front": "a", "back": "b"}
        )
        self.assertEqual(out["audioAssets"], [])
        self.assertEqual(out["imageAssets"], [])
        self.assertEqual(out["hint"], "")
        self.assertEqual(out["sourceNoteId"], "")
        self.assertEqual(out["id"], "")

    def test_double_normalize_is_idempotent(self) -> None:
        raw = {
            "runtimeType": "ankiHtmlCard",
            "id": "anki-x-n1-c0",
            "frontHtml": "f",
            "backHtml": "b",
            "allowJs": False,
        }
        self.assertEqual(normalize_item(normalize_item(raw)), normalize_item(raw))


class AnkiSwitchTest(unittest.TestCase):
    def test_switch_anki_card_to_fill_blank_maps_faces(self) -> None:
        item = {
            "runtimeType": "ankiCard",
            "id": "anki-imp1-n42-c0",
            "front": "Merhaba means?",
            "back": "hello",
            "hint": "greeting",
            "sourceNoteId": "42",
        }
        new_item = switch_runtime_type(item, "fillBlank")
        self.assertEqual(new_item["runtimeType"], "fillBlank")
        # front joins the prompt group -> sentence; back -> answer.
        self.assertEqual(new_item["sentence"], "Merhaba means?")
        self.assertEqual(new_item["answer"], "hello")
        self.assertEqual(new_item["hint"], "greeting")
        # Constraint #3: id immutable across type switches.
        self.assertEqual(new_item["id"], "anki-imp1-n42-c0")
        # Provenance fields do not leak into the new type.
        self.assertNotIn("sourceNoteId", new_item)

    def test_switch_anki_card_to_multiple_choice_keeps_front_as_prompt(self) -> None:
        item = {
            "runtimeType": "ankiCard",
            "id": "anki-imp1-n7-c0",
            "front": "Pick the greeting",
            "back": "merhaba",
            "audioAssets": ["anki://imp1/a.mp3"],
        }
        new_item = switch_runtime_type(item, "multipleChoice")
        self.assertEqual(new_item["prompt"], "Pick the greeting")
        self.assertEqual(new_item["id"], "anki-imp1-n7-c0")
        # multipleChoice has no answer-group slot; back is dropped, not mangled.
        self.assertNotIn("back", new_item)
        # Same-name audioAssets list survives.
        self.assertEqual(new_item["audioAssets"], ["anki://imp1/a.mp3"])

    def test_switch_multiple_choice_to_anki_card(self) -> None:
        item = {
            "runtimeType": "multipleChoice",
            "id": "mc-9",
            "prompt": "Meaning of merhaba?",
            "options": ["hello", "bye"],
            "correctIndex": 0,
            "audioAssets": ["anki://imp1/a.mp3"],
        }
        new_item = switch_runtime_type(item, "ankiCard")
        self.assertEqual(new_item["front"], "Meaning of merhaba?")
        self.assertEqual(new_item["id"], "mc-9")
        self.assertEqual(new_item["audioAssets"], ["anki://imp1/a.mp3"])
        # No options on a flip card; correctIndex has no target field.
        self.assertNotIn("options", new_item)

    def test_switch_anki_html_front_html_joins_prompt_group(self) -> None:
        item = {
            "runtimeType": "ankiHtmlCard",
            "id": "ah-1",
            "frontHtml": "<b>front</b>",
            "backHtml": "<i>back</i>",
        }
        new_item = switch_runtime_type(item, "translateSentence")
        self.assertEqual(new_item["source"], "<b>front</b>")
        self.assertEqual(new_item["expected"], "<i>back</i>")
        self.assertEqual(new_item["id"], "ah-1")


class TemplateSwitchPreservesLinkedGrammarTest(unittest.TestCase):
    """P2.1: content.linkedGrammarPointIds survives template switches."""

    def test_new_lesson_from_template_injects_empty_link_list(self) -> None:
        for tmpl in ("intro", "practice", "review", "legacy", "mastery"):
            unit: dict = {"lessons": []}
            lesson = new_lesson_from_template(tmpl, unit)
            self.assertEqual(
                lesson["content"].get("linkedGrammarPointIds"), [],
                f"template {tmpl}",
            )

    def test_switch_template_keeps_linked_grammar_point_ids(self) -> None:
        unit: dict = {"lessons": []}
        lesson = new_lesson_from_template("review", unit)
        lesson["content"]["linkedGrammarPointIds"] = ["g-1", "g-2"]
        switch_template(lesson, "listening")
        self.assertEqual(lesson["content"].get("linkedGrammarPointIds"), ["g-1", "g-2"])
        switch_template(lesson, "mastery")
        self.assertEqual(lesson["content"].get("linkedGrammarPointIds"), ["g-1", "g-2"])


if __name__ == "__main__":
    unittest.main()
