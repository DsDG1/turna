"""v4.14: chip path records the Experience metrics funnel (§8.12).

The chip flow (teacher/item_ai_chip.py) must record guard rejected/released
and job started/finished/failed like every other AI write path.
"""
from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from tests._qtapp import qt_app  # noqa: E402


class _Signal:
    def __init__(self) -> None:
        self._cbs: list = []

    def connect(self, cb) -> None:
        self._cbs.append(cb)

    def emit(self, *args) -> None:
        for cb in self._cbs:
            cb(*args)


class _FakeWorker:
    last: "_FakeWorker | None" = None

    def __init__(self, fn, *args, **kwargs) -> None:
        self.fn = fn
        self.args = args
        self.kwargs = kwargs
        self.result_ready = _Signal()
        self.error_occurred = _Signal()
        _FakeWorker.last = self

    def cancel(self) -> None:
        pass

    def isRunning(self) -> bool:
        return False

    def start(self) -> None:
        pass


class _Metrics:
    def __init__(self) -> None:
        self.counts: dict[tuple, int] = {}

    def _inc(self, key: tuple) -> None:
        self.counts[key] = self.counts.get(key, 0) + 1

    def inc_guard(self, stage: str) -> None:
        self._inc(("guard", stage))

    def inc_job(self, kind: str, stage: str) -> None:
        self._inc(("job", kind, stage))


class _JobTray:
    def __init__(self) -> None:
        self.jobs: list[str] = []

    def start_job(self, job_id, *a, **k) -> None:
        self.jobs.append(job_id)

    def finish_job(self, job_id) -> None:
        if job_id in self.jobs:
            self.jobs.remove(job_id)


class _Preview:
    def __init__(self) -> None:
        self.offers: list[dict] = []

    def set_busy(self, _msg: str) -> None:
        pass

    def clear(self) -> None:
        pass

    def offer(self, **kwargs) -> None:
        self.offers.append(kwargs)


class ChipMetricsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        qt_app()

    def setUp(self) -> None:
        _FakeWorker.last = None

    def _make_owner(self):
        from PySide6.QtWidgets import QWidget
        from src.backend.experience.conflict_guard import ConflictGuard

        root = QWidget()
        self.addCleanup(root.deleteLater)
        root.preview_host = _Preview()  # type: ignore[attr-defined]
        root.job_tray = _JobTray()  # type: ignore[attr-defined]
        root.conflict_guard = ConflictGuard()  # type: ignore[attr-defined]
        root.experience_metrics = _Metrics()  # type: ignore[attr-defined]
        child = QWidget(root)
        return root, child

    def _run_chip(self, child, after=None):
        from src.teacher.item_ai_chip import run_item_chip

        adapter = SimpleNamespace(vocab=[], expressions=[], grammar_points=[])
        with patch(
            "src.app.current_ai_config",
            return_value=SimpleNamespace(is_complete=True),
        ), patch(
            "src.dialogs.ai.worker.AiRequestWorker", _FakeWorker
        ), patch("src.teacher.item_ai_chip.QMessageBox"):
            run_item_chip(
                child,
                adapter=adapter,
                stage={"id": "st1"},
                item={"id": "q1", "prompt": "old prompt"},
                instruction="make it easier",
                undo_stack=None,
            )
            # Worker callbacks may hit QMessageBox: fire them while patched.
            if after is not None:
                after(_FakeWorker.last)

    def test_success_records_started_finished_and_guard_released(self) -> None:
        root, child = self._make_owner()
        m = root.experience_metrics

        def _fire(worker):
            self.assertIsNotNone(worker)
            self.assertEqual(m.counts.get(("job", "ai", "started")), 1)
            worker.result_ready.emit({"id": "q1", "prompt": "new prompt"})

        self._run_chip(child, after=_fire)
        self.assertEqual(m.counts.get(("job", "ai", "finished")), 1)
        self.assertEqual(m.counts.get(("job", "ai", "failed"), 0), 0)
        self.assertEqual(m.counts.get(("guard", "released")), 1)
        self.assertFalse(root.conflict_guard.is_busy("item:q1"))
        self.assertEqual(len(root.preview_host.offers), 1)

    def test_error_records_failed(self) -> None:
        root, child = self._make_owner()

        def _fire(worker):
            self.assertIsNotNone(worker)
            worker.error_occurred.emit("boom")

        self._run_chip(child, after=_fire)
        m = root.experience_metrics
        self.assertEqual(m.counts.get(("job", "ai", "failed")), 1)
        self.assertEqual(m.counts.get(("job", "ai", "finished"), 0), 0)
        self.assertEqual(m.counts.get(("guard", "released")), 1)
        self.assertFalse(root.conflict_guard.is_busy("item:q1"))

    def test_guard_reject_records_rejected_and_starts_no_job(self) -> None:
        root, child = self._make_owner()
        self.assertTrue(root.conflict_guard.try_acquire("item:q1", "other-job"))
        self._run_chip(child)
        m = root.experience_metrics
        self.assertEqual(m.counts.get(("guard", "rejected")), 1)
        self.assertIsNone(_FakeWorker.last)
        self.assertEqual(root.job_tray.jobs, [])
        self.assertEqual(m.counts.get(("job", "ai", "started"), 0), 0)

    def test_chip_apply_then_undo_restores(self) -> None:
        """R-09: chip → patch → undo restores; on_applied fires for 校验回流."""
        from PySide6.QtGui import QUndoStack
        from PySide6.QtWidgets import QWidget
        from src.backend.experience.conflict_guard import ConflictGuard
        from src.teacher.item_ai_chip import run_item_chip

        root = QWidget()
        self.addCleanup(root.deleteLater)
        root.preview_host = _Preview()  # type: ignore[attr-defined]
        root.job_tray = None  # type: ignore[attr-defined]
        root.conflict_guard = ConflictGuard()  # type: ignore[attr-defined]
        owner = QWidget(root)
        stage = {"id": "st1", "items": [{"id": "q1", "prompt": "old"}]}
        stack = QUndoStack()
        applied: list[str] = []
        adapter = SimpleNamespace(vocab=[], expressions=[], grammar_points=[])
        with patch(
            "src.app.current_ai_config",
            return_value=SimpleNamespace(is_complete=True),
        ), patch(
            "src.dialogs.ai.worker.AiRequestWorker", _FakeWorker
        ), patch("src.teacher.item_ai_chip.QMessageBox"):
            run_item_chip(
                owner,
                adapter=adapter,
                stage=stage,
                item=stage["items"][0],
                instruction="make it easier",
                undo_stack=stack,
                on_applied=lambda: applied.append("ok"),
            )
            worker = _FakeWorker.last
            self.assertIsNotNone(worker)
            worker.result_ready.emit({"id": "q1", "prompt": "new"})
            offer = root.preview_host.offers[-1]
            self.assertIsNotNone(offer)
            offer["apply_fn"]()
        self.assertEqual(stage["items"][0]["prompt"], "new")
        self.assertEqual(stage["items"][0]["id"], "q1")
        self.assertEqual(applied, ["ok"])
        self.assertEqual(stack.count(), 1)
        stack.undo()
        self.assertEqual(stage["items"][0]["prompt"], "old")


