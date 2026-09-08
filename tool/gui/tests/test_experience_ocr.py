"""M-03 (v4.40): textbook.ocr_suggest skill (pure + dispatch)."""
from __future__ import annotations

import os
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from tests._qtapp import qt_app  # noqa: E402

from src.backend.experience.actions import (  # noqa: E402
    DANGEROUS_ACTION_IDS,
    get_action,
)
from src.backend.experience.intent_router import match_commands, route_intent  # noqa: E402
from src.backend.experience.ocr_skill import (  # noqa: E402
    ACTION_ID,
    build_ocr_suggestion,
    is_ocr_enabled,
    ocr_available,
    ocr_records,
    run_ocr,
)
from src.application.settings import Settings  # noqa: E402


def _make_png() -> Path:
    """A tiny real PNG so PIL.Image.open succeeds in run_ocr tests."""
    from PIL import Image

    p = Path(tempfile.gettempdir()) / f"ocr_test_{os.getpid()}_{id(object())}.png"
    Image.new("RGB", (10, 10), (255, 255, 255)).save(p)
    return p


class _FakeTesseract:
    """Stand-in for the pytesseract module (imported lazily by ocr_skill)."""

    class TesseractNotFoundError(Exception):
        pass

    def __init__(self, text: str = "hello", raise_not_found: bool = False) -> None:
        self._text = text
        self._raise = raise_not_found

    def image_to_string(self, image, lang=None):  # noqa: ANN001
        if self._raise:
            raise self.TesseractNotFoundError("no binary")
        return self._text


class IsOcrEnabledTest(unittest.TestCase):
    def test_defaults_off(self) -> None:
        self.assertFalse(is_ocr_enabled(Settings()))
        self.assertFalse(is_ocr_enabled(None))

    def test_reads_flag_on(self) -> None:
        s = Settings()
        s.experience_ocr_enabled = True
        self.assertTrue(is_ocr_enabled(s))
        self.assertTrue(is_ocr_enabled({"experience_ocr_enabled": True}))

    def test_missing_attr_is_false(self) -> None:
        self.assertFalse(is_ocr_enabled(SimpleNamespace()))


class OcrAvailableTest(unittest.TestCase):
    def test_real_env_missing_dep(self) -> None:
        # pytesseract is not installed or binary missing in this environment.
        avail, reason = ocr_available()
        self.assertFalse(avail)
        self.assertIn(reason, ("missing_dep", "missing_binary"))

    def test_ok_with_fake_dep_and_binary(self) -> None:
        fake = _FakeTesseract()
        with patch.dict(sys.modules, {"pytesseract": fake}), patch(
            "shutil.which", return_value="/usr/bin/tesseract"
        ):
            avail, reason = ocr_available()
        self.assertTrue(avail)
        self.assertEqual(reason, "ok")

    def test_missing_binary_with_fake_dep(self) -> None:
        fake = _FakeTesseract()
        with patch.dict(sys.modules, {"pytesseract": fake}), patch(
            "shutil.which", return_value=None
        ):
            avail, reason = ocr_available()
        self.assertFalse(avail)
        self.assertEqual(reason, "missing_binary")


class RunOcrTest(unittest.TestCase):
    def test_non_image_is_no_text(self) -> None:
        text, status = run_ocr("/tmp/not_a_pdf.txt")
        self.assertEqual((text, status), ("", "no_text"))

    def test_real_env_image_missing_dep(self) -> None:
        # Real PNG, but pytesseract absent or binary missing -> missing_dep or missing_binary.
        png = _make_png()
        self.addCleanup(png.unlink, missing_ok=True)
        text, status = run_ocr(png)
        self.assertEqual(text, "")
        self.assertIn(status, ("missing_dep", "missing_binary"))

    def test_ok_with_fake_tesseract(self) -> None:
        png = _make_png()
        self.addCleanup(png.unlink, missing_ok=True)
        fake = _FakeTesseract(text="recognized text")
        with patch.dict(sys.modules, {"pytesseract": fake}):
            text, status = run_ocr(png, lang="tur")
        self.assertEqual(status, "ok")
        self.assertEqual(text, "recognized text")

    def test_no_text_with_fake_tesseract(self) -> None:
        png = _make_png()
        self.addCleanup(png.unlink, missing_ok=True)
        fake = _FakeTesseract(text="   ")
        with patch.dict(sys.modules, {"pytesseract": fake}):
            text, status = run_ocr(png)
        self.assertEqual((text, status), ("", "no_text"))

    def test_missing_binary_with_fake_tesseract(self) -> None:
        png = _make_png()
        self.addCleanup(png.unlink, missing_ok=True)
        fake = _FakeTesseract(raise_not_found=True)
        with patch.dict(sys.modules, {"pytesseract": fake}):
            text, status = run_ocr(png)
        self.assertEqual((text, status), ("", "missing_binary"))

    def test_lang_fallback_to_eng(self) -> None:
        # First lang "tur" errors (missing lang pack - a generic TesseractError,
        # not TesseractNotFoundError); eng succeeds.
        png = _make_png()
        self.addCleanup(png.unlink, missing_ok=True)
        calls: list[str] = []

        class _LangFake:
            class TesseractNotFoundError(Exception):
                pass

            def image_to_string(self, image, lang=None):  # noqa: ANN001
                calls.append(lang)
                if lang == "tur":
                    raise RuntimeError("Failed loading language 'tur'")
                return "english text"

        with patch.dict(sys.modules, {"pytesseract": _LangFake()}):
            text, status = run_ocr(png, lang="tur")
        self.assertEqual(status, "ok")
        self.assertEqual(text, "english text")
        self.assertEqual(calls, ["tur", "eng"])


