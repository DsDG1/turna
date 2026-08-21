"""M-04 (v4.44): voice → palette input channel (pure + UI + controller)."""
from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from tests._qtapp import qt_app  # noqa: E402

from src.application.settings import Settings  # noqa: E402
from src.backend.experience.voice_skill import (  # noqa: E402
    DEFAULT_ENGINE,
    TRANSCRIPT_MAX_CHARS,
    build_voice_metrics,
    is_voice_palette_enabled,
    status_message,
    transcribe_once,
    voice_available,
)


class IsVoicePaletteEnabledTest(unittest.TestCase):
    def test_defaults_off(self) -> None:
        self.assertFalse(is_voice_palette_enabled(Settings()))
        self.assertFalse(is_voice_palette_enabled(None))

    def test_reads_flag_on(self) -> None:
        s = Settings()
        s.experience_voice_palette = True
        self.assertTrue(is_voice_palette_enabled(s))
        self.assertTrue(is_voice_palette_enabled({"experience_voice_palette": True}))

    def test_missing_attr_is_false(self) -> None:
        self.assertFalse(is_voice_palette_enabled(SimpleNamespace()))


class VoiceAvailableTest(unittest.TestCase):
    def test_real_env_missing_dep(self) -> None:
        # SpeechRecognition/pyaudio are optional; typically missing in CI.
        avail, reason = voice_available()
        if not avail:
            self.assertIn(reason, {"missing_dep", "no_mic"})

    def test_ok_with_fake_modules(self) -> None:
        fake_sr = MagicMock()
        fake_sr.Microphone.list_microphone_names.return_value = ["default"]
        fake_py = MagicMock()
        with patch.dict(
            sys.modules,
            {"speech_recognition": fake_sr, "pyaudio": fake_py},
        ):
            avail, reason = voice_available()
        self.assertTrue(avail)
        self.assertEqual(reason, "ok")

    def test_missing_pyaudio(self) -> None:
        fake_sr = MagicMock()
        # Remove pyaudio if present and block import.
        mods = {"speech_recognition": fake_sr}
        # Ensure pyaudio import fails: pop and inject a broken loader.
        with patch.dict(sys.modules, mods, clear=False):
            # Force pyaudio import to fail by patching builtins import of it
            # via missing module entry that raises.
            real_import = __import__

            def _import(name, *a, **k):
                if name == "pyaudio":
                    raise ImportError("no pyaudio")
                return real_import(name, *a, **k)

            with patch("builtins.__import__", side_effect=_import):
                # Also clear cached pyaudio if any
                sys.modules.pop("pyaudio", None)
                avail, reason = voice_available()
        self.assertFalse(avail)
        self.assertEqual(reason, "missing_dep")


class TranscribeOnceTest(unittest.TestCase):
    def test_ok_with_injected_recognizer(self) -> None:
        rec = MagicMock()
        rec.recognize_sphinx.return_value = "  fill empty lessons  "
        text, status = transcribe_once(recognizer=rec, source=object())
        self.assertEqual(status, "ok")
        self.assertEqual(text, "fill empty lessons")

    def test_timeout_from_listen(self) -> None:
        class WaitTimeoutError(Exception):
            pass

        rec = MagicMock()
        rec.listen.side_effect = WaitTimeoutError("timeout")
        text, status = transcribe_once(recognizer=rec, source=object())
        self.assertEqual(text, "")
        self.assertEqual(status, "timeout")

    def test_too_long_capped(self) -> None:
        rec = MagicMock()
        rec.recognize_sphinx.return_value = "x" * (TRANSCRIPT_MAX_CHARS + 50)
        text, status = transcribe_once(recognizer=rec, source=object())
        self.assertEqual(status, "too_long")
        self.assertEqual(len(text), TRANSCRIPT_MAX_CHARS)

    def test_empty_transcript_failed(self) -> None:
        rec = MagicMock()
        rec.recognize_sphinx.return_value = "   "
        text, status = transcribe_once(recognizer=rec, source=object())
        self.assertEqual(text, "")
        self.assertEqual(status, "failed")

    def test_never_raises_on_broken_recognizer(self) -> None:
        rec = MagicMock()
        rec.recognize_sphinx.side_effect = RuntimeError("boom")
        text, status = transcribe_once(recognizer=rec, source=object())
        self.assertEqual(text, "")
        self.assertIn(status, {"failed", "missing_dep"})


class VoiceMetricsRedactionTest(unittest.TestCase):
    def test_closed_set_no_transcript(self) -> None:
        m = build_voice_metrics("ok", ok=True)
        self.assertEqual(set(m.keys()), {"status", "ok", "engine"})
        self.assertTrue(m["ok"])
        self.assertEqual(m["engine"], DEFAULT_ENGINE)
        blob = str(m)
        self.assertNotIn("hello world", blob)
        self.assertNotIn("transcript", blob.lower())

    def test_status_message_known(self) -> None:
        self.assertIn("Enter", status_message("ok"))
        self.assertIn("依赖", status_message("missing_dep"))


class CommandPaletteVoiceUiTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        qt_app()

    def test_mic_hidden_by_default(self) -> None:
        from src.widgets.command_palette import CommandPalette

        dlg = CommandPalette()
        self.assertTrue(dlg.voice_btn.isHidden())

    def test_set_voice_enabled_shows_button(self) -> None:
        from src.widgets.command_palette import CommandPalette

        dlg = CommandPalette()
        dlg.set_voice_enabled(True)
        # Parent dialog may not be shown; isHidden tracks explicit visibility.
        self.assertFalse(dlg.voice_btn.isHidden())
        dlg.set_voice_enabled(False)
        self.assertTrue(dlg.voice_btn.isHidden())

    def test_set_input_text_does_not_dispatch(self) -> None:
        from src.widgets.command_palette import CommandPalette

        dlg = CommandPalette()
        fired: list = []
        dlg.command_triggered.connect(lambda p: fired.append(p))
        dlg.set_input_text("/why")
        self.assertEqual(dlg.input.text(), "/why")
        self.assertEqual(fired, [])
        # Candidates should refresh for slash.
        self.assertTrue(len(dlg._intents) >= 1)


class TranscribeToPaletteTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        qt_app()

    def _make_host(self, *, enabled: bool = False):
        from src.backend.experience.job_registry import JobRegistry
        from src.backend.experience.metrics import ExperienceMetrics

        class Host:
            def __init__(self) -> None:
                self._settings_obj = SimpleNamespace(
                    experience_voice_palette=enabled
                )
                self.job_tray = JobRegistry()
                self.experience_metrics = ExperienceMetrics()
                self._status: list[str] = []
                self._events: list = []
                self._experience_worker = None
                self._active_command_palette = None

            def statusBar(self):  # noqa: N802
                host = self

                class SB:
                    def showMessage(self, msg, ms=0):  # noqa: N802
                        host._status.append(msg)

                return SB()

            def _record_experience_event(self, *a, **k):
                self._events.append((a, k))

            def _make_ai_worker(self, target, *args, **kwargs):
                w = SimpleNamespace()
                handlers_ok: list = []
                handlers_err: list = []

                class Sig:
                    def connect(self, cb):
                        handlers_ok.append(cb) if self is w.result_ready else handlers_err.append(cb)

                # Fix signal objects
                w.result_ready = SimpleNamespace()
                w.error_occurred = SimpleNamespace()
                ok_cbs: list = []
                err_cbs: list = []
                w.result_ready.connect = lambda cb: ok_cbs.append(cb)
                w.error_occurred.connect = lambda cb: err_cbs.append(cb)

                def start():
                    try:
                        result = target(*args, **kwargs)
                    except Exception as exc:  # noqa: BLE001
                        for cb in err_cbs:
                            cb(str(exc))
                    else:
                        for cb in ok_cbs:
                            cb(result)

                w.start = start
                return w

        return Host()

    def test_disabled_status_bar(self) -> None:
        from src.application.palette_controller import transcribe_to_palette

        host = self._make_host(enabled=False)
        transcribe_to_palette(host)
        self.assertTrue(any("未开启" in m for m in host._status))
        self.assertEqual(host._events, [])

    def test_offscreen_blocks_mic(self) -> None:
        from src.application.palette_controller import transcribe_to_palette

        host = self._make_host(enabled=True)
        # Real QT_QPA is offscreen in tests → must not open mic.
        transcribe_to_palette(host)
        self.assertTrue(
            any(
                "可视化" in m or "GUI" in m or "依赖" in m or "麦克风" in m
                for m in host._status
            )
        )

    def test_success_fills_input_no_dispatch(self) -> None:
        from src.application import palette_controller as pc
        from src.widgets.command_palette import CommandPalette

        host = self._make_host(enabled=True)
        dlg = CommandPalette()
        dlg.set_voice_enabled(True)
        host._active_command_palette = dlg
        fired: list = []
        dlg.command_triggered.connect(lambda p: fired.append(p))

        # Bypass offscreen + availability; inject fake transcribe.
        def fake_transcribe(**kwargs):
            return ("validate open", "ok")

        with patch(
            "src.application.palette_controller.transcribe_to_palette"
        ):
            pass  # not recursive

        # Call internals by patching guards inside voice_skill used by controller.
        import src.backend.experience.voice_skill as vs

        with patch.object(vs, "is_voice_palette_enabled", return_value=True), patch.object(
            vs, "voice_available", return_value=(True, "ok")
        ), patch.object(vs, "transcribe_once", side_effect=fake_transcribe), patch(
            "PySide6.QtWidgets.QApplication.instance"
        ) as inst:
            app = MagicMock()
            app.platformName.return_value = "xcb"
            inst.return_value = app
            # Need to re-import path: transcribe_to_palette imports from voice_skill at call time
            pc.transcribe_to_palette(host, dlg)

        self.assertEqual(dlg.input.text(), "validate open")
        self.assertEqual(fired, [])
        self.assertTrue(any("Enter" in m for m in host._status))
        # Redaction: events must not contain transcript.
        self.assertEqual(len(host._events), 1)
        _args, kwargs = host._events[0]
        scope = kwargs.get("scope") or {}
        self.assertNotIn("validate open", str(scope))
        self.assertIn(scope.get("status"), ("ok", "too_long"))
        self.assertTrue(scope.get("ok"))


class OpenPaletteVoiceWiringTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        qt_app()

    def test_open_enables_mic_when_flag_on(self) -> None:
        from src.application.palette_controller import open_command_palette

        host = SimpleNamespace(
            experience_timeline=None,
            experience_metrics=None,
            _settings_obj=SimpleNamespace(experience_voice_palette=True),
            _palette_async_candidate_hook=None,
        )
        dlg = open_command_palette(host)
        self.assertFalse(dlg.voice_btn.isHidden())
        dlg.close()

    def test_open_hides_mic_when_flag_off(self) -> None:
        from src.application.palette_controller import open_command_palette

        host = SimpleNamespace(
            experience_timeline=None,
            experience_metrics=None,
            _settings_obj=SimpleNamespace(experience_voice_palette=False),
            _palette_async_candidate_hook=None,
        )
        dlg = open_command_palette(host)
        self.assertTrue(dlg.voice_btn.isHidden())
        dlg.close()


if __name__ == "__main__":
    unittest.main()
