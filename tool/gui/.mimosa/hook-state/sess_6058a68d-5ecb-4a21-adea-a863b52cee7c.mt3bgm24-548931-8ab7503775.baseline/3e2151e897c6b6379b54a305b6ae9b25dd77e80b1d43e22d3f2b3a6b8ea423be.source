"""M-05 (v4.38): app.screenshot_explain skill (pure + controller + dispatch)."""
from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import MagicMock

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from tests._qtapp import qt_app  # noqa: E402

from src.backend.experience.actions import (  # noqa: E402
    DANGEROUS_ACTION_IDS,
    get_action,
)
from src.backend.experience.intent_router import route_intent  # noqa: E402
from src.backend.experience.screenshot_skill import (  # noqa: E402
    build_screenshot_messages,
    is_screenshot_explain_enabled,
    png_bytes_to_data_url,
    run_screenshot_skill,
    truncate_reply,
)


class MessageBuilderTest(unittest.TestCase):
    def test_messages_have_system_and_user_image(self) -> None:
        msgs = build_screenshot_messages(b"\x89PNG\r\n\x1a\n")
        self.assertEqual(len(msgs), 2)
        self.assertEqual(msgs[0]["role"], "system")
        self.assertEqual(msgs[1]["role"], "user")
        content = msgs[1]["content"]
        self.assertIsInstance(content, list)
        types = [p.get("type") for p in content]
        self.assertEqual(types, ["text", "image_url"])
        self.assertTrue(
            content[1]["image_url"]["url"].startswith("data:image/png;base64,")
        )

    def test_empty_png_falls_back_to_text_only(self) -> None:
        msgs = build_screenshot_messages(b"")
        content = msgs[1]["content"]
        self.assertIsInstance(content, list)
        self.assertEqual([p.get("type") for p in content], ["text"])
        self.assertIn("截图缺失", content[0]["text"])

    def test_data_url_helper(self) -> None:
        self.assertTrue(png_bytes_to_data_url(b"abc").startswith("data:image/png;base64,"))
        self.assertEqual(png_bytes_to_data_url(b""), "")

    def test_never_raises_on_bad_input(self) -> None:
        msgs = build_screenshot_messages(None)  # type: ignore[arg-type]
        self.assertEqual(msgs[1]["content"][0]["type"], "text")


class RunSkillTest(unittest.TestCase):
    def test_extracts_plain_text(self) -> None:
        import src.backend.ai_generator as ai_gen

        orig = ai_gen.request_chat
        ai_gen.request_chat = lambda *a, **k: {  # type: ignore[assignment]
            "choices": [{"message": {"content": "状态：问候课已填充"}}]
        }
        try:
            out = run_screenshot_skill(SimpleNamespace(is_complete=True), b"\x89PNG")
            self.assertEqual(out, "状态：问候课已填充")
        finally:
            ai_gen.request_chat = orig

    def test_empty_choices_returns_empty(self) -> None:
        import src.backend.ai_generator as ai_gen

        orig = ai_gen.request_chat
        ai_gen.request_chat = lambda *a, **k: {"choices": []}  # type: ignore[assignment]
        try:
            self.assertEqual(run_screenshot_skill(SimpleNamespace(), b"x"), "")
        finally:
            ai_gen.request_chat = orig

    def test_failure_raises_runtime(self) -> None:
        import src.backend.ai_generator as ai_gen

        orig = ai_gen.request_chat

        def boom(*a, **k):
            raise RuntimeError("net down")

        ai_gen.request_chat = boom  # type: ignore[assignment]
        try:
            with self.assertRaises(RuntimeError):
                run_screenshot_skill(SimpleNamespace(), b"x")
        finally:
            ai_gen.request_chat = orig


class RedactionTest(unittest.TestCase):
    def test_truncate_reply_short(self) -> None:
        self.assertEqual(truncate_reply("短摘要"), "短摘要")

    def test_truncate_reply_long(self) -> None:
        long = "x" * 200
        out = truncate_reply(long)
        self.assertLessEqual(len(out), 81)
        self.assertTrue(out.endswith("…"))

    def test_truncate_reply_never_leaks_full(self) -> None:
        secret = "超长秘密内容" * 50
        self.assertNotIn(secret, truncate_reply(secret))


class EnabledTest(unittest.TestCase):
    def test_none_is_disabled(self) -> None:
        self.assertFalse(is_screenshot_explain_enabled(None))

    def test_attr_true(self) -> None:
        self.assertTrue(is_screenshot_explain_enabled(SimpleNamespace(experience_screenshot_explain=True)))

    def test_attr_false(self) -> None:
        self.assertFalse(is_screenshot_explain_enabled(SimpleNamespace(experience_screenshot_explain=False)))

    def test_missing_attr_is_false(self) -> None:
        self.assertFalse(is_screenshot_explain_enabled(SimpleNamespace()))