class BuildSuggestionTest(unittest.TestCase):
    def test_closed_set_no_text_or_path(self) -> None:
        s = build_ocr_suggestion("att-abc", "image", "ok")
        self.assertEqual(s["action_id"], ACTION_ID)
        self.assertEqual(s["scope"], {"ref_id": "att-abc", "kind": "image", "status": "ok"})
        # No OCR text or file path leaks into the suggestion.
        blob = str(s)
        self.assertNotIn("/tmp", blob)
        self.assertNotIn("recognized", blob)

    def test_empty_ref_id_returns_none(self) -> None:
        self.assertIsNone(build_ocr_suggestion("", "image", "ok"))
        self.assertIsNone(build_ocr_suggestion(None, "image", "ok"))


class ActionRegistryTest(unittest.TestCase):
    def test_registered_read_only_not_dangerous(self) -> None:
        spec = get_action(ACTION_ID)
        self.assertIsNotNone(spec)
        self.assertFalse(spec.needs_confirm)
        self.assertFalse(spec.dangerous)
        self.assertNotIn(ACTION_ID, DANGEROUS_ACTION_IDS)


class RoutingTest(unittest.TestCase):
    def test_slash_exact(self) -> None:
        i = route_intent("/ocr")
        self.assertIsNotNone(i)
        self.assertEqual(i.action_id, ACTION_ID)
        self.assertEqual(i.confidence, 1.0)

    def test_free_text_keyword_routes_at_06(self) -> None:
        # v4.47 F6: free-text OCR keywords route at conf 0.6 (S-04 confirm
        # gate); unrelated free text still returns None.
        for text in ("ocr", "OCR", "识别文字", "文字识别"):
            i = route_intent(text)
            self.assertIsNotNone(i, text)
            self.assertEqual(i.action_id, ACTION_ID)
            self.assertEqual(i.confidence, 0.6)
        self.assertIsNone(route_intent("图片识别"))

    def test_match_commands_prefix(self) -> None:
        self.assertEqual([i.action_id for i in match_commands("/ocr")], [ACTION_ID])

    def test_golden_has_ocr(self) -> None:
        import json

        path = Path(__file__).resolve().parent / "ai_goldens" / "intent_routes.json"
        rows = json.loads(path.read_text(encoding="utf-8"))
        self.assertTrue(any(r.get("text") == "/ocr" for r in rows))


class _Status:
    def __init__(self, host):
        self._host = host

    def showMessage(self, msg, _ms=0):  # noqa: N802
        self._host._status.append(msg)


def _make_signal():
    sig = MagicMock()
    sig._handlers = []

    def connect(handler):
        sig._handlers.append(handler)

    sig.connect = connect
    return sig


def _fake_worker_factory():
    def factory(target, *args, **kwargs):
        w = SimpleNamespace()
        w.result_ready = _make_signal()
        w.error_occurred = _make_signal()

        def start(*a, **k):
            try:
                result = target(*args, **kwargs)
            except Exception as exc:  # noqa: BLE001
                for cb in list(w.error_occurred._handlers):
                    cb(str(exc))
            else:
                for cb in list(w.result_ready._handlers):
                    cb(result)

        w.start = start
        return w

    return factory


