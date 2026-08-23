"""Anki .apkg import pipeline tests (schema-sync plan P0.3).

Builds a tiny but real .apkg (SQLite collection inside a ZIP) with Python's
stdlib only, runs it through parse_apkg -> convert_to_section_json, and
asserts the produced ankiCard items round-trip through the interaction
schema — the self-check inside convert_to_section_json must accept them
losslessly (schema whitelist = save path).
"""
from __future__ import annotations

import json
import os
import sqlite3
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.anki_import import (  # noqa: E402
    AnkiCard,
    AnkiCollection,
    AnkiDeck,
    AnkiNote,
    AnkiNotetype,
    _strip_html,
    convert_to_section_json,
    parse_apkg,
)
from src.backend.lesson_content import normalize_item  # noqa: E402

FIELD_SEPARATOR = "\x1f"


def _build_collection() -> AnkiCollection:
    col = AnkiCollection()
    col.notetypes[1] = AnkiNotetype(id=1, name="Basic", field_names=["Front", "Back"])
    col.decks[1] = AnkiDeck(id=1, name="Default")
    # Top-level deck (parent 0) so convert_to_section_json emits a section.
    col.decks[2] = AnkiDeck(id=2, name="Turkish::Greetings", parent_id=0)
    for i in range(1, 4):
        col.notes.append(
            AnkiNote(
                id=1700000000 + i,
                mid=1,
                fields=[f"word {i}", f"translation {i}"],
                tags="",
            )
        )
        col.cards.append(AnkiCard(id=1800000000 + i, nid=1700000000 + i, did=2, ord=0))
    return col


def _write_apkg(path: Path) -> None:
    """Write a minimal .apkg: collection.anki2 + media manifest in a ZIP."""
    db_path = path.parent / "collection.anki2"
    conn = sqlite3.connect(db_path)
    conn.executescript(
        """
        CREATE TABLE col (
            id INTEGER PRIMARY KEY, crt INTEGER, mod INTEGER, scm INTEGER,
            ver INTEGER, dty INTEGER, usn INTEGER, ls INTEGER, conf TEXT,
            models TEXT, decks TEXT, dconf TEXT, tags TEXT
        );
        CREATE TABLE notes (
            id INTEGER PRIMARY KEY, guid TEXT, mid INTEGER, mod INTEGER,
            usn INTEGER, tags TEXT, flds TEXT, sfld TEXT, csum INTEGER,
            flags INTEGER, data TEXT
        );
        CREATE TABLE cards (
            id INTEGER PRIMARY KEY, nid INTEGER, did INTEGER, ord INTEGER,
            mod INTEGER, usn INTEGER, type INTEGER, queue INTEGER,
            due INTEGER, ivl INTEGER, factor INTEGER, reps INTEGER,
            lapses INTEGER, left INTEGER, odue INTEGER, odid INTEGER,
            flags INTEGER, data TEXT
        );
        """
    )
    models = {
        "1": {
            "id": 1,
            "name": "Basic",
            "type": 0,
            "flds": [{"name": "Front"}, {"name": "Back"}],
            "tmpls": [{"name": "Card 1"}],
        }
    }
    decks = {
        "1": {"id": 1, "name": "Default"},
        "2": {"id": 2, "name": "Turkish::Greetings"},
    }
    conn.execute(
        "INSERT INTO col (id, models, decks) VALUES (0, ?, ?)",
        (json.dumps(models), json.dumps(decks)),
    )
    for i in range(1, 4):
        nid = 1700000000 + i
        conn.execute(
            "INSERT INTO notes (id, guid, mid, flds) VALUES (?, ?, 1, ?)",
            (nid, f"guid{i}", FIELD_SEPARATOR.join([f"word {i}", f"translation {i}"])),
        )
        conn.execute(
            "INSERT INTO cards (id, nid, did, ord) VALUES (?, ?, 2, 0)",
            (1800000000 + i, nid),
        )
    conn.commit()
    conn.close()

    with zipfile.ZipFile(path, "w") as zf:
        zf.write(db_path, "collection.anki2")
        zf.writestr("media", json.dumps({}))
    db_path.unlink()


class ParseApkgTest(unittest.TestCase):
    def test_parse_apkg_reads_decks_notes_cards(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            apkg = Path(tmp) / "deck.apkg"
            _write_apkg(apkg)
            col = parse_apkg(str(apkg))
        self.assertIn(2, col.decks)
        self.assertEqual(col.decks[2].name, "Turkish::Greetings")
        self.assertEqual(len(col.notes), 3)
        self.assertEqual(col.notes[0].fields, ["word 1", "translation 1"])
        self.assertEqual(len(col.cards), 3)


class ConvertToSectionTest(unittest.TestCase):
    def test_convert_produces_anki_card_items(self) -> None:
        sections = convert_to_section_json(_build_collection(), "imp1")
        self.assertEqual(len(sections), 1)
        section = sections[0]
        self.assertEqual(section["id"], "anki-imp1-s2")
        unit = section["units"][0]
        self.assertEqual(unit["id"], "anki-imp1-u2")
        lesson = unit["lessons"][0]
        self.assertEqual(lesson["template"], "legacy")
        items = [
            item
            for stage in lesson["content"]["stages"]
            for item in stage["items"]
        ]
        self.assertEqual(len(items), 3)
        first = items[0]
        self.assertEqual(first["runtimeType"], "ankiCard")
        self.assertEqual(first["front"], "word 1")
        self.assertEqual(first["back"], "translation 1")
        self.assertEqual(first["id"], "anki-imp1-n1700000001-c0")
        self.assertEqual(first["sourceNoteId"], "1700000001")

    def test_convert_items_pass_normalize_self_check(self) -> None:
        # convert_to_section_json runs normalize_item internally as a
        # self-check (raises on unknown shape); assert the whitelist contract
        # here: every produced field survives normalize untouched, defaults
        # only fill gaps, and a second normalize is a no-op.
        sections = convert_to_section_json(_build_collection(), "imp1")
        for section in sections:
            for unit in section["units"]:
                for lesson in unit["lessons"]:
                    for stage in lesson["content"]["stages"]:
                        for item in stage["items"]:
                            normalized = normalize_item(item)
                            for key, value in item.items():
                                self.assertEqual(
                                    normalized.get(key), value,
                                    f"field {key} lost through normalize",
                                )
                            self.assertEqual(
                                normalize_item(normalized), normalized,
                                "normalize must be idempotent",
                            )

    def test_cards_per_lesson_chunking(self) -> None:
        sections = convert_to_section_json(
            _build_collection(), "imp1", cards_per_lesson=2
        )
        lessons = sections[0]["units"][0]["lessons"]
        self.assertEqual(len(lessons), 2)
        self.assertEqual(len(lessons[0]["content"]["stages"]), 2)
        self.assertEqual(len(lessons[1]["content"]["stages"]), 1)


class StripHtmlTest(unittest.TestCase):
    def test_strip_html_brs_and_entities(self) -> None:
        self.assertEqual(_strip_html("a<br>b<br/>c"), "a\nb\nc")
        self.assertEqual(_strip_html("<b>bold</b>"), "bold")
        self.assertEqual(_strip_html("a &amp; b &lt;c&gt;"), "a & b <c>")
        self.assertEqual(_strip_html("  spaced  "), "spaced")


if __name__ == "__main__":
    unittest.main()
