#!/usr/bin/env python3
"""Scan tool/gui AI layering violations (M0 boundary contract).

Checks:
1. Package-external imports of private ``_*`` symbols from
   ``src.backend.ai_generator`` or ``src.backend.ai*``.
2. ``src/dialogs/**`` imports of ``src.app`` (M3 debt; warn by default).

Usage (repo root or any cwd)::

    python3 tool/gui/tool/check_ai_boundaries.py
    python3 tool/gui/tool/check_ai_boundaries.py --fail-private
    python3 tool/gui/tool/check_ai_boundaries.py --fail-dialogs-app

Exit codes:
  0 — no failing checks (warns still print)
  1 — a requested --fail-* check found violations
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

_GUI_ROOT = Path(__file__).resolve().parents[1]
_SRC = _GUI_ROOT / "src"

_PRIVATE_FROM = re.compile(
    r"from\s+(src\.backend\.ai_generator|src\.backend\.ai(?:\.\w+)?)\s+import\s+"
)
_NAME_TOKEN = re.compile(r"\b(_[A-Za-z]\w*)\b")
# Only match real import statements (not docstrings / comments that mention them).
_DIALOGS_APP = re.compile(
    r"^\s*(?:from\s+src\.app\s+import\s+|import\s+src\.app\b)",
    re.MULTILINE,
)


def _iter_py(root: Path):
    for p in root.rglob("*.py"):
        if "__pycache__" in p.parts:
            continue
        yield p


def _is_ai_impl(path: Path) -> bool:
    """True if path is the AI package or the compatibility shim."""
    rel = path.relative_to(_SRC).as_posix()
    if rel == "backend/ai_generator.py":
        return True
    if rel.startswith("backend/ai/"):
        return True
    return False


def scan_private_imports() -> list[tuple[str, int, str]]:
    """Return (path, line, snippet) for package-external private AI imports."""
    hits: list[tuple[str, int, str]] = []
    for path in _iter_py(_SRC):
        if _is_ai_impl(path):
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        # Multi-line import: crude join of continued parens
        lines = text.splitlines()
        i = 0
        while i < len(lines):
            line = lines[i]
            if _PRIVATE_FROM.search(line):
                block = line
                j = i
                if "(" in line and ")" not in line:
                    while j + 1 < len(lines) and ")" not in block:
                        j += 1
                        block += "\n" + lines[j]
                # names after import
                m = _PRIVATE_FROM.search(block)
                if m:
                    rest = block[m.end() :]
                    # strip parentheses
                    rest = rest.replace("(", " ").replace(")", " ")
                    names = _NAME_TOKEN.findall(rest)
                    # exclude __all__ style dunders
                    names = [n for n in names if not n.startswith("__")]
                    if names:
                        rel = path.relative_to(_GUI_ROOT).as_posix()
                        hits.append((rel, i + 1, f"{names} :: {block.strip()[:120]}"))
                i = j + 1
                continue
            i += 1
    return hits


def scan_dialogs_app_imports() -> list[tuple[str, int, str]]:
    hits: list[tuple[str, int, str]] = []
    dialogs = _SRC / "dialogs"
    if not dialogs.is_dir():
        return hits
    for path in _iter_py(dialogs):
        for n, line in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
            if _DIALOGS_APP.search(line):
                rel = path.relative_to(_GUI_ROOT).as_posix()
                hits.append((rel, n, line.strip()[:160]))
    return hits


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--fail-private",
        action="store_true",
        help="Exit 1 if any package-external private AI import exists",
    )
    parser.add_argument(
        "--fail-dialogs-app",
        action="store_true",
        help="Exit 1 if dialogs import src.app (M3 target)",
    )
    args = parser.parse_args(argv)

    private = scan_private_imports()
    dialogs_app = scan_dialogs_app_imports()

    print("=== AI boundary scan ===")
    print(f"gui root: {_GUI_ROOT}")
    print(f"private AI imports (package-external): {len(private)}")
    for rel, n, snip in private:
        print(f"  PRIV  {rel}:{n}: {snip}")
    print(f"dialogs → src.app imports: {len(dialogs_app)}")
    for rel, n, snip in dialogs_app:
        print(f"  DAPP  {rel}:{n}: {snip}")

    # Baseline summary for docs
    print("---")
    print(f"summary private={len(private)} dialogs_app={len(dialogs_app)}")

    rc = 0
    if args.fail_private and private:
        rc = 1
    if args.fail_dialogs_app and dialogs_app:
        rc = 1
    return rc


if __name__ == "__main__":
    sys.exit(main())
