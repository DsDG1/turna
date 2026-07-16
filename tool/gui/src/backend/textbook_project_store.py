"""Persistence store for ``TextbookProject`` objects.

Projects are stored as ``project.json`` under ``{base_dir}/{project_id}/``.
The store is intentionally simple (plain JSON) to avoid adding a database
dependency.
"""
from __future__ import annotations

import json
import re
import sys
import uuid
from pathlib import Path
from typing import Any

# Ensure ``tool/gui`` is on sys.path when this module is imported directly.
_GUI = Path(__file__).resolve().parents[2]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.textbook_project import TextbookProject


_PROJECT_FILE = "project.json"


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
        pass
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
                pass  # backup is best-effort; migration itself must not fail
        project.version = 2
        try:
            self.save_project(project)
        except OSError:
            pass
        return project

    def save_project(self, project: TextbookProject) -> None:
        """Persist ``project`` to disk, creating its directory if needed."""
        project.touch()
        project_dir = self.project_dir(project.project_id)
        project_dir.mkdir(parents=True, exist_ok=True)
        path = project_dir / _PROJECT_FILE
        path.write_text(
            json.dumps(project.to_dict(), ensure_ascii=False, indent=2),
            encoding="utf-8",
        )

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
        return True

    def project_exists(self, project_id: str) -> bool:
        return self.project_file(project_id).exists()
