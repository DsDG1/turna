"""C-13/M-01/M-03: ExperienceMemory + attachment + OCR wiring tests.

The wiring batch (settings fields -> Settings tab -> host delegates ->
bridge sync) is verified end to end: memory facade instantiation is covered
by the MainWindow fixture indirectly through ``_sync_experience_memory``
delegates; here we test the bridge functions and the WorkshopWindow
attachment surface they consume.
"""
from __future__ import annotations

import os
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import MagicMock

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.application.experience_window_bridge import (  # noqa: E402
    apply_experience_memory_settings,
    record_experience_intent,
    sync_experience_attachments,
    sync_experience_memory,
    sync_usage_today,
)
from src.application.settings import Settings  # noqa: E402
from src.backend.experience.memory import ExperienceMemory  # noqa: E402
from tests._qsettings_mock import make_qsettings  # noqa: E402


class _StubShell:
    """Minimal ExperienceShell stand-in recording setter calls."""

    def __init__(self) -> None:
        self.surface = "tree"
        self.recent_intents = None
        self.author_profile = None
        self.attachments = None
        self.usage_today = None
        self.invalidated = 0

    def set_recent_intents(self, items):
        self.recent_intents = list(items or [])

    def set_author_profile(self, profile):
        self.author_profile = profile

    def set_attachments(self, items):
        self.attachments = list(items or [])

    def set_usage_today(self, usage):
        self.usage_today = dict(usage or {})

    def invalidate(self, *, immediate: bool = False) -> None:
        self.invalidated += 1


class SyncExperienceMemoryTest(unittest.TestCase):
    def test_pushes_context_fields_and_surface(self) -> None:
        mem = ExperienceMemory()
        mem.record_intent("lesson.fill_empty", label="补空课时", scope={"lesson": "l1"})
        shell = _StubShell()
        shell.surface = "resources"
        host = SimpleNamespace(experience_memory=mem, experience=shell)

        sync_experience_memory(host)

        self.assertEqual(len(shell.recent_intents), 1)
        self.assertEqual(shell.recent_intents[0]["action_id"], "lesson.fill_empty")
        self.assertEqual(mem.session.last_surface, "resources")

    def test_noop_without_memory(self) -> None:
        host = SimpleNamespace(experience_memory=None, experience=_StubShell())
        sync_experience_memory(host)  # must not raise


class SyncExperienceAttachmentsTest(unittest.TestCase):
    def test_snapshot_is_closed_shape(self) -> None:
        from src.application.ai_request_worker import AttachmentRecord

        tmp = Path(tempfile.gettempdir()) / "turna_test_attach.txt"
        tmp.write_text("hello ocr", encoding="utf-8")
        try:
            rec = AttachmentRecord(
                temp_path=tmp,
                original_name="note.txt",
                content={"type": "text", "text": "hello ocr"},
            )
            win = SimpleNamespace(attachment_records=lambda: [rec])
            shell = _StubShell()
            host = SimpleNamespace(experience=shell, _workshop_window=win)

            sync_experience_attachments(host)

            self.assertEqual(len(shell.attachments), 1)
            item = shell.attachments[0]
            self.assertEqual(item["name"], "note.txt")
            self.assertIn("kind", item)
            self.assertIn("char_count", item)
            # Raw text must never enter the context snapshot.
            self.assertNotIn("text", item)
            self.assertNotIn("content", item)
            self.assertNotIn("hello ocr", repr(item))
        finally:
            tmp.unlink(missing_ok=True)

    def test_no_window_yields_empty(self) -> None:
        shell = _StubShell()
        host = SimpleNamespace(experience=shell, _workshop_window=None)
        sync_experience_attachments(host)
        self.assertEqual(shell.attachments, [])


class ApplyMemorySettingsTest(unittest.TestCase):
    def test_flags_forwarded(self) -> None:
        mem = ExperienceMemory()
        settings = SimpleNamespace(
            experience_memory_persist_project=True,
            experience_memory_persist_author=True,
        )
        host = SimpleNamespace(experience_memory=mem, _settings_obj=settings)

        apply_experience_memory_settings(host)

        self.assertTrue(mem.project.persist_enabled)
        self.assertTrue(mem.author.persist_enabled)


