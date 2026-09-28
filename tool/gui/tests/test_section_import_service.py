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
from tests._course_samples import sample_section_from_chapter

from PySide6.QtGui import QUndoStack

from src.application.section_import_service import SectionImportService
from src.backend.course_adapter import CourseAdapter
from tests._qtapp import _App


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
        result = self.service.import_section(sample_section_from_chapter("sec-a"))
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
        bad = sample_section_from_chapter("sec-bad")
        del bad["units"]
        result = self.service.import_section(bad)
        self.assertEqual(result.details["outcome"], "blocked")
        self.assertTrue(self.errors)

    def test_skip_existing(self) -> None:
        self.adapter.sections.append(sample_section_from_chapter("sec-x"))
        result = self.service.import_section(
            sample_section_from_chapter("sec-x"), strategy="skip_existing"
        )
        self.assertEqual(result.details["outcome"], "skipped")
        self.assertEqual(self.undo_stack.count(), 0)

    def test_force_replace(self) -> None:
        self.adapter.sections.append(sample_section_from_chapter("sec-x"))
        result = self.service.import_section(
            sample_section_from_chapter("sec-x"), strategy="force_replace"
        )
        self.assertEqual(result.details["outcome"], "replaced")
        self.assertEqual(self.pushed, ["sec-x"])

    def test_append_as_new_rewrites_id(self) -> None:
        self.adapter.sections.append(sample_section_from_chapter("sec-x"))
        self.adapter.index = {"sections": [{"id": "sec-x"}]}
        result = self.service.import_section(
            sample_section_from_chapter("sec-x"), strategy="append_as_new"
        )
        self.assertEqual(result.details["outcome"], "imported")
        self.assertEqual(result.details["section_id"], "sec-x-2")

    def test_append_as_new_rewrites_nested_ids(self) -> None:
        # Nested unit/lesson ids derive from the section id; without rewriting
        # they collide with the original section and the course cannot save.
        original = sample_section_from_chapter("sec-x")
        self.adapter.sections.append(original)
        self.adapter.index = {"sections": [{"id": "sec-x"}]}
        draft = sample_section_from_chapter("sec-x")
        draft_unit_ids = [u["id"] for u in draft["units"]]
        result = self.service.import_section(draft, strategy="append_as_new")
        self.assertEqual(result.details["outcome"], "imported")
        new_section = self.adapter.sections[-1]
        old_unit_ids = {u["id"] for u in original["units"]}
        old_lesson_ids = {
            lesson["id"] for u in original["units"] for lesson in u.get("lessons", [])
        }
        for unit in new_section["units"]:
            self.assertNotIn(unit["id"], old_unit_ids)
            self.assertTrue(unit["id"].startswith("sec-x-2-"))
            for lesson in unit.get("lessons", []):
                self.assertNotIn(lesson["id"], old_lesson_ids)
                self.assertTrue(lesson["id"].startswith(unit["id"] + "-"))
        # The caller's draft must not be mutated in place.
        self.assertEqual([u["id"] for u in draft["units"]], draft_unit_ids)

    def test_merge_approved_by_resolver(self) -> None:
        self.adapter.sections.append(sample_section_from_chapter("sec-x"))
        result = self.service.import_section(sample_section_from_chapter("sec-x"), strategy="merge")
        self.assertEqual(result.details["outcome"], "merged")
        self.merge_resolver.assert_called_once()

    def test_merge_cancelled_by_resolver(self) -> None:
        self.adapter.sections.append(sample_section_from_chapter("sec-x"))
        self.merge_resolver.side_effect = lambda _plan: None
        result = self.service.import_section(sample_section_from_chapter("sec-x"), strategy="merge")
        self.assertEqual(result.details["outcome"], "skipped")

    def test_merge_without_resolver_skips(self) -> None:
        service = SectionImportService(self.adapter, self.undo_stack)
        self.adapter.sections.append(sample_section_from_chapter("sec-x"))
        result = service.import_section(sample_section_from_chapter("sec-x"), strategy="merge")
        self.assertEqual(result.details["outcome"], "skipped")
        self.assertIn("合并决策器", result.message)