def _image_record(name: str = "scan.png"):
    from src.application.ai_request_worker import AttachmentRecord

    return AttachmentRecord(
        temp_path=Path("/tmp/scan.png"),
        original_name=name,
        content={"type": "image_url", "image_url": {"url": "data:image/png;base64,AAA"}},
    )


class DispatchTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        qt_app()

    def _make_host(self, *, enabled=True, records=None, ocr_ok=True):
        from src.backend.experience.job_registry import JobRegistry
        from src.backend.experience.metrics import ExperienceMetrics

        class Host:
            def __init__(self) -> None:
                self._settings_obj = SimpleNamespace(experience_ocr_enabled=enabled)
                self._added: list = []
                self._status: list[str] = []
                self._events: list = []
                self._experience_worker = None
                self.job_tray = JobRegistry()
                self.experience_metrics = ExperienceMetrics()
                self.adapter = SimpleNamespace(index={"language": "tur"})
                self.experience = SimpleNamespace(invalidate=lambda: None)
                self._workshop_window = SimpleNamespace(
                    attachment_records=lambda: list(records or []),
                    add_attachment_record=self._add,
                )
                self._make_ai_worker = _fake_worker_factory()

            def _add(self, rec):
                self._added.append(rec)
                return True

            def statusBar(self):  # noqa: N802
                return _Status(self)

            def _record_experience_event(self, *a, **k):
                self._events.append((a, k))

            def _refresh_experience(self, *a, **k):
                pass

            def _sync_experience_attachments(self):
                pass

        return Host()

    def _call(self, host, scope=None):
        from src.application.experience_skills_mixin import ExperienceSkillsMixin

        ExperienceSkillsMixin._experience_ocr(host, scope)

    def test_switch_off_short_circuits(self) -> None:
        host = self._make_host(enabled=False, records=[_image_record()])
        with patch(
            "src.backend.experience.ocr_skill.ocr_available", return_value=(True, "ok")
        ):
            self._call(host)
        self.assertEqual(host._added, [])
        self.assertTrue(any("未开启" in m for m in host._status))

    def test_no_image_records_status(self) -> None:
        host = self._make_host(enabled=True, records=[])
        with patch(
            "src.backend.experience.ocr_skill.ocr_available", return_value=(True, "ok")
        ):
            self._call(host)
        self.assertEqual(host._added, [])
        self.assertTrue(any("无图片附件" in m for m in host._status))

    def test_missing_dep_status(self) -> None:
        host = self._make_host(enabled=True, records=[_image_record()])
        with patch(
            "src.backend.experience.ocr_skill.ocr_available",
            return_value=(False, "missing_dep"),
        ):
            self._call(host)
        self.assertEqual(host._added, [])
        self.assertTrue(any("OCR 不可用" in m for m in host._status))

    def test_missing_binary_status(self) -> None:
        host = self._make_host(enabled=True, records=[_image_record()])
        with patch(
            "src.backend.experience.ocr_skill.ocr_available",
            return_value=(False, "missing_binary"),
        ):
            self._call(host)
        self.assertEqual(host._added, [])
        self.assertTrue(any("tesseract" in m for m in host._status))

    def test_success_adds_text_record_and_redacts(self) -> None:
        rec = _image_record("scan.png")
        host = self._make_host(enabled=True, records=[rec])
        canned = [(rec, "私密的 OCR 文本内容", "ok")]
        with patch(
            "src.backend.experience.ocr_skill.ocr_available", return_value=(True, "ok")
        ), patch(
            "src.backend.experience.ocr_skill.ocr_records", return_value=canned
        ):
            self._call(host)
        # One text-class attachment added, carrying the OCR text.
        self.assertEqual(len(host._added), 1)
        added = host._added[0]
        self.assertEqual(added.content["type"], "text")
        self.assertEqual(added.content["text"], "私密的 OCR 文本内容")
        self.assertTrue(added.original_name.endswith(".ocr.txt"))
        self.addCleanup(added.temp_path.unlink, missing_ok=True)
        # StatusBar reports success.
        self.assertTrue(any("OCR 完成" in m for m in host._status))
        # Timeline event: action_id + closed-set scope; OCR text never leaks.
        self.assertTrue(host._events)
        args, kwargs = host._events[-1]
        self.assertEqual(kwargs.get("action_id"), ACTION_ID)
        self.assertEqual(kwargs.get("scope"), {"count": 1, "status": "ok"})
        self.assertNotIn("私密的 OCR 文本内容", str(host._events))

    def test_all_no_text_no_record_added(self) -> None:
        rec = _image_record()
        host = self._make_host(enabled=True, records=[rec])
        with patch(
            "src.backend.experience.ocr_skill.ocr_available", return_value=(True, "ok")
        ), patch(
            "src.backend.experience.ocr_skill.ocr_records",
            return_value=[(rec, "", "no_text")],
        ):
            self._call(host)
        self.assertEqual(host._added, [])
        self.assertTrue(any("未识别到文本" in m for m in host._status))

    def test_ocr_all_dedup_skips_already_ocrd(self) -> None:
        from src.application.ai_request_worker import AttachmentRecord

        img = _image_record("a.png")
        txt = AttachmentRecord(
            temp_path=Path("/tmp/a.txt"),
            original_name="a.png.ocr.txt",
            content={"type": "text", "text": "x"},
        )
        host = self._make_host(enabled=True, records=[img, txt])
        with patch(
            "src.backend.experience.ocr_skill.ocr_available", return_value=(True, "ok")
        ):
            self._call(host)
        # a.png.ocr.txt already exists -> a.png skipped -> target empty.
        self.assertEqual(host._added, [])
        self.assertTrue(any("无图片附件" in m for m in host._status))

    def _call_single(self, host, records, unlink_after):
        from src.application.experience_skills_mixin import ExperienceSkillsMixin

        ExperienceSkillsMixin._experience_ocr(
            host, records=records, unlink_after=unlink_after
        )

    def test_single_record_unlinks_orphan(self) -> None:
        from src.application.ai_request_worker import AttachmentRecord

        src = Path(tempfile.gettempdir()) / f"ocr_src_{os.getpid()}.pdf"
        src.write_bytes(b"%PDF fake scanned")
        rec = AttachmentRecord(
            temp_path=src,
            original_name="scan.pdf",
            content={"type": "text", "text": ""},  # marker; OCR uses temp_path
        )
        host = self._make_host(enabled=True, records=[])
        with patch(
            "src.backend.experience.ocr_skill.ocr_available", return_value=(True, "ok")
        ), patch(
            "src.backend.experience.ocr_skill.ocr_records",
            return_value=[(rec, "pdf text", "ok")],
        ):
            self._call_single(host, [rec], unlink_after=True)
        self.assertEqual(len(host._added), 1)
        self.assertEqual(host._added[0].content["text"], "pdf text")
        self.addCleanup(host._added[0].temp_path.unlink, missing_ok=True)
        # Orphan scanned-PDF temp file cleaned up after OCR.
        self.assertFalse(src.exists())

    def test_single_record_no_unlink_when_bar_owned(self) -> None:
        from src.application.ai_request_worker import AttachmentRecord

        src = Path(tempfile.gettempdir()) / f"ocr_keep_{os.getpid()}.png"
        src.write_bytes(b"\x89PNG fake")
        rec = AttachmentRecord(
            temp_path=src,
            original_name="img.png",
            content={"type": "image_url", "image_url": {"url": "data:x"}},
        )
        host = self._make_host(enabled=True, records=[])
        with patch(
            "src.backend.experience.ocr_skill.ocr_available", return_value=(True, "ok")
        ), patch(
            "src.backend.experience.ocr_skill.ocr_records",
            return_value=[(rec, "img text", "ok")],
        ):
            self._call_single(host, [rec], unlink_after=False)
        self.assertEqual(len(host._added), 1)
        self.addCleanup(host._added[0].temp_path.unlink, missing_ok=True)
        # Bar-owned temp file is NOT unlinked (bar cleanup owns it).
        self.assertTrue(src.exists())
        src.unlink(missing_ok=True)


