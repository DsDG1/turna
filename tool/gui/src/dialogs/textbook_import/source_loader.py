"""Source file reading, attachment extraction, and chapter splitting for textbook import."""
from __future__ import annotations

from pathlib import Path
from typing import Callable

from src.backend.attachment_extractor import extract_attachment
from src.backend.import_step_result import ImportStepResult
from src.backend.markdown_chopper import Chapter, split_chapters


def read_source_text(path: Path) -> str:
    """Read text from a .md/.txt file or extract it from a text PDF.

    Raises ``OSError`` for filesystem errors and ``RuntimeError`` for
    parse/extraction errors so both sync and async callers can share the
    same message conversion.
    """
    suffix = path.suffix.lower()
    if suffix in (".md", ".txt"):
        return path.read_text(encoding="utf-8")

    result = extract_attachment(path)
    if not result.ok:
        raise RuntimeError(
            f"{result.error}\n建议改用 .md/.txt，或使用文本原生 PDF（扫描件暂不支持）。"
        )
    text = result.content.get("text", "") if result.content else ""
    if not text.strip():
        raise RuntimeError("PDF 未提取到文本（可能是扫描件）。")
    return text


def validate_source_path(path: Path) -> ImportStepResult | None:
    """Validate that the source file exists and has a supported extension.

    Returns None if valid, or an error ImportStepResult if invalid.
    """
    if not path.exists():
        return ImportStepResult.error("pick", f"文件不存在：{path}")
    suffix = path.suffix.lower()
    if suffix not in (".md", ".txt", ".pdf"):
        return ImportStepResult.error(
            "pick",
            "不支持的文件类型，请选择 .md / .txt / .pdf。",
            recoverable=True,
            recovery_options=["重新选择"],
        )
    return None


def split_markdown_into_chapters(md_text: str) -> list[Chapter]:
    """Split raw markdown text into Chapter objects."""
    return split_chapters(md_text)
