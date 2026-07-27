"""M-03 OCR suggestion skill (pure Python, no Qt).

Read-only Experience skill: when an image attachment carries no extracted
text, run local OCR (``pytesseract`` + system ``tesseract``) on the
attachment's temp file and turn the recognized text into a new text-class
``AttachmentRecord`` that re-enters the M-01 workshop link. Nothing is
written to the course tree - no ConflictGuard, no sandbox, no undo, no
``dangerous`` flag. OCR is a local, offline operation (zero network, zero
LLM cost).

红线（§14.5.3 M-03）：
* 纯函数构造建议 / 归一状态；无 Qt、不写树、不写盘（OCR 文本只经工坊
  ``AttachmentRecord`` 回流，不进 Context/telemetry）。
* OCR 抽出文本 / 文件路径 / 系统二进制路径一律不进 Timeline/telemetry --
  只记 ``action_id`` + 闭集 scope（``count`` / ``status``）。
* 永不抛：坏输入 / 缺依赖 / 缺二进制 / 空文本归一为状态串，对齐 §14.5.2
  失败安全默认；缺依赖降级 statusBar，绝不崩主路径。
* 默认关 ``experience/ocr_enabled``（§6.4 新能力新键默认关；OCR 读盘 +
  跑外部进程属有副效应感知能力，且系统 ``tesseract`` 非必装）。
"""
from __future__ import annotations

import shutil
from pathlib import Path
from typing import Any, Literal

# Action id this skill is dispatched under (mirrors actions.py registry).
ACTION_ID = "textbook.ocr_suggest"

# Closed status set for OCR results + telemetry (no free-form text).
OcrStatus = Literal["ok", "missing_dep", "missing_binary", "no_text", "disabled"]

# Image extensions PIL/pytesseract can OCR directly (superset of
# attachment_extractor.IMAGE_EXTENSIONS plus common OCR formats).
_IMAGE_EXTS = frozenset(
    {".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp", ".tiff", ".tif"}
)


def is_ocr_enabled(settings: Any) -> bool:
    """True only when the ``experience/ocr_enabled`` switch is on.

    Reads ``experience_ocr_enabled`` from a settings object/dataclass (or
    Mapping); never raises - missing/false -> False (default off).
    """
    try:
        if settings is None:
            return False
        if isinstance(settings, dict) or hasattr(settings, "__getitem__"):
            try:
                return bool(settings.get("experience_ocr_enabled", False))
            except Exception:
                pass
        return bool(getattr(settings, "experience_ocr_enabled", False))
    except Exception:
        return False


def ocr_available() -> tuple[bool, str]:
    """Lazy-probe whether local OCR can run.

    Returns ``(True, "ok")`` when both the ``pytesseract`` Python package and
    the system ``tesseract`` binary are usable; otherwise ``(False, reason)``
    where reason ∈ {"missing_dep","missing_binary"}. Never raises.
    """
    try:
        import pytesseract  # noqa: F401
    except Exception:
        return False, "missing_dep"
    try:
        if not shutil.which("tesseract"):
            return False, "missing_binary"
    except Exception:
        return False, "missing_binary"
    return True, "ok"


def _is_image_path(path: Any) -> bool:
    try:
        return Path(path).suffix.lower() in _IMAGE_EXTS
    except Exception:
        return False


def _lang_fallback(lang: str) -> tuple[str, ...]:
    """Course lang first, then ``eng`` (design §1.2 / open item §5.1)."""
    lang = (str(lang or "").strip()) or "eng"
    if lang == "eng":
        return ("eng",)
    return (lang, "eng")


def _is_pdf_path(path: Any) -> bool:
    try:
        return Path(path).suffix.lower() == ".pdf"
    except Exception:
        return False


def _ocr_pil_image(img: Any, lang: str) -> tuple[str, str]:
    """OCR an open PIL Image with lang fallback; return ``(text, status)``.

    status ∈ {"ok","missing_binary","no_text"}. ``missing_dep`` for
    pytesseract is checked by the caller (image/PDF open already imported
    PIL). Never raises.
    """
    try:
        import pytesseract
    except Exception:
        return "", "missing_dep"
    not_found = getattr(pytesseract, "TesseractNotFoundError", Exception)
    text: str | None = None
    for attempt in _lang_fallback(lang):
        try:
            text = pytesseract.image_to_string(img, lang=attempt)
            break
        except not_found:
            return "", "missing_binary"
        except Exception:
            # Lang pack missing / unreadable page -> try next lang.
            text = None
            continue
    text = (text or "").strip()
    return (text, "ok") if text else ("", "no_text")


