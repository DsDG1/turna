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
5. ``src/application/**`` / ``src/app.py`` imports of ``src.dialogs`` — the
   application layer must not reach into the dialogs UI package.
6. ``src/dialogs/**`` direct imports of ``backend.ai_pipeline`` /
   ``backend.ai_phased`` — dialogs must go through ``src.backend.ai.facade``.
7. Ratchet: count of silent ``except Exception: pass`` handlers in src must
   not exceed a ceiling (debt only shrinks, never grows).

Usage (repo root or any cwd)::

    python3 tool/gui/tool/check_ai_boundaries.py
    python3 tool/gui/tool/check_ai_boundaries.py --fail-private
    python3 tool/gui/tool/check_ai_boundaries.py --fail-dialogs-app
    python3 tool/gui/tool/check_ai_boundaries.py --fail-backend-app
    python3 tool/gui/tool/check_ai_boundaries.py --fail-backend-ui
    python3 tool/gui/tool/check_ai_boundaries.py --fail-app-dialogs
    python3 tool/gui/tool/check_ai_boundaries.py --fail-dialogs-pipeline
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
_TOOL_DIR = Path(__file__).resolve().parent

_PRIVATE_FROM = re.compile(
    r"from\s+(src\.backend\.ai_generator|src\.backend\.ai(?:\.\w+)?)\s+import\s+"
)
_NAME_TOKEN = re.compile(r"\b(_[A-Za-z]\w*)\b")
# Only match real import statements (not docstrings / comments that mention them).
_DIALOGS_APP = re.compile(
    r"^\s*(?:from\s+src\.app\s+import\s+|import\s+src\.app\b)",
    re.MULTILINE,
)
_APP_DIALOGS = re.compile(
    r"^\s*(?:from\s+src\.dialogs(?:\.\w+)*\s+import\s+|import\s+src\.dialogs\b)",
    re.MULTILINE,
)
_DIALOGS_PIPELINE = re.compile(
    r"^\s*from\s+src\.backend\.ai_(?:pipeline|phased)\s+import\s+",
    re.MULTILINE,
)
_UI_MODULES = r"(?:app|main|theme|theme_tokens|widgets|dialogs|teacher)"
_BACKEND_UI = re.compile(
    rf"^\s*(?:from\s+src\.{_UI_MODULES}(?:\.|\s+import\s)|import\s+src\.{_UI_MODULES}\b)",
    re.MULTILINE,
)
_BACKEND_QT = re.compile(
    r"^\s*(?:from\s+PySide6(?:\.\w+)*\s+import\s|import\s+PySide6\b)",
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
    return bool(rel.startswith("backend/ai/"))


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


def scan_app_dialogs_imports() -> list[tuple[str, int, str]]:
    """application/** or src/app.py importing the dialogs UI package.

    The application layer must not reach into ``src.dialogs`` (widgets/panels
    live above it); shared Qt plumbing belongs in ``src/application`` itself.
    """
    hits: list[tuple[str, int, str]] = []
    targets = [Path(_SRC) / "app.py"]
    app_root = _SRC / "application"
    if app_root.is_dir():
        targets.extend(_iter_py(app_root))
    for path in targets:
        if not path.is_file():
            continue
        for n, line in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
            if _APP_DIALOGS.search(line):
                rel = path.relative_to(_GUI_ROOT).as_posix()
                hits.append((rel, n, line.strip()[:160]))
    return hits


def scan_dialogs_pipeline_imports() -> list[tuple[str, int, str]]:
    """dialogs/** importing ai_pipeline / ai_phased directly.

    Dialogs must go through the ``src.backend.ai.facade`` entry point; the
    pipeline internals are not public API.
    """
    hits: list[tuple[str, int, str]] = []
    dialogs = _SRC / "dialogs"
    if not dialogs.is_dir():
        return hits
    for path in _iter_py(dialogs):
        for n, line in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
            if _DIALOGS_PIPELINE.search(line):
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


def scan_backend_qt_imports() -> list[tuple[str, int, str]]:
    """backend/ importing PySide6 directly (framework coupling, Qt-free rule)."""
    hits: list[tuple[str, int, str]] = []
    root = _SRC / "backend"
    if not root.is_dir():
        return hits
    for path in _iter_py(root):
        for n, line in enumerate(
            path.read_text(encoding="utf-8", errors="replace").splitlines(), 1
        ):
            if _BACKEND_QT.search(line):
                rel = path.relative_to(_GUI_ROOT).as_posix()
                hits.append((rel, n, line.strip()[:160]))
    return hits


# --- UI layer vs backend ---------------------------------------------------
# The layers that are supposed to talk to the application layer, which in turn
# owns the backend services. Every ``src.backend`` import from here is a bypass.
_UI_LAYERS = ("dialogs", "widgets", "teacher")
_BACKEND_IMPORT = re.compile(
    r"^\s*(?:from\s+src\.backend(?:\.\w+)*\s+import\s+|import\s+src\.backend\b)"
)
# ``course_cli`` may only be bound inside its designated gateway.
_COURSE_CLI_BIND = re.compile(r"^\s*(?:import\s+course_cli\b|from\s+[\w.]*\s+import\s+.*\bcourse_cli\b)")


def scan_ui_backend_imports() -> list[tuple[str, int, str]]:
    """Return (relpath, lineno, line) for every UI-layer -> src.backend import.

    Includes lazy (function-body) imports: they are still the UI layer reaching
    past the application facade, and three quarters of the existing edges are
    of that kind. A ratchet over this count is the migration signal — see
    ``--max-ui-backend-imports``.
    """
    hits: list[tuple[str, int, str]] = []
    for layer in _UI_LAYERS:
        root = _SRC / layer
        if not root.is_dir():
            continue
        for path in _iter_py(root):
            for n, line in enumerate(
                path.read_text(encoding="utf-8", errors="replace").splitlines(), 1
            ):
                if _BACKEND_IMPORT.search(line):
                    rel = path.relative_to(_GUI_ROOT).as_posix()
                    hits.append((rel, n, line.strip()[:160]))
    return hits


def scan_course_cli_bindings() -> list[tuple[str, int, str]]:
    """Modules binding the name ``course_cli`` outside ``src/backend/api.py``.

    ``api.py`` is the documented single gateway (it puts ``tool/`` on
    ``sys.path`` and re-exports the CLI surface). Anyone else binding that name
    — directly, or via ``from src.backend.api import course_cli`` — re-exports
    the CLI internals and breaks the contract.
    """
    gateway = (_SRC / "backend" / "api.py").resolve()
    hits: list[tuple[str, int, str]] = []
    for path in _iter_py(_SRC):
        if path.resolve() == gateway:
            continue
        for n, line in enumerate(
            path.read_text(encoding="utf-8", errors="replace").splitlines(), 1
        ):
            if _COURSE_CLI_BIND.search(line) and "course_cli" in line:
                rel = path.relative_to(_GUI_ROOT).as_posix()
                hits.append((rel, n, line.strip()[:160]))
    return hits


def _module_level_imports(path: Path) -> list[tuple[str, int]]:
    """(dotted module, lineno) for imports in the module body only.

    Function-body imports are skipped on purpose: several of them exist purely
    to break a cycle, so they are not evidence of a structural one.
    """
    try:
        tree = ast.parse(path.read_text(encoding="utf-8", errors="replace"))
    except (OSError, SyntaxError):
        return []
    out: list[tuple[str, int]] = []
    for node in tree.body:  # module level only
        if isinstance(node, ast.Import):
            for alias in node.names:
                out.append((alias.name, node.lineno))
        elif isinstance(node, ast.ImportFrom):
            if node.level or not node.module:
                continue
            out.append((node.module, node.lineno))
    return out


def _module_path(dotted: str) -> Path | None:
    parts = dotted.split(".")
    if not parts or parts[0] != "src":
        return None
    base = _SRC.joinpath(*parts[1:])
    if base.with_suffix(".py").is_file():
        return base.with_suffix(".py")
    if (base / "__init__.py").is_file():
        return base / "__init__.py"
    return None


def count_module_import_cycles() -> list[list[str]]:
    """Module-level import cycles inside src/ (Tarjan SCC over the import graph)."""
    graph: dict[str, set[str]] = {}
    for path in _iter_py(_SRC):
        rel = path.relative_to(_SRC).as_posix()
        key = rel[:-3] if rel.endswith(".py") else rel
        if key.endswith("/__init__"):
            key = key[: -len("/__init__")]
        targets: set[str] = set()
        for dotted, _line in _module_level_imports(path):
            target = _module_path(dotted)
            if target is None:
                continue
            trel = target.relative_to(_SRC).as_posix()
            tkey = trel[:-3] if trel.endswith(".py") else trel
            if tkey.endswith("/__init__"):
                tkey = tkey[: -len("/__init__")]
            if tkey != key:
                targets.add(tkey)
        graph[key] = targets

    # Tarjan strongly-connected components; anything with >1 member is a cycle.
    index: dict[str, int] = {}
    low: dict[str, int] = {}
    on_stack: set[str] = set()
    stack: list[str] = []
    counter = [0]
    cycles: list[list[str]] = []

    def strongconnect(v: str) -> None:
        # Iterative to survive deep graphs.
        work: list[tuple[str, list[str]]] = [(v, iter(sorted(graph.get(v, ()))))]
        index[v] = low[v] = counter[0]
        counter[0] += 1
        stack.append(v)
        on_stack.add(v)
        while work:
            node, it = work[-1]
            advanced = False
            for w in it:
                if w not in index:
                    index[w] = low[w] = counter[0]
                    counter[0] += 1
                    stack.append(w)
                    on_stack.add(w)
                    work.append((w, iter(sorted(graph.get(w, ())))))
                    advanced = True
                    break
                if w in on_stack:
                    low[node] = min(low[node], index[w])
            if advanced:
                continue
            if low[node] == index[node]:
                comp: list[str] = []
                while True:
                    w = stack.pop()
                    on_stack.discard(w)
                    comp.append(w)
                    if w == node:
                        break
                if len(comp) > 1 or node in graph.get(node, ()):
                    cycles.append(sorted(comp))
            work.pop()
            if work:
                parent = work[-1][0]
                low[parent] = min(low[parent], low[node])

    for node in sorted(graph):
        if node not in index:
            strongconnect(node)
    return sorted(cycles)


def _is_broad_except(t: ast.expr | None) -> bool:
    """True for silent-failure-class catches: bare ``except:``, ``except Exception``,
    ``except BaseException``, or a tuple containing one of those.

    Narrow handlers (``except KeyError:``, ``except RuntimeError:`` …) are
    deliberate, self-documenting control flow — a "skip the malformed item"
    or "is this C++ object still alive?" probe — and are NOT silent failures.
    Both the ``pass`` and the ``continue`` ratchets share this predicate so
    the two metrics cannot drift apart.
    """
    if t is None:
        return True
    names = (t.elts if isinstance(t, ast.Tuple) else [t])
    return any(
        isinstance(e, ast.Name) and e.id in ("Exception", "BaseException")
        for e in names
    )


def count_silent_except_pass() -> int:
    """Count broad ``except`` handlers whose body is a bare ``pass`` (AST).

    Breadth-filtered for the same reason as ``count_silent_except_continue``:
    a narrow ``except RuntimeError: pass`` used as an existence probe is not
    a swallowed failure. An empty ``pass`` is counted regardless of whether
    it carries an explanatory comment — the ratchet target is a logged
    handler (``logger.debug(..., exc_info=True)``), not a comment.
    """
    total = 0
    for path in _iter_py(_SRC):
        try:
            tree = ast.parse(path.read_text(encoding="utf-8", errors="replace"))
        except SyntaxError:
            continue
        for node in ast.walk(tree):
            if (
                isinstance(node, ast.ExceptHandler)
                and _is_broad_except(node.type)
                and len(node.body) == 1
                and isinstance(node.body[0], ast.Pass)
            ):
                total += 1
    return total


def count_broad_except() -> int:
    """Count broad ``except`` handlers in src (ratchet; debt only shrinks).

    Uses the same ``_is_broad_except`` predicate as the pass/continue ratchets
    so ``except (Exception, X)`` tuples cannot slip past on a technicality.
    """
    total = 0
    for path in _iter_py(_SRC):
        try:
            tree = ast.parse(path.read_text(encoding="utf-8", errors="replace"))
        except SyntaxError:
            continue
        for node in ast.walk(tree):
            if isinstance(node, ast.ExceptHandler) and _is_broad_except(node.type):
                total += 1
    return total


def count_silent_except_continue() -> int:
    """Count broad ``except`` handlers whose body is a bare ``continue`` (AST).

    Only flags broad catches (bare ``except:``, ``except Exception``,
    ``except BaseException``, or a tuple containing one) — the same
    silent-failure class as ``except: pass``. Narrow handlers like
    ``except KeyError: continue`` are legitimate skip-malformed-item
    idioms and are not counted. Shares ``_is_broad_except`` with
    ``count_silent_except_pass`` so the two ratchets stay aligned.
    """
    total = 0
    for path in _iter_py(_SRC):
        try:
            tree = ast.parse(path.read_text(encoding="utf-8", errors="replace"))
        except SyntaxError:
            continue
        for node in ast.walk(tree):
            if (
                isinstance(node, ast.ExceptHandler)
                and _is_broad_except(node.type)
                and len(node.body) == 1
                and isinstance(node.body[0], ast.Continue)
            ):
                total += 1
    return total


_HEX_COLOR = re.compile(r"#[0-9a-fA-F]{3,8}\b")
_PALETTE_HINT = re.compile(
    r"_pal\(|current_palette|ai_color|palette\(|_chat_palette|palette\["
)
# ``.get("token", "#hex")`` fallback literals are palette-driven — the hex
# only ships when the token is missing, so it must not count as hard-coded.
_GET_FALLBACK_HEX = re.compile(
    r"(\.get\([^)]*,\s*['\"])#[0-9a-fA-F]{3,8}(['\"])"
)


def count_hardcoded_style_hex() -> int:
    """Count ``setStyleSheet`` calls embedding a hex color with no palette use.

    Palette-driven inline styles stay themeable; hex literals without a
    palette lookup render the same color in every theme (dark-mode bugs).
    Ratchet: this count must not grow.
    """
    total = 0
    for path in _iter_py(_SRC):
        src = path.read_text(encoding="utf-8", errors="replace")
        try:
            tree = ast.parse(src)
        except SyntaxError:
            continue
        for node in ast.walk(tree):
            if (
                isinstance(node, ast.Call)
                and isinstance(node.func, ast.Attribute)
                and node.func.attr == "setStyleSheet"
            ):
                seg = ast.get_source_segment(src, node)
                if not seg:
                    continue
                seg_no_fallback = _GET_FALLBACK_HEX.sub(r"\1\2", seg)
                if _HEX_COLOR.search(seg_no_fallback) and not _PALETTE_HINT.search(seg):
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

        def _note(name: str, lineno: int, snippet: str,
                  seen: dict[str, tuple[int, str]] = seen) -> None:
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
        for _name, (lineno, snippet) in sorted(seen.items()):
            rel = path.relative_to(_GUI_ROOT).as_posix()
            hits.append((rel, lineno, snippet))
    return hits


def main(argv: list[str] | None = None) -> int:
    # Single source of truth for ratchet baselines: guard_limits.json next to
    # this script. CLI flags override, so experiments stay possible, but the
    # Makefile / workflows / contract doc no longer hand-copy the numbers.
    import json

    _LIMIT_KEYS = (
        "max_except_pass",
        "max_except_continue",
        "max_broad_except",
        "max_hardcoded_style_hex",
        "max_ui_backend_imports",
        "max_import_cycles",
    )

    limits: dict[str, int] = {}
    _limits_path = _TOOL_DIR / "guard_limits.json"
    _cli_args = sys.argv[1:] if argv is None else list(argv)
    if "--help" not in _cli_args and "-h" not in _cli_args:
        try:
            raw = json.loads(_limits_path.read_text(encoding="utf-8"))
            limits = {
                k: int(v)
                for k, v in raw.items()
                # Tolerate "_comment"-style annotation keys.
                if not k.startswith("_")
            }
            missing = [k for k in _LIMIT_KEYS if k not in limits]
            unknown = [
                k for k in limits if k not in _LIMIT_KEYS
            ]
            if missing or unknown:
                # A typo'd key silently disarms its check (flag default None
                # skips it) — refuse to run on a malformed limits file.
                print(
                    "guard_limits.json key mismatch:"
                    f" missing={missing} unknown={unknown}",
                    file=sys.stderr,
                )
                return 1
        except (OSError, ValueError) as exc:
            # The limits file is the single source of the ratchet numbers now
            # that Makefile/workflows stopped hand-passing them — a broken
            # file must fail loudly instead of silently disarming every
            # numeric check.
            print(f"guard_limits.json unreadable ({exc})", file=sys.stderr)
            return 1

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
        "--fail-app-dialogs",
        action="store_true",
        help="Exit 1 if application/ or src/app.py imports src.dialogs",
    )
    parser.add_argument(
        "--fail-dialogs-pipeline",
        action="store_true",
        help="Exit 1 if dialogs/ imports backend.ai_pipeline or backend.ai_phased",
    )
    parser.add_argument(
        "--fail-backend-qt",
        action="store_true",
        help="Exit 1 if backend/ imports PySide6 (Qt-free backend rule)",
    )
    parser.add_argument(
        "--max-except-pass",
        type=int,
        default=limits.get("max_except_pass"),
        metavar="N",
        help="Exit 1 if silent `except: pass` count in src/ exceeds N "
        "(ratchet; current baseline 0)",
    )
    parser.add_argument(
        "--max-broad-except",
        type=int,
        default=limits.get("max_broad_except"),
        metavar="N",
        help="Exit 1 if `except Exception` handler count in src/ exceeds N "
        "(ratchet; baseline recorded in ai_refactor_contract.md)",
    )
    parser.add_argument(
        "--max-except-continue",
        type=int,
        default=limits.get("max_except_continue"),
        metavar="N",
        help="Exit 1 if silent broad `except: continue` handler count in "
        "src/ exceeds N (ratchet; current baseline 0 — log before skipping)",
    )
    parser.add_argument(
        "--max-hardcoded-style-hex",
        type=int,
        default=limits.get("max_hardcoded_style_hex"),
        metavar="N",
        help="Exit 1 if inline setStyleSheet calls with a hex color and no "
        "palette lookup exceed N (ratchet)",
    )
    parser.add_argument(
        "--fail-undeclared-host-access",
        action="store_true",
        help="Exit 1 if ExperienceHost-annotated modules touch undeclared "
        "private host members",
    )
    parser.add_argument(
        "--fail-course-cli-binding",
        action="store_true",
        help="Exit 1 if any module other than src/backend/api.py binds the "
        "name course_cli (single-gateway contract)",
    )
    parser.add_argument(
        "--max-ui-backend-imports",
        type=int,
        default=limits.get("max_ui_backend_imports"),
        metavar="N",
        help="Exit 1 if the number of dialogs/widgets/teacher -> src.backend "
        "import statements exceeds N (ratchet; includes lazy imports)",
    )
    parser.add_argument(
        "--max-import-cycles",
        type=int,
        default=limits.get("max_import_cycles"),
        metavar="N",
        help="Exit 1 if the number of module-level import cycles inside src/ "
        "exceeds N (ratchet)",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Print every UI→backend edge instead of a per-layer breakdown",
    )
    args = parser.parse_args(argv)

    private = scan_private_imports()
    dialogs_app = scan_dialogs_app_imports()
    backend_app = scan_lower_layer_app_imports()
    backend_ui = scan_backend_ui_imports()
    backend_qt = scan_backend_qt_imports()
    except_pass = count_silent_except_pass()
    host_drift = scan_undeclared_host_access()
    app_dialogs = scan_app_dialogs_imports()
    dialogs_pipeline = scan_dialogs_pipeline_imports()
    broad_except = count_broad_except()
    except_continue = count_silent_except_continue()
    style_hex = count_hardcoded_style_hex()
    ui_backend = scan_ui_backend_imports()
    course_cli = scan_course_cli_bindings()
    cycles = count_module_import_cycles()

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
    print(f"backend → PySide6 imports: {len(backend_qt)}")
    for rel, n, snip in backend_qt:
        print(f"  BQT   {rel}:{n}: {snip}")
    print(f"application/app → dialogs imports: {len(app_dialogs)}")
    for rel, n, snip in app_dialogs:
        print(f"  ADLG  {rel}:{n}: {snip}")
    print(f"dialogs → ai_pipeline/ai_phased direct imports: {len(dialogs_pipeline)}")
    for rel, n, snip in dialogs_pipeline:
        print(f"  DPIP  {rel}:{n}: {snip}")
    print(f"undeclared host._x accesses: {len(host_drift)}")
    for rel, n, snip in host_drift:
        print(f"  HOST  {rel}:{n}: {snip}")
    print(f"silent except-pass handlers in src: {except_pass}")
    print(f"silent except-continue handlers in src: {except_continue}")
    print(f"broad `except Exception` handlers in src: {broad_except}")
    print(f"inline setStyleSheet with hex + no palette: {style_hex}")
    print(f"UI layer → src.backend import statements: {len(ui_backend)}")
    # Per-layer breakdown + a short sample: the full edge list is ~160 lines and
    # would bury every other metric in the CI log. `--verbose` prints them all.
    by_layer: dict[str, int] = {}
    for rel, _n, _s in ui_backend:
        layer = rel.split("/")[1] if rel.startswith("src/") else rel
        by_layer[layer] = by_layer.get(layer, 0) + 1
    if by_layer:
        print("  by layer: " + ", ".join(f"{k}={v}" for k, v in sorted(by_layer.items())))
    if args.verbose:
        for rel, n, snip in ui_backend:
            print(f"  UIBK  {rel}:{n}: {snip}")
    else:
        for rel, n, snip in ui_backend[:8]:
            print(f"  UIBK  {rel}:{n}: {snip}")
        if len(ui_backend) > 8:
            print(f"  UIBK  ... {len(ui_backend) - 8} more (use --verbose)")
    print(f"course_cli bound outside api.py: {len(course_cli)}")
    for rel, n, snip in course_cli:
        print(f"  CCLI  {rel}:{n}: {snip}")
    print(f"module-level import cycles in src: {len(cycles)}")
    for comp in cycles:
        print(f"  CYCLE {' -> '.join(comp)}")

    # Baseline summary for docs
    print("---")
    print(
        f"summary private={len(private)} dialogs_app={len(dialogs_app)} "
        f"backend_app={len(backend_app)} backend_ui={len(backend_ui)} "
        f"backend_qt={len(backend_qt)} "
        f"app_dialogs={len(app_dialogs)} dialogs_pipeline={len(dialogs_pipeline)} "
        f"host_drift={len(host_drift)} except_pass={except_pass} "
        f"except_continue={except_continue} "
        f"broad_except={broad_except} style_hex={style_hex} "
        f"ui_backend={len(ui_backend)} course_cli={len(course_cli)} "
        f"cycles={len(cycles)}"
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
    if args.fail_app_dialogs and app_dialogs:
        rc = 1
    if args.fail_dialogs_pipeline and dialogs_pipeline:
        rc = 1
    if args.fail_backend_qt and backend_qt:
        rc = 1
    if args.fail_undeclared_host_access and host_drift:
        rc = 1
    if args.fail_course_cli_binding and course_cli:
        rc = 1
    if args.max_except_pass is not None and except_pass > args.max_except_pass:
        rc = 1
    if args.max_broad_except is not None and broad_except > args.max_broad_except:
        rc = 1
    if args.max_except_continue is not None and except_continue > args.max_except_continue:
        rc = 1
    if args.max_hardcoded_style_hex is not None and style_hex > args.max_hardcoded_style_hex:
        rc = 1
    if args.max_ui_backend_imports is not None and len(ui_backend) > args.max_ui_backend_imports:
        rc = 1
    if args.max_import_cycles is not None and len(cycles) > args.max_import_cycles:
        rc = 1
    return rc


if __name__ == "__main__":
    sys.exit(main())
