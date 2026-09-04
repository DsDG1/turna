"""Persistence store for ``TextbookProject`` objects.

Projects are stored as ``project.json`` under ``{base_dir}/{project_id}/``.
The store is intentionally simple (plain JSON) to avoid adding a database
dependency.
"""
from __future__ import annotations

import json
import os
import re
import sys
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Any

# Ensure ``tool/gui`` is on sys.path when this module is imported directly.
_GUI = Path(__file__).resolve().parents[2]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.textbook_project import TextbookProject
import logging
logger = logging.getLogger(__name__)


_PROJECT_FILE = "project.json"
_INDEX_FILE = "index.json"
_INDEX_VERSION = 1


@dataclass
class ProjectSummary:
    """Lightweight row for the project library list."""

    project_id: str
    name: str
    updated_at: str
    current_step: int
    language: str
    source_language: str
    source_path: str | None
    has_source: bool
    imported: bool

    def to_dict(self) -> dict[str, Any]:
        return {
            "project_id": self.project_id,
            "name": self.name,
            "updated_at": self.updated_at,
            "current_step": self.current_step,
            "language": self.language,
            "source_language": self.source_language,
            "source_path": self.source_path,
            "has_source": self.has_source,
            "imported": self.imported,
        }

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "ProjectSummary":
        return cls(
            project_id=data.get("project_id", ""),
            name=data.get("name", ""),
            updated_at=data.get("updated_at", ""),
            current_step=data.get("current_step", 0),
            language=data.get("language", "Turkish"),
            source_language=data.get("source_language", "Chinese"),
            source_path=data.get("source_path"),
            has_source=bool(data.get("has_source", False)),
            imported=bool(data.get("imported", False)),
        )

    @classmethod
    def from_project(cls, project: TextbookProject) -> "ProjectSummary":
        return cls(
            project_id=project.project_id,
            name=project.name,
            updated_at=project.updated_at,
            current_step=project.current_step,
            language=project.language,
            source_language=project.source_language,
            source_path=project.source_path,
            has_source=project.source_path is not None,
            imported=project.is_fully_imported,
        )


def _safe_name(name: str) -> str:
    """Turn a project name into a filesystem-safe directory suffix."""
    safe = re.sub(r"[^\w\-]+", "_", name).strip("_")[:40]
    return safe or "project"


def _new_project_id(name: str) -> str:
    """Generate a unique project id like ``turkish_reader_abc123de``."""
    suffix = _safe_name(name)
    uid = uuid.uuid4().hex[:8]
    return f"{suffix}_{uid}" if suffix else uid


#: Step index recorded once at least one section has been imported. Matches
#: ``TextbookImportController.STEP_IMPORT``; kept as a literal to avoid a
#: backend → dialogs dependency.
STEP_IMPORT_INDEX = 5


def record_imported_sections(
    project: TextbookProject,
    section_ids: list[str],
    *,
    store: "TextbookProjectStore | None" = None,
    id_pairs: list[tuple[str, str]] | None = None,
) -> list[str]:
    """Record successfully imported section ids on ``project`` and persist.

    Only ids not already known are appended; when at least one new id is
    recorded, ``current_step`` advances to the import step so
    ``TextbookProject.is_fully_imported`` becomes true and the project
    library can show 已导入. ``id_pairs`` (source id, final id) additionally
    fills ``import_map`` so re-imports can tell where each chapter landed
    (relevant when ``append_as_new`` rewrote the id). Returns the newly
    added ids. Persistence errors are swallowed: the course import itself
    already succeeded — this flag is bookkeeping.
    """
    known = set(project.imported_section_ids)
    added = [sid for sid in section_ids if sid and sid not in known]
    if id_pairs:
        for source_id, final_id in id_pairs:
            if source_id and final_id:
                project.import_map[source_id] = final_id
    if not added and not id_pairs:
        return []
    project.imported_section_ids.extend(added)
    if added:
        project.current_step = max(project.current_step, STEP_IMPORT_INDEX)
    try:
        (store or TextbookProjectStore()).save_project(project)
    except Exception:
        logger.debug("backend/textbook_project_store.py:record_imported_sections best-effort step failed", exc_info=True)
    return added