class ActionRegistryTest(unittest.TestCase):
    def test_registered_read_only_not_dangerous(self) -> None:
        spec = get_action("app.screenshot_explain")
        self.assertIsNotNone(spec)
        self.assertFalse(spec.needs_confirm)
        self.assertFalse(spec.dangerous)
        self.assertNotIn("app.screenshot_explain", DANGEROUS_ACTION_IDS)


class RoutingTest(unittest.TestCase):
    def test_slash_exact(self) -> None:
        i = route_intent("/screenshot-explain")
        self.assertIsNotNone(i)
        self.assertEqual(i.action_id, "app.screenshot_explain")
        self.assertEqual(i.confidence, 1.0)

    def test_keyword(self) -> None:
        self.assertEqual(route_intent("截图解释").action_id, "app.screenshot_explain")

    def test_golden_has_screenshot(self) -> None:
        import json

        path = Path(__file__).resolve().parent / "ai_goldens" / "intent_routes.json"
        rows = json.loads(path.read_text(encoding="utf-8"))
        self.assertTrue(any(r.get("text") == "/screenshot-explain" for r in rows))


class CaptureWidgetTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        qt_app()

    def test_none_widget_no_window(self) -> None:
        from src.application.screenshot_controller import capture_widget_to_png_bytes

        data, status = capture_widget_to_png_bytes(None)
        self.assertEqual(data, b"")
        self.assertEqual(status, "no_window")

    def test_real_widget_produces_png(self) -> None:
        from PySide6.QtWidgets import QLabel

        from src.application.screenshot_controller import capture_widget_to_png_bytes

        w = QLabel("hello screenshot")
        w.resize(40, 20)
        data, status = capture_widget_to_png_bytes(w)
        self.addCleanup(w.deleteLater)
        self.assertEqual(status, "ok")
        self.assertTrue(data)
        self.assertTrue(data.startswith(b"\x89PNG"))


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


def _fake_worker_factory(captured: dict):
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
        captured["target"] = target
        return w

    return factory


class ExplainCurrentTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        qt_app()

    def _make_host(self, *, enabled=False, ai_complete=True, offscreen=True):
        from src.backend.experience.job_registry import JobRegistry
        from src.backend.experience.metrics import ExperienceMetrics

        class Host:
            def __init__(self) -> None:
                self._settings_obj = SimpleNamespace(
                    experience_screenshot_explain=enabled
                )
                self._ai_config = SimpleNamespace(is_complete=ai_complete)
                self.job_tray = JobRegistry()
                self.experience_metrics = ExperienceMetrics()
                self._status: list[str] = []
                self._events: list = []
                self._shown: list[str] = []
                self._experience_worker = None
                self._refresh_called = False

            def statusBar(self):  # noqa: N802
                return _Status(self)

            def _record_experience_event(self, *a, **k):
                self._events.append((a, k))

            def _refresh_experience(self, immediate=False, focus_only=False):
                self._refresh_called = True

            def _show_git_skill_result(self, title, text):
                self._shown.append(text)

        host = Host()
        host._offscreen = offscreen
        return host

    def _patch_app(self, offscreen: bool):
        # Patch QApplication.instance() inside screenshot_controller so the
        # offscreen guard can be toggled per-test.
        import src.application.screenshot_controller as sc
        from PySide6.QtWidgets import QApplication

        orig_instance = QApplication.instance

        def fake_instance():
            app = MagicMock()
            app.platformName = lambda: "offscreen" if offscreen else "xcb"
            return app

        QApplication.instance = staticmethod(fake_instance)  # type: ignore[assignment]
        return orig_instance

    def test_disabled_short_circuits_status(self) -> None:
        from src.application.screenshot_controller import explain_current

        host = self._make_host(enabled=False)
        orig = self._patch_app(offscreen=True)
        try:
            explain_current(host)
        finally:
            from PySide6.QtWidgets import QApplication

            QApplication.instance = orig  # type: ignore[assignment]
        self.assertTrue(any("未开启" in m for m in host._status))
        self.assertIsNone(host._experience_worker)

    def test_offscreen_guard_status(self) -> None:
        from src.application.screenshot_controller import explain_current

        host = self._make_host(enabled=True, offscreen=True)
        orig = self._patch_app(offscreen=True)
        try:
            explain_current(host)
        finally:
            from PySide6.QtWidgets import QApplication

            QApplication.instance = orig  # type: ignore[assignment]
        self.assertTrue(any("可视化窗口" in m for m in host._status))
        self.assertIsNone(host._experience_worker)

    def test_no_config_status(self) -> None:
        from src.application.screenshot_controller import explain_current

        host = self._make_host(enabled=True, ai_complete=False, offscreen=False)
        orig = self._patch_app(offscreen=False)
        try:
            explain_current(host)
        finally:
            from PySide6.QtWidgets import QApplication

            QApplication.instance = orig  # type: ignore[assignment]
        self.assertTrue(any("配置不完整" in m for m in host._status))
        self.assertIsNone(host._experience_worker)

    def test_full_path_runs_worker_and_preview(self) -> None:
        import src.backend.ai_generator as ai_gen

        from src.application.screenshot_controller import explain_current

        orig_chat = ai_gen.request_chat
        ai_gen.request_chat = lambda *a, **k: {  # type: ignore[assignment]
            "choices": [{"message": {"content": "状态：空课可补全"}}]
        }
        try:
            host = self._make_host(enabled=True, ai_complete=True, offscreen=False)
            orig = self._patch_app(offscreen=False)
            try:
                # Replace host's grab-able self with a real widget for capture.
                from PySide6.QtWidgets import QLabel

                label = QLabel("shot")
                label.resize(30, 20)
                host_self = label  # win == host used as widget for grab()
                captured: dict = {}
                host_self._make_ai_worker = _fake_worker_factory(captured)
                host_self._settings_obj = host._settings_obj
                host_self._ai_config = host._ai_config
                host_self.job_tray = host.job_tray
                host_self.experience_metrics = host.experience_metrics
                host_self._experience_worker = None
                host_self._status = host._status
                host_self._events = host._events
                host_self._shown = host._shown
                host_self._refresh_called = False
                host_self.statusBar = lambda: _Status(host)  # type: ignore[assignment]

                def _ev(*a, **k):
                    host._events.append((a, k))
                host_self._record_experience_event = _ev

                def _show(title, text):
                    host._shown.append(text)
                host_self._show_git_skill_result = _show

                def _refr(**k):
                    host._refresh_called = True
                host_self._refresh_experience = _refr

                explain_current(host_self)
                self.addCleanup(label.deleteLater)
            finally:
                from PySide6.QtWidgets import QApplication

                QApplication.instance = orig  # type: ignore[assignment]
            self.assertEqual(host._shown, ["状态：空课可补全"])
            # Timeline recorded with action_id, no screenshot/reply body leak.
            self.assertTrue(host._events)
            args, kwargs = host._events[0]
            self.assertEqual(kwargs.get("action_id"), "app.screenshot_explain")
            joined = str(args) + str(kwargs)
            self.assertNotIn("状态：空课可补全", joined)
            self.assertNotIn("base64", joined)
        finally:
            ai_gen.request_chat = orig_chat

    def test_ai_error_status_no_modal(self) -> None:
        import src.backend.ai_generator as ai_gen

        from src.application.screenshot_controller import explain_current

        orig_chat = ai_gen.request_chat

        def boom(*a, **k):
            raise RuntimeError("net down")

        ai_gen.request_chat = boom  # type: ignore[assignment]
        try:
            host = self._make_host(enabled=True, ai_complete=True, offscreen=False)
            orig = self._patch_app(offscreen=False)
            try:
                from PySide6.QtWidgets import QLabel

                label = QLabel("shot")
                label.resize(30, 20)
                captured: dict = {}
                label._make_ai_worker = _fake_worker_factory(captured)
                label._settings_obj = host._settings_obj
                label._ai_config = host._ai_config
                label.job_tray = host.job_tray
                label.experience_metrics = host.experience_metrics
                label._experience_worker = None
                label._status = host._status
                label._events = host._events
                label._shown = host._shown
                label._refresh_called = False
                label.statusBar = lambda: _Status(host)  # type: ignore[assignment]

                def _ev(*a, **k):
                    host._events.append((a, k))
                label._record_experience_event = _ev

                def _show(title, text):
                    host._shown.append(text)
                label._show_git_skill_result = _show

                def _refr(**k):
                    host._refresh_called = True
                label._refresh_experience = _refr

                explain_current(label)
                self.addCleanup(label.deleteLater)
            finally:
                from PySide6.QtWidgets import QApplication

                QApplication.instance = orig  # type: ignore[assignment]
            self.assertEqual(host._shown, [])
            self.assertTrue(any("失败" in m for m in host._status))
        finally:
            ai_gen.request_chat = orig_chat


if __name__ == "__main__":
    unittest.main()