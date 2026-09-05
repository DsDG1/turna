"""Unit tests for GeneratorWizardPanel."""
from __future__ import annotations

import unittest
from unittest.mock import MagicMock

from PySide6.QtCore import Qt
from tests._qtapp import qt_app

from src.dialogs.ai.generator_wizard_panel import GeneratorWizardPanel


class TestGeneratorWizardPanel(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = qt_app()

    def setUp(self):
        self.adapter = MagicMock()
        self.word = {"id": "w-hello", "term": "hello", "translation": "你好"}
        self.adapter.vocab = [self.word]
        self.adapter.vocab_options.return_value = [("w-hello", "hello — 你好")]
        self.panel = GeneratorWizardPanel(self.adapter)

    def test_initial_state(self):
        self.assertEqual(self.panel.word_list.count(), 1)
        item = self.panel.word_list.item(0)
        self.assertEqual(item.checkState(), Qt.CheckState.Unchecked)

    def test_generate_requires_words(self):
        # No words selected
        res = self.panel.generate()
        self.assertIsNone(res)
        self.assertIn("至少选择 1 个词", self.panel.summary_label.text())

    def test_generate_success(self):
        item = self.panel.word_list.item(0)
        item.setCheckState(Qt.CheckState.Checked)
        self.panel.name_edit.setText("Greetings")
        self.panel.desc_edit.setText("Learn greetings")

        captured = []
        self.panel.generated_ready.connect(captured.append)

        section = self.panel.generate()
        self.assertIsNotNone(section)
        self.assertEqual(section["name"], "Greetings")
        self.assertEqual(len(section["units"]), 1)
        self.assertEqual(len(captured), 1)
        self.assertEqual(captured[0], section)


if __name__ == "__main__":
    unittest.main()
