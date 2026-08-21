"""Tests for the functional-lesson preset library (workshop2 P1)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.course_adapter import CourseAdapter  # noqa: E402
from src.backend.lesson_content import (  # noqa: E402
    CONTENT_BY_TEMPLATE,
    PRIMARY_CONTENT_KEY,
    all_lesson_ids,
)
from src.backend.lesson_presets import (  # noqa: E402
    FUNCTIONAL_PRESETS,
    FUNCTIONAL_TEMPLATES,
    PRESET_BY_ID,
    build_preset_lesson,
    presets_for_template,
)


def _all_item_ids(lesson: dict) -> list[str]:
    ids: list[str] = []
    content = lesson.get("content", {})

    def collect(items):
        for it in items:
            if it.get("id"):
                ids.append(it["id"])

    for sub in content.get("subLessons", []):
        ids.append(sub.get("id", ""))
        for st in sub.get("stages", []):
            ids.append(st.get("id", ""))
            collect(st.get("items", []))
    for st in content.get("stages", []):
        ids.append(st.get("id", ""))
        collect(st.get("items", []))
    for ph in content.get("listeningPhases", []):
        ids.append(ph.get("id", ""))
        collect(ph.get("items", []))
    return ids


class PresetRegistryTest(unittest.TestCase):
    def test_registry_has_functional_presets(self) -> None:
        templates = {p.template for p in FUNCTIONAL_PRESETS}
        for ft in FUNCTIONAL_TEMPLATES:
            self.assertIn(ft, templates, f"missing preset for functional template {ft}")

    def test_presets_for_template_filters(self) -> None:
        self.assertTrue(all(p.template == "listening" for p in presets_for_template("listening")))
        self.assertTrue(len(presets_for_template("listening")) >= 1)
        self.assertEqual(presets_for_template("nonexistent"), [])

    def test_preset_by_id_covers_all(self) -> None:
        for p in FUNCTIONAL_PRESETS:
            self.assertIs(PRESET_BY_ID[p.id], p)


class PresetBuildTest(unittest.TestCase):
    def setUp(self) -> None:
        self.adapter = CourseAdapter()  # empty; validate with check_existing=False

    def _wrap_section(self, lesson: dict) -> dict:
        return {
            "id": "sec-test",
            "name": "Test section",
            "level": "A1",
            "prerequisiteSectionIds": [],
            "units": [
                {"id": "u-test", "name": "Test unit", "lessons": [lesson]},
            ],
        }

    def test_each_preset_builds_validator_passing_lesson(self) -> None:
        for preset in FUNCTIONAL_PRESETS:
            with self.subTest(preset=preset.id):
                lesson = build_preset_lesson(preset.id, name=f"课-{preset.id}")
                self.assertEqual(lesson["template"], preset.template)
                self.assertEqual(lesson["name"], f"课-{preset.id}")
                self.assertTrue(lesson["id"])
                section = self._wrap_section(lesson)
                problems = self.adapter.validate_section_json(
                    section, check_existing_ids=False
                )
                errors = [p for p in problems if p.get("level") == "error"]
                self.assertFalse(errors, f"{preset.id} produced errors: {errors}")

    def test_each_preset_content_shape_matches_template(self) -> None:
        for preset in FUNCTIONAL_PRESETS:
            with self.subTest(preset=preset.id):
                lesson = build_preset_lesson(preset.id)
                allowed = CONTENT_BY_TEMPLATE[preset.template]
                content_keys = set(lesson.get("content", {}).keys())
                self.assertTrue(
                    content_keys <= allowed,
                    f"{preset.id}: content keys {content_keys} not subset of {allowed}",
                )
                primary = PRIMARY_CONTENT_KEY[preset.template]
                self.assertIn(primary, lesson["content"])

    def test_each_preset_has_unique_structural_ids(self) -> None:
        for preset in FUNCTIONAL_PRESETS:
            with self.subTest(preset=preset.id):
                lesson = build_preset_lesson(preset.id)
                ids = [lesson["id"]] + _all_item_ids(lesson)
                self.assertTrue(all(ids), f"{preset.id}: empty structural id in {ids}")
                self.assertEqual(
                    len(ids), len(set(ids)), f"{preset.id}: duplicate ids {ids}"
                )

    def test_two_builds_produce_different_ids(self) -> None:
        preset = PRESET_BY_ID["listening-3phase"]
        a = preset.build("A")
        b = preset.build("B")
        self.assertNotEqual(a["id"], b["id"])
        self.assertNotEqual(
            a["content"]["listeningPhases"][0]["id"],
            b["content"]["listeningPhases"][0]["id"],
        )

    def test_build_preset_lesson_unknown_id_raises(self) -> None:
        with self.assertRaises(KeyError):
            build_preset_lesson("does-not-exist")

    def test_functional_presets_have_expected_seed_content(self) -> None:
        listening = build_preset_lesson("listening-3phase")
        phases = listening["content"]["listeningPhases"]
        self.assertEqual([p["type"] for p in phases], ["wordPairing", "dialogue", "summary"])

        reading = build_preset_lesson("reading-3q")
        rts = [it["runtimeType"] for it in reading["content"]["stages"][0]["items"]]
        self.assertEqual(rts, ["readingMcq", "readingTrueFalse", "readingShortAnswer"])

        mastery = build_preset_lesson("mastery-mix")
        rts = [it["runtimeType"] for it in mastery["content"]["stages"][0]["items"]]
        self.assertIn("multipleChoice", rts)
        self.assertIn("fillBlank", rts)

    def test_preset_lesson_id_not_in_all_lesson_ids_of_empty_course(self) -> None:
        lesson = build_preset_lesson("reading-3q")
        self.assertNotIn(lesson["id"], all_lesson_ids([]))


if __name__ == "__main__":
    unittest.main()
