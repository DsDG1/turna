"""Tests for src.backend.textbook_presets (bookplan2 Phase 5)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.textbook_presets import (
    BUILTIN_TEXTBOOK_PRESETS,
    TextbookPreset,
    preset_for,
    preset_names,
)


class BuiltinPresetsTest(unittest.TestCase):
    def test_four_builtin_presets_present(self) -> None:
        self.assertEqual(
            set(preset_names()), {"general", "grammar", "dialogue", "reading"}
        )
        for name in preset_names():
            self.assertIn(name, BUILTIN_TEXTBOOK_PRESETS)

    def test_general_is_safe_default(self) -> None:
        general = preset_for("general")
        self.assertEqual(general.strategy, "standard")
        self.assertEqual(general.lesson_template, "intro")
        self.assertAlmostEqual(general.temperature, 0.3)

    def test_grammar_low_temperature(self) -> None:
        grammar = preset_for("grammar")
        self.assertLess(grammar.temperature, preset_for("general").temperature)
        self.assertEqual(grammar.strategy, "standard")
        self.assertIsNotNone(grammar.max_tokens)

    def test_dialogue_higher_temperature(self) -> None:
        dialogue = preset_for("dialogue")
        self.assertGreater(dialogue.temperature, preset_for("general").temperature)

    def test_reading_uses_vocab_only_strategy(self) -> None:
        reading = preset_for("reading")
        self.assertEqual(reading.strategy, "vocab_only")
        self.assertGreater(reading.max_chapter_chars, preset_for("general").max_chapter_chars)

    def test_unknown_name_falls_back_to_general(self) -> None:
        self.assertEqual(preset_for("nonexistent").name, "general")

    def test_preset_is_frozen(self) -> None:
        preset = preset_for("general")
        with self.assertRaises(Exception):
            preset.temperature = 0.9  # type: ignore[misc]

    def test_labels_are_distinct_and_nonempty(self) -> None:
        labels = {preset_for(n).label for n in preset_names()}
        self.assertEqual(len(labels), len(preset_names()))
        self.assertTrue(all(labels))

    def test_all_presets_use_intro_lesson_template(self) -> None:
        # Only "intro" is meaningfully wired today; every built-in must default
        # to it so build_section_from_chapter never picks an unwired template.
        for name in preset_names():
            self.assertEqual(preset_for(name).lesson_template, "intro")

    def test_all_presets_have_positive_max_chapter_chars(self) -> None:
        for name in preset_names():
            self.assertGreater(preset_for(name).max_chapter_chars, 0)

    def test_all_presets_strategy_is_valid(self) -> None:
        for name in preset_names():
            self.assertIn(preset_for(name).strategy, ("standard", "vocab_only"))
