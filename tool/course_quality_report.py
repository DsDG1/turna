from __future__ import annotations

import json
import re
from collections import Counter
from pathlib import Path
from typing import Any

from course_pedagogy import CHOICE_TYPES, PRODUCTION_TYPES, lesson_items, lesson_sub_lessons, sub_lesson_items

REPO = Path(__file__).resolve().parent.parent


def _iter_lessons(course_dir: Path):
    index = json.loads((course_dir / "index.json").read_text(encoding="utf-8"))
    for section_entry in index.get("sections", []):
        section = json.loads((course_dir / section_entry["file"]).read_text(encoding="utf-8"))
        for unit in section.get("units", []):
            for lesson in unit.get("lessons", []):
                location = f"{section_entry['id']}/{unit.get('id', '')}/{lesson.get('id', '')}"
                yield location, lesson


def _mentions(item: dict[str, Any], term: str) -> bool:
    if not term:
        return False
    text = json.dumps(item, ensure_ascii=False).casefold()
    return re.search(rf"(?<!\w){re.escape(term.casefold())}(?!\w)", text) is not None


def _media_kind(field: str) -> str:
    return "image" if field.lower().startswith("image") else "audio"


def _media_exists(course_dir: Path, asset: str, kind: str) -> bool | None:
    if "://" in asset:
        return None
    normalized = asset.replace("\\", "/").strip()
    if normalized.startswith("assets/"):
        path = REPO / normalized
    elif normalized.startswith("media/"):
        path = course_dir / normalized
    elif kind == "audio":
        path = REPO / "assets" / "sounds" / "listening" / f"{normalized}.mp3"
    else:
        path = REPO / normalized
    return path.is_file()


def build_quality_report(course_dir: Path) -> dict[str, Any]:
    vocab = json.loads((course_dir / "vocab.json").read_text(encoding="utf-8")).get("words", [])
    word_terms = {str(word["id"]): str(word.get("term") or "") for word in vocab if word.get("id")}
    word_stats = {
        word_id: {"first": "", "production": "", "review": "", "exposure_only": True}
        for word_id in word_terms
    }
    interaction_counts: Counter[str] = Counter()
    template_counts: Counter[str] = Counter()
    answer_positions: Counter[str] = Counter()
    activity_counts: Counter[str] = Counter()
    sublesson_lengths: list[dict[str, Any]] = []
    media: dict[tuple[str, str], dict[str, Any]] = {}
    listening_rows: list[dict[str, Any]] = []
    reading_rows: list[dict[str, Any]] = []
    review_rows: list[dict[str, Any]] = []
    seen_terms: set[str] = set()
    playable_nodes = 0

    for location, lesson in _iter_lessons(course_dir):
        items = lesson_items(lesson)
        template = str(lesson.get("template") or "legacy")
        template_counts[template] += 1
        sub_lessons = lesson_sub_lessons(lesson)
        if sub_lessons:
            for sub_lesson in sub_lessons:
                sub_items = sub_lesson_items(sub_lesson)
                if sub_items:
                    playable_nodes += 1
                sublesson_lengths.append(
                    {"id": sub_lesson.get("id", ""), "items": len(sub_items), "location": location}
                )
        elif items or (lesson.get("content") or {}).get("readingPassage"):
            playable_nodes += 1

        current_terms: set[str] = set()
        for item in items:
            runtime_type = str(item.get("runtimeType") or "")
            interaction_counts[runtime_type] += 1
            if runtime_type == "showWord":
                activity_counts["display"] += 1
            elif runtime_type in PRODUCTION_TYPES:
                activity_counts["production"] += 1
            else:
                activity_counts["recognition"] += 1
            if runtime_type in CHOICE_TYPES and type(item.get("correctIndex")) is int:
                answer_positions[str(item["correctIndex"])] += 1
            for word_id, term in word_terms.items():
                if not _mentions(item, term):
                    continue
                current_terms.add(term)
                stats = word_stats[word_id]
                if not stats["first"]:
                    stats["first"] = location
                if runtime_type == "showWord" and item.get("wordId") == word_id:
                    stats["exposure_only"] = False
                if runtime_type in PRODUCTION_TYPES and not stats["production"]:
                    stats["production"] = location
                if stats["first"] and stats["first"] != location and not stats["review"]:
                    stats["review"] = location

        if template == "review":
            unknown = sorted(current_terms - seen_terms)
            policy = (lesson.get("content") or {}).get("reviewPolicy") or {}
            review_rows.append(
                {
                    "location": location,
                    "pool": len(items),
                    "min": policy.get("minItems", "—"),
                    "max": policy.get("maxItems", "—"),
                    "unknown": unknown,
                }
            )
        seen_terms.update(current_terms)

        content = lesson.get("content") or {}
        if template == "listening":
            phases = content.get("listeningPhases") or []
            listening_rows.append(
                {
                    "location": location,
                    "phases": len(phases),
                    "missing_audio": sum(not str(phase.get("audioAsset") or "").strip() for phase in phases),
                    "missing_transcript": sum(not str(phase.get("transcript") or "").strip() for phase in phases),
                }
            )
        if template == "reading":
            passage = content.get("readingPassage") or {}
            linked = list(passage.get("linkedWordIds") or [])
            reading_rows.append(
                {
                    "location": location,
                    "paragraphs": len(passage.get("paragraphs") or []),
                    "linked_words": len(linked),
                    "missing_links": [word_id for word_id in linked if word_id not in word_terms],
                }
            )

        def walk_media(value: Any) -> None:
            if isinstance(value, dict):
                for field, child in value.items():
                    if field in {"audioAsset", "imageAsset"} and isinstance(child, str) and child.strip():
                        values = [child]
                    elif field in {"audioAssets", "imageAssets"} and isinstance(child, list):
                        values = [entry for entry in child if isinstance(entry, str) and entry.strip()]
                    else:
                        values = []
                    for asset in values:
                        kind = _media_kind(field)
                        key = (asset, kind)
                        row = media.setdefault(
                            key,
                            {"asset": asset, "kind": kind, "exists": _media_exists(course_dir, asset, kind), "locations": set()},
                        )
                        row["locations"].add(location)
                    walk_media(child)
            elif isinstance(value, list):
                for child in value:
                    walk_media(child)

        walk_media(content)

    return {
        "playable_nodes": playable_nodes,
        "interaction_counts": dict(sorted(interaction_counts.items())),
        "template_counts": dict(sorted(template_counts.items())),
        "answer_positions": dict(sorted(answer_positions.items())),
        "activity_counts": dict(sorted(activity_counts.items())),
        "sublesson_lengths": sublesson_lengths,
        "media": sorted(media.values(), key=lambda row: (row["kind"], row["asset"])),
        "words": word_stats,
        "listening": listening_rows,
        "reading": reading_rows,
        "reviews": review_rows,
    }


