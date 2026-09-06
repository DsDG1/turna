"""Prompt template library and generation history for the AI generator.

Templates and history are persisted in QSettings under the namespace
``Turna/CourseEditor/ai/prompts``. The module has no PySide6 dependency in
its data classes but uses QSettings for storage so it integrates with the rest
of the application.
"""
from __future__ import annotations

import json
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:
    from PySide6.QtCore import QSettings

from src.backend.ai import AiCourseSpec
import logging
logger = logging.getLogger(__name__)


@dataclass
class AiPromptTemplate:
    """A reusable prompt template capturing the full generation spec.

    ``kind`` distinguishes template families (connectplan P1-3): ``course_gen``
    templates drive course generation; other kinds (e.g. ``extraction``) share
    the storage but are managed by their own UIs. Old QSettings entries have
    no ``kind`` and load as ``course_gen``.
    """

    name: str
    topic: str = ""
    level: str = "A1"
    unit_count: int = 1
    lessons_per_unit: int = 3
    template: str = "mixed"
    use_genre_batch: bool = False
    extra_instructions: str = ""
    created_at: str = ""
    kind: str = "course_gen"

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "AiPromptTemplate":
        return cls(**{k: v for k, v in data.items() if k in cls.__dataclass_fields__})

    @classmethod
    def from_spec(cls, name: str, spec: AiCourseSpec) -> "AiPromptTemplate":
        return cls(
            name=name,
            topic=spec.topic,
            level=spec.level,
            unit_count=spec.unit_count,
            lessons_per_unit=spec.lessons_per_unit,
            template=spec.template,
            use_genre_batch=spec.use_genre_batch,
            extra_instructions=spec.extra_instructions,
            created_at=datetime.now(timezone.utc).isoformat(),
        )

    def apply_to_spec(self, spec: AiCourseSpec) -> AiCourseSpec:
        """Return a new AiCourseSpec with template values overlaid."""
        from dataclasses import replace

        return replace(
            spec,
            topic=self.topic,
            level=self.level,
            unit_count=self.unit_count,
            lessons_per_unit=self.lessons_per_unit,
            template=self.template,
            use_genre_batch=self.use_genre_batch,
            extra_instructions=self.extra_instructions,
        )


@dataclass
class AiPromptHistory:
    """A single generation history entry."""

    topic: str = ""
    extra_instructions: str = ""
    level: str = "A1"
    unit_count: int = 1
    lessons_per_unit: int = 3
    template: str = "mixed"
    use_genre_batch: bool = False
    created_at: str = ""

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "AiPromptHistory":
        return cls(**{k: v for k, v in data.items() if k in cls.__dataclass_fields__})

    @classmethod
    def from_spec(cls, spec: AiCourseSpec) -> "AiPromptHistory":
        return cls(
            topic=spec.topic,
            extra_instructions=spec.extra_instructions,
            level=spec.level,
            unit_count=spec.unit_count,
            lessons_per_unit=spec.lessons_per_unit,
            template=spec.template,
            use_genre_batch=spec.use_genre_batch,
            created_at=datetime.now(timezone.utc).isoformat(),
        )


