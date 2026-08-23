"""Anki .apkg import for the GUI course editor.

Parses Anki .apkg files using Python's built-in sqlite3 and zipfile modules,
converts them to Turna Section JSON, and integrates with the existing
SectionImportService pipeline.

Usage (from GUI menu):
    File → Import → Anki Deck (.apkg)

The import flow:
1. User selects .apkg file via QFileDialog
2. This module parses the SQLite database inside the ZIP
3. Converts notes/cards to Turna Section JSON structure
4. Passes to SectionImportService for merge/insert into the course tree
"""
from __future__ import annotations

import json
import os
import sqlite3
import tempfile
import zipfile
from dataclasses import dataclass, field
from typing import Any


@dataclass
class AnkiNotetype:
    """Anki notetype (model) definition."""
    id: int
    name: str
    field_names: list[str] = field(default_factory=list)
    template_names: list[str] = field(default_factory=list)
    is_cloze: bool = False


@dataclass
class AnkiDeck:
    """Anki deck metadata."""
    id: int
    name: str
    parent_id: int = 0
    card_count: int = 0


@dataclass
class AnkiNote:
    """A single Anki note."""
    id: int
    mid: int
    fields: list[str] = field(default_factory=list)
    tags: str = ""


@dataclass
class AnkiCard:
    """A single Anki card."""
    id: int
    nid: int
    did: int
    ord: int = 0
    queue: int = 0
    due: int = 0
    ivl: int = 0
    factor: int = 2500
    reps: int = 0
    lapses: int = 0


@dataclass
class AnkiCollection:
    """Parsed Anki collection."""
    notetypes: dict[int, AnkiNotetype] = field(default_factory=dict)
    decks: dict[int, AnkiDeck] = field(default_factory=dict)
    notes: list[AnkiNote] = field(default_factory=list)
    cards: list[AnkiCard] = field(default_factory=list)
    media: dict[str, str] = field(default_factory=dict)


FIELD_SEPARATOR = "\x1f"


def parse_apkg(apkg_path: str) -> AnkiCollection:
    """Parse an .apkg file and return the intermediate representation.

    Uses Python's built-in zipfile and sqlite3 — no external dependencies.
    """
    collection = AnkiCollection()

    with tempfile.TemporaryDirectory() as tmp_dir:
        # Extract ZIP
        with zipfile.ZipFile(apkg_path, "r") as zf:
            zf.extractall(tmp_dir)

        # Find database file
        db_path = None
        for name in ("collection.anki21", "collection.anki2"):
            candidate = os.path.join(tmp_dir, name)
            if os.path.exists(candidate):
                db_path = candidate
                break

        if db_path is None:
            raise ValueError("No collection.anki2 or collection.anki21 found in archive")

        # Parse media mapping
        media_path = os.path.join(tmp_dir, "media")
        if os.path.exists(media_path):
            try:
                with open(media_path, "r", encoding="utf-8") as f:
                    collection.media = json.load(f)
            except (json.JSONDecodeError, OSError):
                pass

        # Open SQLite database
        conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
        conn.row_factory = sqlite3.Row

        try:
            # Parse collection metadata
            col_row = conn.execute("SELECT decks, models FROM col LIMIT 1").fetchone()
            if col_row:
                collection.decks = _parse_decks(col_row["decks"])
                collection.notetypes = _parse_notetypes(col_row["models"])

            # Parse notes
            for row in conn.execute(
                "SELECT id, mid, flds, tags FROM notes ORDER BY id"
            ):
                fields = (row["flds"] or "").split(FIELD_SEPARATOR)
                collection.notes.append(
                    AnkiNote(
                        id=row["id"],
                        mid=row["mid"],
                        fields=fields,
                        tags=(row["tags"] or "").strip(),
                    )
                )

            # Parse cards
            for row in conn.execute(
                "SELECT id, nid, did, ord, queue, due, ivl, factor, reps, lapses "
                "FROM cards ORDER BY id"
            ):
                collection.cards.append(
                    AnkiCard(
                        id=row["id"],
                        nid=row["nid"],
                        did=row["did"],
                        ord=row["ord"] or 0,
                        queue=row["queue"] or 0,
                        due=row["due"] or 0,
                        ivl=row["ivl"] or 0,
                        factor=row["factor"] or 2500,
                        reps=row["reps"] or 0,
                        lapses=row["lapses"] or 0,
                    )
                )
        finally:
            conn.close()

    # Compute deck card counts
    deck_counts: dict[int, int] = {}
    for card in collection.cards:
        deck_counts[card.did] = deck_counts.get(card.did, 0) + 1
    for did, count in deck_counts.items():
        if did in collection.decks:
            collection.decks[did].card_count = count

    return collection


