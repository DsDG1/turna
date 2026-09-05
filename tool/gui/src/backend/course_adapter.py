"""Adapter bridging the GUI to the stable backend API.

The GUI no longer imports ``course_cli`` directly; all loading, saving,
validating and linting goes through ``src.backend.api``. JSON remains the
single source of truth; this adapter only holds an in-memory working copy.
"""
from __future__ import annotations

import logging
import time
from pathlib import Path
from typing import Any

logger = logging.getLogger(__name__)

from src.backend import api
from src.infrastructure.telemetry import telemetry

# Kept for backwards compatibility with git_library.py.
_REPO_ROOT = Path(__file__).resolve().parents[4]


from src.backend.course_io import CourseIoService, SaveResult
from src.backend.course_exchange import CourseExchangeService
from src.backend.course_release import CourseReleaseService
from src.backend.schema_constants import ResourceKey


from src.backend.course_section_merge import (
    MergeAction,
    SectionMergePlan,
    CourseSectionMergeService,
)


class CourseAdapter:
    """In-memory working copy of a course directory with save/validate/lint."""

    def __init__(self) -> None:
        self.course_dir: Path | None = None
        self.index: dict[str, Any] = {}
        self.sections: list[dict[str, Any]] = []
        self.vocab: list[dict[str, Any]] = []
        self.expressions: list[dict[str, Any]] = []
        self.grammar_points: list[dict[str, Any]] = []
        self.expressions_version: int = 1
        self._snapshot: dict[str, Any] | None = None
        self._hash_cache: dict[str, int] = {}
        self._resource_listeners: list = []
        # id -> (section, unit) and id -> (section, unit, lesson) indexes
        # used by find_unit/find_lesson to avoid full-tree scans on every
        # command. Lazily rebuilt when ``_node_index_dirty`` is set.
        self._unit_index: dict[str, tuple[dict[str, Any], dict[str, Any]]] = {}
        self._lesson_index: dict[str, tuple[dict[str, Any], dict[str, Any], dict[str, Any]]] = {}
        self._node_index_dirty: bool = True

    # --- Resource change notification (A3) --------------------------------

    def add_resource_listener(self, callback) -> None:
        """Register a callable invoked whenever in-memory resources change.

        The callback receives no arguments; listeners re-query
        ``vocab_options`` / ``expression_options`` / ``grammar_options`` to
        refresh their reference dropdowns in place.
        """
        if callable(callback) and callback not in self._resource_listeners:
            self._resource_listeners.append(callback)

    def remove_resource_listener(self, callback) -> None:
        try:
            self._resource_listeners.remove(callback)
        except ValueError:
            logger.warning("Tried to remove a resource listener that was not registered")

    def notify_resources_changed(self) -> None:
        """Fire resource listeners. Called by the resource editor after any
        in-memory vocab/expressions/grammar mutation."""
        for cb in list(self._resource_listeners):
            try:
                cb()
            except Exception:
                logger.exception("Resource listener failed")

    def load(self, course_dir: Path) -> None:
        self.course_dir = Path(course_dir)
        start = time.perf_counter()
        try:
            bundle = api.load_course(self.course_dir)
            self.index = bundle.index
            self.sections = bundle.sections
            self.vocab = bundle.vocab
            self.expressions = bundle.expressions
            self.grammar_points = bundle.grammar_points
            self.expressions_version = bundle.expressions_version
            self._snapshot = self._deep_snapshot()
            self._refresh_hash_cache()
            self.invalidate_node_index()
        except Exception:
            telemetry.record_error(
                context={"action": "repo.load", "course_dir": str(self.course_dir)},
            )
            raise
        finally:
            telemetry.record_duration(
                "repo.load",
                (time.perf_counter() - start) * 1000,
                payload={"course_dir": str(self.course_dir)},
            )

    def _refresh_hash_cache(self) -> None:
        """Cache hashes of the last-saved snapshot."""
        snap = self._snapshot or self._deep_snapshot()
        self._hash_cache = {
            "index": self._state_hash({"index": snap["index"]}),
            "sections": self._state_hash({"sections": snap["sections"]}),
            ResourceKey.VOCAB: self._state_hash({ResourceKey.VOCAB: snap[ResourceKey.VOCAB]}),
            ResourceKey.EXPRESSIONS: self._state_hash({ResourceKey.EXPRESSIONS: snap[ResourceKey.EXPRESSIONS]}),
            ResourceKey.GRAMMAR_POINTS: self._state_hash({ResourceKey.GRAMMAR_POINTS: snap[ResourceKey.GRAMMAR_POINTS]}),
        }

    def invalidate_node_index(self) -> None:
        """Mark the id->node index as stale.

        Call after any mutation that reorders, adds, removes, or replaces
        entries in ``self.sections`` (or sub-lists). The next ``find_unit``
        / ``find_lesson`` will rebuild lazily. Cheap if nothing queries.
        """
        self._node_index_dirty = True

    def _rebuild_node_indexes(self) -> None:
        """Rebuild ``_unit_index`` and ``_lesson_index`` from ``self.sections``."""
        self._unit_index = {}
        self._lesson_index = {}
        for section in self.sections:
            for unit in section.get("units") or []:
                if not isinstance(unit, dict):
                    continue
                uid = unit.get("id")
                if uid:
                    self._unit_index[uid] = (section, unit)
                for lesson in unit.get("lessons") or []:
                    if not isinstance(lesson, dict):
                        continue
                    lid = lesson.get("id")
                    if lid:
                        self._lesson_index[lid] = (section, unit, lesson)
        self._node_index_dirty = False

    def _ensure_node_index(self) -> None:
        if self._node_index_dirty:
            self._rebuild_node_indexes()

    @staticmethod
    def is_course_dir(path: Path) -> bool:
        """Return True if ``path`` looks like a course directory."""
        return (Path(path) / "index.json").is_file()

    def init_new(self, course_dir: Path, meta: dict[str, Any]) -> None:
        """Create a brand-new sample course directory and load it."""
        from src.backend.course_scaffold import CourseScaffold

        CourseScaffold.init_new(course_dir, meta, load_fn=self.load)

    @staticmethod
    def _sample_section_description(index: int, source_language: str) -> str:
        from src.backend.course_scaffold import CourseScaffold

        return CourseScaffold.sample_section_description(index, source_language)

    @staticmethod
    def _sample_vocab(language: str) -> list[dict[str, Any]]:
        from src.backend.course_scaffold import CourseScaffold

        return CourseScaffold.sample_vocab(language)

    @staticmethod
    def _sample_expressions(language: str) -> list[dict[str, Any]]:
        from src.backend.course_scaffold import CourseScaffold

        return CourseScaffold.sample_expressions(language)

    @staticmethod
    def _sample_grammar_points(language: str) -> list[dict[str, Any]]:
        from src.backend.course_scaffold import CourseScaffold

        return CourseScaffold.sample_grammar_points(language)

    @staticmethod
    def _build_sample_intro_lesson(*args, **kwargs) -> dict[str, Any]:
        from src.backend.course_scaffold import CourseScaffold

        if len(args) == 3 and not isinstance(args[0], str):
            return CourseScaffold.build_sample_intro_lesson(args[1], args[2])
        return CourseScaffold.build_sample_intro_lesson(*args, **kwargs)

    def vocab_options(self) -> list[tuple[str, str]]:
        return [(w["id"], f"{w.get('term', w['id'])} — {w.get('translation', '')}")
                for w in self.vocab]

    def expression_options(self) -> list[tuple[str, str]]:
        return [(e["id"], f"{e.get('term', e['id'])} — {e.get('translation', '')}")
                for e in self.expressions]

    def grammar_options(self) -> list[tuple[str, str]]:
        return [(g["id"], g.get("title", g["id"])) for g in self.grammar_points]

    def section_file(self, section_id: str) -> Path:
        for entry in self.index.get("sections", []):
            if entry["id"] == section_id:
                return self.course_dir / entry["file"]
        raise KeyError(f"unknown section id: {section_id}")

    def find_section(self, section_id: str) -> dict[str, Any]:
        for section in self.sections:
            if section.get("id") == section_id:
                return section
        raise KeyError(f"unknown section: {section_id}")

    def find_unit(self, unit_id: str) -> tuple[dict[str, Any], dict[str, Any]]:
        self._ensure_node_index()
        hit = self._unit_index.get(unit_id)
        if hit is not None:
            section, unit = hit
            # Validate: the cached (section, unit) must still be wired into
            # self.sections. Commands that move lessons/units mutate lists
            # in place, so a stale cache can point at a detached unit dict.
            lessons = unit.get("lessons")
            if any(section is s for s in self.sections) and any(unit is u for u in (section.get("units") or [])):
                return section, unit
            # Stale — drop and fall through to rescan.
            self._unit_index.pop(unit_id, None)
        for section in self.sections:
            for unit in section.get("units") or []:
                if isinstance(unit, dict) and unit.get("id") == unit_id:
                    self._unit_index[unit_id] = (section, unit)
                    return section, unit
        raise KeyError(f"unknown unit: {unit_id}")

    def find_lesson(self, lesson_id: str) -> tuple[dict[str, Any], dict[str, Any], dict[str, Any]]:
        self._ensure_node_index()
        hit = self._lesson_index.get(lesson_id)
        if hit is not None:
            section, unit, lesson = hit
            if (
                any(section is s for s in self.sections)
                and any(unit is u for u in (section.get("units") or []))
                and any(lesson is l for l in (unit.get("lessons") or []))
            ):
                return section, unit, lesson
            self._lesson_index.pop(lesson_id, None)
        for section in self.sections:
            for unit in section.get("units") or []:
                for lesson in unit.get("lessons") or []:
                    if isinstance(lesson, dict) and lesson.get("id") == lesson_id:
                        self._lesson_index[lesson_id] = (section, unit, lesson)
                        return section, unit, lesson
        raise KeyError(f"unknown lesson: {lesson_id}")

    @staticmethod
    def move_within(items: list[Any], from_idx: int, to_idx: int) -> bool:
        """Move an element within a list in place (sibling reorder only).

        Returns True if the move was applied, False if indices were out of
        range or the move was a no-op. Used by the tree-level move commands
        (MoveSection/Unit/Lesson) which only ever reorder within a single
        parent list — hierarchy is preserved by construction.
        """
        if not (0 <= from_idx < len(items) and 0 <= to_idx < len(items)):
            return False
        if from_idx == to_idx:
            return False
        items.insert(to_idx, items.pop(from_idx))
        return True

    def validate_section_json(
        self,
        section_json: dict[str, Any],
        *,
        check_existing_ids: bool = True,
    ) -> list[dict[str, str]]:
        """Validate an AI-generated section dict before importing it."""
        return CourseSectionMergeService.validate_section_json(
            self, section_json, check_existing_ids=check_existing_ids
        )

    def plan_section_merge(
        self,
        target_section_id: str | None,
        incoming_section: dict[str, Any],
    ) -> SectionMergePlan:
        """Compute a merge plan for importing an AI-generated section."""
        return CourseSectionMergeService.plan_section_merge(
            self, target_section_id, incoming_section
        )

    @staticmethod
    def _plan_lesson_merge(
        plan: SectionMergePlan,
        unit_id: str,
        incoming_unit: dict[str, Any],
        target_section: dict[str, Any],
    ) -> None:
        """Classify lessons inside a unit that already exists in the target."""
        CourseSectionMergeService.plan_lesson_merge(
            plan, unit_id, incoming_unit, target_section
        )

    def update_section_meta(self, section_id: str, name: str, description: str) -> None:
        section = self.find_section(section_id)
        section["name"] = name
        section["description"] = description
        for entry in self.index.get("sections", []):
            if entry["id"] == section_id:
                entry["name"] = name
                entry["description"] = description

    def update_lesson_prereqs(self, lesson_id: str, prereq_ids: list[str]) -> None:
        _section, _unit, lesson = self.find_lesson(lesson_id)
        lesson["prerequisiteLessonIds"] = [p for p in prereq_ids if p != lesson_id]

    def set_linked_grammar_points(self, lesson_id: str, ids: list[str]) -> None:
        """Write ``content.linkedGrammarPointIds`` (app SRS registration reads it).

        Mirrors update_lesson_prereqs; lives under content, not the lesson
        top level. Existing lessons without the key get it created on first
        edit — new lessons (init_new / new_lesson_from_template) start with [].
        """
        _section, _unit, lesson = self.find_lesson(lesson_id)
        content = lesson.setdefault("content", {})
        content["linkedGrammarPointIds"] = list(ids)

    def linked_grammar_options(self) -> list[tuple[str, str]]:
        """(id, label) options for the linked-grammar multi-select editor."""
        return [(g.get("id", ""), f"{g.get('title', g.get('id', ''))} ({g.get('id', '')})")
                for g in self.grammar_points if g.get("id")]

    def section_prereq_options(self, exclude_id: str) -> list[tuple[str, str]]:
        return [(s["id"], f"{s.get('name', s['id'])} ({s['id']})")
                for s in self.sections if s.get("id") != exclude_id]

    def unit_prereq_options(self, section_id: str, exclude_id: str) -> list[tuple[str, str]]:
        section = self.find_section(section_id)
        return [(u["id"], f"{u.get('name', u['id'])} ({u['id']})")
                for u in section.get("units", []) if u.get("id") != exclude_id]

    def lesson_prereq_options(self, unit_id: str, exclude_id: str) -> list[tuple[str, str]]:
        _section, unit = self.find_unit(unit_id)
        return [(l["id"], f"{l.get('name', l['id'])} ({l['id']})")
                for l in unit.get("lessons", []) if l.get("id") != exclude_id]

    def new_lesson(self, unit_id: str, template: str) -> str:
        from src.backend.lesson_content import new_lesson_from_template
        _section, unit = self.find_unit(unit_id)
        lesson = new_lesson_from_template(template, unit)
        return lesson["id"]

    def delete_lesson(self, lesson_id: str) -> None:
        for section in self.sections:
            for unit in section.get("units", []):
                lessons = unit.get("lessons", [])
                for i, lesson in enumerate(lessons):
                    if lesson.get("id") == lesson_id:
                        del lessons[i]
                        return
        raise KeyError(f"unknown lesson: {lesson_id}")

    def duplicate_lesson(self, lesson_id: str) -> str:
        """Deep-copy a lesson with fresh structural ids into the same unit.

        Returns the new lesson id. Reference ids (wordId/expressionId/etc.)
        are preserved so the clone points at the same resources as the
        original (workshop2 P1).
        """
        from src.backend.lesson_content import clone_lesson_with_fresh_ids

        _section, unit, lesson = self.find_lesson(lesson_id)
        clone = clone_lesson_with_fresh_ids(
            lesson, name=f"{lesson.get('name', lesson_id)} 副本"
        )
        unit.setdefault("lessons", []).append(clone)
        return clone["id"]

    def new_unit(self, section_id: str, name: str = "New unit") -> str:
        from src.backend.lesson_content import short_id
        section = self.find_section(section_id)
        unit = {
            "id": short_id("u"),
            "name": name,
            "description": "",
            "prerequisiteUnitIds": [],
            "lessons": [],
        }
        section.setdefault("units", []).append(unit)
        return unit["id"]

    def delete_unit(self, unit_id: str) -> None:
        for section in self.sections:
            units = section.get("units", [])
            for i, unit in enumerate(units):
                if unit.get("id") == unit_id:
                    del units[i]
                    return
        raise KeyError(f"unknown unit: {unit_id}")

    def section_is_referenced(self, section_id: str) -> list[str]:
        """Return ids of other sections whose prerequisiteSectionIds include
        ``section_id``. Used to block deletion of a depended-on section."""
        refs: list[str] = []
        for section in self.sections:
            sid = section.get("id", "")
            if sid == section_id:
                continue
            if section_id in section.get("prerequisiteSectionIds", []):
                refs.append(sid)
        return refs

    def delete_section(self, section_id: str) -> None:
        """Remove a section from ``self.sections`` and from ``index["sections"]``.

        Does NOT clear prerequisiteSectionIds references in other sections; the
        caller should check ``section_is_referenced`` first and block deletion
        when references exist.
        """
        removed = False
        for i, section in enumerate(self.sections):
            if section.get("id") == section_id:
                del self.sections[i]
                removed = True
                break
        entries = self.index.get("sections", [])
        for i, entry in enumerate(entries):
            if entry.get("id") == section_id:
                del entries[i]
                break
        if not removed:
            raise KeyError(f"unknown section: {section_id}")

    def replace_section(self, section_id: str, new_section: dict[str, Any]) -> None:
        """Replace the section with id ``section_id`` by ``new_section`` in both
        ``self.sections`` and ``index["sections"]``. ``new_section["id"]`` must
        equal ``section_id`` (or the index entry keeps the old id)."""
        for i, section in enumerate(self.sections):
            if section.get("id") == section_id:
                self.sections[i] = new_section
                break
        else:
            raise KeyError(f"unknown section: {section_id}")
        for entry in self.index.get("sections", []):
            if entry.get("id") == section_id:
                entry["name"] = new_section.get("name", entry.get("name", ""))
                entry["description"] = new_section.get(
                    "description", entry.get("description", "")
                )
                entry["level"] = new_section.get(
                    "level", entry.get("level", "")
                )
                entry["prerequisiteSectionIds"] = new_section.get(
                    "prerequisiteSectionIds", entry.get("prerequisiteSectionIds", [])
                )
                break

    def replace_unit(
        self, section_id: str, unit_id: str, new_unit: dict[str, Any]
    ) -> None:
        """Replace the unit with id ``unit_id`` within the section ``section_id``."""
        section = self.find_section(section_id)
        units = section.get("units", [])
        for i, unit in enumerate(units):
            if unit.get("id") == unit_id:
                units[i] = new_unit
                return
        raise KeyError(f"unknown unit: {unit_id}")

    def replace_lesson(self, lesson_id: str, new_lesson: dict[str, Any]) -> None:
        """Replace the lesson with id ``lesson_id`` in its containing unit."""
        for section in self.sections:
            for unit in section.get("units", []):
                lessons = unit.get("lessons", [])
                for i, lesson in enumerate(lessons):
                    if lesson.get("id") == lesson_id:
                        lessons[i] = new_lesson
                        return
        raise KeyError(f"unknown lesson: {lesson_id}")

    def _resource_list(self, row_type: str) -> list[dict[str, Any]]:
        if row_type == ResourceKey.VOCAB:
            return self.vocab
        if row_type == ResourceKey.EXPRESSIONS:
            return self.expressions
        if row_type == ResourceKey.GRAMMAR_POINTS:
            return self.grammar_points
        raise ValueError(f"unknown resource type: {row_type}")

    def _set_resource_list(
        self, row_type: str, entries: list[dict[str, Any]]
    ) -> None:
        if row_type == ResourceKey.VOCAB:
            self.vocab = entries
        elif row_type == ResourceKey.EXPRESSIONS:
            self.expressions = entries
        elif row_type == ResourceKey.GRAMMAR_POINTS:
            self.grammar_points = entries
        else:
            raise ValueError(f"unknown resource type: {row_type}")

    def add_resource_entry(self, row_type: str) -> str:
        """Append a blank entry with a fresh id, return the id."""
        from src.backend.lesson_content import short_id
        if row_type in (ResourceKey.VOCAB, ResourceKey.EXPRESSIONS):
            prefix = "w" if row_type == ResourceKey.VOCAB else "e"
            entry: dict[str, Any] = {
                "id": short_id(prefix),
                "term": "",
                "translation": "",
                "pronunciation": None,
                "audioAsset": None,
                "tags": [],
            }
        elif row_type == ResourceKey.GRAMMAR_POINTS:
            entry = {
                "id": short_id("g"),
                "title": "",
                "explanation": "",
                "exampleExpressionIds": [],
                "exampleSentenceIds": [],
                "practiceItems": [],
            }
        else:
            raise ValueError(f"unknown resource type: {row_type}")
        self._resource_list(row_type).append(entry)
        return entry["id"]

    def delete_resource_entry(self, row_type: str, entry_id: str) -> None:
        entries = self._resource_list(row_type)
        for i, e in enumerate(entries):
            if e.get("id") == entry_id:
                del entries[i]
                return
        raise KeyError(f"unknown {row_type} id: {entry_id}")

    def merge_section_resources(self, section: dict[str, Any]) -> dict[str, int]:
        """Merge a section's top-level words/expressions/grammarPoints into the
        course resource lists, skipping ids that already exist.

        Returns a dict with counts: {"vocab": n, "expressions": n, "grammar_points": n}.
        """
        mapping = {
            "words": ("vocab", self.vocab),
            "expressions": ("expressions", self.expressions),
            "grammarPoints": ("grammar_points", self.grammar_points),
        }
        added: dict[str, int] = {"vocab": 0, "expressions": 0, "grammar_points": 0}
        for section_key, (row_type, target) in mapping.items():
            existing_ids = {e.get("id") for e in target}
            for entry in section.get(section_key) or []:
                if not isinstance(entry, dict):
                    continue
                eid = entry.get("id")
                if not eid or eid in existing_ids:
                    continue
                target.append(entry)
                existing_ids.add(eid)
                added[row_type] += 1
        return added

    def import_csv(
        self, row_type: str, csv_path: Path
    ) -> list[dict[str, str]]:
        """Read CSV, merge into memory, return problems. Does not write files."""
        return CourseExchangeService.import_csv(self, row_type, csv_path)

    def export_csv(self, row_type: str, output_path: Path) -> None:
        """Write current in-memory resources to CSV."""
        CourseExchangeService.export_csv(self, row_type, output_path)

    def sync_resources_with_git(self, git_dir: Path, lang: str) -> str:
        """Bidirectionally merge local resources with a git clone's resource JSON."""
        return CourseExchangeService.sync_resources_with_git(self, git_dir, lang)

    def detect_duplicates(self) -> list[dict[str, str]]:
        """Detect duplicate terms across vocab and expressions."""
        return CourseExchangeService.detect_duplicates(self)

    def export_resource_pack(self, output_path: Path) -> Path:
        """Export all resource lists as a single JSON file (resource pack)."""
        return CourseExchangeService.export_resource_pack(self, output_path)

    def import_resource_pack(self, pack_path: Path, *, replace: bool = False) -> dict[str, int]:
        """Import a resource pack JSON file, merging by id."""
        return CourseExchangeService.import_resource_pack(self, pack_path, replace=replace)

    def _state_hash(self, data: dict[str, Any]) -> str:
        """Return a stable, salt-independent hash for a state dict."""
        return CourseReleaseService.state_hash(data)

    def detect_changes(self) -> dict[str, bool]:
        """Compare current in-memory state vs last-saved snapshot using cached hashes."""
        return CourseReleaseService.detect_changes(self)

    def version_bump_plan(
        self, changes: dict[str, bool] | None = None
    ) -> dict[str, tuple[int, int]]:
        """Return {file: (current_version, next_version)} for files to bump."""
        return CourseReleaseService.version_bump_plan(self, changes)

    def apply_version_bump(self, plan: dict[str, tuple[int, int]]) -> None:
        """Apply version bumps to in-memory state (caller then save())."""
        CourseReleaseService.apply_version_bump(self, plan)

    def audio_manifest_rows(self) -> list[dict[str, str]]:
        """Return audio manifest rows (delegates to backend API)."""
        return CourseReleaseService.audio_manifest_rows(self)

    def release_diff(self) -> dict[str, dict[str, Any]]:
        """Compare last-saved snapshot (before) vs current (after) by id sets."""
        return CourseReleaseService.release_diff(self)

    def release_report(self) -> dict[str, Any]:
        """Aggregate release checklist data for the publish dialog."""
        return CourseReleaseService.release_report(self)

    def _deep_snapshot(self) -> dict[str, Any]:
        from src.backend.course_io import CourseIoService

        return CourseIoService.deep_snapshot(self)

    def _restore_from(self, snapshot: dict[str, Any]) -> None:
        from src.backend.course_io import CourseIoService

        CourseIoService.restore_from(self, snapshot)

    def _write_files_to_dir(self, target_dir: Path) -> None:
        from src.backend.course_io import CourseIoService

        CourseIoService.write_files_to_dir(self, target_dir)

    def _backup_json_files(self, src: Path, dst: Path) -> None:
        from src.backend.course_io import CourseIoService

        CourseIoService.backup_json_files(src, dst)

    @staticmethod
    def _prune_old_backups(backup_root: Path, keep: int = 20) -> None:
        from src.backend.course_io import CourseIoService

        CourseIoService.prune_old_backups(backup_root, keep=keep)

    def _replace_course_files_with(self, tmp_dir: Path, course_dir: Path) -> None:
        from src.backend.course_io import CourseIoService

        CourseIoService.replace_course_files_with(tmp_dir, course_dir)

    def save(self) -> SaveResult:
        from src.backend.course_io import CourseIoService

        return CourseIoService.save(self)
