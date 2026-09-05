#!/usr/bin/env python3
"""Scan tool/gui AI layering violations (M0 boundary contract).

Checks:
1. Package-external imports of private ``_*`` symbols from
   ``src.backend.ai_generator`` or ``src.backend.ai*``.
2. ``src/dialogs/**`` imports of ``src.app`` (M3 debt; warn by default).
3. ``src/backend/**`` / ``src/application/**`` imports of ``src.app``
   (lower layers must read settings via ``src.application.runtime_context``).
4. ``src/backend/**`` imports of UI layers (widgets/dialogs/teacher/theme/app)
   — backend must stay UI-free.
5. Ratchet: count of silent ``except Exception: pass`` handlers in src must
   not exceed a ceiling (debt only shrinks, never grows).

Usage (repo root or any cwd)::

    python3 tool/gui/tool/check_ai_boundaries.py
    python3 tool/gui/tool/check_ai_boundaries.py --fail-private
    python3 tool/gui/tool/check_ai_boundaries.py --fail-dialogs-app
    python3 tool/gui/tool/check_ai_boundaries.py --fail-backend-app
    python3 tool/gui/tool/check_ai_boundaries.py --fail-backend-ui
    python3 tool/gui/tool/check_ai_boundaries.py --max-except-pass 0

Exit codes:
  0 — no failing checks (warns still print)
  1 — a requested --fail-* / --max-* check found violations
"""
from __future__ import annotations

import argparse
import ast
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
_UI_MODULES = r"(?:app|main|theme|theme_tokens|widgets|dialogs|teacher)"
_BACKEND_UI = re.compile(
    rf"^\s*(?:from\s+src\.{_UI_MODULES}(?:\.|\s+import\s)|import\s+src\.{_UI_MODULES}\b)",
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


def scan_lower_layer_app_imports() -> list[tuple[str, int, str]]:
    """backend/ or application/ importing src.app (reverse UI dependency)."""
    hits: list[tuple[str, int, str]] = []
    for layer in ("backend", "application"):
        root = _SRC / layer
        if not root.is_dir():
            continue
        for path in _iter_py(root):
            for n, line in enumerate(
                path.read_text(encoding="utf-8", errors="replace").splitlines(), 1
            ):
                if _DIALOGS_APP.search(line):
                    rel = path.relative_to(_GUI_ROOT).as_posix()
                    hits.append((rel, n, line.strip()[:160]))
    return hits


def scan_backend_ui_imports() -> list[tuple[str, int, str]]:
    """backend/ importing any UI-layer module (widgets/dialogs/teacher/theme/app)."""
    hits: list[tuple[str, int, str]] = []
    root = _SRC / "backend"
    if not root.is_dir():
        return hits
    for path in _iter_py(root):
        for n, line in enumerate(
            path.read_text(encoding="utf-8", errors="replace").splitlines(), 1
        ):
            if _BACKEND_UI.search(line):
                rel = path.relative_to(_GUI_ROOT).as_posix()
                hits.append((rel, n, line.strip()[:160]))
    return hits


def count_silent_except_pass() -> int:
    """Count ``except ...:`` handlers whose body is a bare ``pass`` (AST)."""
    total = 0
    for path in _iter_py(_SRC):
        try:
            tree = ast.parse(path.read_text(encoding="utf-8", errors="replace"))
        except SyntaxError:
            continue
        for node in ast.walk(tree):
            if isinstance(node, ast.ExceptHandler) and len(node.body) == 1 and isinstance(
                node.body[0], ast.Pass
            ):
                total += 1
    return total


def _declared_host_members() -> set[str]:
    """Names declared on the ExperienceHost protocol (or empty if absent)."""
    proto = _SRC / "application" / "experience_host.py"
    if not proto.is_file():
        return set()
    try:
        tree = ast.parse(proto.read_text(encoding="utf-8", errors="replace"))
    except SyntaxError:
        return set()
    names: set[str] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.ClassDef) and node.name == "ExperienceHost":
            for item in node.body:
                if isinstance(item, ast.AnnAssign) and isinstance(item.target, ast.Name):
                    names.add(item.target.id)
                elif isinstance(item, ast.FunctionDef):
                    names.add(item.name)
    return names


