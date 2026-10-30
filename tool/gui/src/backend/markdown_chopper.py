"""Split a textbook Markdown dump into chapters by heading level.

Pure-Python, no I/O. Used as the ②→③ step of the textbook import pipeline
(bookplan.md): MinerU yields a merged Markdown file, this module chops it into
``Chapter`` objects keyed by ``#{1..3}`` headings so the downstream knowledge
extractor can run per-chapter.

Real course material is not always ATX-Markdown: a syllabus exported from Word
or a PDF-to-text pass keeps ``1.`` / ``1.2`` numbering, Turkish unit words
(``Ünite 1`` / ``Bölüm 2`` / ``Ders 3``) or bold-only lines. ``split_chapters_auto``
promotes those shapes to headings first, so the same extractor can run on a
textbook chapter and on a teaching syllabus without manual cleanup.
"""
from __future__ import annotations

import re
from collections import Counter
from dataclasses import dataclass

from src.backend.lesson_content import slugify

# Match ATX headings of level 1..3 at the start of a line.
_HEADING_RE = re.compile(r"^(#{1,3})\s+(.+?)\s*#*\s*$")

# --- plain-heading shapes (promoted to ``##`` by ``promote_plain_headings``) --
# ``1.`` / ``1.2`` / ``3)`` / ``4、`` at line start, followed by a title.
_NUMBERED_RE = re.compile(r"^\s*(\d{1,2}(?:\.\d{1,2}){0,2})\s*[\.\)、:：]?\s+(\S.*)$")
# Turkish / English / Chinese unit words: ``Ünite 1``, ``Bölüm 2: ...``,
# ``Unit 3``, ``Lesson 4``, ``第 2 章``.
_UNIT_WORD_RE = re.compile(
    r"^\s*(Ünite|Unite|Bölüm|Bolum|Ders|Unit|Lesson|Chapter|Module|Kapitel|"
    r"Lección|Leccion|单元|模块|第\s*\d+\s*[章节课])\s*(.*)$",
    re.IGNORECASE,
)
# ``**Ünite 1**`` / ``__Bölüm 2__`` — bold-only pseudo headings.
_BOLD_RE = re.compile(r"^\s*(?:\*\*|__)(.+?)(?:\*\*|__)\s*$")

#: A plain-heading line never ends like a sentence and never gets long.
_MAX_PLAIN_HEADING_CHARS = 90
_SENTENCE_ENDINGS = ("。", "！", "？", ".", "!", "?", "；", ";")


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
    for h_i, (_line_i, level, _title) in enumerate(headings):
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


def heading_style(md: str) -> str:
    """Return the heading convention of ``md``.

    ``"atx"`` when the document already has ``#`` headings, otherwise the
    plain shape that ``promote_plain_headings`` can lift: ``"unit"`` (Turkish /
    English unit words), ``"numbered"`` (``1.`` / ``1.2``) or ``"bold"``
    (``**...**``-only lines). ``"none"`` means no usable heading at all.
    """
    if not md:
        return "none"
    if _parse_headings(md):
        return "atx"
    kinds = {kind for _, kind, _ in _plain_heading_candidates(md)}
    for kind in ("unit", "numbered", "bold"):
        if kind in kinds:
            return kind
    return "none"


def _dominant_atx_level(headings: list[tuple[int, int, str]]) -> int:
    """Pick the ATX level that best represents chapters.

    Level 2 wins whenever a document has at least two of them (the historical
    default, and what an EPUB/PDF conversion produces for chapters). Otherwise
    the most frequent level is used, so a level-3-only dump still splits.
    """
    counts = Counter(level for _, level, _ in headings)
    if counts.get(2, 0) >= 2:
        return 2
    if counts.get(1, 0) >= 2:
        return 1
    return max(counts.items(), key=lambda item: (item[1], -item[0]))[0]


