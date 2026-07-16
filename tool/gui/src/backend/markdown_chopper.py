"""Split a textbook Markdown dump into chapters by heading level.

Pure-Python, no I/O. Used as the ②→③ step of the textbook import pipeline
(bookplan.md): MinerU yields a merged Markdown file, this module chops it into
``Chapter`` objects keyed by ``#{1..3}`` headings so the downstream knowledge
extractor can run per-chapter.
"""
from __future__ import annotations

import re
from dataclasses import dataclass

from src.backend.lesson_content import slugify

# Match ATX headings of level 1..3 at the start of a line.
_HEADING_RE = re.compile(r"^(#{1,3})\s+(.+?)\s*#*\s*$")


@dataclass
class Chapter:
    """One chopped chapter.

    ``idx`` is 1-based position among the chapters that survived ``min_level``.
    ``markdown`` includes the heading line itself plus all body lines up to the
    next heading at the same or shallower level (i.e. the next heading that
    opens a sibling/new chapter). Sub-headings deeper than the chapter's level
    stay inside its markdown.
    """

    idx: int
    level: int
    title: str
    slug: str
    markdown: str


def _parse_headings(md: str) -> list[tuple[int, int, str]]:
    """Return [(line_index, level, title)] for each ``#{1..3}`` line."""
    headings: list[tuple[int, int, str]] = []
    for i, line in enumerate(md.splitlines()):
        m = _HEADING_RE.match(line)
        if m:
            level = len(m.group(1))
            title = m.group(2).strip()
            headings.append((i, level, title))
    return headings


def split_chapters(md: str, min_level: int = 2) -> list[Chapter]:
    """Split Markdown ``md`` into chapters by heading.

    A heading at exactly ``min_level`` opens a new chapter. Deeper headings
    (level > ``min_level``) are treated as body content of the enclosing
    chapter — they do not start chapters. Shallower headings (level <
    ``min_level``, e.g. a ``#`` book title) act as boundaries: they end the
    current chapter but do not start one, and their following body lines are
    dropped unless absorbed into the next qualifying chapter.

    Returns an ordered list with ``idx`` starting at 1. An empty or
    heading-less document returns ``[]``.
    """
    if not md:
        return []
    lines = md.splitlines()
    headings = _parse_headings(md)
    if not headings:
        return []

    chapters: list[Chapter] = []
    # (heading_index_into_headings, end_line_exclusive)
    spans: list[tuple[int, int]] = []
    for h_i, (line_i, level, _title) in enumerate(headings):
        # Only headings at exactly min_level open a chapter. Deeper headings
        # belong to the enclosing chapter; shallower headings are boundaries.
        if level != min_level:
            continue
        end = len(lines)
        for nxt_i in range(h_i + 1, len(headings)):
            _, nxt_level, _ = headings[nxt_i]
            if nxt_level <= level:
                end = headings[nxt_i][0]
                break
        spans.append((h_i, end))

    for idx, (h_i, end) in enumerate(spans, start=1):
        line_i, level, title = headings[h_i]
        body = "\n".join(lines[line_i:end])
        # Reattach trailing newline if the slice originally had one.
        if end < len(lines) or md.endswith("\n"):
            body = body + "\n"
        chapters.append(
            Chapter(
                idx=idx,
                level=level,
                title=title,
                slug=slugify(title),
                markdown=body,
            )
        )
    return chapters