class BulkUndoCompositeTest(unittest.TestCase):
    """T9: a batch import is ONE undo entry, and a mid-batch failure rolls
    the whole batch back instead of leaving half of it applied."""

    def setUp(self) -> None:
        _App.get()
        self.adapter = CourseAdapter()
        self.undo_stack = QUndoStack()
        self.statuses: list[str] = []
        self.service = SectionImportService(
            self.adapter,
            self.undo_stack,
            merge_resolver=MagicMock(side_effect=lambda plan: plan),
            bulk_merge_resolver=MagicMock(side_effect=lambda plans: list(plans)),
            on_status=self.statuses.append,
        )

    def _sections(self, *ids: str) -> list[dict]:
        return [sample_section_from_chapter(i) for i in ids]

    def test_bulk_import_pushes_exactly_one_undo_entry(self) -> None:
        _results, counts = self.service.import_bulk(
            self._sections("sec-a", "sec-b", "sec-c"), strategy="merge"
        )
        self.assertEqual(counts["imported"], 3)
        # Before T9 this was 3 — Ctrl+Z peeled one section at a time.
        self.assertEqual(self.undo_stack.count(), 1)
        # The composite skips its first redo (children ran while building),
        # so the sections must be present exactly once.
        self.assertEqual(len(self.adapter.sections), 3)
        self.assertEqual(
            [s["id"] for s in self.adapter.sections], ["sec-a", "sec-b", "sec-c"]
        )

    def test_one_undo_removes_the_whole_batch_and_redo_restores_it(self) -> None:
        self.service.import_bulk(self._sections("sec-a", "sec-b"), strategy="merge")
        self.undo_stack.undo()
        self.assertEqual(len(self.adapter.sections), 0)
        self.undo_stack.redo()
        self.assertEqual(
            sorted(s["id"] for s in self.adapter.sections), ["sec-a", "sec-b"]
        )
        self.assertEqual(self.undo_stack.count(), 1)  # still one entry

    def test_single_section_batch_still_lands_one_entry(self) -> None:
        # A one-section batch has nothing to composite; it must still push
        # exactly one undo entry (the pre-T9 contract).
        _results, counts = self.service.import_bulk(
            self._sections("sec-only"), strategy="merge"
        )
        self.assertEqual(counts["imported"], 1)
        self.assertEqual(self.undo_stack.count(), 1)
        self.undo_stack.undo()
        self.assertEqual(len(self.adapter.sections), 0)

    def test_batch_progress_is_reported_per_section(self) -> None:
        self.service.import_bulk(
            self._sections("sec-a", "sec-b", "sec-c"), strategy="merge"
        )
        progress = [s for s in self.statuses if "导入中" in s]
        self.assertEqual(len(progress), 3)
        self.assertIn("(1/3)", progress[0])
        self.assertIn("(3/3)", progress[-1])

    def test_mid_batch_failure_rolls_everything_back(self) -> None:
        real = self.service.import_section
        seen = {"n": 0}

        def flaky(*args, **kwargs):
            seen["n"] += 1
            if seen["n"] == 2:
                raise RuntimeError("boom")
            return real(*args, **kwargs)

        self.service.import_section = flaky
        results, counts = self.service.import_bulk(
            self._sections("sec-a", "sec-b", "sec-c"), strategy="merge"
        )

        # Nothing half-applied, nothing on the undo stack.
        self.assertEqual(len(self.adapter.sections), 0)
        self.assertEqual(self.undo_stack.count(), 0)
        # Counts must stop claiming the earlier section was imported.
        self.assertEqual(counts["imported"], 0)
        self.assertEqual(counts["blocked"], 2)  # sec-a rolled back + sec-b failed
        self.assertEqual(counts["cancelled"], 1)  # sec-c never attempted
        self.assertTrue(all(r.outcome == "error" for r in results[:2]))
        self.assertTrue((results[0].details or {}).get("rolled_back"))
        self.assertTrue(any("已整体回滚" in s for s in self.statuses))


