"""Shared sample course-section builders for tests.

These keep the literally-identical ``_section()`` helpers that were duplicated
across design_controller / design_panel / review_panel tests in sync.

``sample_section`` returns a hand-written minimal section dict (used by the
design/review panel tests). ``sample_section_from_chapter`` builds one via the
real ``build_section_from_chapter`` pipeline (used by the bulk-merge /
section-import service tests, which need a realistically-shaped section).
"""
from __future__ import annotations

from src.backend.knowledge_schema import coerce_knowledge_points  # noqa: E402
from src.backend.markdown_chopper import split_chapters  # noqa: E402
from src.backend.textbook_to_course import build_section_from_chapter  # noqa: E402


def sample_section(*, unit_id: str = "u", lesson_id: str = "l") -> dict:
    """Minimal hand-written greetings section with one unit/lesson + one word."""
    return {
        "id": "greetings",
        "name": "Greetings",
        "units": [
            {
                "id": unit_id,
                "name": "U1",
                "lessons": [
                    {
                        "id": lesson_id,
                        "name": "L1",
                        "template": "intro",
                        "content": {"subLessons": []},
                    }
                ],
            }
        ],
        "words": [{"id": "w-1", "term": "merhaba", "translation": "hello"}],
    }


def sample_section_from_chapter(section_id: str) -> dict:
    """Build a sample section via the real chapter pipeline, then set its id."""
    chapter = split_chapters("## 1 Merhaba\nhello\n")[0]
    kp = coerce_knowledge_points(
        {"words": [{"term": "merhaba", "translation": "hello"}]}
    )
    section = build_section_from_chapter(chapter, kp, 1)
    section["id"] = section_id
    return section