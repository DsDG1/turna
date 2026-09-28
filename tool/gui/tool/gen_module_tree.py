#!/usr/bin/env python3
"""Generate the tool/gui module tree embedded in README.md.

Why this exists
---------------
The README used to carry a hand-maintained ``### 模块目录映射`` tree. It
drifted: entries pointed at files that had moved layer
(``backend/credential_store.py`` → ``application/credential_store.py``), at
files that no longer exist (``dialogs/ai_generator_dialog.py``), and it
omitted whole packages (``i18n/``, ``infrastructure/``, ``teacher/``). A
hand-written inventory of a 300-file tree rots on every refactor.

This script derives the tree from the filesystem, so it cannot drift, and
``--check`` turns "is the README still true?" into a CI-verifiable question —
the same ratchet idea as ``check_ai_boundaries.py``.

Scope: package-level structure (what a reader needs to navigate the
architecture) with per-package ``.py`` counts and each package's docstring
summary. File-level detail is left to the filesystem — listing 300 files in a
README helps nobody.

Usage (repo root or any cwd)::

    python3 tool/gui/tool/gen_module_tree.py            # print the tree
    python3 tool/gui/tool/gen_module_tree.py --check    # exit 1 if README is stale
    python3 tool/gui/tool/gen_module_tree.py --write    # rewrite the README block

Exit codes:
    0 — tree generated, or README already up to date
    1 — ``--check`` found a stale README block
    2 — README has no ``<!-- module-tree:start -->`` marker pair
"""
from __future__ import annotations

import argparse
import ast
import re
import sys
from pathlib import Path

_GUI_ROOT = Path(__file__).resolve().parents[1]
_SRC = _GUI_ROOT / "src"
_README = _GUI_ROOT / "README.md"

START = "<!-- module-tree:start -->"
END = "<!-- module-tree:end -->"
FENCE = "`" * 3

# Marker matching is whitespace-tolerant on purpose: a hand-edited marker with
# a stray space used to defeat the plain-substring split and produced a second
# marker pair instead of a clean replacement.
_MARKED_BLOCK = re.compile(
    r"[ \t]*<!--\s*module-tree:start\s*-->[ \t]*\n.*?"
    r"[ \t]*<!--\s*module-tree:end\s*-->[ \t]*\n?",
    re.S,
)
# First-run bootstrap: the fenced block under the section heading.
_LEGACY_BLOCK = re.compile(
    r"(###\s*模块目录映射)[ \t]*\n(?:[ \t]*\n)*"
    + re.escape(FENCE) + r".*?" + re.escape(FENCE) + r"[ \t]*\n?",
    re.S,
)

# One-line purpose per top-level package. Kept here (not scraped from
# docstrings) because these are *editorial*: they say why the package exists,
# not just what it is called. Everything else in the tree is derived.
_PURPOSE = {
    "main.py": "程序主入口（--gallery 打开组件画廊）",
    "app.py": "MainWindow（宿主属性 + 委托方法）",
    "theme.py": "主题应用（调色板 + 密度 + UI 缩放）",
    "theme_tokens.py": "设计 token 单一真源（色/间距/圆角/字阶/层级/密度，Qt-free）",
    "icons": "vendored Lucide SVG + DPR 渲染/着色/缓存",
    "theme_styles": "模块化 QSS（builder 组装）",
    "application": "应用层：控制器 / 门面 / 命令 / 保存与校验管线",
    "backend": "后端：领域逻辑 + 数据 IO（Qt-free，禁 import UI）",
    "dialogs": "对话框与独立子窗口",
    "widgets": "可复用 UI 组件",
    "teacher": "教师模式：线性流程 / 题目卡 / 词表 / 模板编辑",
    "infrastructure": "横切设施：操作日志 / 遥测 / 滚轮防误触 / 屏幕适配",
    "i18n": "界面文案表（中文为主）",
}

_SIBLINGS = {
    "tests": "unittest 自动化测试套件（分档见 run_gui_tests.py）",
    "docs": "契约与设计文档（ai_refactor_contract.md 为门禁契约）",
    "tool": "门禁与生成脚本（check_ai_boundaries.py / gen_module_tree.py）",
}

_SKIP_DIRS = {"__pycache__"}
_SKIP_FILES = {"__init__.py"}


def _py_files(directory: Path) -> list[Path]:
    """All .py under a package, including its ``__init__.py``."""
    return sorted(
        p
        for p in directory.rglob("*.py")
        if not (_SKIP_DIRS & set(p.parts))
    )


def _subpackages(directory: Path) -> list[Path]:
    return sorted(
        p
        for p in directory.iterdir()
        if p.is_dir() and p.name not in _SKIP_DIRS and not p.name.startswith(".")
    )