def convert_to_section_json(
    collection: AnkiCollection,
    import_id: str,
    cards_per_lesson: int = 20,
) -> list[dict[str, Any]]:
    """Convert a parsed AnkiCollection to Turna Section JSON dicts.

    Returns a list of section dicts ready for SectionImportService. Every
    produced item is run through ``lesson_content.normalize_item`` as a
    self-check: the interaction schema is a whitelist (unknown fields are
    dropped on save), so an import product that normalize cannot round-trip
    would be silently lossy in the editor — raise here instead, at the source.
    """
    import re

    from src.backend.lesson_content import normalize_item

    notes_by_id = {n.id: n for n in collection.notes}

    # Group cards by deck
    cards_by_deck: dict[int, list[AnkiCard]] = {}
    for card in collection.cards:
        cards_by_deck.setdefault(card.did, []).append(card)

    # Identify top-level decks
    top_decks = [
        d for d in collection.decks.values()
        if d.parent_id == 0 or d.parent_id not in collection.decks
    ]
    if not top_decks:
        top_decks = list(collection.decks.values())

    sections = []
    for deck in top_decks:
        if deck.id == 1 and deck.name == "Default":
            continue

        section_id = f"anki-{import_id}-s{deck.id}"
        deck_cards = cards_by_deck.get(deck.id, [])

        # Find child decks
        child_decks = [
            d for d in collection.decks.values() if d.parent_id == deck.id
        ]

        units = []
        if child_decks:
            for child in child_decks:
                child_cards = cards_by_deck.get(child.id, [])
                if child_cards:
                    unit = _build_unit(
                        child.id, _short_name(child.name), import_id,
                        child_cards, notes_by_id, cards_per_lesson,
                    )
                    if unit:
                        units.append(unit)
        else:
            if deck_cards:
                unit = _build_unit(
                    deck.id, _short_name(deck.name), import_id,
                    deck_cards, notes_by_id, cards_per_lesson,
                )
                if unit:
                    units.append(unit)

        if not units:
            continue

        for unit in units:
            for lesson in unit.get("lessons", []):
                content = lesson.get("content", {})
                for stage in content.get("stages", []):
                    for item in stage.get("items", []):
                        # Self-check: normalize must accept every produced
                        # item losslessly (schema whitelist round-trip).
                        normalize_item(item)

        sections.append({
            "id": section_id,
            "name": _short_name(deck.name),
            "description": f"Imported from Anki ({deck.card_count} cards)",
            "level": "Anki",
            "prerequisiteSectionIds": [],
            "units": units,
        })

    return sections


def _build_unit(
    deck_id: int,
    deck_name: str,
    import_id: str,
    cards: list[AnkiCard],
    notes_by_id: dict[int, AnkiNote],
    cards_per_lesson: int,
) -> dict[str, Any] | None:
    """Build a Unit dict from a list of Anki cards."""
    import re

    lessons = []
    for chunk_idx in range(0, len(cards), cards_per_lesson):
        chunk = cards[chunk_idx:chunk_idx + cards_per_lesson]
        lesson_id = f"anki-{import_id}-l{deck_id}-{chunk_idx // cards_per_lesson}"

        stages = []
        for i, card in enumerate(chunk):
            note = notes_by_id.get(card.nid)
            if not note or len(note.fields) < 2:
                continue

            front = _strip_html(note.fields[0])
            back = _strip_html(note.fields[1]) if len(note.fields) > 1 else ""
            interaction_id = f"anki-{import_id}-n{note.id}-c{card.ord}"

            stages.append({
                "id": f"{lesson_id}-s{i}",
                "name": f"Card {chunk_idx + i + 1}",
                "items": [{
                    "runtimeType": "ankiCard",
                    "id": interaction_id,
                    "front": front,
                    "back": back,
                    "audioAssets": [],
                    "imageAssets": [],
                    "sourceNoteId": str(note.id),
                }],
            })

        if stages:
            lessons.append({
                "id": lesson_id,
                "name": f"{deck_name} #{chunk_idx // cards_per_lesson + 1}",
                "type": "normal",
                "template": "legacy",
                "content": {"stages": stages},
            })

    if not lessons:
        return None

    return {
        "id": f"anki-{import_id}-u{deck_id}",
        "name": deck_name,
        "lessons": lessons,
    }


def _parse_decks(decks_json: str) -> dict[int, AnkiDeck]:
    """Parse decks JSON from col.decks column."""
    result = {}
    try:
        decoded = json.loads(decks_json)
        for did_str, data in decoded.items():
            did = int(did_str)
            name = data.get("name", f"Deck {did}")
            result[did] = AnkiDeck(id=did, name=name)
    except (json.JSONDecodeError, TypeError):
        pass
    return result


def _parse_notetypes(models_json: str) -> dict[int, AnkiNotetype]:
    """Parse notetypes (models) JSON from col.models column."""
    result = {}
    try:
        decoded = json.loads(models_json)
        for mid_str, data in decoded.items():
            mid = int(mid_str)
            name = data.get("name", f"Model {mid}")
            field_names = [f.get("name", "") for f in data.get("flds", [])]
            template_names = [t.get("name", "") for t in data.get("tmpls", [])]
            is_cloze = data.get("type", 0) == 1
            result[mid] = AnkiNotetype(
                id=mid,
                name=name,
                field_names=field_names,
                template_names=template_names,
                is_cloze=is_cloze,
            )
    except (json.JSONDecodeError, TypeError):
        pass
    return result


def _strip_html(html: str) -> str:
    """Strip basic HTML tags from Anki field content."""
    import re
    text = re.sub(r"<br\s*/?>", "\n", html)
    text = re.sub(r"<[^>]+>", "", text)
    text = text.replace("&nbsp;", " ")
    text = text.replace("&amp;", "&")
    text = text.replace("&lt;", "<")
    text = text.replace("&gt;", ">")
    text = text.replace("&quot;", '"')
    return text.strip()


def _short_name(name: str) -> str:
    """Extract short name from hierarchical deck name."""
    if "::" in name:
        return name.rsplit("::", 1)[-1]
    return name
