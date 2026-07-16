"""Tests for TextbookProject model and TextbookProjectStore."""
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.knowledge_schema import KnowledgePoints, coerce_knowledge_points
from src.backend.markdown_chopper import Chapter, split_chapters
from src.backend.textbook_project import TextbookProject
from src.backend.textbook_project_store import (
    TextbookProjectStore,
    record_imported_sections,
)


def _sample_md() -> str:
    return "## 1 Merhaba\nhello\n## 2 Aile\nfamily\n"


def _sample_kp() -> KnowledgePoints:
    return coerce_knowledge_points(
        {
            "words": [{"term": "merhaba", "translation": "hello"}],
            "expressions": [{"term": "Selam!", "translation": "Hi!"}],
            "grammarPoints": [{"title": "Greetings", "explanation": "hi"}],
        }
    )


class TextbookProjectModelTest(unittest.TestCase):
    def test_round_trip_dict(self) -> None:
        project = TextbookProject.create(
            project_id="p1",
            name="Turkish Reader",
            source_path=Path("/tmp/book.md"),
            markdown=_sample_md(),
        )
        ch = split_chapters(_sample_md())
        project.set_chapters(
            [(ch[0], True, _sample_kp(), ""), (ch[1], False, None, "")]
        )
        project.current_step = 4

        data = project.to_dict()
        restored = TextbookProject.from_dict(data)
        self.assertEqual(restored.project_id, "p1")
        self.assertEqual(restored.name, "Turkish Reader")
        self.assertEqual(restored.current_step, 4)
        chapters = restored.get_chapters()
        self.assertEqual(len(chapters), 2)
        self.assertEqual(chapters[0][0].title, "1 Merhaba")
        self.assertTrue(chapters[0][1])
        self.assertIsNotNone(chapters[0][2])
        self.assertEqual(chapters[0][2].words[0]["term"], "merhaba")

    def test_source_changed_detects_modification(self) -> None:
        with tempfile.NamedTemporaryFile(mode="w", suffix=".md", delete=False) as f:
            f.write("hello")
            path = Path(f.name)
        try:
            project = TextbookProject.create(
                project_id="p2", name="x", source_path=path
            )
            self.assertFalse(project.source_changed())
            path.write_text("world")
            self.assertTrue(project.source_changed())
        finally:
            path.unlink()

    def test_merge_from_preserves_identity(self) -> None:
        a = TextbookProject.create(project_id="p3", name="A", source_path=None)
        a.imported_section_ids = ["s1"]
        b = TextbookProject.create(project_id="p4", name="B", source_path=None)
        b.name = "B2"
        b.current_step = 5
        a.merge_from(b)
        self.assertEqual(a.project_id, "p3")
        self.assertEqual(a.name, "B2")
        self.assertEqual(a.current_step, 5)
        self.assertEqual(a.imported_section_ids, ["s1"])


class TextbookProjectStoreTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.store = TextbookProjectStore(base_dir=Path(self.tmp.name))

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def test_create_and_load(self) -> None:
        project = self.store.create_project(name="Test", source_path=None)
        loaded = self.store.load_project(project.project_id)
        self.assertIsNotNone(loaded)
        self.assertEqual(loaded.name, "Test")

    def test_list_sorted_by_updated(self) -> None:
        p1 = self.store.create_project(name="First", source_path=None)
        p2 = self.store.create_project(name="Second", source_path=None)
        projects = self.store.list_projects()
        self.assertEqual([p.name for p in projects], ["Second", "First"])

    def test_delete_removes_project(self) -> None:
        project = self.store.create_project(name="ToDelete", source_path=None)
        self.assertTrue(self.store.delete_project(project.project_id))
        self.assertIsNone(self.store.load_project(project.project_id))
        self.assertFalse(self.store.delete_project(project.project_id))

    def test_save_preserves_chapters(self) -> None:
        project = self.store.create_project(name="Chapters", source_path=None)
        ch = split_chapters(_sample_md())
        project.set_chapters([(ch[0], True, _sample_kp(), "")])
        self.store.save_project(project)
        loaded = self.store.load_project(project.project_id)
        self.assertEqual(len(loaded.get_chapters()), 1)


class RecordImportedSectionsTest(unittest.TestCase):
    """connectplan P0-2: real writeback of imported_section_ids."""

    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.store = TextbookProjectStore(base_dir=Path(self.tmp.name))

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def test_records_ids_and_marks_fully_imported(self) -> None:
        project = self.store.create_project(name="Book", source_path=None)
        added = record_imported_sections(project, ["ch-a-1", "ch-b-2"], store=self.store)
        self.assertEqual(added, ["ch-a-1", "ch-b-2"])
        self.assertTrue(project.is_fully_imported)
        loaded = self.store.load_project(project.project_id)
        self.assertEqual(loaded.imported_section_ids, ["ch-a-1", "ch-b-2"])
        self.assertEqual(loaded.current_step, 5)
        self.assertTrue(loaded.is_fully_imported)

    def test_dedupes_already_known_ids(self) -> None:
        project = self.store.create_project(name="Book", source_path=None)
        record_imported_sections(project, ["ch-a-1"], store=self.store)
        added = record_imported_sections(
            project, ["ch-a-1", "ch-c-3"], store=self.store
        )
        self.assertEqual(added, ["ch-c-3"])
        self.assertEqual(project.imported_section_ids, ["ch-a-1", "ch-c-3"])

    def test_empty_input_is_noop(self) -> None:
        project = self.store.create_project(name="Book", source_path=None)
        added = record_imported_sections(project, [], store=self.store)
        self.assertEqual(added, [])
        self.assertFalse(project.is_fully_imported)

    def test_step_never_regresses(self) -> None:
        project = self.store.create_project(name="Book", source_path=None)
        project.current_step = 99  # hypothetical future step
        record_imported_sections(project, ["s1"], store=self.store)
        self.assertEqual(project.current_step, 99)


if __name__ == "__main__":
    unittest.main()
