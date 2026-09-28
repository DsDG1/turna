#!/usr/bin/env python3
"""Check that every markdown file under tool/gui/docs appears in docs/README.md.

Why this exists
---------------
`docs/archive/experienceai.md` was the *upstream spec* for four in-flight design
documents and was referenced by three test modules — while sitting in
``archive/`` with no index anywhere. Four of the six files in ``docs/`` and four
of the five in ``docs/archive/`` were referenced by nothing at all, so a reader
had no way to tell live spec from archaeology.

A generator would not help here: the one-line purpose of each document is
editorial. What *can* be checked mechanically is completeness — "no document is
an orphan" — which is exactly the failure that produced the mess. So this
asserts the invariant instead of rewriting the prose.

Usage::

    python3 tool/gui/tool/check_docs_index.py            # report orphans
    python3 tool/gui/tool/check_docs_index.py --quiet    # only the summary

Exit codes:
    0 — every document is indexed
    1 — at least one document is missing from docs/README.md
    2 — docs/README.md or the docs directory is missing
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

_GUI_ROOT = Path(__file__).resolve().parents[1]
_DOCS = _GUI_ROOT / "docs"
_INDEX = _DOCS / "README.md"


def _documents() -> list[Path]:
    """Every markdown file under docs/, excluding the index itself."""
    if not _DOCS.is_dir():
        return []
    return sorted(
        p
        for p in _DOCS.rglob("*.md")
        if p.name != "README.md" and "__pycache__" not in p.parts
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--quiet", action="store_true",
                        help="print only the summary line")
    args = parser.parse_args(argv)

    if not _DOCS.is_dir():
        print(f"error: docs directory not found: {_DOCS}", file=sys.stderr)
        return 2
    if not _INDEX.is_file():
        print(f"error: docs index not found: {_INDEX}", file=sys.stderr)
        return 2

    index_text = _INDEX.read_text(encoding="utf-8")
    docs = _documents()
    orphans: list[Path] = []
    for doc in docs:
        # Match on the path as written in the index, relative to docs/.
        rel = doc.relative_to(_DOCS).as_posix()
        if rel in index_text or f"./{rel}" in index_text or doc.name in index_text:
            continue
        orphans.append(doc)

    if not args.quiet:
        for doc in docs:
            rel = doc.relative_to(_DOCS).as_posix()
            mark = "ORPHAN" if doc in orphans else "  ok  "
            print(f"  [{mark}] {rel}")

    if orphans:
        print(f"\n{len(orphans)} document(s) missing from docs/README.md:",
              file=sys.stderr)
        for doc in orphans:
            print(f"  {doc.relative_to(_DOCS).as_posix()}", file=sys.stderr)
        print("Add a row to docs/README.md describing what each one is for.",
              file=sys.stderr)
        return 1

    print(f"docs index complete: {len(docs)} documents, 0 orphans")
    return 0


if __name__ == "__main__":
    sys.exit(main())
