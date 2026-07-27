"""S-07 JobTray multi-job UI tests (+ O-03 duration tooltip)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from tests._qtapp import qt_app  # noqa: E402


class JobTrayTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        qt_app()

    def test_multi_job_and_finish_one(self) -> None:
        from src.widgets.job_tray import JobTray

        tray = JobTray()
        tray.start_job("validate-open", "本地诊断中 …", kind="validate")
        tray.start_job("stubs-s1", "清待补 …", kind="ai", node_key="section:s1")
        self.assertEqual(tray.job_count(), 2)
        self.assertTrue(tray.is_busy())
        self.assertTrue(tray.is_busy_ai())
        text = tray._label.text()
        self.assertIn("（2）", text)
        tray.finish_job("validate-open")
        self.assertEqual(tray.job_count(), 1)
        self.assertTrue(tray.is_busy_ai())
        tray.finish_job("stubs-s1")
        self.assertFalse(tray.is_busy())
        self.assertEqual(tray._label.text(), "任务：空闲")

    def test_legacy_set_idle_does_not_clear_other_jobs(self) -> None:
        from src.widgets.job_tray import JobTray

        tray = JobTray()
        tray.start_job("chip-1", "AI 改题", kind="ai")
        tray.set_busy("旧式 busy")
        self.assertEqual(tray.job_count(), 2)
        tray.set_idle()  # only legacy
        self.assertEqual(tray.job_count(), 1)
        self.assertIsNotNone(tray.registry.get("chip-1"))
        tray.set_idle(all_jobs=True)
        self.assertEqual(tray.job_count(), 0)

    def test_active_jobs_snapshots(self) -> None:
        from src.widgets.job_tray import JobTray

        tray = JobTray()
        tray.start_job("a", "A", kind="ai")
        jobs = tray.active_jobs()
        self.assertEqual(len(jobs), 1)
        self.assertEqual(jobs[0]["job_id"], "a")

    def test_context_receives_active_jobs(self) -> None:
        from src.application.experience_shell import ExperienceShell
        from src.widgets.job_tray import JobTray

        class _Stub:
            sections: list = []
            vocab: list = []
            expressions: list = []
            grammar_points: list = []
            index: dict = {"language": "tr"}
            course_dir = None

        tray = JobTray()
        tray.start_job("j1", "进行中", kind="ai")
        shell = ExperienceShell(debounce_ms=0)
        shell.set_adapter(_Stub())
        shell.set_active_jobs(tray.active_jobs())
        ctx = shell.rebuild_now()
        self.assertIsNotNone(ctx)
        self.assertEqual(len(ctx.active_jobs), 1)
        self.assertEqual(ctx.active_jobs[0]["job_id"], "j1")

    def test_flyout_locate_emits_signal(self) -> None:
        from src.widgets.job_tray import JobTray

        tray = JobTray()
        tray.start_job("stubs-s1", "清待补 …", kind="ai", node_key="section:s1")
        received: list[str] = []
        tray.job_activated.connect(lambda jid: received.append(jid))
        tray.emit_locate("stubs-s1")
        self.assertEqual(received, ["stubs-s1"])
        # Signal emission does not change the registry.
        self.assertEqual(tray.job_count(), 1)

    def test_flyout_locate_unknown_job_emits_id_only(self) -> None:
        # Emitting for an unknown id still fires (owner handles gracefully).
        from src.widgets.job_tray import JobTray

        tray = JobTray()
        received: list[str] = []
        tray.job_activated.connect(lambda jid: received.append(jid))
        tray.emit_locate("nope")
        self.assertEqual(received, ["nope"])

    def test_cancel_signal_exists(self) -> None:
        from src.widgets.job_tray import JobTray

        tray = JobTray()
        # Signal is reserved; surface exists for future cooperative cancel.
        self.assertTrue(hasattr(tray, "job_cancel_requested"))


class JobTrayLocateWiringTest(unittest.TestCase):
    """app._on_job_activated locates the job's node in the tree."""

    @classmethod
    def setUpClass(cls) -> None:
        from tests._mainwindow_fixture import build_main_window

        cls.win = build_main_window()

    def setUp(self) -> None:
        from tests._mainwindow_fixture import reset_main_window

        reset_main_window(self.win)

    def test_locate_section_selects_tree(self) -> None:
        from unittest.mock import MagicMock

        self.win.tree.select_section = MagicMock()
        self.win.job_tray.start_job("stubs-s1", "清待补 …", kind="ai", node_key="section:s1")
        self.win._on_job_activated("stubs-s1")
        self.win.tree.select_section.assert_called_once_with("s1")

    def test_locate_lesson_selects_tree(self) -> None:
        from unittest.mock import MagicMock

        self.win.tree.select_lesson = MagicMock()
        self.win.job_tray.start_job("chip-q1", "AI 改题", kind="ai", node_key="lesson:s1-l2")
        self.win._on_job_activated("chip-q1")
        self.win.tree.select_lesson.assert_called_once_with("s1-l2")

    def test_locate_job_without_node_key_warns(self) -> None:
        from unittest.mock import MagicMock

        self.win.tree.select_section = MagicMock()
        self.win.job_tray.start_job("validate-open", "本地诊断", kind="validate")
        # No node_key → no selection, status message only.
        self.win._on_job_activated("validate-open")
        self.win.tree.select_section.assert_not_called()

    def test_locate_unknown_job_warns(self) -> None:
        from unittest.mock import MagicMock

        self.win.tree.select_lesson = MagicMock()
        self.win._on_job_activated("does-not-exist")
        self.win.tree.select_lesson.assert_not_called()


class JobTrayDurationTooltipTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        qt_app()

    def test_tray_shows_estimate(self) -> None:
        from src.widgets.job_tray import JobTray

        tray = JobTray()
        self.addCleanup(tray.deleteLater)
        with patch("src.backend.experience.job_registry.time") as t:
            t.time.side_effect = [100.0, 190.0, 200.0]
            tray.start_job("a", "清待补：正在补全词条 …", kind="ai")
            tray.finish_job("a")
            tray.start_job("b", "清待补：正在补全词条 …", kind="ai")
        self.assertIn("约 2 分钟", tray._label.toolTip())


if __name__ == "__main__":
    unittest.main()