def scan_undeclared_host_access() -> list[tuple[str, int, str]]:
    """Files annotated with ExperienceHost must only touch declared members.

    Checks ``host._x`` / ``getattr(host, "_x"…)`` in any application module
    that imports the protocol; undeclared private access = contract drift.
    """
    declared = _declared_host_members()
    if not declared:
        return []
    hits: list[tuple[str, int, str]] = []
    root = _SRC / "application"
    for path in _iter_py(root):
        text = path.read_text(encoding="utf-8", errors="replace")
        if "ExperienceHost" not in text:
            continue
        try:
            tree = ast.parse(text)
        except SyntaxError:
            continue
        seen: dict[str, tuple[int, str]] = {}

        def _note(name: str, lineno: int, snippet: str) -> None:
            if name.startswith("_") and name not in declared:
                seen.setdefault(name, (lineno, snippet))

        for node in ast.walk(tree):
            if (
                isinstance(node, ast.Attribute)
                and isinstance(node.value, ast.Name)
                and node.value.id in ("host", "h")
            ):
                _note(node.attr, node.lineno, f"host.{node.attr}")
            if (
                isinstance(node, ast.Call)
                and isinstance(node.func, ast.Name)
                and node.func.id in ("getattr", "hasattr", "setattr")
                and node.args
                and isinstance(node.args[0], ast.Name)
                and node.args[0].id in ("host", "h")
                and len(node.args) > 1
                and isinstance(node.args[1], ast.Constant)
                and isinstance(node.args[1].value, str)
            ):
                _note(node.args[1].value, node.lineno,
                      f"{node.func.id}(host, \"{node.args[1].value}\")")
        for name, (lineno, snippet) in sorted(seen.items()):
            rel = path.relative_to(_GUI_ROOT).as_posix()
            hits.append((rel, lineno, snippet))
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
    parser.add_argument(
        "--fail-backend-app",
        action="store_true",
        help="Exit 1 if backend/ or application/ import src.app",
    )
    parser.add_argument(
        "--fail-backend-ui",
        action="store_true",
        help="Exit 1 if backend/ imports widgets/dialogs/teacher/theme/app",
    )
    parser.add_argument(
        "--max-except-pass",
        type=int,
        default=None,
        metavar="N",
        help="Exit 1 if silent `except: pass` count in src/ exceeds N "
        "(ratchet; current baseline 0)",
    )
    parser.add_argument(
        "--fail-undeclared-host-access",
        action="store_true",
        help="Exit 1 if ExperienceHost-annotated modules touch undeclared "
        "private host members",
    )
    args = parser.parse_args(argv)

    private = scan_private_imports()
    dialogs_app = scan_dialogs_app_imports()
    backend_app = scan_lower_layer_app_imports()
    backend_ui = scan_backend_ui_imports()
    except_pass = count_silent_except_pass()
    host_drift = scan_undeclared_host_access()

    print("=== AI boundary scan ===")
    print(f"gui root: {_GUI_ROOT}")
    print(f"private AI imports (package-external): {len(private)}")
    for rel, n, snip in private:
        print(f"  PRIV  {rel}:{n}: {snip}")
    print(f"dialogs → src.app imports: {len(dialogs_app)}")
    for rel, n, snip in dialogs_app:
        print(f"  DAPP  {rel}:{n}: {snip}")
    print(f"backend/application → src.app imports: {len(backend_app)}")
    for rel, n, snip in backend_app:
        print(f"  BAPP  {rel}:{n}: {snip}")
    print(f"backend → UI-layer imports: {len(backend_ui)}")
    for rel, n, snip in backend_ui:
        print(f"  BUI   {rel}:{n}: {snip}")
    print(f"undeclared host._x accesses: {len(host_drift)}")
    for rel, n, snip in host_drift:
        print(f"  HOST  {rel}:{n}: {snip}")
    print(f"silent except-pass handlers in src: {except_pass}")

    # Baseline summary for docs
    print("---")
    print(
        f"summary private={len(private)} dialogs_app={len(dialogs_app)} "
        f"backend_app={len(backend_app)} backend_ui={len(backend_ui)} "
        f"host_drift={len(host_drift)} except_pass={except_pass}"
    )

    rc = 0
    if args.fail_private and private:
        rc = 1
    if args.fail_dialogs_app and dialogs_app:
        rc = 1
    if args.fail_backend_app and backend_app:
        rc = 1
    if args.fail_backend_ui and backend_ui:
        rc = 1
    if args.fail_undeclared_host_access and host_drift:
        rc = 1
    if args.max_except_pass is not None and except_pass > args.max_except_pass:
        rc = 1
    return rc


if __name__ == "__main__":
    sys.exit(main())