class RunOcrPdfTest(unittest.TestCase):
    def test_missing_dep_when_no_fitz(self) -> None:
        # When PyMuPDF is absent, a .pdf path -> missing_dep (never raises).
        pdf = Path(tempfile.gettempdir()) / f"ocr_pdf_{os.getpid()}.pdf"
        pdf.write_bytes(b"%PDF-1.4 fake")
        self.addCleanup(pdf.unlink, missing_ok=True)
        with patch.dict(sys.modules, {"fitz": None}):
            text, status = run_ocr(pdf, lang="eng")
        self.assertEqual((text, status), ("", "missing_dep"))

    def test_ok_with_fake_fitz_and_tesseract(self) -> None:
        from PIL import Image

        png_bytes_path = Path(tempfile.gettempdir()) / f"pg_{os.getpid()}.png"
        Image.new("RGB", (8, 8), (255, 255, 255)).save(png_bytes_path)
        png_bytes = png_bytes_path.read_bytes()
        png_bytes_path.unlink(missing_ok=True)

        class _FakePix:
            def tobytes(self, fmt):  # noqa: ANN001
                return png_bytes

        class _FakePage:
            def get_pixmap(self, dpi=200):  # noqa: ANN001
                return _FakePix()

        class _FakeDoc:
            def __iter__(self):
                return iter([_FakePage()])

            def close(self):
                pass

        class _FakeFitz:
            @staticmethod
            def open(path):  # noqa: ANN001
                return _FakeDoc()

        fake_tesseract = _FakeTesseract(text="pdf page text")
        pdf = Path(tempfile.gettempdir()) / f"ocr_pdf_ok_{os.getpid()}.pdf"
        pdf.write_bytes(b"%PDF-1.4 fake")
        self.addCleanup(pdf.unlink, missing_ok=True)
        with patch.dict(sys.modules, {"fitz": _FakeFitz, "pytesseract": fake_tesseract}):
            text, status = run_ocr(pdf, lang="eng")
        self.assertEqual(status, "ok")
        self.assertEqual(text, "pdf page text")


