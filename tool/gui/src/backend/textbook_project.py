"""Textbook import project model.

A project captures the full state of an in-progress textbook import so a teacher
can close the dialog and resume later. It stores the source file reference (not
the file itself), parsed markdown, chapter split results, extracted knowledge
points, and the current UI step.
"""
from __future__ import annotations

import hashlib
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from src.backend.knowledge_schema import KnowledgePoints
from src.backend.markdown_chopper import Chapter

PROJECT_VERSION = 2


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _empty_resource_pool() -> dict[str, Any]:
    """Default resource-pool snapshot (connectplan §3.1).

    The pool is a *snapshot* of the knowledge extracted across kept chapters;
    dedup still happens at import time via ``KnowledgeMerger``.
    """
    return {"words": [], "expressions": [], "grammarPoints": [], "updated_at": ""}


def _empty_design() -> dict[str, Any]:
    """Default AI-design state (written from Phase 3 onward)."""
    return {"chat_history": [], "params": {}, "draft_sections": [], "explanation": ""}


def _checksum(path: Path | None) -> str | None:
    if path is None or not path.exists():
        return None
    h = hashlib.sha256()
    h.update(path.read_bytes())
    return h.hexdigest()


@dataclass
class TextbookProject:
    """Serializable state of one textbook-import session.

    Attributes:
        project_id: Stable identifier used as directory name.
        name: Human-readable project name (usually the source file stem).
        created_at: ISO 8601 UTC timestamp.
        updated_at: ISO 8601 UTC timestamp.
        current_step: Index matching ``TextbookImportController`` step enum.
        source_path: Absolute path to the original source file, if any.
        source_checksum: SHA256 of the source file for change detection.
        markdown: Parsed markdown content.
        language: Target language being taught.
        source_language: Source/explanation language.
        chapters: Serialized chapter results (chapter + keep + knowledge + error).
        imported_section_ids: Section ids that have already been imported.
        resource_pool: Merged knowledge snapshot across kept chapters (v2).
        design: AI design state — chat history, params, draft sections (v2;
            populated from Phase 3 onward).
        import_map: Source section id → actually imported section id (v2).
        version: Format version for migrations.
    """

    project_id: str
    name: str
    created_at: str
    updated_at: str
    current_step: int
    source_path: str | None
    source_checksum: str | None
    markdown: str
    language: str
    source_language: str
    chapters: list[dict[str, Any]] = field(default_factory=list)
    imported_section_ids: list[str] = field(default_factory=list)
    resource_pool: dict[str, Any] = field(default_factory=_empty_resource_pool)
    design: dict[str, Any] = field(default_factory=_empty_design)
    import_map: dict[str, str] = field(default_factory=dict)
    version: int = PROJECT_VERSION

    def to_dict(self) -> dict[str, Any]:
        return {
            "version": self.version,
            "project_id": self.project_id,
            "name": self.name,
            "created_at": self.created_at,
            "updated_at": self.updated_at,
            "current_step": self.current_step,
            "source_path": self.source_path,
            "source_checksum": self.source_checksum,
            "markdown": self.markdown,
            "language": self.language,
            "source_language": self.source_language,
            "chapters": self.chapters,
            "imported_section_ids": self.imported_section_ids,
            "resource_pool": self.resource_pool,
            "design": self.design,
            "import_map": self.import_map,
        }

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "TextbookProject":
        return cls(
            project_id=data.get("project_id", ""),
            name=data.get("name", ""),
            created_at=data.get("created_at", _utc_now()),
            updated_at=data.get("updated_at", _utc_now()),
            current_step=data.get("current_step", 0),
            source_path=data.get("source_path"),
            source_checksum=data.get("source_checksum"),
            markdown=data.get("markdown", ""),
            language=data.get("language", "Turkish"),
            source_language=data.get("source_language", "Chinese"),
            chapters=list(data.get("chapters", [])),
            imported_section_ids=list(data.get("imported_section_ids", [])),
            resource_pool=data.get("resource_pool") or _empty_resource_pool(),
            design=data.get("design") or _empty_design(),
            import_map=dict(data.get("import_map", {})),
            # Missing version key means a pre-v2 file.
            version=data.get("version", 1),
        )

    def touch(self) -> None:
        """Bump ``updated_at`` to now."""
        self.updated_at = _utc_now()

    @property
    def is_fully_imported(self) -> bool:
        """True once the import step has been reached and at least one section
        was imported."""
        return self.current_step >= 5 and bool(self.imported_section_ids)

    @staticmethod
    def _chapter_to_dict(chapter: Chapter) -> dict[str, Any]:
        return {
            "idx": chapter.idx,
            "level": chapter.level,
            "title": chapter.title,
            "slug": chapter.slug,
            "markdown": chapter.markdown,
        }

    @staticmethod
    def _chapter_from_dict(data: dict[str, Any]) -> Chapter:
        return Chapter(
            idx=data["idx"],
            level=data["level"],
            title=data["title"],
            slug=data["slug"],
            markdown=data["markdown"],
        )

    @staticmethod
    def _knowledge_to_dict(kp: KnowledgePoints | None) -> dict[str, Any] | None:
        if kp is None:
            return None
        return {
            "words": list(kp.words),
            "expressions": list(kp.expressions),
            "grammarPoints": list(kp.grammarPoints),
        }

    @staticmethod
    def _knowledge_from_dict(data: dict[str, Any] | None) -> KnowledgePoints | None:
        if data is None:
            return None
        return KnowledgePoints(
            words=list(data.get("words", [])),
            expressions=list(data.get("expressions", [])),
            grammarPoints=list(data.get("grammarPoints", [])),
        )

    def set_chapters(
        self,
        chapters: list[tuple[Chapter, bool, KnowledgePoints | None, str]],
    ) -> None:
        """Replace ``self.chapters`` from controller-style chapter results."""
        self.chapters = [
            {
                "chapter": self._chapter_to_dict(ch),
                "keep": keep,
                "knowledge": self._knowledge_to_dict(kp),
                "error": error,
            }
            for ch, keep, kp, error in chapters
        ]

    def get_chapters(
        self,
    ) -> list[tuple[Chapter, bool, KnowledgePoints | None, str]]:
        """Return controller-style chapter results."""
        return [
            (
                self._chapter_from_dict(item["chapter"]),
                item.get("keep", True),
                self._knowledge_from_dict(item.get("knowledge")),
                item.get("error", ""),
            )
            for item in self.chapters
        ]

    def source_changed(self) -> bool:
        """True if the source file on disk no longer matches ``source_checksum``."""
        if self.source_path is None:
            return False
        path = Path(self.source_path)
        current = _checksum(path)
        return current != self.source_checksum

    def merge_from(self, other: "TextbookProject") -> None:
        """Update mutable fields from ``other`` while preserving identity.

        Preserves ``project_id``, ``created_at``, ``imported_section_ids``,
        ``design``, and ``import_map`` — those are owned by import/design
        bookkeeping and must not be clobbered by an autosave snapshot.
        ``resource_pool`` *is* copied: it is derived from ``chapters`` (which
        is also copied), so keeping the two in sync is correct.
        """
        self.name = other.name
        self.updated_at = other.updated_at
        self.current_step = other.current_step
        self.source_path = other.source_path
        self.source_checksum = other.source_checksum
        self.markdown = other.markdown
        self.language = other.language
        self.source_language = other.source_language
        self.chapters = list(other.chapters)
        self.resource_pool = other.resource_pool

    def update_resource_pool(self) -> None:
        """Refresh the resource-pool snapshot from the current chapters.

        Concatenates the extracted knowledge of all kept chapters in chapter
        order. Dedup is deliberately *not* done here — the import-time
        ``KnowledgeMerger`` owns that; the pool is a display/grounding
        snapshot (connectplan §3.1).
        """
        words: list[dict[str, Any]] = []
        expressions: list[dict[str, Any]] = []
        grammar: list[dict[str, Any]] = []
        for item in self.chapters:
            if not item.get("keep", True):
                continue
            kp = item.get("knowledge")
            if not kp:
                continue
            words.extend(kp.get("words", []))
            expressions.extend(kp.get("expressions", []))
            grammar.extend(kp.get("grammarPoints", []))
        if not (words or expressions or grammar):
            return  # keep the previous snapshot when nothing is extracted
        self.resource_pool = {
            "words": words,
            "expressions": expressions,
            "grammarPoints": grammar,
            "updated_at": _utc_now(),
        }

    @classmethod
    def create(
        cls,
        project_id: str,
        name: str,
        source_path: Path | None,
        markdown: str = "",
        language: str = "Turkish",
        source_language: str = "Chinese",
    ) -> "TextbookProject":
        now = _utc_now()
        return cls(
            project_id=project_id,
            name=name,
            created_at=now,
            updated_at=now,
            current_step=0,
            source_path=str(source_path) if source_path else None,
            source_checksum=_checksum(source_path),
            markdown=markdown,
            language=language,
            source_language=source_language,
        )