class LessonStyleChipTest(unittest.TestCase):
    """R-07 (v4.51): applied chip instruction → per-lesson session style memory."""

    @classmethod
    def setUpClass(cls) -> None:
        qt_app()

    def setUp(self) -> None:
        _FakeWorker.last = None

    def _make_owner(self):
        from PySide6.QtWidgets import QWidget
        from src.backend.experience.conflict_guard import ConflictGuard
        from src.backend.experience.memory import ExperienceMemory

        root = QWidget()
        self.addCleanup(root.deleteLater)
        root.preview_host = _Preview()  # type: ignore[attr-defined]
        root.job_tray = None  # type: ignore[attr-defined]
        root.conflict_guard = ConflictGuard()  # type: ignore[attr-defined]
        root.experience_memory = ExperienceMemory()  # type: ignore[attr-defined]
        return root, QWidget(root)

    def _run_chip(
        self, child, stage: dict, *, lesson_id: str, instruction: str, apply: bool
    ) -> None:
        from src.teacher.item_ai_chip import run_item_chip

        adapter = SimpleNamespace(vocab=[], expressions=[], grammar_points=[])
        with patch(
            "src.app.current_ai_config",
            return_value=SimpleNamespace(is_complete=True),
        ), patch(
            "src.dialogs.ai.worker.AiRequestWorker", _FakeWorker
        ), patch("src.teacher.item_ai_chip.QMessageBox"):
            run_item_chip(
                child,
                adapter=adapter,
                stage=stage,
                item=stage["items"][0],
                instruction=instruction,
                undo_stack=None,
                lesson_id=lesson_id,
            )
            worker = _FakeWorker.last
            self.assertIsNotNone(worker)
            worker.result_ready.emit({"id": "q1", "prompt": "new"})
            if apply:
                root = child.parentWidget()
                root.preview_host.offers[-1]["apply_fn"]()

    def test_apply_records_style_in_session_memory(self) -> None:
        root, child = self._make_owner()
        stage = {"id": "st1", "items": [{"id": "q1", "prompt": "old"}]}
        self._run_chip(child, stage, lesson_id="l-1", instruction="更口语化", apply=True)
        self.assertEqual(
            root.experience_memory.lesson_style_hints("l-1"), ["更口语化"]
        )

    def test_discard_does_not_record(self) -> None:
        root, child = self._make_owner()
        stage = {"id": "st1", "items": [{"id": "q1", "prompt": "old"}]}
        self._run_chip(child, stage, lesson_id="l-1", instruction="更口语化", apply=False)
        self.assertEqual(root.experience_memory.lesson_style_hints("l-1"), [])

    def test_next_same_lesson_instruction_carries_style_suffix(self) -> None:
        root, child = self._make_owner()
        stage = {"id": "st1", "items": [{"id": "q1", "prompt": "old"}]}
        self._run_chip(child, stage, lesson_id="l-1", instruction="更口语化", apply=True)
        self._run_chip(child, stage, lesson_id="l-1", instruction="换一种问法", apply=False)
        worker = _FakeWorker.last
        self.assertIsNotNone(worker)
        sent = str(worker.args[2])
        self.assertIn("换一种问法", sent)
        self.assertIn("本课已用风格", sent)
        self.assertIn("更口语化", sent)

    def test_other_lesson_gets_no_style_suffix(self) -> None:
        root, child = self._make_owner()
        stage = {"id": "st1", "items": [{"id": "q1", "prompt": "old"}]}
        self._run_chip(child, stage, lesson_id="l-1", instruction="更口语化", apply=True)
        self._run_chip(child, stage, lesson_id="l-2", instruction="换一种问法", apply=False)
        worker = _FakeWorker.last
        self.assertIsNotNone(worker)
        self.assertNotIn("本课已用风格", str(worker.args[2]))


if __name__ == "__main__":
    unittest.main()
