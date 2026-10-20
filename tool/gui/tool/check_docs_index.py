#!/usr/bin/env python3
"""Check the GUI document tree: index completeness and pointer liveness.

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

The second invariant is pointer liveness: a document that names a markdown file
which no longer exists sends the reader to a file that cannot be opened. This
is the failure mode that survives an index check — the index can be perfect
while every cross-reference inside the body points at nothing. Both invariants
are mechanical, so both are asserted here.

Usage::

    python3 tool/gui/tool/check_docs_index.py            # report findings
    python3 tool/gui/tool/check_docs_index.py --quiet    # only the summary

Exit codes:
    0 — every document is indexed and every pointer resolves
    1 — an unindexed document or an unresolved pointer was found
    2 — docs/README.md or the docs directory is missing
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

_GUI_ROOT = Path(__file__).resolve().parents[1]
_REPO_ROOT = _GUI_ROOT.parents[1]
_DOCS = _GUI_ROOT / "docs"
_INDEX = _DOCS / "README.md"

# Directories that hold build output or tool caches, never hand-written prose.
_SKIP_DIRS = {
    "__pycache__",
    ".pytest_cache",
    ".mypy_cache",
    ".ruff_cache",
    ".venv",
    "build",
    "dist",
    "node_modules",
}

# A line that says so explicitly is not a pointer.
_EXEMPT = ("不在本仓库内", "仓库外", "已删", "已移除", "已移至")

_NAME_RE = re.compile(r"`([A-Za-z0-9_\-./]+\.md)`")
_LINK_RE = re.compile(r"\[[^\]]*\]\(([^)\s]+)\)")


def _documents() -> list[Path]:
    """Every markdown file under docs/, excluding the index itself."""
    if not _DOCS.is_dir():
        return []
    return sorted(
        p
        for p in _DOCS.rglob("*.md")
        if p.name != "README.md" and "__pycache__" not in p.parts
    )


def _markdown_files() -> list[Path]:
    """Every markdown file in the GUI project, caches excluded."""
    return sorted(
        p
        for p in _GUI_ROOT.rglob("*.md")
        if not (_SKIP_DIRS & set(p.parts))
    )


def _resolve(base: Path, target: str) -> Path | None:
    """Resolve a relative target against a base directory."""
    clean = target.split("#", 1)[0].split("?", 1)[0]
    if not clean or clean.startswith(("/", "http:", "https:", "mailto:")):
        return None
    return (base / clean).resolve()


def _pointer_findings() -> list[str]:
    """Markdown references inside the GUI tree that resolve to nothing.

    A name written in backticks is resolved against three bases, because the
    GUI tree mixes them: the file that mentions it, the GUI project root, and
    the repository root. A link target is resolved against the file that
    contains it, because a link is an explicit path by construction.
    """
    findings: list[str] = []
    for doc in _markdown_files():
        try:
            text = doc.read_text(encoding="utf-8")
        except OSError:
            continue
        rel_doc = doc.relative_to(_GUI_ROOT).as_posix()
        for number, line in enumerate(text.splitlines(), 1):
            if any(marker in line for marker in _EXEMPT):
                continue
            # A link label is not a pointer; its target is checked below.
            prose = _LINK_RE.sub("", line)

            for match in _NAME_RE.finditer(prose):
                name = match.group(1)
                if any(
                    candidate is not None and candidate.exists()
                    for candidate in (
                        _resolve(doc.parent, name),
                        _resolve(_GUI_ROOT, name),
                        _resolve(_REPO_ROOT, name),
                    )
                ):
                    continue
                findings.append(f"{rel_doc}:{number}  names a missing file `{name}`")

            for match in _LINK_RE.finditer(line):
                target = match.group(1)
                resolved = _resolve(doc.parent, target)
                if resolved is None:
                    continue
                if not resolved.exists():
                    findings.append(f"{rel_doc}:{number}  link -> missing `{target}`")
    return findings


def _unbalanced_code_spans() -> list[str]:
    """Files whose inline code spans do not pair up.

    A sentence cut in half leaves an unclosed backtick behind. Counting
    backticks outside fenced blocks is language-independent and needs no
    wording rules, so it catches damage that reads like ordinary prose —
    an ADR that ends its line mid-identifier is invisible to a reader and
    to every other check here.
    """
    findings: list[str] = []
    for doc in _markdown_files():
        try:
            text = doc.read_text(encoding="utf-8")
        except OSError:
            continue
        rel_doc = doc.relative_to(_GUI_ROOT).as_posix()
        count = 0
        in_fence = False
        for raw in text.splitlines():
            stripped = raw.strip()
            if stripped.startswith("```"):
                in_fence = not in_fence
                continue
            if in_fence:
                continue
            count += raw.count("`")
        if count % 2 == 1:
            findings.append(f"{rel_doc}  has {count} backticks (odd) — a code span is left open")
    return findings


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

    pointers = _pointer_findings()
    unbalanced = _unbalanced_code_spans()

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

    if pointers:
        print(f"\n{len(pointers)} unresolved document pointer(s):",
              file=sys.stderr)
        for finding in pointers:
            print(f"  {finding}", file=sys.stderr)
        print("Point them at the surviving document, or say the file was removed.",
              file=sys.stderr)

    if unbalanced:
        print(f"\n{len(unbalanced)} file(s) with an unbalanced code span:",
              file=sys.stderr)
        for finding in unbalanced:
            print(f"  {finding}", file=sys.stderr)
        print("A sentence was cut in half — finish it.", file=sys.stderr)

    if orphans or pointers or unbalanced:
        return 1

    print(f"docs index complete: {len(docs)} documents, 0 orphans; "
          f"0 unresolved pointers; 0 unbalanced code spans")
    return 0


if __name__ == "__main__":
    sys.exit(main())