class AiPromptLibrary:
    """Storage backend for prompt templates and recent history."""

    def __init__(self, qsettings: "QSettings | None" = None) -> None:
        if qsettings is None:
            from PySide6.QtCore import QSettings

            self._settings = QSettings("Turna", "CourseEditor")
        else:
            self._settings = qsettings
        self._settings.beginGroup("ai/prompts")

    def _template_list(self) -> list[dict[str, Any]]:
        raw = self._settings.value("templates", "[]")
        if isinstance(raw, str):
            try:
                parsed = json.loads(raw)
                if isinstance(parsed, list):
                    return parsed
            except Exception:
                logger.debug("backend/ai_prompt_library.py:_template_list best-effort step failed", exc_info=True)
        return []

    def _save_template_list(self, templates: list[dict[str, Any]]) -> None:
        self._settings.setValue("templates", json.dumps(templates, ensure_ascii=False))

    def list_templates(self, kind: str | None = None) -> list[AiPromptTemplate]:
        templates = [AiPromptTemplate.from_dict(d) for d in self._template_list()]
        if kind is not None:
            templates = [t for t in templates if t.kind == kind]
        return templates

    def save_template(self, template: AiPromptTemplate) -> None:
        templates = self._template_list()
        templates = [d for d in templates if d.get("name") != template.name]
        template.created_at = datetime.now(timezone.utc).isoformat()
        templates.insert(0, template.to_dict())
        self._save_template_list(templates)

    def delete_template(self, name: str) -> bool:
        templates = self._template_list()
        before = len(templates)
        templates = [d for d in templates if d.get("name") != name]
        if len(templates) == before:
            return False
        self._save_template_list(templates)
        return True

    def record_history(self, spec: AiCourseSpec) -> None:
        entry = AiPromptHistory.from_spec(spec).to_dict()
        history = self._history_list()
        # Deduplicate by identical fields except created_at.
        key_fields = {"topic", "extra_instructions", "level", "unit_count",
                      "lessons_per_unit", "template", "use_genre_batch"}
        history = [
            d for d in history
            if {k: d.get(k) for k in key_fields} != {k: entry.get(k) for k in key_fields}
        ]
        history.insert(0, entry)
        self._save_history_list(history[:20])

    def _history_list(self) -> list[dict[str, Any]]:
        raw = self._settings.value("history", "[]")
        if isinstance(raw, str):
            try:
                parsed = json.loads(raw)
                if isinstance(parsed, list):
                    return parsed
            except Exception:
                logger.debug("backend/ai_prompt_library.py:_history_list best-effort step failed", exc_info=True)
        return []

    def _save_history_list(self, history: list[dict[str, Any]]) -> None:
        self._settings.setValue("history", json.dumps(history, ensure_ascii=False))

    def recent_history(self, limit: int = 20) -> list[AiPromptHistory]:
        return [AiPromptHistory.from_dict(d) for d in self._history_list()[:limit]]

    # --- Extraction prompt overrides (connectplan P1-3) --------------------
    #
    # Per-language-pair overrides for the textbook knowledge-extraction
    # prompts (``knowledge_prompt.KnowledgePromptTemplates``). Stored under a
    # separate QSettings key so course-gen templates stay untouched.

    @staticmethod
    def _pair_key(language: str, source_language: str) -> str:
        return f"{language.strip().lower()}|{source_language.strip().lower()}"

    def _overrides_dict(self) -> dict[str, dict[str, Any]]:
        raw = self._settings.value("extraction_overrides", "{}")
        if isinstance(raw, str):
            try:
                parsed = json.loads(raw)
                if isinstance(parsed, dict):
                    return parsed
            except Exception:
                logger.debug("backend/ai_prompt_library.py:_overrides_dict best-effort step failed", exc_info=True)
        return {}

    def _save_overrides_dict(self, overrides: dict[str, dict[str, Any]]) -> None:
        self._settings.setValue(
            "extraction_overrides", json.dumps(overrides, ensure_ascii=False)
        )

    def save_extraction_override(
        self, language: str, source_language: str, blocks: dict[str, Any]
    ) -> None:
        """Persist a prompt-template override for one language pair."""
        overrides = self._overrides_dict()
        overrides[self._pair_key(language, source_language)] = dict(blocks)
        self._save_overrides_dict(overrides)

    def extraction_override(
        self, language: str, source_language: str
    ) -> dict[str, Any] | None:
        return self._overrides_dict().get(
            self._pair_key(language, source_language)
        )

    def delete_extraction_override(self, language: str, source_language: str) -> bool:
        overrides = self._overrides_dict()
        key = self._pair_key(language, source_language)
        if key not in overrides:
            return False
        del overrides[key]
        self._save_overrides_dict(overrides)
        return True

    def list_extraction_overrides(self) -> dict[str, dict[str, Any]]:
        """All overrides keyed by ``"lang|src"`` (lowercase)."""
        return self._overrides_dict()


def prompt_library() -> AiPromptLibrary:
    """Return the default prompt library using the application QSettings."""
    return AiPromptLibrary()
