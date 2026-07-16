"""Tests for SectionImportService (connectplan P1-2).

Uses a real ``CourseAdapter`` (validation + merge planning are pure) and a
real ``QUndoStack``; UI callbacks are recording fakes.
"""
from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from PySide6.QtWidgets import QApplication  # noqa: E402
from PySide6.QtGui import QUndoStack  # noqa: E402

from src.application.section_import_service import SectionImportService  # noqa: E402
from src.backend.course_adapter import CourseAdapter  # noqa: E402
from src.backend.knowledge_schema import coerce_knowledge_points  # noqa: E402
from src.backend.markdown_chopper import split_chapters  # noqa: E402
from src.backend.textbook_to_course import build_section_from_chapter  # noqa: E402


class _App:
    _app = None

    @classmethod
    def get(cls) -> QApplication:
        if cls._app is None:
            cls._app = QApplication.instance() or QApplication([])
        return cls._app


def _section(suffix: str = "1") -> dict:
    chapter = split_chapters("## 1 Merhaba\nhello\n")[0]
    kp = coerce_knowledge_points(
        {"words": [{"term": "merhaba", "translation": "hello"}]}
    )
    section = build_section_from_chapter(chapter, kp, 1)
    section["id"] = f"sec-{suffix}"
    return section


class SectionImportServiceTest(unittest.TestCase):
    def setUp(self) -> None:
        _App.get()
        self.adapter = CourseAdapter()
        self.undo_stack = QUndoStack()
        self.errors: list[tuple[str, str]] = []
        self.infos: list[tuple[str, str]] = []
        self.pushed: list[str] = []
        self.statuses: list[str] = []
        self.merge_resolver = MagicMock(side_effect=lambda plan: plan)
        self.bulk_resolver = MagicMock(
            side_effect=lambda plans: list(plans)
        )
        self.service = SectionImportService(
            self.adapter,
            self.undo_stack,
            show_error=lambda t, m: self.errors.append((t, m)),
            show_info=lambda t, m: self.infos.append((t, m)),
            merge_resolver=self.merge_resolver,
            bulk_merge_resolver=self.bulk_resolver,
            on_command_pushed=lambda _cmd, sid: self.pushed.append(sid),
            on_status=self.statuses.append,
        )

    def test_append_new_section(self) -> None:
        result = self.service.import_section(_section("a"))
        self.assertEqual(result.details["outcome"], "imported")
        self.assertEqual(result.details["section_id"], "sec-a")
        self.assertEqual(len(self.adapter.sections), 1)
        self.assertEqual(self.pushed, ["sec-a"])
        self.assertEqual(self.undo_stack.count(), 1)

    def test_missing_id_blocked_with_error(self) -> None:
        result = self.service.import_section({"name": "no id"})
        self.assertEqual(result.details["outcome"], "blocked")
        self.assertEqual(len(self.errors), 1)

    def test_validation_error_blocked(self) -> None:
        bad = _section("bad")
        del bad["units"]
        result = self.service.import_section(bad)
        self.assertEqual(result.details["outcome"], "blocked")
        self.assertTrue(self.errors)

    def test_skip_existing(self) -> None:
        self.adapter.sections.append(_section("x"))
        result = self.service.import_section(
            _section("x"), strategy="skip_existing"
        )
        self.assertEqual(result.details["outcome"], "skipped")
        self.assertEqual(self.undo_stack.count(), 0)

    def test_force_replace(self) -> None:
        self.adapter.sections.append(_section("x"))
        result = self.service.import_section(
            _section("x"), strategy="force_replace"
        )
        self.assertEqual(result.details["outcome"], "replaced")
        self.assertEqual(self.pushed, ["sec-x"])

    def test_append_as_new_rewrites_id(self) -> None:
        self.adapter.sections.append(_section("x"))
        self.adapter.index = {"sections": [{"id": "sec-x"}]}
        result = self.service.import_section(
            _section("x"), strategy="append_as_new"
        )
        self.assertEqual(result.details["outcome"], "imported")
        self.assertEqual(result.details["section_id"], "sec-x-2")

    def test_merge_approved_by_resolver(self) -> None:
        self.adapter.sections.append(_section("x"))
        result = self.service.import_section(_section("x"), strategy="merge")
        self.assertEqual(result.details["outcome"], "merged")
        self.merge_resolver.assert_called_once()

    def test_merge_cancelled_by_resolver(self) -> None:
        self.adapter.sections.append(_section("x"))
        self.merge_resolver.side_effect = lambda _plan: None
        result = self.service.import_section(_section("x"), strategy="merge")
        self.assertEqual(result.details["outcome"], "skipped")

    def test_merge_without_resolver_skips(self) -> None:
        service = SectionImportService(self.adapter, self.undo_stack)
        self.adapter.sections.append(_section("x"))
        result = service.import_section(_section("x"), strategy="merge")
        self.assertEqual(result.details["outcome"], "skipped")
        self.assertIn("合并决策器", result.message)


