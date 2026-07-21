"""Tests for split_chapter_windows (aiEnhance P4-1 sliding windows).

Covers: short-chapter single-window passthrough, paragraph-boundary splits,
window slug/title derivation, overlap repetition, and the unsplittable
single-oversized-paragraph fallback.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.markdown_chopper import split_chapter_windows, split_chapters  # noqa: E402


def _chapter(body: str, title: str = "1 Merhaba"):
    return split_chapters(f"## {title}\n{body}")[0]


def _paras(count: int) -> list[str]:
    # 56-char paragraphs; two fit under max_chars=120, three do not.
    return [f"para{i} " + "x" * 50 for i in range(count)]


class SplitChapterWindowsTest(unittest.TestCase):
    def test_short_chapter_returns_single_window_unchanged(self) -> None:
        ch = _chapter("merhaba means hello\n")
        windows = split_chapter_windows(ch, max_chars=8000)
        self.assertEqual(len(windows), 1)
        # The chapter itself is returned - no derived slug, no copy.
        self.assertIs(windows[0], ch)

    def test_non_positive_max_chars_disables_windowing(self) -> None:
        ch = _chapter("x" * 500)
        self.assertEqual(len(split_chapter_windows(ch, max_chars=0)), 1)
        self.assertEqual(len(split_chapter_windows(ch, max_chars=-5)), 1)

    def test_long_chapter_splits_at_paragraph_boundaries(self) -> None:
        paras = _paras(6)
        ch = _chapter("\n\n".join(paras))
        windows = split_chapter_windows(ch, max_chars=120, overlap_chars=0)
        self.assertGreater(len(windows), 1)
        for n, w in enumerate(windows, start=1):
            self.assertEqual(w.slug, f"{ch.slug}#w{n}")
            self.assertEqual(w.idx, ch.idx)
            self.assertEqual(w.level, ch.level)
        # No window body exceeds the cap when overlap is disabled.
        for w in windows:
            self.assertLessEqual(len(w.markdown), 120)
        # Every paragraph survives in exactly one window (no overlap).
        for p in paras:
            self.assertEqual(sum(p in w.markdown for w in windows), 1)

    def test_overlap_repeats_previous_window_tail(self) -> None:
        paras = _paras(6)
        ch = _chapter("\n\n".join(paras))
        windows = split_chapter_windows(ch, max_chars=120, overlap_chars=60)
        self.assertGreater(len(windows), 1)
        first_paras = set(windows[0].markdown.split("\n\n"))
        second_paras = windows[1].markdown.split("\n\n")
        # Window 2 opens with a paragraph that already closed window 1.
        self.assertIn(second_paras[0], first_paras)

    def test_overlap_zero_disables_repetition(self) -> None:
        paras = _paras(4)
        ch = _chapter("\n\n".join(paras))
        windows = split_chapter_windows(ch, max_chars=120, overlap_chars=0)
        bodies = [set(w.markdown.split("\n\n")) for w in windows]
        for i in range(len(bodies)):
            for j in range(i + 1, len(bodies)):
                self.assertFalse(bodies[i] & bodies[j])

    def test_single_oversized_paragraph_stays_whole(self) -> None:
        ch = _chapter("x" * 500)  # no blank line -> cannot split at a boundary
        windows = split_chapter_windows(ch, max_chars=100)
        self.assertEqual(len(windows), 1)
        self.assertEqual(windows[0].markdown, ch.markdown)

    def test_window_title_marks_part_number(self) -> None:
        paras = _paras(4)
        ch = _chapter("\n\n".join(paras))
        windows = split_chapter_windows(ch, max_chars=120, overlap_chars=0)
        total = len(windows)
        self.assertIn(f"第 1/{total} 部分", windows[0].title)
        self.assertIn(f"第 {total}/{total} 部分", windows[-1].title)


if __name__ == "__main__":
    unittest.main()
