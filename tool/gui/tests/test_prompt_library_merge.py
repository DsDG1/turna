"""Tests for the merged prompt library (connectplan P1-3).

Covers the ``kind`` field on course-gen templates, per-language-pair
extraction overrides persisted via ``AiPromptLibrary``, and the bridge
``knowledge_prompt.load_overrides_from``.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.ai_prompt_library import AiPromptLibrary, AiPromptTemplate
from src.backend.knowledge_prompt import (
    KnowledgePromptLibrary,
    KnowledgePromptTemplates,
    build_extraction_messages,
    load_overrides_from,
)
from src.backend.markdown_chopper import split_chapters


def _make_qsettings() -> MagicMock:
    store: dict[str, str] = {}
    qs = MagicMock()
    qs.value = lambda key, default="": store.get(key, default)
    qs.setValue = lambda key, value: store.__setitem__(key, value)
    qs.beginGroup = lambda _name: None
    qs.endGroup = lambda: None
    return qs


class TemplateKindTest(unittest.TestCase):
    def test_kind_defaults_to_course_gen(self) -> None:
        tpl = AiPromptTemplate(name="t")
        self.assertEqual(tpl.kind, "course_gen")

    def test_kind_round_trip(self) -> None:
        tpl = AiPromptTemplate(name="t", kind="extraction")
        restored = AiPromptTemplate.from_dict(tpl.to_dict())
        self.assertEqual(restored.kind, "extraction")

    def test_old_data_without_kind_loads_as_course_gen(self) -> None:
        restored = AiPromptTemplate.from_dict({"name": "legacy", "topic": "x"})
        self.assertEqual(restored.kind, "course_gen")

    def test_list_templates_filters_by_kind(self) -> None:
        lib = AiPromptLibrary(_make_qsettings())
        lib.save_template(AiPromptTemplate(name="a", kind="course_gen"))
        lib.save_template(AiPromptTemplate(name="b", kind="extraction"))
        self.assertEqual(len(lib.list_templates()), 2)
        kinds = [t.name for t in lib.list_templates(kind="course_gen")]
        self.assertEqual(kinds, ["a"])


class ExtractionOverrideStoreTest(unittest.TestCase):
    def setUp(self) -> None:
        self.lib = AiPromptLibrary(_make_qsettings())

    def test_save_and_get(self) -> None:
        self.lib.save_extraction_override(
            "Turkish", "Chinese", {"intro": "自定义引导语"}
        )
        blocks = self.lib.extraction_override("Turkish", "Chinese")
        self.assertEqual(blocks, {"intro": "自定义引导语"})

    def test_language_pair_is_case_insensitive(self) -> None:
        self.lib.save_extraction_override("TURKISH", "Chinese", {"intro": "x"})
        self.assertIsNotNone(self.lib.extraction_override("turkish", "CHINESE"))

    def test_missing_pair_returns_none(self) -> None:
        self.assertIsNone(self.lib.extraction_override("Spanish", "English"))

    def test_delete(self) -> None:
        self.lib.save_extraction_override("Turkish", "Chinese", {"intro": "x"})
        self.assertTrue(self.lib.delete_extraction_override("Turkish", "Chinese"))
        self.assertIsNone(self.lib.extraction_override("Turkish", "Chinese"))
        self.assertFalse(self.lib.delete_extraction_override("Turkish", "Chinese"))

    def test_list_all(self) -> None:
        self.lib.save_extraction_override("Turkish", "Chinese", {"intro": "a"})
        self.lib.save_extraction_override("Spanish", "English", {"intro": "b"})
        overrides = self.lib.list_extraction_overrides()
        self.assertEqual(set(overrides), {"turkish|chinese", "spanish|english"})


class KnowledgeTemplatesDictTest(unittest.TestCase):
    def test_round_trip(self) -> None:
        tpl = KnowledgePromptTemplates(intro="custom intro")
        restored = KnowledgePromptTemplates.from_dict(tpl.to_dict())
        self.assertEqual(restored.intro, "custom intro")
        self.assertEqual(restored.system, tpl.system)

    def test_partial_dict_falls_back_to_defaults(self) -> None:
        restored = KnowledgePromptTemplates.from_dict({"intro": "只给 intro"})
        self.assertEqual(restored.intro, "只给 intro")
        default = KnowledgePromptTemplates()
        self.assertEqual(restored.schema_block, default.schema_block)
        self.assertEqual(restored.system, default.system)


class LoadOverridesFromTest(unittest.TestCase):
    def setUp(self) -> None:
        # Isolate the module-level default library from other tests.
        import src.backend.knowledge_prompt as kp

        self._kp = kp
        self._old = kp.DEFAULT_LIBRARY
        kp.DEFAULT_LIBRARY = KnowledgePromptLibrary()

    def tearDown(self) -> None:
        self._kp.DEFAULT_LIBRARY = self._old

    def _chapter(self):
        return split_chapters("## 1 Merhaba\nhello\n")[0]

    def test_loaded_override_is_used_in_messages(self) -> None:
        lib = AiPromptLibrary(_make_qsettings())
        lib.save_extraction_override("Turkish", "Chinese", {"intro": "覆盖引导语XYZ"})
        count = load_overrides_from(lib)
        self.assertEqual(count, 1)
        messages = build_extraction_messages("Turkish", "Chinese", self._chapter())
        self.assertIn("覆盖引导语XYZ", messages[1]["content"])

    def test_pair_without_override_uses_default(self) -> None:
        lib = AiPromptLibrary(_make_qsettings())
        lib.save_extraction_override("Turkish", "Chinese", {"intro": "覆盖引导语XYZ"})
        load_overrides_from(lib)
        messages = build_extraction_messages("Spanish", "English", self._chapter())
        self.assertNotIn("覆盖引导语XYZ", messages[1]["content"])
        self.assertIn("Extract teachable knowledge points", messages[1]["content"])

    def test_in_memory_register_wins_over_persisted(self) -> None:
        lib = AiPromptLibrary(_make_qsettings())
        lib.save_extraction_override("Turkish", "Chinese", {"intro": "持久化"})
        load_overrides_from(lib)
        self._kp.DEFAULT_LIBRARY.register(
            "Turkish", "Chinese", KnowledgePromptTemplates(intro="内存版")
        )
        messages = build_extraction_messages("Turkish", "Chinese", self._chapter())
        self.assertIn("内存版", messages[1]["content"])

    def test_unregister_persisted_restores_default(self) -> None:
        lib = AiPromptLibrary(_make_qsettings())
        lib.save_extraction_override("Turkish", "Chinese", {"intro": "持久化"})
        load_overrides_from(lib)
        self._kp.DEFAULT_LIBRARY.unregister_persisted("Turkish", "Chinese")
        messages = build_extraction_messages("Turkish", "Chinese", self._chapter())
        self.assertNotIn("持久化", messages[1]["content"])


if __name__ == "__main__":
    unittest.main()