class OcrRecordsTest(unittest.TestCase):
    def _rec(self, ctype, name="x", temp=None):
        from src.application.ai_request_worker import AttachmentRecord

        content = (
            {"type": "image_url", "image_url": {"url": "data:x"}}
            if ctype == "image_url"
            else {"type": "text", "text": "hi"}
        )
        return AttachmentRecord(
            temp_path=temp or Path("/tmp/whatever"), original_name=name, content=content
        )

    def test_ocrs_given_records_by_temp_path(self):
        irec = self._rec("image_url", "a.png")
        prec = self._rec("text", "s.pdf", temp=Path("/tmp/s.pdf"))
        with patch(
            "src.backend.experience.ocr_skill.run_ocr",
            side_effect=[("img", "ok"), ("pdf", "ok")],
        ):
            out = ocr_records([irec, prec], lang="eng")
        self.assertEqual([(o[1], o[2]) for o in out], [("img", "ok"), ("pdf", "ok")])
        self.assertIs(out[0][0], irec)
        self.assertIs(out[1][0], prec)

    def test_skips_records_without_temp_path(self):
        from src.application.ai_request_worker import AttachmentRecord

        rec = AttachmentRecord(
            temp_path=None,
            original_name="x",
            content={"type": "image_url", "image_url": {"url": "d"}},
        )
        with patch("src.backend.experience.ocr_skill.run_ocr") as m:
            self.assertEqual(ocr_records([rec]), [])
        m.assert_not_called()


class AttachmentBarOcrButtonTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        qt_app()

    def _bar_with_records(self):
        from src.dialogs.ai.attachment_bar import AttachmentBar
        from src.application.ai_request_worker import AttachmentRecord

        bar = AttachmentBar()
        self.addCleanup(bar.deleteLater)
        img = AttachmentRecord(
            temp_path=Path("/tmp/x.png"),
            original_name="x.png",
            content={"type": "image_url", "image_url": {"url": "data:x"}},
        )
        txt = AttachmentRecord(
            temp_path=Path("/tmp/x.txt"),
            original_name="x.txt",
            content={"type": "text", "text": "hi"},
        )
        bar.add_attachment(img)
        bar.add_attachment(txt)
        return bar

    @staticmethod
    def _ocr_buttons(bar):
        from PySide6.QtWidgets import QPushButton

        return [b for b in bar.findChildren(QPushButton) if b.text() == "OCR"]

    def test_button_only_when_enabled_and_image(self):
        bar = self._bar_with_records()
        # Disabled: no OCR buttons.
        bar.set_ocr_enabled(False)
        self.assertEqual(len(self._ocr_buttons(bar)), 0)
        # Enabled: exactly one OCR button (image chip only; text chip has none).
        bar.set_ocr_enabled(True)
        self.assertEqual(len(self._ocr_buttons(bar)), 1)

    def test_click_emits_ocr_requested(self):
        bar = self._bar_with_records()
        bar.set_ocr_enabled(True)
        received: list = []
        bar.ocr_requested.connect(lambda p, n, u: received.append((p, n, u)))
        self._ocr_buttons(bar)[0].click()
        self.assertEqual(received, [("/tmp/x.png", "x.png", False)])


class DesignPanelScannedPdfOfferTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        qt_app()

    def _make_panel(self):
        from src.dialogs.ai.design_panel import DesignPanel

        panel = DesignPanel(None, None)
        self.addCleanup(panel.deleteLater)
        return panel

    def _scanned_pdf(self):
        pdf = Path(tempfile.gettempdir()) / f"scan_{os.getpid()}_{id(object())}.pdf"
        pdf.write_bytes(b"%PDF-1.4 fake scanned")
        self.addCleanup(pdf.unlink, missing_ok=True)
        return pdf

    def test_offer_emits_when_yes(self):
        from PySide6.QtWidgets import QMessageBox
        from src.backend.attachment_extractor import ExtractionResult

        panel = self._make_panel()
        panel.set_ocr_enabled(True)
        pdf = self._scanned_pdf()
        received: list = []
        panel.ocr_requested.connect(lambda p, n, u: received.append((p, n, u)))
        with patch(
            "src.backend.attachment_extractor._pdf_content",
            return_value=ExtractionResult(
                error="PDF 未提取到文本（可能是扫描件或图片 PDF）。"
            ),
        ), patch(
            "src.backend.experience.ocr_skill.ocr_available", return_value=(True, "ok")
        ), patch(
            "src.dialogs.ai.design_panel.QMessageBox.question",
            return_value=QMessageBox.StandardButton.Yes,
        ):
            panel._add_attachment_paths([pdf])
        self.assertEqual(len(received), 1)
        p, n, u = received[0]
        self.assertEqual(n, pdf.name)
        self.assertTrue(u)  # unlink_after=True (orphan temp owned by OCR)
        # Panel did NOT unlink the temp copy (app owns it after emit); clean up.
        self.addCleanup(Path(p).unlink, missing_ok=True)
        # The original file is never touched by the panel.
        self.assertTrue(pdf.exists())

    def test_no_offer_when_unavailable_falls_through(self):
        from PySide6.QtWidgets import QMessageBox
        from src.backend.attachment_extractor import ExtractionResult

        panel = self._make_panel()
        panel.set_ocr_enabled(True)
        pdf = self._scanned_pdf()
        received: list = []
        panel.ocr_requested.connect(lambda p, n, u: received.append((p, n, u)))
        with patch(
            "src.backend.attachment_extractor._pdf_content",
            return_value=ExtractionResult(
                error="PDF 未提取到文本（可能是扫描件或图片 PDF）。"
            ),
        ), patch(
            "src.backend.experience.ocr_skill.ocr_available",
            return_value=(False, "missing_dep"),
        ), patch("src.dialogs.ai.design_panel.QMessageBox.warning") as _w:
            panel._add_attachment_paths([pdf])
        # No OCR request emitted; warning shown (current skip behavior).
        self.assertEqual(received, [])
        _w.assert_called_once()


class ObserverAllowsOcrTest(unittest.TestCase):
    def test_observer_allows_readonly_ocr(self):
        # OCR is read-only (needs_confirm=False); observer must allow it.
        from src.backend.experience import can_dispatch, get_action, resolve_policy

        spec = get_action(ACTION_ID)
        policy = resolve_policy(
            Settings(experience_mode="observer"), action_id=ACTION_ID
        )
        allowed, _ = can_dispatch(spec, policy)
        self.assertTrue(allowed)


class AppOcrHandlerTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        qt_app()

    def test_handler_builds_record_and_dispatches(self):
        from tests._mainwindow_fixture import build_main_window

        win = build_main_window()
        self.addCleanup(win.deleteLater)
        src = Path(tempfile.gettempdir()) / f"app_ocr_{os.getpid()}_{id(object())}.pdf"
        src.write_bytes(b"%PDF")
        try:
            with patch.object(win, "_experience_ocr") as mock_ocr:
                win._on_workshop_ocr_requested(str(src), "scan.pdf", True)
            mock_ocr.assert_called_once()
            kwargs = mock_ocr.call_args.kwargs
            self.assertTrue(kwargs.get("unlink_after"))
            recs = kwargs.get("records")
            self.assertEqual(len(recs), 1)
            self.assertEqual(recs[0].original_name, "scan.pdf")
            self.assertEqual(recs[0].temp_path, src)
        finally:
            src.unlink(missing_ok=True)


if __name__ == "__main__":
    unittest.main()
