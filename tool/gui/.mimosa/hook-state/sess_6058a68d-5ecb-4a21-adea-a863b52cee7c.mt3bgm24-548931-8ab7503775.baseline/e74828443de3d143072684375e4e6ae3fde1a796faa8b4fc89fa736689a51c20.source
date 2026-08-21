"""S-10 final v4.56: save_host Soft / execute_save / brief (L1 duck host)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.application.save_host import (  # noqa: E402
    after_save_quality_hints,
    apply_soft_before_save,
    execute_save,
    on_save,
    want_save_brief,
)
from src.application.save_pipeline import SaveRequest  # noqa: E402


class WantBriefTest(unittest.TestCase):
    def test_default_off(self) -> None:
        host = SimpleNamespace(_settings_obj=SimpleNamespace())
        self.assertFalse(want_save_brief(host))

    def test_flag_on(self) -> None:
        host = SimpleNamespace(
            _settings_obj=SimpleNamespace(experience_save_brief=True)
        )
        self.assertTrue(want_save_brief(host))


class SoftBeforeSaveTest(unittest.TestCase):
    def test_soft_denied_returns_zero(self) -> None:
        host = SimpleNamespace(
            _settings_obj=object(),
            adapter=object(),
            undo_stack=MagicMock(),
        )
        with patch(
            "src.backend.experience.resolve_policy",
            return_value=SimpleNamespace(allow_soft=False),
        ):
            self.assertEqual(apply_soft_before_save(host), 0)
        host.undo_stack.push.assert_not_called()

    def test_soft_applies_and_pushes(self) -> None:
        class _Batch:
            fixes = [1, 2, 3]

            def __len__(self) -> int:
                return 3

        host = SimpleNamespace(
            _settings_obj=object(),
            adapter=object(),
            undo_stack=MagicMock(),
            _record_experience_event=MagicMock(),
        )
        with (
            patch(
                "src.backend.experience.resolve_policy",
                return_value=SimpleNamespace(allow_soft=True),
            ),
            patch(
                "src.backend.experience.soft_autopilot.evaluate_soft_fixes",
                return_value=_Batch(),
            ),
            patch("src.application.commands.SoftHygieneCommand") as Cmd,
        ):
            Cmd.return_value = MagicMock()
            n = apply_soft_before_save(host)
            self.assertEqual(n, 3)
            host.undo_stack.push.assert_called_once()
            host._record_experience_event.assert_called()


class ExecuteSaveTest(unittest.TestCase):
    def _host(self, *, save_ok=True):
        adapter = MagicMock()
        result = SimpleNamespace(ok=save_ok, message="ok" if save_ok else "fail", errors=[])
        if not save_ok:
            result.errors = [{"level": "error", "message": "x"}]
        adapter.save = MagicMock(return_value=result)
        return SimpleNamespace(
            adapter=adapter,
            tree=MagicMock(),
            undo_stack=MagicMock(),
            experience=MagicMock(context=None),
            statusBar=MagicMock(return_value=MagicMock()),
            _sync_focus_ring=MagicMock(),
            _refresh_experience=MagicMock(),
            _show_validation_report=MagicMock(),
            _settings_obj=SimpleNamespace(experience_save_brief=False),
            _record_experience_event=MagicMock(),
            _refresh_ambient=MagicMock(),
        )

    def test_success_refreshes_tree_and_clean(self) -> None:
        host = self._host(save_ok=True)
        with (
            patch(
                "src.application.save_host.apply_soft_before_save", return_value=0
            ),
            patch("src.infrastructure.telemetry.telemetry"),
        ):
            out = execute_save(host, SaveRequest(reason="menu", run_soft=True))
        self.assertTrue(out.ok)
        host.tree.refresh.assert_called()
        host.undo_stack.setClean.assert_called()

    def test_failure_shows_validation_when_ui(self) -> None:
        host = self._host(save_ok=False)
        with (
            patch(
                "src.application.save_host.apply_soft_before_save", return_value=0
            ),
            patch("src.infrastructure.telemetry.telemetry"),
        ):
            out = execute_save(
                host,
                SaveRequest(
                    reason="menu", run_soft=True, show_validation_ui=True
                ),
            )
        self.assertFalse(out.ok)
        host._show_validation_report.assert_called()

    def test_on_save_returns_bool(self) -> None:
        host = self._host(save_ok=True)
        with (
            patch(
                "src.application.save_host.execute_save",
                return_value=SimpleNamespace(ok=True),
            ) as ex,
        ):
            self.assertTrue(on_save(host, reason="menu"))
            ex.assert_called_once()


class YellowHintsTest(unittest.TestCase):
    def test_no_hints_empty_string(self) -> None:
        host = SimpleNamespace(
            experience=SimpleNamespace(context=None),
            _refresh_ambient=MagicMock(),
            _record_experience_event=MagicMock(),
        )
        with patch(
            "src.backend.experience.scope_format.yellow_quality_summary",
            return_value={"has_hints": False},
        ):
            self.assertEqual(after_save_quality_hints(host), "")


if __name__ == "__main__":
    unittest.main()