def _first_docstring_line(path: Path) -> str:
    try:
        tree = ast.parse(path.read_text(encoding="utf-8", errors="replace"))
    except (OSError, SyntaxError):
        return ""
    doc = ast.get_docstring(tree) or ""
    first = doc.strip().splitlines()[0].strip() if doc.strip() else ""
    return first if len(first) <= 68 else first[:65] + "..."


def _count(directory: Path) -> int:
    return len(_py_files(directory))


def build_tree() -> str:
    """Return the generated tree block (without the HTML markers)."""
    if not _SRC.is_dir():
        raise SystemExit(f"error: source root not found: {_SRC}")

    lines: list[str] = ["```", "tool/gui/", "├── src/"]

    def emit(directory: Path, prefix: str, depth: int) -> list[str]:
        """Emit one package level.

        Files are listed only at ``depth == 0`` (the handful of root modules
        a reader must know about). Below that the tree stays at package
        granularity — expanding 300 files into the README would triple its
        length and help nobody navigate; the filesystem is the file index.
        """
        out: list[str] = []
        subs = _subpackages(directory)
        mods = (
            sorted(p for p in directory.glob("*.py") if p.name not in _SKIP_FILES)
            if depth == 0
            else []
        )
        entries = len(mods) + len(subs)
        for i, p in enumerate(mods):
            last = i == entries - 1
            branch = "└──" if last else "├──"
            note = _PURPOSE.get(p.name) or _first_docstring_line(p)
            out.append(f"{prefix}{branch} {p.name:<24}# {note}")
        for i, sub in enumerate(subs):
            last = i == entries - 1
            branch = "└──" if last else "├──"
            n = _count(sub)
            note = _PURPOSE.get(sub.name, "") if depth == 0 else _first_docstring_line(
                sub / "__init__.py"
            )
            head = f"{prefix}{branch} {sub.name + '/':<24}# {n} 个 .py"
            if note:
                head += f" — {note}"
            out.append(head)
            if depth == 0:
                out.extend(emit(sub, prefix + ("    " if last else "│   "), depth + 1))
        return out

    lines.extend(emit(_SRC, "│   ", 0))

    # Sibling directories a reader needs to know exist.
    present = [(n, note) for n, note in _SIBLINGS.items() if (_GUI_ROOT / n).is_dir()]
    for i, (name, note) in enumerate(present):
        last = i == len(present) - 1
        branch = "└──" if last else "├──"
        lines.append(f"{branch} {name + '/':<24}# {note}")
    lines.append("```")
    return "\n".join(lines)


def _readme_text() -> tuple[str, str]:
    """Return ``(text, newline)`` reading without newline translation.

    ``Path.read_text`` applies universal newlines, which would silently turn
    this CRLF README into an LF one on the first ``--write``. The repo
    convention is to preserve a file's existing line endings, so the newline
    is detected from the raw bytes and passed back explicitly.
    """
    if not _README.is_file():
        raise SystemExit(f"error: README not found: {_README}")
    raw = _README.read_bytes()
    newline = "\r\n" if b"\r\n" in raw else "\n"
    return raw.decode("utf-8").replace("\r\n", "\n"), newline


def _replace_block(text: str, tree: str) -> str | None:
    """Swap the generated tree into the README.

    Handles both the marked form and the legacy hand-written block that
    preceded it, so migrating needs no throwaway script. Exactly one marker
    pair ever exists afterwards.
    """
    block = f"{START}\n\n{tree}\n\n{END}\n"
    new_text, n = _MARKED_BLOCK.subn(lambda _m: block, text, count=1)
    if n:
        return new_text
    new_text, n = _LEGACY_BLOCK.subn(
        lambda m: m.group(1) + "\n\n" + block, text, count=1
    )
    if n:
        return new_text
    return None


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--check", action="store_true",
                       help="Exit 1 if the README block differs from the generated tree")
    group.add_argument("--write", action="store_true",
                       help="Rewrite the README block in place")
    args = parser.parse_args(argv)

    tree = build_tree()

    if not args.check and not args.write:
        print(tree)
        return 0

    text, newline = _readme_text()
    updated = _replace_block(text, tree)
    if updated is None:
        print(
            f"error: could not locate the README module tree — add {START} / {END} "
            f"markers around it, or a '### 模块目录映射' heading followed by a "
            f"fenced block",
            file=sys.stderr,
        )
        return 2

    if args.write:
        if updated == text:
            print("README module tree already up to date.")
            return 0
        with open(_README, "w", encoding="utf-8", newline=newline) as fh:
            fh.write(updated)
        print(f"rewrote module tree in {_README.name} (newline={newline!r})")
        return 0

    # --check
    if updated != text:
        print("README module tree is STALE — regenerate with:", file=sys.stderr)
        print("    python3 tool/gui/tool/gen_module_tree.py --write", file=sys.stderr)
        print(tree, file=sys.stderr)
        return 1
    print("README module tree is up to date.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