def render_quality_markdown(report: dict[str, Any]) -> str:
    lines = [
        "## Course Quality Metrics",
        "",
        f"- Playable nodes: {report['playable_nodes']}",
        f"- Interaction items: {sum(report['interaction_counts'].values())}",
        f"- Display / recognition / production: {report['activity_counts'].get('display', 0)} / {report['activity_counts'].get('recognition', 0)} / {report['activity_counts'].get('production', 0)}",
        f"- Choice answer positions: {report['answer_positions']}",
        f"- Lesson templates: {report['template_counts']}",
        "- Learning metrics: 未导入经学习者同意的真实记录，因此不报告完成率或学习效果。",
        "",
        "### SubLesson sizes",
        "",
        "| subLesson | items | location |",
        "|---|---:|---|",
    ]
    for row in report["sublesson_lengths"]:
        lines.append(f"| {row['id']} | {row['items']} | {row['location']} |")
    lines.extend(["", "### Interaction items", "", "| type | count |", "|---|---:|"])
    for runtime_type, count in report["interaction_counts"].items():
        lines.append(f"| {runtime_type} | {count} |")
    lines.extend(["", "### Vocabulary recurrence", "", "| word | first exposure | production | later lesson |", "|---|---|---|---|"])
    for word_id, row in report["words"].items():
        lines.append(f"| {word_id} | {row['first'] or '—'} | {row['production'] or '—'} | {row['review'] or '—'} |")
    lines.extend(["", "### Listening coverage", "", "| lesson | phases | missing audio | missing transcript |", "|---|---:|---:|---:|"])
    for row in report["listening"]:
        lines.append(f"| {row['location']} | {row['phases']} | {row['missing_audio']} | {row['missing_transcript']} |")
    lines.extend(["", "### Reading coverage", "", "| lesson | paragraphs | linked words | missing links |", "|---|---:|---:|---|"])
    for row in report["reading"]:
        lines.append(f"| {row['location']} | {row['paragraphs']} | {row['linked_words']} | {', '.join(row['missing_links']) or '—'} |")
    lines.extend(["", "### Review pools", "", "| lesson | pool | min | max | terms not seen before |", "|---|---:|---:|---:|---|"])
    for row in report["reviews"]:
        lines.append(f"| {row['location']} | {row['pool']} | {row['min']} | {row['max']} | {', '.join(row['unknown']) or '—'} |")
    lines.extend(["", "### Media existence", "", "| asset | kind | status | referenced in |", "|---|---|---|---|"])
    for row in report["media"]:
        status = "external" if row["exists"] is None else ("ok" if row["exists"] else "missing")
        lines.append(f"| {row['asset']} | {row['kind']} | {status} | {'; '.join(sorted(row['locations']))} |")
    lines.append("")
    return "\n".join(lines)