class BulkImportTest(unittest.TestCase):
    def setUp(self) -> None:
        _App.get()
        self.adapter = CourseAdapter()
        self.undo_stack = QUndoStack()
        self.merge_resolver = MagicMock(side_effect=lambda plan: plan)
        self.bulk_resolver = MagicMock(side_effect=lambda plans: list(plans))
        self.service = SectionImportService(
            self.adapter,
            self.undo_stack,
            merge_resolver=self.merge_resolver,
            bulk_merge_resolver=self.bulk_resolver,
        )

    def test_bulk_counts_and_source_id(self) -> None:
        results, counts = self.service.import_bulk(
            [_section("a"), _section("b")], strategy="merge"
        )
        self.assertEqual(counts["imported"], 2)
        self.assertEqual(counts["merged"], 0)
        self.assertEqual(results[0].details["source_id"], "sec-a")
        self.bulk_resolver.assert_not_called()

    def test_bulk_resolver_called_once_for_multiple_collisions(self) -> None:
        self.adapter.sections.append(_section("a"))
        self.adapter.sections.append(_section("b"))
        results, counts = self.service.import_bulk(
            [_section("a"), _section("b")], strategy="merge"
        )
        self.bulk_resolver.assert_called_once()
        plans_arg = self.bulk_resolver.call_args.args[0]
        self.assertEqual(len(plans_arg), 2)
        self.assertEqual(counts["merged"], 2)
        self.merge_resolver.assert_not_called()

    def test_bulk_resolver_cancel_skips_all_merges(self) -> None:
        self.adapter.sections.append(_section("a"))
        self.adapter.sections.append(_section("b"))
        self.bulk_resolver.side_effect = lambda _plans: None
        _results, counts = self.service.import_bulk(
            [_section("a"), _section("b")], strategy="merge"
        )
        self.assertEqual(counts["skipped"], 2)
        self.assertEqual(counts["merged"], 0)

    def test_single_collision_falls_back_to_per_section_resolver(self) -> None:
        self.adapter.sections.append(_section("a"))
        _results, counts = self.service.import_bulk(
            [_section("a"), _section("new")], strategy="merge"
        )
        self.bulk_resolver.assert_not_called()
        self.merge_resolver.assert_called_once()
        self.assertEqual(counts["merged"], 1)
        self.assertEqual(counts["imported"], 1)

    def test_bulk_append_as_new_uses_planned_ids(self) -> None:
        self.adapter.sections.append(_section("a"))
        self.adapter.index = {"sections": [{"id": "sec-a"}]}
        results, counts = self.service.import_bulk(
            [_section("a")], strategy="append_as_new"
        )
        self.assertEqual(counts["imported"], 1)
        self.assertEqual(results[0].details["section_id"], "sec-a-2")
        self.assertEqual(results[0].details["source_id"], "sec-a")

    def test_telemetry_emitted_per_outcome(self) -> None:
        with unittest.mock.patch(
            "src.application.section_import_service.telemetry"
        ) as mock_tel:
            self.service.import_bulk([_section("a")], strategy="merge")
            events = [c.args[0] for c in mock_tel.record_event.call_args_list]
            self.assertIn("textbook.import.imported", events)


if __name__ == "__main__":
    unittest.main()