def _looks_like_heading_text(text: str) -> bool:
    """True when ``text`` reads like a heading rather than a sentence."""
    stripped = text.strip()
    if not stripped or len(stripped) > _MAX_PLAIN_HEADING_CHARS:
        return False
    if stripped.endswith(_SENTENCE_ENDINGS):
        return False
    return True


def _plain_heading_candidates(md: str) -> list[tuple[int, str, str]]:
    """Return ``(line_index, kind, title)`` for plain pseudo-heading lines."""
    lines = md.splitlines()
    out: list[tuple[int, str, str]] = []
    numbered: list[tuple[int, int, str, str]] = []  # (line, depth, num, rest)
    for i, line in enumerate(lines):
        stripped = line.strip()
        if not stripped or _HEADING_RE.match(line):
            continue
        bold = _BOLD_RE.match(stripped)
        if bold and _looks_like_heading_text(bold.group(1)):
            out.append((i, "bold", bold.group(1).strip()))
            continue
        unit = _UNIT_WORD_RE.match(stripped)
        if unit and _looks_like_heading_text(stripped):
            out.append((i, "unit", stripped))
            continue
        numbered_match = _NUMBERED_RE.match(stripped)
        if numbered_match and _looks_like_heading_text(stripped):
            num = numbered_match.group(1)
            numbered.append(
                (i, num.count("."), num, numbered_match.group(2).strip())
            )
    if numbered:
        # Only the shallowest numbering depth opens chapters; ``1.1`` under
        # ``1.`` is a sub-heading and stays inside its chapter body. A lone or
        # non-1-based run is far more likely to be an ordered list than a
        # chapter ladder, so it is left as body text.
        depth = min(item[1] for item in numbered)
        top_level = [item for item in numbered if item[1] == depth]
        first_number = _leading_int(top_level[0][2])
        if len(top_level) >= 2 and first_number == 1:
            for i, _item_depth, _num, _rest in top_level:
                out.append((i, "numbered", lines[i].strip()))
    out.sort(key=lambda item: item[0])
    return out


def _leading_int(numbering: str) -> int:
    """Return the first numeric segment of ``1.2.3`` as an int (0 on failure)."""
    try:
        return int(str(numbering).split(".", 1)[0])
    except (TypeError, ValueError):
        return 0


def promote_plain_headings(md: str) -> str | None:
    """Return ``md`` with plain pseudo-headings rewritten as ``##`` titles.

    Returns ``None`` when no plain heading is found (nothing to promote). The
    body text is untouched — only the heading line itself gains the ``##``
    prefix — so chapter markdown still contains the original wording.
    """
    candidates = _plain_heading_candidates(md)
    if not candidates:
        return None
    lines = md.splitlines()
    for line_index, kind, title in candidates:
        if kind == "bold":
            lines[line_index] = f"## {title}"
        else:
            lines[line_index] = f"## {title.lstrip('#').strip()}"
    return "\n".join(lines) + ("\n" if md.endswith("\n") else "")


def split_chapters_auto(md: str, min_level: int | None = None) -> list[Chapter]:
    """Split ``md`` into chapters, tolerating non-Markdown heading shapes.

    - ``min_level`` given: historical behaviour (``split_chapters``).
    - ATX headings present: the chapter level is auto-detected (level 2 when
      the document has at least two of them, else the dominant level).
    - No ATX headings: numbered / unit-word / bold pseudo-headings are
      promoted to ``##`` first. Documents with neither yield ``[]``.

    This is the entry point the textbook importer uses; ``split_chapters``
    keeps its explicit-level contract for callers that already know the shape.
    """
    if not md:
        return []
    headings = _parse_headings(md)
    if headings:
        level = min_level if min_level is not None else _dominant_atx_level(headings)
        chapters = split_chapters(md, level)
        # A syllabus often has ONE ``#`` document title plus a plain
        # ``Ünite 1`` / ``1.`` ladder. Splitting on the ATX heading would yield
        # a single chapter, so fall through to the plain-heading path.
        if min_level is None and len(chapters) < 2:
            promoted = promote_plain_headings(md)
            if promoted is not None:
                promoted_chapters = split_chapters(promoted, 2)
                if len(promoted_chapters) >= 2:
                    return promoted_chapters
        return chapters
    if min_level is not None:
        return split_chapters(md, min_level)
    promoted = promote_plain_headings(md)
    if promoted is None:
        return []
    return split_chapters(promoted, 2)


