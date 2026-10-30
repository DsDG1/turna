"""Tests for the auto-detecting chapter splitter (syllabus-tolerant)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.markdown_chopper import (
    heading_style,
    plain_unit_titles,
    promote_plain_headings,
    split_chapters,
    split_chapters_auto,
)


class HeadingStyleTest(unittest.TestCase):
    def test_atx_detected(self) -> None:
        self.assertEqual(heading_style("# Book\n\n## Chapter 1\n\n## Chapter 2\n"), "atx")

    def test_unit_words_detected(self) -> None:
        md = "Ünite 1: Tanışma\n\nMerhaba.\n\nÜnite 2: Aile\n\nAnne.\n"
        self.assertEqual(heading_style(md), "unit")

    def test_numbered_detected(self) -> None:
        md = "1. Tanışma\n\nMerhaba.\n\n2. Aile\n\nAnne.\n"
        self.assertEqual(heading_style(md), "numbered")

    def test_bold_detected(self) -> None:
        md = "**Ünite 1**\n\nMerhaba.\n\n**Ünite 2**\n\nAnne.\n"
        self.assertEqual(heading_style(md), "bold")

    def test_none_for_plain_prose(self) -> None:
        self.assertEqual(heading_style("Just a paragraph of text.\n"), "none")


class AutoSplitTest(unittest.TestCase):
    def test_atx_level_two_is_preferred(self) -> None:
        md = "# Book\n\nintro\n\n## One\n\nA\n\n## Two\n\nB\n"
        chapters = split_chapters_auto(md)
        self.assertEqual([c.title for c in chapters], ["One", "Two"])

    def test_level_three_only_document_still_splits(self) -> None:
        md = "### One\n\nA\n\n### Two\n\nB\n"
        chapters = split_chapters_auto(md)
        self.assertEqual([c.title for c in chapters], ["One", "Two"])
        self.assertEqual(chapters[0].level, 3)

    def test_numbered_syllabus_splits(self) -> None:
        md = (
            "1. Tanışma ve selamlaşma\n\n"
            "Öğrenci selamlaşır.\n\n"
            "2. Aile ve yakınlar\n\n"
            "Aile bireylerini tanıtır.\n\n"
            "3. Günlük rutin\n\n"
            "Saatleri söyler.\n"
        )
        chapters = split_chapters_auto(md)
        self.assertEqual(len(chapters), 3)
        self.assertEqual(chapters[1].title, "2. Aile ve yakınlar")

    def test_unit_word_syllabus_splits(self) -> None:
        md = (
            "Ünite 1: Tanışma\n\nHedef: selamlaşmak.\n\n"
            "Ünite 2: Aile\n\nHedef: aileyi tanıtmak.\n"
        )
        chapters = split_chapters_auto(md)
        self.assertEqual([c.title for c in chapters], ["Ünite 1: Tanışma", "Ünite 2: Aile"])

    def test_ordered_list_is_not_a_chapter_ladder(self) -> None:
        # Sentences end with a period, so this stays body text (one chapter
        # would be wrong too — a heading-less doc yields no chapters).
        md = (
            "Alışveriş metni.\n\n"
            "1. Ekmeği al.\n"
            "2. Sütü al.\n"
            "3. Meyveyi al.\n"
        )
        self.assertEqual(split_chapters_auto(md), [])

    def test_single_numbered_item_is_not_a_chapter(self) -> None:
        md = "Giriş\n\n1. Tek madde\n\nMetin devam ediyor.\n"
        self.assertEqual(split_chapters_auto(md), [])

    def test_deeper_numbering_stays_inside_chapter(self) -> None:
        md = (
            "1. Birinci ünite\n\n"
            "1.1 Alt başlık\n\n"
            "Metin.\n\n"
            "2. İkinci ünite\n\n"
            "1.1 Alt başlık\n\n"
            "Metin.\n"
        )
        chapters = split_chapters_auto(md)
        self.assertEqual(len(chapters), 2)
        self.assertIn("1.1 Alt başlık", chapters[0].markdown)

    def test_explicit_min_level_keeps_historical_behaviour(self) -> None:
        md = "# One\n\nA\n\n# Two\n\nB\n"
        self.assertEqual(len(split_chapters(md, 1)), 2)
        self.assertEqual(split_chapters_auto(md, min_level=1)[0].level, 1)

    def test_promote_returns_none_without_headings(self) -> None:
        self.assertIsNone(promote_plain_headings("plain text only\n"))


class UnitTitlesTest(unittest.TestCase):
    def test_plain_unit_titles_from_atx(self) -> None:
        md = "## One\n\nA\n\n## Two\n\nB\n"
        self.assertEqual(plain_unit_titles(md), ["One", "Two"])

    def test_plain_unit_titles_from_unit_words(self) -> None:
        md = "Ünite 1: Tanışma\n\nA\n\nÜnite 2: Aile\n\nB\n"
        self.assertEqual(plain_unit_titles(md), ["Ünite 1: Tanışma", "Ünite 2: Aile"])


if __name__ == "__main__":
    unittest.main()
