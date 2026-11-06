from __future__ import annotations

import sys
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from tests._qtapp import qt_app

from src.backend.course_adapter import CourseAdapter
from src.backend.course_preview.document import build_document
from src.backend.lesson_content import new_lesson_from_template
from src.widgets.lesson_editor import DialogueEditor, ReviewPolicyEditor


class DialogueReviewEditorTest(unittest.TestCase):
    def setUp(self) -> None:
        qt_app()
        self.adapter = CourseAdapter()

    def test_dialogue_editor_updates_scene_and_turn(self) -> None:
        lesson = new_lesson_from_template("dialogue", {})
        editor = DialogueEditor(self.adapter, lesson)
        editor.title_edit.setText("Cafe")
        editor.turns.item(0, 2).setText("Merhaba!")

        self.assertEqual(lesson["content"]["dialogueScene"]["title"], "Cafe")
        self.assertEqual(
            lesson["content"]["dialogueScene"]["turns"][0]["text"],
            "Merhaba!",
        )
        editor.deleteLater()

    def test_dialogue_preview_shows_roles_without_filling_learner_answer(self) -> None:
        lesson = new_lesson_from_template("dialogue", {})
        lesson["content"]["stages"][0]["items"][0]["answer"] = "Teşekkürler"
        section = {
            "id": "section",
            "name": "Section",
            "units": [{"id": "unit", "name": "Unit", "lessons": [lesson]}],
        }
        document = build_document(section)
        context = document.units[0].lessons[0].context
        self.assertIn("Ayşe：Merhaba!", context)
        self.assertIn("你：（学习者回应）", context)
        self.assertNotIn("Teşekkürler", context)

    def test_review_editor_updates_bounds_and_type_weight(self) -> None:
        lesson = new_lesson_from_template("review", {})
        lesson["content"]["stages"][0]["items"].append({
            "runtimeType": "fillBlank",
            "id": "fill-1",
            "sentence": "_____",
            "answer": "A",
            "choices": [],
        })
        editor = ReviewPolicyEditor(lesson)
        editor.min_spin.setValue(1)
        editor.max_spin.setValue(1)
        weight = editor.weights.cellWidget(0, 1)
        weight.setValue(1.5)

        policy = lesson["content"]["reviewPolicy"]
        self.assertEqual(policy["minItems"], 1)
        self.assertEqual(policy["maxItems"], 1)
        self.assertEqual(policy["typeWeights"]["fillBlank"], 1.5)
        editor.enabled.setChecked(False)
        self.assertNotIn("reviewPolicy", lesson["content"])
        editor.deleteLater()


if __name__ == "__main__":
    unittest.main()