def plain_unit_titles(md: str) -> list[str]:
    """Return the chapter titles ``split_chapters_auto`` would produce.

    Used by the document profiler / syllabus reader to count units without
    building ``Chapter`` objects (they need ids and bodies they will not use).
    """
    if not md:
        return []
    headings = _parse_headings(md)
    atx_titles: list[str] = []
    if headings:
        level = _dominant_atx_level(headings)
        atx_titles = [title for _, lv, title in headings if lv == level]
        if len(atx_titles) >= 2:
            return atx_titles
    plain_titles = [
        title
        for _, kind, title in _plain_heading_candidates(md)
        if kind in ("unit", "numbered")
    ]
    if len(plain_titles) >= 2:
        return plain_titles
    return atx_titles


def split_chapter_windows(
    chapter: Chapter, max_chars: int, overlap_chars: int = 500
) -> list[Chapter]:
    """Split an over-long chapter into sliding windows at paragraph boundaries.

    P4-1 of the textbook-extraction enhancements (aiEnhance.md): instead of
    truncating a long chapter (and silently losing its tail), the extractor can
    walk these windows and merge the per-window results.

    - Chapters that already fit under ``max_chars`` (or a non-positive
      ``max_chars``) are returned as a single window — the chapter itself — so
      short-chapter behaviour is byte-for-byte unchanged.
    - Longer chapters are packed into windows of at most ~``max_chars`` at
      blank-line boundaries; every window after the first re-includes up to
      ``overlap_chars`` of the previous window's trailing paragraphs, so
      knowledge near a seam is seen twice and can be deduplicated downstream.
    - A chapter whose single paragraph exceeds the cap cannot be split at a
      paragraph boundary; it is returned whole (the extractor's truncation
      fallback still applies, as before).

    Window slugs are derived as ``{slug}#w{n}`` (1-based) and titles gain a
    ``（第 n/N 部分）`` suffix so per-window extraction stays traceable in
    prompts and logs; the merged result regenerates ids from the parent
    chapter's slug (see ``knowledge_extractor.merge_window_knowledge``).
    """
    if max_chars <= 0 or len(chapter.markdown) <= max_chars:
        return [chapter]

    paragraphs = chapter.markdown.split("\n\n")
    windows_md: list[str] = []
    current = ""
    for para in paragraphs:
        candidate = para if not current else f"{current}\n\n{para}"
        if current and len(candidate) > max_chars:
            windows_md.append(current)
            current = para
        else:
            current = candidate
    if current:
        windows_md.append(current)
    if len(windows_md) <= 1:
        return [chapter]

    total = len(windows_md)
    windows: list[Chapter] = []
    for n, body in enumerate(windows_md, start=1):
        if n > 1:
            overlap = _trailing_overlap(windows_md[n - 2], overlap_chars)
            if overlap:
                body = f"{overlap}\n\n{body}"
        windows.append(
            Chapter(
                idx=chapter.idx,
                level=chapter.level,
                title=f"{chapter.title}（第 {n}/{total} 部分）",
                slug=f"{chapter.slug}#w{n}",
                markdown=body,
            )
        )
    return windows


def _trailing_overlap(md: str, overlap_chars: int) -> str:
    """Return trailing paragraphs of ``md`` totalling at most ~``overlap_chars``."""
    if overlap_chars <= 0:
        return ""
    picked: list[str] = []
    total = 0
    for para in reversed(md.split("\n\n")):
        added = len(para) + (2 if picked else 0)
        if picked and total + added > overlap_chars:
            break
        picked.append(para)
        total += added
        if total >= overlap_chars:
            break
    return "\n\n".join(reversed(picked))
