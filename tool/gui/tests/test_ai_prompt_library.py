"""Tests for the AI prompt template library and history."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.ai_generator import AiCourseSpec
from src.backend.ai_prompt_library import (
    AiPromptHistory,
    AiPromptLibrary,
    AiPromptTemplate,
)


def _make_qsettings() -> MagicMock:
    store: dict[str, str] = {}
    qs = MagicMock()
    qs.value = lambda key, default="": store.get(key, default)
    qs.setValue = lambda key, value: store.__setitem__(key, value)
    qs.beginGroup = lambda _name: None
    qs.endGroup = lambda: None
    return qs


class AiPromptTemplateTest(unittest.TestCase):
    def test_from_spec_round_trip(self) -> None:
        spec = AiCourseSpec(
            topic="旅行",
            level="A1",
            unit_count=2,
            lessons_per_unit=3,
            template="mixed",
            use_genre_batch=True,
            extra_instructions="加听力",
        )
        tpl = AiPromptTemplate.from_spec("旅行模板", spec)
        self.assertEqual(tpl.topic, "旅行")
        self.assertEqual(tpl.use_genre_batch, True)
        applied = tpl.apply_to_spec(AiCourseSpec())
        self.assertEqual(applied.topic, "旅行")
        self.assertEqual(applied.level, "A1")


class AiPromptLibraryTest(unittest.TestCase):
    def test_save_and_list_templates(self) -> None:
        qs = _make_qsettings()
        lib = AiPromptLibrary(qs)
        tpl = AiPromptTemplate(name="test", topic="旅行")
        lib.save_template(tpl)
        templates = lib.list_templates()
        self.assertEqual(len(templates), 1)
        self.assertEqual(templates[0].name, "test")

    def test_save_overwrites_same_name(self) -> None:
        qs = _make_qsettings()
        lib = AiPromptLibrary(qs)
        lib.save_template(AiPromptTemplate(name="x", topic="a"))
        lib.save_template(AiPromptTemplate(name="x", topic="b"))
        self.assertEqual(len(lib.list_templates()), 1)
        self.assertEqual(lib.list_templates()[0].topic, "b")

    def test_delete_template(self) -> None:
        qs = _make_qsettings()
        lib = AiPromptLibrary(qs)
        lib.save_template(AiPromptTemplate(name="x"))
        self.assertTrue(lib.delete_template("x"))
        self.assertFalse(lib.delete_template("x"))

    def test_record_history_deduplicates_and_caps(self) -> None:
        qs = _make_qsettings()
        lib = AiPromptLibrary(qs)
        spec = AiCourseSpec(topic="a")
        for _ in range(22):
            lib.record_history(spec)
        self.assertEqual(len(lib.recent_history()), 1)

    def test_history_differentiated_by_fields(self) -> None:
        qs = _make_qsettings()
        lib = AiPromptLibrary(qs)
        lib.record_history(AiCourseSpec(topic="a"))
        lib.record_history(AiCourseSpec(topic="b"))
        self.assertEqual(len(lib.recent_history()), 2)


if __name__ == "__main__":
    unittest.main()
