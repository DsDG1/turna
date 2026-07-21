#!/usr/bin/env python3
"""One-time split of monolithic kannada_lessons.json into per-section layout.

Produces assets/courses/turkish/{index.json, sections/<id>.json, vocab.json}.
Re-runnable: produces identical output from the same source file.
"""
import json
import os
import pathlib
import shutil

ROOT = pathlib.Path(__file__).resolve().parent.parent
LESSONS = ROOT / "assets/courses/kannada_lessons.json"
VOCAB = ROOT / "assets/courses/kannada_vocab.json"
OUT = ROOT / "assets/courses/turkish"


def _atomic_write_text(path: pathlib.Path, text: str) -> None:
    """Write text to ``path`` via a sibling tmp file + ``os.replace``.

    A crash mid-write to the tmp file cannot truncate the destination
    because the destination is only touched atomically by rename. (P8)
    """
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(text, encoding="utf-8")
    os.replace(tmp, path)


def main() -> None:
    src = json.loads(LESSONS.read_text(encoding="utf-8"))
    (OUT / "sections").mkdir(parents=True, exist_ok=True)

    index_sections = []
    for s in src["sections"]:
        section_path = OUT / "sections" / f"{s['id']}.json"
        _atomic_write_text(
            section_path,
            json.dumps(s, indent=2, ensure_ascii=False),
        )
        index_sections.append({
            "id": s["id"],
            "name": s["name"],
            "description": s.get("description", ""),
            "prerequisiteSectionIds": s.get("prerequisiteSectionIds", []),
            "file": f"sections/{s['id']}.json",
        })

    index = {
        "version": src["version"],
        "language": src["language"],
        "displayName": src["displayName"],
        "sections": index_sections,
    }
    _atomic_write_text(
        OUT / "index.json",
        json.dumps(index, indent=2, ensure_ascii=False),
    )

    # Re-wrap vocab into the object form the loader expects
    # ({"version":1,"language":..,"words":[...]}). A bare ``shutil.copyfile``
    # of a legacy bare-list kannada_vocab.json would leave the new course
    # with vocab.json in the wrong shape: ``load_vocab`` reads
    # ``data.get("words", [])`` and would silently return [] (B17).
    raw_vocab = json.loads(VOCAB.read_text(encoding="utf-8"))
    if isinstance(raw_vocab, list):
        words = raw_vocab
    elif isinstance(raw_vocab, dict):
        words = raw_vocab.get("words", [])
    else:
        words = []
    vocab_bundle = {
        "version": 1,
        "language": src.get("language", ""),
        "words": words,
    }
    _atomic_write_text(
        OUT / "vocab.json",
        json.dumps(vocab_bundle, indent=2, ensure_ascii=False),
    )
    print(f"Wrote {OUT}/index.json, {len(index_sections)} section files, vocab.json")


if __name__ == "__main__":
    main()