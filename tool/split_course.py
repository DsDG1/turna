#!/usr/bin/env python3
"""One-time split of monolithic kannada_lessons.json into per-section layout.

Produces assets/courses/swahili/{index.json, sections/<id>.json, vocab.json}.
Re-runnable: produces identical output from the same source file.
"""
import json
import pathlib
import shutil

ROOT = pathlib.Path(__file__).resolve().parent.parent
LESSONS = ROOT / "assets/courses/kannada_lessons.json"
VOCAB = ROOT / "assets/courses/kannada_vocab.json"
OUT = ROOT / "assets/courses/swahili"


def main() -> None:
    src = json.loads(LESSONS.read_text(encoding="utf-8"))
    (OUT / "sections").mkdir(parents=True, exist_ok=True)

    index_sections = []
    for s in src["sections"]:
        section_path = OUT / "sections" / f"{s['id']}.json"
        section_path.write_text(
            json.dumps(s, indent=2, ensure_ascii=False), encoding="utf-8")
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
    (OUT / "index.json").write_text(
        json.dumps(index, indent=2, ensure_ascii=False), encoding="utf-8")

    shutil.copyfile(VOCAB, OUT / "vocab.json")
    print(f"Wrote {OUT}/index.json, {len(index_sections)} section files, vocab.json")


if __name__ == "__main__":
    main()