"""Section assembly, knowledge merging, and import strategy planning for textbook import."""
from __future__ import annotations

from typing import Any

from src.backend.import_strategy import SectionImportPreview, plan_bulk_import
from src.backend.knowledge_merger import MergeReport, apply as merge_knowledge_points
from src.backend.knowledge_schema import KnowledgePoints
from src.backend.markdown_chopper import Chapter
from src.backend.textbook_to_course import build_section_from_chapter
from src.infrastructure.telemetry import telemetry


def build_raw_sections(
    chapters: list[Any],
    *,
    lesson_template: str | None = None,
) -> list[tuple[int, dict[str, Any]]]:
    """Build ``(0-based chapter index, section dict)`` for kept, non-empty chapters.

    Shared by ``build_sections`` and ``preview_import`` so the preview's section
    ids match what import will actually emit.

    The section ``idx`` passed to ``build_section_from_chapter`` is the 1-based
    position over **all** chapters (kept or not), matching the historical
    deterministic id scheme.
    """
    out: list[tuple[int, dict[str, Any]]] = []
    for ci, cr in enumerate(chapters, start=1):
        if not cr.keep or cr.knowledge is None:
            continue
        kp = cr.knowledge
        if not kp.words and not kp.expressions and not kp.grammarPoints:
            continue
        out.append(
            (
                ci - 1,
                build_section_from_chapter(
                    cr.chapter, kp, ci, lesson_template=lesson_template
                ),
            )
        )
    return out


def merge_knowledge_in_place(
    chapters_tuples: list[tuple[Chapter, KnowledgePoints | None]],
    adapter: Any | None,
) -> MergeReport:
    """Dedup intra-project ids and align course-collision ids in place.

    Idempotent. Call before ``build_sections`` so the emitted sections carry
    unified ids and ``CourseAdapter.merge_section_resources`` does not create
    duplicate terms. Returns the merger report for telemetry / display.
    """
    report = merge_knowledge_points(chapters_tuples, adapter)
    telemetry.record_event(
        "textbook.merge.applied",
        payload={
            "intra_project": report.intra_project_count,
            "course_collisions": report.course_collision_count,
        },
    )
    return report


def compute_import_previews(
    chapters_tuples: list[tuple[Chapter, KnowledgePoints | None]],
    built_sections: list[tuple[int, dict[str, Any]]],
    chapters: list[Any],
    adapter: Any | None,
    strategy: str,
) -> list[SectionImportPreview]:
    """Compute a read-only per-section import plan for the preview panel.

    Does not mutate chapter knowledge: the ``KnowledgeMerger`` is run in
    analyze-only mode so ``new_*`` / ``duplicate_*`` counts reflect the
    post-merge state the user will get on confirm. Section-id planning
    delegates to ``plan_bulk_import`` so the preview matches execution.
    """
    from src.backend.knowledge_merger import analyze as analyze_knowledge

    if not built_sections:
        return []
    sections = [s for _, s in built_sections]
    report = analyze_knowledge(chapters_tuples, adapter)
    plans = plan_bulk_import(sections, adapter, strategy)

    previews: list[SectionImportPreview] = []
    for (chapter_index, section), plan in zip(built_sections, plans):
        cr = chapters[chapter_index]
        kp = cr.knowledge
        words = len(kp.words) if kp else 0
        expressions = len(kp.expressions) if kp else 0
        grammar = len(kp.grammarPoints) if kp else 0
        dup_words = dup_expr = dup_gram = 0
        for col in report.collisions_for_chapter(chapter_index):
            if not col.target_id:
                continue
            if col.resource_type == "word":
                dup_words += 1
            elif col.resource_type == "expression":
                dup_expr += 1
            else:
                dup_gram += 1
        previews.append(
            SectionImportPreview(
                chapter_index=chapter_index,
                title=cr.chapter.title,
                source_id=plan.source_id,
                target_id=plan.target_id,
                exists=plan.exists,
                action=plan.action,
                word_count=words,
                expression_count=expressions,
                grammar_count=grammar,
                new_words=words - dup_words,
                new_expressions=expressions - dup_expr,
                new_grammar=grammar - dup_gram,
                duplicate_words=dup_words,
                duplicate_expressions=dup_expr,
                duplicate_grammar=dup_gram,
            )
        )
    return previews