class RollbackAfterPartialApplyTest(unittest.TestCase):
    """T9 hardening: a redo that raises part-way must not orphan the section.

    ``ImportAiSectionCommand.redo`` appends the section before it merges the
    section's resources, so a failure in the merge leaves the section in the
    adapter. If the command was only registered with the batch's collector
    *after* a successful redo, the rollback loop would never see it: the
    course keeps a section the undo stack does not know about, while the UI
    reports 「已整体回滚」.
    """

    def setUp(self) -> None:
        _App.get()
        self.adapter = CourseAdapter()
        self.undo_stack = QUndoStack()
        self.statuses: list[str] = []
        self.service = SectionImportService(
            self.adapter,
            self.undo_stack,
            merge_resolver=MagicMock(side_effect=lambda plan: plan),
            bulk_merge_resolver=MagicMock(side_effect=lambda plans: list(plans)),
            on_status=self.statuses.append,
        )

    def _section(self, section_id: str) -> dict:
        return sample_section_from_chapter(section_id)

    def test_section_is_not_left_behind_when_the_merge_fails(self) -> None:
        real_merge = self.adapter.merge_section_resources
        seen = {"n": 0}

        def flaky(section_json):
            seen["n"] += 1
            if seen["n"] == 2:
                raise RuntimeError("disk error while merging resources")
            return real_merge(section_json)

        self.adapter.merge_section_resources = flaky  # type: ignore[method-assign]
        _results, counts = self.service.import_bulk(
            [self._section("sec-a"), self._section("sec-b"), self._section("sec-c")],
            strategy="merge",
        )

        self.assertEqual(
            [s.get("id") for s in self.adapter.sections],
            [],
            "a partially-applied section was left in the course",
        )
        self.assertEqual(self.undo_stack.count(), 0)
        self.assertEqual(counts["imported"], 0)
        self.assertTrue(any("已整体回滚" in s for s in self.statuses))

    def test_orphan_is_absent_even_when_the_first_section_fails(self) -> None:
        """The single-section path cannot collect, so the failure is handled
        where push() is called.

        ``QUndoStack.push`` registers the command *before* calling redo() and
        does not remove it when redo raises, so one inert entry remains on the
        stack. The property that matters is that it does nothing: the section
        must not come back on a later undo or redo.
        """
        vocab_before = len(self.adapter.vocab)

        def always_fail(_section_json):
            raise RuntimeError("merge unavailable")

        self.adapter.merge_section_resources = always_fail  # type: ignore[method-assign]
        self.service.import_bulk([self._section("sec-a")], strategy="merge")

        self.assertEqual(self.adapter.sections, [])
        self.assertEqual(len(self.adapter.vocab), vocab_before)
        self.assertEqual(self.undo_stack.index(), 1)  # the inert leftover entry

        # Ctrl+Z then Ctrl+Y must be no-ops for a failed import.
        self.undo_stack.undo()
        self.assertEqual(self.adapter.sections, [])
        self.undo_stack.redo()
        self.assertEqual(
            self.adapter.sections,
            [],
            "Ctrl+Y resurrected an import that was reported as failed",
        )
        self.assertEqual(len(self.adapter.vocab), vocab_before)

    def test_composite_path_leaves_nothing_on_the_stack(self) -> None:
        # With a collector the command never reaches push(), so the batch
        # rolls back cleanly and the stack is untouched.
        def always_fail(_section_json):
            raise RuntimeError("merge unavailable")

        self.adapter.merge_section_resources = always_fail  # type: ignore[method-assign]
        self.service.import_bulk(
            [self._section("sec-a"), self._section("sec-b")], strategy="merge"
        )
        self.assertEqual(self.adapter.sections, [])
        self.assertEqual(self.undo_stack.count(), 0)

    def test_resources_partially_merged_by_a_failing_command_are_rolled_back(self) -> None:
        # The merge adds a word and *then* raises: the word must not survive,
        # which requires the added-id snapshot to be recorded in a finally.
        before = len(self.adapter.vocab)
        real_merge = self.adapter.merge_section_resources
        seen = {"n": 0}

        def flaky(section_json):
            seen["n"] += 1
            real_merge(section_json)
            if seen["n"] == 2:
                raise RuntimeError("crash after writing resources")

        self.adapter.merge_section_resources = flaky  # type: ignore[method-assign]
        self.service.import_bulk(
            [self._section("sec-a"), self._section("sec-b"), self._section("sec-c")],
            strategy="merge",
        )
        self.assertEqual(len(self.adapter.vocab), before)
        self.assertEqual(self.adapter.sections, [])

    def test_a_successful_batch_is_unaffected_by_the_hardening(self) -> None:
        _results, counts = self.service.import_bulk(
            [self._section("sec-a"), self._section("sec-b")], strategy="merge"
        )
        self.assertEqual(counts["imported"], 2)
        self.assertEqual(self.undo_stack.count(), 1)
        self.assertEqual(
            sorted(s["id"] for s in self.adapter.sections), ["sec-a", "sec-b"]
        )
        self.undo_stack.undo()
        self.assertEqual(self.adapter.sections, [])


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
            [sample_section_from_chapter("sec-a"), sample_section_from_chapter("sec-b")], strategy="merge"
        )
        self.assertEqual(counts["imported"], 2)
        self.assertEqual(counts["merged"], 0)
        self.assertEqual(results[0].details["source_id"], "sec-a")
        self.bulk_resolver.assert_not_called()

    def test_bulk_resolver_called_once_for_multiple_collisions(self) -> None:
        self.adapter.sections.append(sample_section_from_chapter("sec-a"))
        self.adapter.sections.append(sample_section_from_chapter("sec-b"))
        _results, counts = self.service.import_bulk(
            [sample_section_from_chapter("sec-a"), sample_section_from_chapter("sec-b")], strategy="merge"
        )
        self.bulk_resolver.assert_called_once()
        plans_arg = self.bulk_resolver.call_args.args[0]
        self.assertEqual(len(plans_arg), 2)
        self.assertEqual(counts["merged"], 2)
        self.merge_resolver.assert_not_called()

    def test_bulk_resolver_cancel_aborts_entire_import(self) -> None:
        """#10: whole-batch cancel aborts EVERYTHING — never a partial import.

        The old behavior skipped only the collisions and still imported the
        non-conflicting sections, then announced 导入完成.
        """
        self.adapter.sections.append(sample_section_from_chapter("sec-a"))
        self.adapter.sections.append(sample_section_from_chapter("sec-b"))
        self.bulk_resolver.side_effect = lambda _plans: None
        results, counts = self.service.import_bulk(
            [
                sample_section_from_chapter("sec-a"),
                sample_section_from_chapter("sec-b"),
                sample_section_from_chapter("sec-new"),  # no collision
            ],
            strategy="merge",
        )
        self.assertEqual(counts["cancelled"], 3)
        self.assertEqual(counts["skipped"], 0)
        self.assertEqual(counts["imported"], 0)
        self.assertEqual(self.undo_stack.count(), 0)  # nothing pushed
        self.assertTrue(all(r.outcome == "cancelled" for r in results))

    def test_single_conflict_cancel_continues_after_confirm(self) -> None:
        self.adapter.sections.append(sample_section_from_chapter("sec-a"))
        self.merge_resolver.side_effect = lambda _plan: None  # user cancels
        confirm = MagicMock(return_value=True)
        service = SectionImportService(
            self.adapter,
            self.undo_stack,
            merge_resolver=self.merge_resolver,
            confirm_continue=confirm,
        )
        _results, counts = service.import_bulk(
            [sample_section_from_chapter("sec-a"), sample_section_from_chapter("sec-new")],
            strategy="merge",
        )
        confirm.assert_called_once_with(1)
        self.assertEqual(counts["skipped"], 1)
        self.assertEqual(counts["imported"], 1)
        self.assertEqual(counts["cancelled"], 0)
        self.assertEqual(self.undo_stack.count(), 1)

    def test_single_conflict_cancel_aborts_remaining_by_default(self) -> None:
        self.adapter.sections.append(sample_section_from_chapter("sec-a"))
        self.merge_resolver.side_effect = lambda _plan: None  # user cancels
        confirm = MagicMock(return_value=False)  # safe_question default: No
        service = SectionImportService(
            self.adapter,
            self.undo_stack,
            merge_resolver=self.merge_resolver,
            confirm_continue=confirm,
        )
        results, counts = service.import_bulk(
            [
                sample_section_from_chapter("sec-a"),
                sample_section_from_chapter("sec-new"),
                sample_section_from_chapter("sec-other"),
            ],
            strategy="merge",
        )
        self.assertEqual(counts["skipped"], 1)
        self.assertEqual(counts["cancelled"], 2)
        self.assertEqual(counts["imported"], 0)
        self.assertEqual(self.undo_stack.count(), 0)
        self.assertTrue(results[1].outcome == "cancelled")
        self.assertTrue(results[2].outcome == "cancelled")

    def test_single_collision_falls_back_to_per_section_resolver(self) -> None:
        self.adapter.sections.append(sample_section_from_chapter("sec-a"))
        _results, counts = self.service.import_bulk(
            [sample_section_from_chapter("sec-a"), sample_section_from_chapter("sec-new")], strategy="merge"
        )
        self.bulk_resolver.assert_not_called()
        self.merge_resolver.assert_called_once()
        self.assertEqual(counts["merged"], 1)
        self.assertEqual(counts["imported"], 1)

    def test_bulk_append_as_new_uses_planned_ids(self) -> None:
        self.adapter.sections.append(sample_section_from_chapter("sec-a"))
        self.adapter.index = {"sections": [{"id": "sec-a"}]}
        results, counts = self.service.import_bulk(
            [sample_section_from_chapter("sec-a")], strategy="append_as_new"
        )
        self.assertEqual(counts["imported"], 1)
        self.assertEqual(results[0].details["section_id"], "sec-a-2")
        self.assertEqual(results[0].details["source_id"], "sec-a")

    def test_telemetry_emitted_per_outcome(self) -> None:
        with unittest.mock.patch(
            "src.application.section_import_service.telemetry"
        ) as mock_tel:
            self.service.import_bulk([sample_section_from_chapter("sec-a")], strategy="merge")
            events = [c.args[0] for c in mock_tel.record_event.call_args_list]
            self.assertIn("textbook.import.imported", events)


if __name__ == "__main__":
    unittest.main()
