#!/usr/bin/env python3
"""Export a content inventory for the Turkish course.

Outputs a Markdown report listing all vocabulary, expressions, grammar points,
and where each is referenced inside lessons. This is the starting point for
future3 Phase 13: content audit and migration mapping.
"""

from __future__ import annotations

import json
from collections import defaultdict
from pathlib import Path
from typing import Any

COURSE_DIR = Path(__file__).resolve().parent.parent / "assets" / "courses" / "turkish"
OUTPUT = Path(__file__).resolve().parent.parent / "docs" / "content_inventory_current.md"


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def find_word_ids(obj: Any) -> set[str]:
    ids: set[str] = set()
    if isinstance(obj, dict):
        if obj.get("runtimeType") == "showWord" and "wordId" in obj:
            ids.add(obj["wordId"])
        if "linkedWordIds" in obj:
            ids.update(obj["linkedWordIds"])
        for value in obj.values():
            ids.update(find_word_ids(value))
    elif isinstance(obj, list):
        for item in obj:
            ids.update(find_word_ids(item))
    return ids


def find_expression_ids(obj: Any) -> set[str]:
    ids: set[str] = set()
    if isinstance(obj, dict):
        if obj.get("runtimeType") == "showExpression" and "expressionId" in obj:
            ids.add(obj["expressionId"])
        if "exampleExpressionIds" in obj:
            ids.update(obj["exampleExpressionIds"])
        for value in obj.values():
            ids.update(find_expression_ids(value))
    elif isinstance(obj, list):
        for item in obj:
            ids.update(find_expression_ids(item))
    return ids


def find_grammar_point_ids(obj: Any) -> set[str]:
    ids: set[str] = set()
    if isinstance(obj, dict):
        if "grammarPointId" in obj:
            ids.add(obj["grammarPointId"])
        if "linkedGrammarPointIds" in obj:
            ids.update(obj["linkedGrammarPointIds"])
        for value in obj.values():
            ids.update(find_grammar_point_ids(value))
    elif isinstance(obj, list):
        for item in obj:
            ids.update(find_grammar_point_ids(item))
    return ids


def find_audio_assets(obj: Any) -> set[str]:
    assets: set[str] = set()
    if isinstance(obj, dict):
        if "audioAsset" in obj and isinstance(obj["audioAsset"], str):
            assets.add(obj["audioAsset"])
        for value in obj.values():
            assets.update(find_audio_assets(value))
    elif isinstance(obj, list):
        for item in obj:
            assets.update(find_audio_assets(item))
    return assets


def collect_section_stats() -> list[dict[str, Any]]:
    """Per-section unit/lesson counts for scale-contract reporting."""
    index = load_json(COURSE_DIR / "index.json")
    rows: list[dict[str, Any]] = []
    for section in index.get("sections", []):
        section_id = section["id"]
        section_file = COURSE_DIR / section["file"]
        section_data = load_json(section_file)
        units = section_data.get("units", [])
        lesson_count = sum(len(u.get("lessons", [])) for u in units)
        max_lessons = max((len(u.get("lessons", [])) for u in units), default=0)
        rows.append(
            {
                "id": section_id,
                "name": section.get("name", section_data.get("name", "")),
                "units": len(units),
                "lessons": lesson_count,
                "max_lessons_per_unit": max_lessons,
            }
        )
    return rows


def collect_references() -> dict[str, dict[str, set[str]]]:
    index = load_json(COURSE_DIR / "index.json")
    refs: dict[str, dict[str, set[str]]] = defaultdict(lambda: defaultdict(set))

    for section in index.get("sections", []):
        section_id = section["id"]
        section_file = COURSE_DIR / section["file"]
        section_data = load_json(section_file)

        for unit in section_data.get("units", []):
            unit_id = unit["id"]
            for lesson in unit.get("lessons", []):
                lesson_id = lesson["id"]
                content = lesson.get("content", {})
                location = f"{section_id}/{unit_id}/{lesson_id}"

                for wid in find_word_ids(content):
                    refs["word"][wid].add(location)
                for eid in find_expression_ids(content):
                    refs["expression"][eid].add(location)
                for gid in find_grammar_point_ids(content):
                    refs["grammar"][gid].add(location)
                for asset in find_audio_assets(content):
                    refs["audio"][asset].add(location)

    return refs


def build_word_rows(refs: dict[str, dict[str, set[str]]]) -> list[dict[str, Any]]:
    vocab = load_json(COURSE_DIR / "vocab.json")
    words = vocab.get("words", [])
    by_id = {w["id"]: w for w in words}

    rows = []
    for wid in sorted(by_id.keys()):
        word = by_id[wid]
        rows.append(
            {
                "id": wid,
                "term": word.get("term", ""),
                "translation": word.get("translation", ""),
                "tags": ", ".join(word.get("tags", [])),
                "referenced_in": "; ".join(sorted(refs["word"].get(wid, {"(unused)"}))),
            }
        )
    return rows


