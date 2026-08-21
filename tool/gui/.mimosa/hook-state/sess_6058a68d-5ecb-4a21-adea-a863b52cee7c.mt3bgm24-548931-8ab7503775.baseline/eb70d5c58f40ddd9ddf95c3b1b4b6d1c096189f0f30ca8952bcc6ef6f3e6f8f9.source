"""Tests for src.backend.attachment_extractor (bookplan2 Phase 6 coverage).

Pure-Python, tempfile-based. Does not require PyPDF2 / python-docx to be
installed: the PDF/Word branches are exercised via import patching.
"""
from __future__ import annotations

import base64
import builtins
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.attachment_extractor import (
    extract_attachment,
    summarize_attachment,
)


def _write(tmpdir: Path, name: str, data: bytes | str) -> Path:
    p = tmpdir / name
    if isinstance(data, str):
        p.write_text(data, encoding="utf-8")
    else:
        p.write_bytes(data)
    return p


class ExtractAttachmentTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self._tmp.name)

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def test_missing_file_returns_error(self) -> None:
        result = extract_attachment(self.dir / "nope.txt")
        self.assertFalse(result.ok)
        self.assertIn("文件不存在", result.error)

    def test_unsupported_extension(self) -> None:
        p = _write(self.dir, "f.xyz", "hello")
        result = extract_attachment(p)
        self.assertFalse(result.ok)
        self.assertIn("不支持的文件类型", result.error)

    def test_text_file_extracted(self) -> None:
        p = _write(self.dir, "note.md", "# Title\n正文内容")
        result = extract_attachment(p)
        self.assertTrue(result.ok)
        self.assertEqual(result.content["type"], "text")
        self.assertIn("正文内容", result.content["text"])

    def test_txt_utf8_text(self) -> None:
        p = _write(self.dir, "note.txt", "merhaba means hello")
        result = extract_attachment(p)
        self.assertTrue(result.ok)
        self.assertEqual(result.content["text"], "merhaba means hello")

    def test_non_utf8_text_returns_error(self) -> None:
        # Write raw bytes that are not valid UTF-8.
        p = _write(self.dir, "bad.txt", b"\xff\xfe\x00bad")
        result = extract_attachment(p)
        self.assertFalse(result.ok)
        self.assertIn("UTF-8", result.error)

    def test_image_file_base64_round_trip(self) -> None:
        payload = b"\x89PNG\r\n\x1a\n" + b"\x00" * 50  # fake png bytes
        p = _write(self.dir, "pic.png", payload)
        result = extract_attachment(p)
        self.assertTrue(result.ok)
        self.assertEqual(result.content["type"], "image_url")
        url = result.content["image_url"]["url"]
        self.assertTrue(url.startswith("data:image/png;base64,"))
        encoded = url.split("base64,", 1)[1]
        self.assertEqual(base64.b64decode(encoded), payload)

    def test_image_missing_mime_falls_back(self) -> None:
        # .webp is supported; an unknown mime falls back to octet-stream.
        p = _write(self.dir, "x.webp", b"\x00\x01\x02")
        result = extract_attachment(p)
        self.assertTrue(result.ok)
        self.assertIn("image_url", result.content["type"])

    def test_pdf_missing_dependency(self) -> None:
        p = _write(self.dir, "doc.pdf", b"%PDF-1.4 fake")

        real_import = builtins.__import__

        def fake_import(name, *args, **kwargs):
            if name == "PyPDF2":
                raise ImportError("no PyPDF2")
            return real_import(name, *args, **kwargs)

        with patch("builtins.__import__", side_effect=fake_import):
            result = extract_attachment(p)
        self.assertFalse(result.ok)
        self.assertIn("PyPDF2", result.error)

    def test_pdf_no_text_is_scan_fallback(self) -> None:
        p = _write(self.dir, "scan.pdf", b"%PDF-1.4")

        class _FakePage:
            def extract_text(self) -> str:
                return ""

        class _FakeReader:
            def __init__(self, _path) -> None:
                self.pages = [_FakePage()]

        fake_module = type(sys)("PyPDF2")
        fake_module.PdfReader = _FakeReader  # type: ignore[attr-defined]
        with patch.dict(sys.modules, {"PyPDF2": fake_module}):
            result = extract_attachment(p)
        self.assertFalse(result.ok)
        self.assertIn("扫描件", result.error)

    def test_pdf_text_extracted(self) -> None:
        p = _write(self.dir, "doc.pdf", b"%PDF-1.4")

        class _FakePage:
            def extract_text(self) -> str:
                return "extracted page text"

        class _FakeReader:
            def __init__(self, _path) -> None:
                self.pages = [_FakePage()]

        fake_module = type(sys)("PyPDF2")
        fake_module.PdfReader = _FakeReader  # type: ignore[attr-defined]
        with patch.dict(sys.modules, {"PyPDF2": fake_module}):
            result = extract_attachment(p)
        self.assertTrue(result.ok)
        self.assertEqual(result.content["text"], "extracted page text")

    def test_docx_missing_dependency(self) -> None:
        p = _write(self.dir, "doc.docx", b"PK fake zip")

        real_import = builtins.__import__

        def fake_import(name, *args, **kwargs):
            if name == "docx":
                raise ImportError("no docx")
            return real_import(name, *args, **kwargs)

        with patch("builtins.__import__", side_effect=fake_import):
            result = extract_attachment(p)
        self.assertFalse(result.ok)
        self.assertIn("python-docx", result.error)


class SummarizeAttachmentTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self._tmp.name)

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def test_long_text_truncated_with_ellipsis(self) -> None:
        p = _write(self.dir, "long.txt", "x" * 500)
        summary = summarize_attachment(p)
        self.assertTrue(summary.endswith("..."))
        self.assertLessEqual(len(summary), 123 + 3)  # 120 preview + ellipsis

    def test_short_text_shown_in_full(self) -> None:
        p = _write(self.dir, "short.txt", "hi there")
        self.assertEqual(summarize_attachment(p), "hi there")

    def test_image_summary_label(self) -> None:
        p = _write(self.dir, "pic.png", b"\x89PNG")
        self.assertEqual(summarize_attachment(p), "[图片]")

    def test_failure_summary_prefixed(self) -> None:
        self.assertEqual(
            summarize_attachment(self.dir / "missing.txt"),
            "[提取失败] 文件不存在: " + str(self.dir / "missing.txt"),
        )


if __name__ == "__main__":
    unittest.main()