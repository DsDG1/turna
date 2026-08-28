"""E5-A SavePipeline pure orchestration tests (no MainWindow required)."""
from __future__ import annotations

import sys
import unittest
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.application.save_pipeline import (  # noqa: E402
    CLOSE_REASONS,
    REASON_CLOSE_AUTO,
    REASON_MENU,
    REASON_PALETTE,
    SaveOutcome,
    SaveRequest,
    compose_status_message,
    run_save_pipeline,
)


@dataclass
class _FakeSaveResult:
    ok: bool
    message: str = ""
    errors: list[dict[str, Any]] = field(default_factory=list)


class SavePipelineTest(unittest.TestCase):
    def test_success_without_soft(self) -> None:
        calls: list[str] = []

        def do_save() -> _FakeSaveResult:
            calls.append("save")
            return _FakeSaveResult(ok=True, message="保存成功")

        outcome = run_save_pipeline(
            SaveRequest(reason=REASON_MENU, run_soft=False),
            do_save=do_save,
            apply_soft=lambda: (_ for _ in ()).throw(AssertionError("soft off")),
            after_success=lambda o: calls.append(f"ok:{o.soft_count}"),
        )
        self.assertTrue(outcome.ok)
        self.assertEqual(outcome.soft_count, 0)
        self.assertEqual(calls, ["save", "ok:0"])

    def test_soft_runs_before_save(self) -> None:
        order: list[str] = []

        def apply_soft() -> int:
            order.append("soft")
            return 3

        def do_save() -> _FakeSaveResult:
            order.append("save")
            return _FakeSaveResult(ok=True, message="ok")

        outcome = run_save_pipeline(
            SaveRequest(reason=REASON_MENU, run_soft=True),
            do_save=do_save,
            apply_soft=apply_soft,
        )
        self.assertEqual(order, ["soft", "save"])
        self.assertEqual(outcome.soft_count, 3)
        self.assertTrue(outcome.ok)

    def test_soft_error_does_not_block_save(self) -> None:
        soft_errs: list[str] = []
        successes: list[SaveOutcome] = []

        def apply_soft() -> int:
            raise RuntimeError("soft boom")

        outcome = run_save_pipeline(
            SaveRequest(reason=REASON_MENU, run_soft=True),
            do_save=lambda: _FakeSaveResult(ok=True, message="保存成功"),
            apply_soft=apply_soft,
            on_soft_error=lambda e: soft_errs.append(str(e)),
            after_success=lambda o: successes.append(o),
        )
        self.assertTrue(outcome.ok)
        self.assertEqual(outcome.soft_count, 0)
        self.assertIn("soft boom", outcome.soft_error or "")
        self.assertEqual(soft_errs, ["soft boom"])
        self.assertEqual(len(successes), 1)

    def test_validation_failure_calls_after_failure(self) -> None:
        failures: list[SaveOutcome] = []
        errors = [{"level": "error", "message": "bad"}]

        outcome = run_save_pipeline(
            SaveRequest(reason=REASON_CLOSE_AUTO, run_soft=True),
            do_save=lambda: _FakeSaveResult(
                ok=False, message="校验失败，已回滚", errors=errors
            ),
            apply_soft=lambda: 0,
            after_success=lambda o: self.fail("should not succeed"),
            after_failure=lambda o: failures.append(o),
        )
        self.assertFalse(outcome.ok)
        self.assertEqual(outcome.errors, errors)
        self.assertEqual(outcome.blocked_reason, "validation")
        self.assertEqual(len(failures), 1)
        self.assertTrue(outcome.is_close)

    def test_run_soft_false_skips_apply(self) -> None:
        applied = {"n": 0}

        def apply_soft() -> int:
            applied["n"] += 1
            return 1

        run_save_pipeline(
            SaveRequest(reason=REASON_MENU, run_soft=False),
            do_save=lambda: _FakeSaveResult(ok=True),
            apply_soft=apply_soft,
        )
        self.assertEqual(applied["n"], 0)

    def test_on_triggered_receives_reason(self) -> None:
        seen: list[str] = []

        run_save_pipeline(
            SaveRequest(reason=REASON_PALETTE, run_soft=False),
            do_save=lambda: _FakeSaveResult(ok=True),
            on_triggered=lambda r: seen.append(r.reason),
        )
        self.assertEqual(seen, [REASON_PALETTE])

    def test_compose_status_message_soft_and_yellow(self) -> None:
        self.assertEqual(
            compose_status_message(base="保存成功", soft_count=2),
            "保存成功 · 规则规范化 2 项",
        )
        self.assertEqual(
            compose_status_message(
                base="保存成功",
                soft_count=1,
                yellow_summary="仍有 2 处可改善",
            ),
            "仍有 2 处可改善 · 规则规范化 1 项",
        )
        self.assertEqual(
            compose_status_message(base="保存成功", soft_count=0),
            "保存成功",
        )

    def test_close_reasons_constant(self) -> None:
        self.assertIn(REASON_CLOSE_AUTO, CLOSE_REASONS)

    def test_menu_and_close_same_soft_order(self) -> None:
        """Regression: close must be able to run Soft before save (E5-A)."""

        def once(reason: str) -> list[str]:
            order: list[str] = []
            run_save_pipeline(
                SaveRequest(reason=reason, run_soft=True),
                do_save=lambda: (order.append("save") or _FakeSaveResult(ok=True)),
                apply_soft=lambda: (order.append("soft") or 1),
            )
            return order

        self.assertEqual(once(REASON_MENU), ["soft", "save"])
        self.assertEqual(once(REASON_CLOSE_AUTO), ["soft", "save"])


