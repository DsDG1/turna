"""Tests for AuthoringProject v2: model fields, v1→v2 migration, import_map.

connectplan P1-1. Covers the on-disk migration in
``TextbookProjectStore.load_project`` and the resource_pool snapshot written
by the controller's ``to_project``.
"""
from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.ai_generator import AiApiConfig  # noqa: E402
from src.backend.knowledge_schema import coerce_knowledge_points  # noqa: E402
from src.backend.textbook_project import TextbookProject  # noqa: E402
from src.backend.textbook_project_store import (  # noqa: E402
    TextbookProjectStore,
    record_imported_sections,
)
from src.dialogs.textbook_import_controller import TextbookImportController  # noqa: E402


def _v1_dict() -> dict:
    """A minimal project.json as written by the v1 format."""
    return {
        "version": 1,
        "project_id": "legacy_book",
        "name": "Legacy Book",
        "created_at": "2026-01-01T00:00:00+00:00",
        "updated_at": "2026-01-01T00:00:00+00:00",
        "current_step": 4,
        "source_path": "/tmp/legacy.md",
        "source_checksum": None,
        "markdown": "## 1 Merhaba\nhello\n",
        "language": "Turkish",
        "source_language": "Chinese",
        "chapters": [],
        "imported_section_ids": [],
    }


class V1ToV2MigrationTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.store = TextbookProjectStore(base_dir=Path(self.tmp.name))
        project_dir = self.store.project_dir("legacy_book")
        project_dir.mkdir(parents=True)
        (project_dir / "project.json").write_text(
            json.dumps(_v1_dict(), ensure_ascii=False), encoding="utf-8"
        )

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def test_v1_loads_with_defaults_and_backs_up(self) -> None:
        project = self.store.load_project("legacy_book")
        self.assertIsNotNone(project)
        self.assertEqual(project.version, 2)
        self.assertEqual(project.resource_pool["words"], [])
        self.assertEqual(project.design["draft_sections"], [])
        self.assertEqual(project.import_map, {})
        backup = self.store.project_dir("legacy_book") / "project.v1.json.bak"
        self.assertTrue(backup.exists())
        backed_up = json.loads(backup.read_text(encoding="utf-8"))
        self.assertEqual(backed_up["version"], 1)

    def test_migrated_file_is_v2_on_disk(self) -> None:
        self.store.load_project("legacy_book")
        on_disk = json.loads(
            self.store.project_file("legacy_book").read_text(encoding="utf-8")
        )
        self.assertEqual(on_disk["version"], 2)
        self.assertIn("resource_pool", on_disk)
        self.assertIn("design", on_disk)
        self.assertIn("import_map", on_disk)

    def test_migration_is_idempotent(self) -> None:
        self.store.load_project("legacy_book")
        backup = self.store.project_dir("legacy_book") / "project.v1.json.bak"
        mtime = backup.stat().st_mtime
        project = self.store.load_project("legacy_book")
        self.assertEqual(project.version, 2)
        self.assertEqual(backup.stat().st_mtime, mtime)  # not rewritten

    def test_v2_round_trip(self) -> None:
        project = TextbookProject.create(
            project_id="p9", name="N", source_path=None
        )
        project.resource_pool = {
            "words": [{"id": "w1", "term": "merhaba"}],
            "expressions": [],
            "grammarPoints": [],
            "updated_at": "2026-07-16T00:00:00+00:00",
        }
        project.design = {
            "chat_history": [{"role": "user", "content": "hi"}],
            "params": {"units": 2},
            "draft_sections": [{"id": "sec-1"}],
            "explanation": "exp",
        }
        project.import_map = {"ch-a-1": "ch-a-1-2"}
        restored = TextbookProject.from_dict(project.to_dict())
        self.assertEqual(restored.version, 2)
        self.assertEqual(restored.resource_pool["words"][0]["id"], "w1")
        self.assertEqual(restored.design["params"]["units"], 2)
        self.assertEqual(restored.design["draft_sections"][0]["id"], "sec-1")
        self.assertEqual(restored.import_map, {"ch-a-1": "ch-a-1-2"})

    def test_merge_from_preserves_design_and_import_map(self) -> None:
        a = TextbookProject.create(project_id="p10", name="A", source_path=None)
        a.imported_section_ids = ["s1"]
        a.design = {"chat_history": [], "params": {"x": 1},
                    "draft_sections": [], "explanation": ""}
        a.import_map = {"ch-a-1": "ch-a-1"}
        b = TextbookProject.create(project_id="p11", name="B", source_path=None)
        b.resource_pool = {"words": [{"id": "w1"}], "expressions": [],
                           "grammarPoints": [], "updated_at": "t"}
        a.merge_from(b)
        self.assertEqual(a.imported_section_ids, ["s1"])
        self.assertEqual(a.design["params"], {"x": 1})
        self.assertEqual(a.import_map, {"ch-a-1": "ch-a-1"})
        # resource_pool follows chapters-derived state → copied.
        self.assertEqual(a.resource_pool["words"][0]["id"], "w1")


class ResourcePoolSnapshotTest(unittest.TestCase):
    def test_to_project_writes_resource_pool(self) -> None:
        ctrl = TextbookImportController(
            ai_config_fn=lambda: AiApiConfig(
                base_url="http://localhost", api_key="k", model="m"
            )
        )
        ctrl._md = "## 1 Merhaba\nhello\n## 2 Aile\nfamily\n"
        ctrl._split_into_chapters()
        kp = coerce_knowledge_points(
            {"words": [{"term": "merhaba", "translation": "hello"}]}
        )
        ctrl._chapters[0].knowledge = kp
        ctrl._chapters[1].knowledge = kp
        ctrl._chapters[1].keep = False  # excluded from the pool
        project = ctrl.to_project("Book")
        self.assertEqual(len(project.resource_pool["words"]), 1)
        self.assertEqual(project.resource_pool["words"][0]["term"], "merhaba")
        self.assertTrue(project.resource_pool["updated_at"])

    def test_empty_extraction_keeps_previous_pool(self) -> None:
        project = TextbookProject.create(project_id="p12", name="N", source_path=None)
        project.resource_pool = {"words": [{"id": "w-old"}], "expressions": [],
                                 "grammarPoints": [], "updated_at": "t"}
        project.update_resource_pool()  # no chapters → no-op
        self.assertEqual(project.resource_pool["words"][0]["id"], "w-old")


class ImportMapTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.store = TextbookProjectStore(base_dir=Path(self.tmp.name))

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def test_id_pairs_written_to_import_map(self) -> None:
        project = self.store.create_project(name="Book", source_path=None)
        record_imported_sections(
            project,
            ["ch-a-1-2"],
            store=self.store,
            id_pairs=[("ch-a-1", "ch-a-1-2")],
        )
        self.assertEqual(project.import_map, {"ch-a-1": "ch-a-1-2"})
        loaded = self.store.load_project(project.project_id)
        self.assertEqual(loaded.import_map, {"ch-a-1": "ch-a-1-2"})

    def test_old_signature_still_works(self) -> None:
        project = self.store.create_project(name="Book", source_path=None)
        added = record_imported_sections(project, ["s1"], store=self.store)
        self.assertEqual(added, ["s1"])
        self.assertEqual(project.import_map, {})


if __name__ == "__main__":
    unittest.main()