class RecordIntentTest(unittest.TestCase):
    def test_records_and_invalidates(self) -> None:
        mem = ExperienceMemory()
        shell = _StubShell()
        host = SimpleNamespace(experience_memory=mem, experience=shell)

        record_experience_intent(
            host, "course.validate", label="校验", scope={"s": 1}, source="dock"
        )

        intents = mem.session.recent_intent_dicts()
        self.assertEqual(len(intents), 1)
        self.assertEqual(intents[0]["action_id"], "course.validate")
        self.assertEqual(shell.recent_intents[0]["action_id"], "course.validate")
        self.assertGreaterEqual(shell.invalidated, 1)


class SyncUsageTodayTest(unittest.TestCase):
    def test_feeds_shell_bucket(self) -> None:
        shell = _StubShell()
        host = SimpleNamespace(experience=shell)
        sync_usage_today(host)
        self.assertIsNotNone(shell.usage_today)
        for key in ("requests", "success", "failure", "total_tokens"):
            self.assertIn(key, shell.usage_today)


class OcrSettingsRoundTripTest(unittest.TestCase):
    def test_ocr_enabled_persists(self) -> None:
        qs = make_qsettings()
        settings = Settings()
        settings.experience_ocr_enabled = True
        settings.save_to_qsettings(qs)

        loaded = Settings.load_from_qsettings(qs)
        self.assertTrue(loaded.experience_ocr_enabled)

    def test_ocr_enabled_default_off(self) -> None:
        qs = make_qsettings()
        loaded = Settings.load_from_qsettings(qs)
        self.assertFalse(loaded.experience_ocr_enabled)


class WorkshopAttachmentSurfaceTest(unittest.TestCase):
    """WorkshopWindow exposes the surface workshop_controller probes for."""

    def setUp(self) -> None:
        from tests._qtapp import _App

        _App.get()
        self.tmp = tempfile.TemporaryDirectory()
        from src.backend.textbook_project_store import TextbookProjectStore
        from src.dialogs.workshop_window import WorkshopWindow

        self.store = TextbookProjectStore(base_dir=Path(self.tmp.name))
        self.win = WorkshopWindow(None, None, store=self.store)

    def tearDown(self) -> None:
        self.win.deleteLater()
        self.tmp.cleanup()

    def test_empty_before_canvas(self) -> None:
        self.assertEqual(self.win.attachment_records(), [])
        self.assertFalse(self.win.add_attachment_record(MagicMock()))

    def test_records_and_signal_after_canvas(self) -> None:
        from src.backend.markdown_chopper import split_chapters
        from src.backend.knowledge_schema import coerce_knowledge_points

        src = Path(self.tmp.name) / "book.md"
        src.write_text("## 1 Merhaba\nhello\n", encoding="utf-8")
        project = self.store.create_project(name="Book", source_path=src)
        ch = split_chapters("## 1 Merhaba\nhello\n")
        kp = coerce_knowledge_points(
            {"words": [{"term": "merhaba", "translation": "hello"}]}
        )
        project.set_chapters([(ch[0], True, kp, "")])
        project.update_resource_pool()
        self.store.save_project(project)
        self.win._on_project_selected(project)

        fired: list[bool] = []
        self.win.attachments_changed.connect(lambda: fired.append(True))

        from src.application.ai_request_worker import AttachmentRecord

        rec = AttachmentRecord(
            temp_path=src,
            original_name="book.md",
            content={"type": "text", "text": "hi"},
        )
        self.assertTrue(self.win.add_attachment_record(rec))
        self.assertEqual(len(self.win.attachment_records()), 1)
        self.assertEqual(
            self.win.attachment_records()[0].original_name, "book.md"
        )
        self.assertTrue(fired)

        # OCR gate passthrough reaches the design panel's bar.
        self.win.set_ocr_enabled(True)
        self.assertTrue(self.win._design_panel._ocr_enabled)
        self.assertTrue(self.win._design_panel._attachment_bar._ocr_enabled)


if __name__ == "__main__":
    unittest.main()