def build_expression_rows(refs: dict[str, dict[str, set[str]]]) -> list[dict[str, Any]]:
    expressions = load_json(COURSE_DIR / "expressions.json")
    items = expressions.get("expressions", [])
    by_id = {e["id"]: e for e in items}

    rows = []
    for eid in sorted(by_id.keys()):
        expr = by_id[eid]
        rows.append(
            {
                "id": eid,
                "term": expr.get("term", ""),
                "translation": expr.get("translation", ""),
                "tags": ", ".join(expr.get("tags", [])),
                "referenced_in": "; ".join(sorted(refs["expression"].get(eid, {"(unused)"}))),
            }
        )
    return rows


def build_grammar_rows(refs: dict[str, dict[str, set[str]]]) -> list[dict[str, Any]]:
    grammar = load_json(COURSE_DIR / "grammar_points.json")
    points = grammar.get("grammarPoints", [])

    rows = []
    for gp in points:
        gid = gp["id"]
        rows.append(
            {
                "id": gid,
                "title": gp.get("title", ""),
                "referenced_in": "; ".join(sorted(refs["grammar"].get(gid, {"(unused)"}))),
            }
        )
    return rows


def render_markdown(
    word_rows: list[dict[str, Any]],
    expression_rows: list[dict[str, Any]],
    grammar_rows: list[dict[str, Any]],
    audio_assets: set[str],
    section_stats: list[dict[str, Any]] | None = None,
) -> str:
    section_stats = section_stats or []
    total_units = sum(s["units"] for s in section_stats)
    total_lessons = sum(s["lessons"] for s in section_stats)
    lines = [
        "# Content Inventory (Turkish Course)",
        "",
        f"> Generated from `{COURSE_DIR.relative_to(Path(__file__).resolve().parent.parent)}`.",
        "> This is a future3 Phase 13 artifact used to plan the content migration planning.",
        "",
        "## Summary",
        "",
        f"- Vocabulary entries: {len(word_rows)}",
        f"- Expression entries: {len(expression_rows)}",
        f"- Grammar points: {len(grammar_rows)}",
        f"- Distinct audio asset references: {len(audio_assets)}",
        f"- Vocabulary words referenced by at least one lesson: {sum(1 for r in word_rows if r['referenced_in'] != '(unused)')}",
        f"- Sections: {len(section_stats)}",
        f"- Units (all sections): {total_units}",
        f"- Lessons (all sections): {total_lessons}",
        "",
        "## Section scale (design contract: ≤60 units/section, ≤40 lessons/unit)",
        "",
        "| section | name | units | lessons | max lessons/unit |",
        "|---|---|---:|---:|---:|",
    ]
    for s in section_stats:
        lines.append(
            f"| {s['id']} | {s['name']} | {s['units']} | {s['lessons']} | "
            f"{s['max_lessons_per_unit']} |"
        )
    lines.extend(
        [
            "",
            "## Vocabulary",
            "",
            "| id | term | translation | tags | referenced in |",
            "|---|---|---|---|---|",
        ]
    )
    for row in word_rows:
        lines.append(
            f"| {row['id']} | {row['term']} | {row['translation']} | {row['tags']} | {row['referenced_in']} |"
        )

    lines.extend(
        [
            "",
            "## Expressions",
            "",
            "| id | term | translation | tags | referenced in |",
            "|---|---|---|---|---|",
        ]
    )
    for row in expression_rows:
        lines.append(
            f"| {row['id']} | {row['term']} | {row['translation']} | {row['tags']} | {row['referenced_in']} |"
        )

    lines.extend(
        [
            "",
            "## Grammar Points",
            "",
            "| id | title | referenced in |",
            "|---|---|---|",
        ]
    )
    for row in grammar_rows:
        lines.append(f"| {row['id']} | {row['title']} | {row['referenced_in']} |")

    lines.extend(
        [
            "",
            "## Audio Asset References",
            "",
            "| asset | referenced in |",
            "|---|---|",
        ]
    )
    for asset in sorted(audio_assets):
        locations = "; ".join(sorted(refs["audio"].get(asset, set())))
        lines.append(f"| {asset} | {locations} |")

    lines.append("")
    return "\n".join(lines)


def main() -> None:
    global refs
    refs = collect_references()
    section_stats = collect_section_stats()
    word_rows = build_word_rows(refs)
    expression_rows = build_expression_rows(refs)
    grammar_rows = build_grammar_rows(refs)
    audio_assets = set(refs["audio"].keys())

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(
        render_markdown(
            word_rows,
            expression_rows,
            grammar_rows,
            audio_assets,
            section_stats=section_stats,
        ),
        encoding="utf-8",
    )
    print(f"Wrote content inventory to {OUTPUT}")


if __name__ == "__main__":
    main()