class TextbookProjectStore:
    """CRUD for textbook projects on the local filesystem."""

    def __init__(self, base_dir: Path | None = None) -> None:
        if base_dir is None:
            base_dir = Path(__file__).resolve().parents[3] / "var" / "textbooks"
        self.base_dir = base_dir
        self.base_dir.mkdir(parents=True, exist_ok=True)

    def project_dir(self, project_id: str) -> Path:
        return self.base_dir / project_id

    def project_file(self, project_id: str) -> Path:
        return self.project_dir(project_id) / _PROJECT_FILE

    def index_file(self) -> Path:
        return self.base_dir / _INDEX_FILE

    def list_projects(self) -> list[TextbookProject]:
        """Return all stored projects, sorted by most recently updated first."""
        projects: list[TextbookProject] = []
        if not self.base_dir.exists():
            return projects
        for child in self.base_dir.iterdir():
            if not child.is_dir():
                continue
            project = self.load_project(child.name)
            if project is not None:
                projects.append(project)
        projects.sort(key=lambda p: p.updated_at, reverse=True)
        return projects

    def list_project_summaries(self) -> list[ProjectSummary]:
        """Return lightweight summaries for the project library.

        Uses a cached ``index.json`` when possible. If a project's
        ``project.json`` mtime is newer than the cached entry, that project is
        reloaded individually and the index is rewritten. If the index is
        missing, corrupt, or out of date, it is rebuilt from a full scan.
        """
        summaries: list[ProjectSummary] = []
        index_path = self.index_file()
        index_data: dict[str, Any] | None = None
        if index_path.exists():
            try:
                index_data = json.loads(index_path.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError):
                index_data = None

        if index_data is not None and index_data.get("version") == _INDEX_VERSION:
            entries = index_data.get("projects", [])
            stale = False
            for entry in entries:
                summary = ProjectSummary.from_dict(entry)
                project_path = self.project_file(summary.project_id)
                if not project_path.exists():
                    stale = True
                    continue
                try:
                    mtime = project_path.stat().st_mtime
                except OSError:
                    stale = True
                    continue
                cached_mtime = entry.get("_mtime")
                if cached_mtime is None or mtime > cached_mtime:
                    project = self.load_project(summary.project_id)
                    if project is None:
                        stale = True
                        continue
                    summary = ProjectSummary.from_project(project)
                    stale = True
                summaries.append(summary)
            if stale:
                self._write_index(summaries)
            summaries.sort(key=lambda s: s.updated_at, reverse=True)
            return summaries

        # Index missing or unusable: full scan and rebuild.
        projects = self.list_projects()
        summaries = [ProjectSummary.from_project(p) for p in projects]
        self._write_index(summaries)
        return summaries

    def _write_index(self, summaries: list[ProjectSummary]) -> None:
        """Atomically rewrite the project index from the given summaries."""
        index_path = self.index_file()
        entries = []
        for summary in summaries:
            entry = summary.to_dict()
            project_path = self.project_file(summary.project_id)
            try:
                entry["_mtime"] = project_path.stat().st_mtime
            except OSError:
                entry["_mtime"] = 0.0
            entries.append(entry)
        data = {"version": _INDEX_VERSION, "projects": entries}
        tmp = index_path.with_suffix(index_path.suffix + ".tmp")
        tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
        os.replace(tmp, index_path)

    def load_project(self, project_id: str) -> TextbookProject | None:
        """Load a project by id, or None if missing/corrupt.

        v1 files are migrated to v2 in place (defaults filled, original kept
        as ``project.v1.json.bak``); the migration is idempotent.
        """
        path = self.project_file(project_id)
        if not path.exists():
            return None
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return None
        project = TextbookProject.from_dict(data)
        if project.version < 2:
            project = self._migrate_v1_to_v2(project, original_path=path)
        return project

    def _migrate_v1_to_v2(
        self, project: TextbookProject, *, original_path: Path
    ) -> TextbookProject:
        """Upgrade a v1 project in place, keeping a one-time backup."""
        backup = original_path.with_name("project.v1.json.bak")
        if not backup.exists():
            try:
                backup.write_text(
                    original_path.read_text(encoding="utf-8"), encoding="utf-8"
                )
            except OSError:
                logger.debug("backend/textbook_project_store.py:_migrate_v1_to_v2 best-effort step failed", exc_info=True)
        project.version = 2
        try:
            self.save_project(project)
        except OSError:
            logger.debug("backend/textbook_project_store.py:_migrate_v1_to_v2 best-effort step failed", exc_info=True)
        return project

    def save_project(self, project: TextbookProject) -> None:
        """Persist ``project`` to disk, creating its directory if needed.

        Writes via a sibling temp file + ``os.replace`` so a crash mid-write
        cannot leave a truncated ``project.json`` behind (which would make
        the project silently disappear from the library on next load).
        """
        project.touch()
        project_dir = self.project_dir(project.project_id)
        project_dir.mkdir(parents=True, exist_ok=True)
        path = project_dir / _PROJECT_FILE
        tmp = path.with_suffix(path.suffix + ".tmp")
        tmp.write_text(
            json.dumps(project.to_dict(), ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
        os.replace(tmp, path)
        self._update_index_for_project(project)

    def _update_index_for_project(self, project: TextbookProject) -> None:
        """Update or append a single project entry in the index."""
        index_path = self.index_file()
        summaries: list[ProjectSummary] = []
        if index_path.exists():
            try:
                data = json.loads(index_path.read_text(encoding="utf-8"))
                if data.get("version") == _INDEX_VERSION:
                    summaries = [
                        ProjectSummary.from_dict(e)
                        for e in data.get("projects", [])
                    ]
            except (OSError, json.JSONDecodeError):
                logger.debug("backend/textbook_project_store.py:_update_index_for_project best-effort step failed", exc_info=True)

        by_id = {s.project_id: s for s in summaries}
        by_id[project.project_id] = ProjectSummary.from_project(project)
        self._write_index(list(by_id.values()))

    def create_project(
        self,
        name: str,
        source_path: Path | None = None,
        markdown: str = "",
        language: str = "Turkish",
        source_language: str = "Chinese",
    ) -> TextbookProject:
        """Create and persist a new project."""
        project_id = _new_project_id(name)
        project = TextbookProject.create(
            project_id=project_id,
            name=name,
            source_path=source_path,
            markdown=markdown,
            language=language,
            source_language=source_language,
        )
        self.save_project(project)
        return project

    def delete_project(self, project_id: str) -> bool:
        """Delete a project directory. Returns True if it existed."""
        project_dir = self.project_dir(project_id)
        if not project_dir.exists():
            return False
        import shutil

        shutil.rmtree(project_dir)
        self._remove_from_index(project_id)
        return True

    def _remove_from_index(self, project_id: str) -> None:
        """Remove a project from the index if present."""
        index_path = self.index_file()
        if not index_path.exists():
            return
        try:
            data = json.loads(index_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return
        if data.get("version") != _INDEX_VERSION:
            return
        original = data.get("projects", [])
        filtered = [e for e in original if e.get("project_id") != project_id]
        if len(filtered) == len(original):
            return
        data["projects"] = filtered
        tmp = index_path.with_suffix(index_path.suffix + ".tmp")
        tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
        os.replace(tmp, index_path)