class SavePipelineHostIntegrationTest(unittest.TestCase):
    """Light MainWindow wiring: menu and close_auto both hit Soft when allowed."""

    @classmethod
    def setUpClass(cls) -> None:
        from tests._mainwindow_fixture import build_main_window, qt_app

        qt_app()
        cls.win = build_main_window()

    def setUp(self) -> None:
        from tests._mainwindow_fixture import reset_main_window

        reset_main_window(self.win)
        self.win._settings_obj.experience_soft_autopilot = True
        self.win._settings_obj.experience_mode = "copilot"
        self.win.adapter.vocab = [
            {"id": "w1", "term": "  merhaba  ", "translation": "hi", "tags": []}
        ]
        self.win.adapter.expressions = []

    def test_execute_save_close_auto_runs_soft(self) -> None:
        from src.application.save_pipeline import REASON_CLOSE_AUTO, SaveRequest
        from unittest.mock import MagicMock

        # Avoid real disk save; Soft should still mutate vocab before do_save.
        saved = {"n": 0}

        def fake_save():
            saved["n"] += 1
            # Soft must have already trimmed.
            self.assertEqual(self.win.adapter.vocab[0]["term"], "merhaba")
            return _FakeSaveResult(ok=True, message="保存成功")

        self.win.adapter.save = fake_save  # type: ignore[method-assign]
        outcome = self.win._execute_save(
            SaveRequest(
                reason=REASON_CLOSE_AUTO,
                run_soft=True,
                show_validation_ui=False,
            )
        )
        self.assertTrue(outcome.ok)
        self.assertGreaterEqual(outcome.soft_count, 1)
        self.assertEqual(saved["n"], 1)
        self.assertEqual(self.win.adapter.vocab[0]["term"], "merhaba")

    def test_on_save_dispatches_async_worker(self) -> None:
        """Menu save runs adapter.save on a worker; completion is signalled.

        (Was ``test_on_save_returns_bool`` when the save was synchronous and
        returned its outcome directly.)
        """
        import time

        saved = {"n": 0}

        def fake_save(**_kwargs):
            saved["n"] += 1
            return _FakeSaveResult(ok=True, message="ok")

        self.win.adapter.save = fake_save  # type: ignore[method-assign]
        self.win._settings_obj.experience_soft_autopilot = False
        self.win._on_save(reason="menu")
        self.assertIsNotNone(self.win._save_worker)
        from tests._qtapp import qt_app

        t0 = time.perf_counter()
        while self.win._save_worker is not None:
            qt_app().processEvents()
            if time.perf_counter() - t0 > 5.0:
                self.fail("save worker did not finish")
        self.assertEqual(saved["n"], 1)


if __name__ == "__main__":
    unittest.main()