def _run_ocr_pdf(path: Any, lang: str) -> tuple[str, str]:
    """OCR a scanned PDF via PyMuPDF (``fitz``) lazy render; never raises.

    Renders each page to a PIL image at 200 DPI and OCRs it via
    ``_ocr_pil_image``. Returns ``(text, "ok"|"missing_dep"|"missing_binary"|
    "no_text")``. ``fitz`` absent -> ``missing_dep`` (PDF rendering is an
    optional dep, not required for image OCR).
    """
    try:
        import io

        import fitz  # PyMuPDF
        from PIL import Image
    except Exception:
        return "", "missing_dep"
    try:
        not_found_dep = False
        parts: list[str] = []
        doc = fitz.open(str(path))
        try:
            for page in doc:
                try:
                    pix = page.get_pixmap(dpi=200)
                    img = Image.open(io.BytesIO(pix.tobytes("png")))
                except Exception:
                    continue
                try:
                    t, status = _ocr_pil_image(img, lang)
                finally:
                    try:
                        img.close()
                    except Exception:
                        pass
                if status == "missing_dep":
                    not_found_dep = True
                    continue
                if status == "missing_binary":
                    return "", "missing_binary"
                if t:
                    parts.append(t)
        finally:
            try:
                doc.close()
            except Exception:
                pass
        if not_found_dep:
            # Dep missing surfaced mid-loop but we may still have text.
            pass
        text = "\n".join(parts).strip()
        return (text, "ok") if text else ("", "no_text")
    except Exception:
        return "", "no_text"


def run_ocr(path: Any, *, lang: str = "eng") -> tuple[str, str]:
    """OCR an image or scanned-PDF file at *path*; return ``(text, status)``.

    status ∈ {"ok","missing_dep","missing_binary","no_text"}. Never raises -
    every failure path (unsupported format, missing PIL/pytesseract/fitz,
    missing tesseract binary, unreadable file, empty result) is normalized to
    a status string. Images use PIL+pytesseract; PDFs render via PyMuPDF
    (``fitz``, lazy) then OCR each page. Tries the requested ``lang`` first,
    then falls back to ``eng`` when the course lang pack is unavailable.
    """
    try:
        if _is_image_path(path):
            try:
                from PIL import Image
            except Exception:
                return "", "missing_dep"
            try:
                img = Image.open(Path(path))
            except Exception:
                return "", "no_text"
            try:
                return _ocr_pil_image(img, lang)
            finally:
                try:
                    img.close()
                except Exception:
                    pass
        if _is_pdf_path(path):
            return _run_ocr_pdf(path, lang)
        return "", "no_text"
    except Exception:
        return "", "no_text"


def ocr_records(records: Any, *, lang: str = "eng") -> list[tuple[Any, str, str]]:
    """OCR a list of attachment records by ``temp_path``; never raises.

    Returns a list of ``(record, text, status)`` tuples (one per input record
    that has a usable ``temp_path``). No content-type filtering -- the caller
    decides which records to pass (image chips, scanned-PDF markers, etc.);
    ``run_ocr`` dispatches image vs PDF by extension. Designed to run inside
    ``AiRequestWorker`` (generic thread); touches only ``record.temp_path``
    (filesystem read, thread-safe).
    """
    out: list[tuple[Any, str, str]] = []
    try:
        for record in records or []:
            try:
                temp_path = getattr(record, "temp_path", None)
                if not temp_path:
                    continue
                text, status = run_ocr(temp_path, lang=lang)
                out.append((record, text, status))
            except Exception:
                continue
    except Exception:
        return out
    return out



def build_ocr_suggestion(ref_id: Any, kind: Any, status: Any) -> dict[str, Any] | None:
    """Closed-shape Dock suggestion for OCR (no text / no path).

    Vestigial for the ``/ocr`` (OCR-all) path but kept for the future
    per-attachment Dock suggestion (design §1.4). scope carries only
    ``ref_id`` / ``kind`` / ``status`` - never OCR text or file paths.
    """
    try:
        rid = str(ref_id or "").strip()
        if not rid:
            return None
        return {
            "priority": 2,
            "title": "OCR 图片附件转文本",
            "action_id": ACTION_ID,
            "scope": {
                "ref_id": rid,
                "kind": str(kind or ""),
                "status": str(status or ""),
            },
        }
    except Exception:
        return None
