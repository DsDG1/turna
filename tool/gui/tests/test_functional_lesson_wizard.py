"""Tests for the functional-lesson wizard (workshop2 P2)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))
from tests._qtapp import _App  # noqa: E402


from src.backend.course_adapter import CourseAdapter  # noqa: E402
from src.backend.lesson_content import CONTENT_BY_TEMPLATE  # noqa: E402
from src.backend.lesson_presets import FUNCTIONAL_TEMPLATES, presets_for_template  # noqa: E402
from src.dialogs.functional_lesson_wizard import (  # noqa: E402
    FunctionalLessonWizard,
    _empty_functional_lesson,
)


def _wrap_section(lesson):
    return {
        "id": "sec-w",
        "name": "Wizard test",
        "level": "A1",
        "prerequisiteSectionIds": [],
        "units": [{"id": "u-w", "name": "U", "lessons": [lesson]}],
    }


class EmptyFunctionalLessonTest(unittest.TestCase):
    def test_empty_functional_lesson_shapes(self) -> None:
        listening = _empty_functional_lesson("listening", "L")
        self.assertEqual(listening["template"], "listening")
        self.assertEqual(listening["content"], {"listeningPhases": []})

        reading = _empty_functional_lesson("reading", "R")
        self.assertIn("readingPassage", reading["content"])
        self.assertIn("stages", reading["content"])

        mastery = _empty_functional_lesson("mastery", "M")
        self.assertEqual(len(mastery["content"]["stages"]), 1)
        self.assertEqual(mastery["content"]["stages"][0]["items"], [])


class WizardBuildTest(unittest.TestCase):
    def setUp(self) -> None:
        _App.get()
        self.adapter = CourseAdapter()

    def _wizard(self, template, name="课"):
        return FunctionalLessonWizard(
            self.adapter, "u-w", None, initial_template=template, initial_name=name
        )

    def test_builds_validator_passing_lesson_for_each_preset(self) -> None:
        for template in FUNCTIONAL_TEMPLATES:
            for preset in presets_for_template(template):
                with self.subTest(template=template, preset=preset.id):
                    wiz = self._wizard(template)
                    # Select this preset (index 1 = first preset after 空白).
                    self.assertEqual(wiz._preset_combo.itemData(1), preset.id)
                    wiz._preset_combo.setCurrentIndex(1)
                    wiz._build_working_lesson()
                    lesson = wiz.result_lesson()
                    self.assertEqual(lesson["template"], template)
                    self.assertTrue(lesson["id"])
                    problems = self.adapter.validate_section_json(
                        _wrap_section(lesson), check_existing_ids=False
                    )
                    errors = [p for p in problems if p.get("level") == "error"]
                    self.assertFalse(errors, f"{preset.id}: {errors}")
                    # Content keys respect the template shape.
                    keys = set(lesson.get("content", {}))
                    self.assertTrue(keys <= CONTENT_BY_TEMPLATE[template])

    def test_empty_skeleton_path(self) -> None:
        wiz = self._wizard("listening")
        # 空白骨架 is index 0.
        wiz._preset_combo.setCurrentIndex(0)
        wiz._build_working_lesson()
        lesson = wiz.result_lesson()
        self.assertEqual(lesson["content"], {"listeningPhases": []})

    def test_step_navigation_renders_config_and_preview(self) -> None:
        wiz = self._wizard("reading")
        wiz._goto_step(1)  # builds lesson + renders config
        self.assertEqual(wiz._step, 1)
        self.assertIsNotNone(wiz._lesson)
        # config host should have content.
        self.assertGreater(wiz._config_layout.count(), 0)
        wiz._goto_step(2)  # renders preview
        self.assertEqual(wiz._step, 2)
        self.assertGreater(wiz._preview_layout.count(), 0)
        wiz._back()
        self.assertEqual(wiz._step, 1)


class WizardMasteryConfigTest(unittest.TestCase):
    def setUp(self) -> None:
        _App.get()
        self.adapter = CourseAdapter()

    def test_toggling_mastery_type_adds_and_removes_items(self) -> None:
        wiz = FunctionalLessonWizard(
            self.adapter, "u-w", None, initial_template="mastery", initial_name="M"
        )
        wiz._goto_step(1)  # renders mastery config -> _mastery_checks populated
        stage = wiz._lesson["content"]["stages"][0]

        # mastery-mix preset seeds all three; untick multipleChoice.
        wiz._mastery_checks["multipleChoice"].setChecked(False)
        self.assertFalse(
            any(it.get("runtimeType") == "multipleChoice" for it in stage["items"])
        )
        # Re-tick -> exactly one multipleChoice item added.
        wiz._mastery_checks["multipleChoice"].setChecked(True)
        mc = [it for it in stage["items"] if it.get("runtimeType") == "multipleChoice"]
        self.assertEqual(len(mc), 1)


class WizardListeningConfigTest(unittest.TestCase):
    def setUp(self) -> None:
        _App.get()
        self.adapter = CourseAdapter()

    def test_add_and_delete_phase(self) -> None:
        from src.backend.lesson_content import LISTENING_PHASE_TYPES

        wiz = FunctionalLessonWizard(
            self.adapter, "u-w", None, initial_template="listening", initial_name="L"
        )
        wiz._goto_step(1)
        before = len(wiz._lesson["content"]["listeningPhases"])
        # Pick a phase type and add.
        wiz._phase_type_combo.setCurrentIndex(
            LISTENING_PHASE_TYPES.index("summary")
        )
        wiz._on_wizard_add_phase()
        self.assertEqual(len(wiz._lesson["content"]["listeningPhases"]), before + 1)
        # Delete the newly added phase (last one).
        last = wiz._lesson["content"]["listeningPhases"][-1]
        wiz._on_wizard_delete_phase(last)
        self.assertEqual(len(wiz._lesson["content"]["listeningPhases"]), before)

    def test_changing_preset_on_step0_rebuilds_lesson(self) -> None:
        from src.backend.lesson_presets import presets_for_template

        wiz = FunctionalLessonWizard(
            self.adapter, "u-w", None, initial_template="listening", initial_name="L"
        )
        # First preset (index 1) builds a 3-phase lesson.
        wiz._preset_combo.setCurrentIndex(1)
        wiz._goto_step(1)
        self.assertEqual(len(wiz._lesson["content"]["listeningPhases"]), 3)
        # Go back, switch to 空白骨架 (index 0), forward again.
        wiz._goto_step(0)
        wiz._preset_combo.setCurrentIndex(0)
        wiz._goto_step(1)
        self.assertEqual(wiz._lesson["content"]["listeningPhases"], [])
        # Back, switch to the preset again -> rebuilt with 3 phases.
        wiz._goto_step(0)
        wiz._preset_combo.setCurrentIndex(1)
        wiz._goto_step(1)
        self.assertEqual(len(wiz._lesson["content"]["listeningPhases"]), 3)


if __name__ == "__main__":
    unittest.main()
