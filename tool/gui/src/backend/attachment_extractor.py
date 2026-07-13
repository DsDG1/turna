"""Extract local files into OpenAI-compatible message content pieces.

No PySide6 dependency — pure Python so it can be unit-tested without a GUI.
Supported file kinds:
- images (png, jpg, jpeg, gif, webp) -> base64 image_url
- PDF -> text extracted via PyPDF2
- Word (doc/docx) -> text extracted via python-docx
- plain text files -> UTF-8 text

Optional dependencies are imported lazily so the module can still be imported
when they are absent; extraction of the corresponding file type will fail
with a clear message.
"""
from __future__ import annotations

import base64
import mimetypes
from dataclasses import dataclass
from pathlib import Path
from typing import Any


@dataclass
class ExtractionResult:
    """Result of extracting a file into an OpenAI content piece."""

    content: dict[str, Any] | None = None
    error: str = ""

    @property
    def ok(self) -> bool:
        return self.content is not None and not self.error


IMAGE_EXTENSIONS = {".png", ".jpg", ".jpeg", ".gif", ".webp"}
TEXT_EXTENSIONS = {
    ".txt",
    ".md",
    ".csv",
    ".json",
    ".py",
    ".dart",
    ".yaml",
    ".yml",
    ".html",
    ".css",
    ".js",
    ".ts",
    ".xml",
}
DOCUMENT_EXTENSIONS = {".pdf", ".doc", ".docx"}
SUPPORTED_EXTENSIONS = IMAGE_EXTENSIONS | TEXT_EXTENSIONS | DOCUMENT_EXTENSIONS


def _image_content(path: Path) -> ExtractionResult:
    mime, _ = mimetypes.guess_type(str(path))
    if mime is None:
        mime = "application/octet-stream"
    try:
        data = path.read_bytes()
    except OSError as exc:
        return ExtractionResult(error=f"无法读取图片: {exc}")
    encoded = base64.b64encode(data).decode("ascii")
    return ExtractionResult(
        content={
            "type": "image_url",
            "image_url": {"url": f"data:{mime};base64,{encoded}"},
        }
    )


def _text_content(path: Path) -> ExtractionResult:
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError as exc:
        return ExtractionResult(error=f"无法按 UTF-8 读取文本文件: {exc}")
    except OSError as exc:
        return ExtractionResult(error=f"无法读取文件: {exc}")
    return ExtractionResult(content={"type": "text", "text": text})


def _pdf_content(path: Path) -> ExtractionResult:
    try:
        from PyPDF2 import PdfReader
    except ImportError:
        return ExtractionResult(
            error="缺少 PyPDF2 依赖，无法提取 PDF 文本。请运行 pip install PyPDF2。"
        )
    try:
        reader = PdfReader(str(path))
        parts: list[str] = []
        for page in reader.pages:
            page_text = page.extract_text()
            if page_text:
                parts.append(page_text)
        text = "\n".join(parts).strip()
        if not text:
            return ExtractionResult(error="PDF 未提取到文本（可能是扫描件或图片 PDF）。")
        return ExtractionResult(content={"type": "text", "text": text})
    except Exception as exc:  # noqa: BLE001
        return ExtractionResult(error=f"PDF 提取失败: {exc}")


def _word_content(path: Path) -> ExtractionResult:
    try:
        from docx import Document
    except ImportError:
        return ExtractionResult(
            error="缺少 python-docx 依赖，无法提取 Word 文本。请运行 pip install python-docx。"
        )
    try:
        doc = Document(str(path))
        paragraphs = [p.text for p in doc.paragraphs if p.text.strip()]
        text = "\n".join(paragraphs).strip()
        if not text:
            return ExtractionResult(error="Word 文档未提取到文本。")
        return ExtractionResult(content={"type": "text", "text": text})
    except Exception as exc:  # noqa: BLE001
        return ExtractionResult(error=f"Word 提取失败: {exc}")


def extract_attachment(path: Path) -> ExtractionResult:
    """Return an OpenAI-compatible content piece for the given file path.

    The caller is responsible for cleaning up the temporary file.
    """
    path = Path(path)
    if not path.exists():
        return ExtractionResult(error=f"文件不存在: {path}")
    ext = path.suffix.lower()
    if ext not in SUPPORTED_EXTENSIONS:
        return ExtractionResult(
            error=f"不支持的文件类型 {ext}。支持：图片、PDF、Word、纯文本文件。"
        )
    if ext in IMAGE_EXTENSIONS:
        return _image_content(path)
    if ext in TEXT_EXTENSIONS:
        return _text_content(path)
    if ext == ".pdf":
        return _pdf_content(path)
    if ext in (".doc", ".docx"):
        return _word_content(path)
    return ExtractionResult(error=f"未实现的文件类型: {ext}")


def summarize_attachment(path: Path) -> str:
    """Human-readable summary of the extraction result for UI display."""
    result = extract_attachment(path)
    if not result.ok:
        return f"[提取失败] {result.error}"
    content = result.content or {}
    if content.get("type") == "image_url":
        return "[图片]"
    text = str(content.get("text", ""))
    preview = text.replace("\n", " ")[:120]
    if len(text) > 120:
        preview += "..."
    return preview or "[空内容]"
