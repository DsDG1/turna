"""#6/#7: AutoApplyToken scope + auto-path PreviewHost behaviour.

The token used to stay bound on the host for the whole session after one
auto dispatch, so every later manual menu/right-key confirm was silently
answered Yes. It now follows the offer lifecycle: consumed by the offer
that used it, dropped when an offer clears, and only honored by
``safe_question`` while the strip truly has a pending AI action.
"""
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

from PySide6.QtWidgets import QWidget

from tests._qtapp import _App


class _TokenHost(QWidget):
    """Top-level widget standing in for the MainWindow (token + strip)."""


class _FakePreview:
    """Duck-typed strip for hosts that are not real widgets."""

    def __init__(self, pending: bool = False) -> None:
        self._pending = pending

    def has_pending(self) -> bool:
        return self._pending


def _token(opaque: bool = False):
    from src.backend.experience.auto_apply import issue_auto_apply_token

    return issue_auto_apply_token("lesson.fill_empty", opaque=opaque)


class AutoApplyScopeTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        _App.get()

    def test_bound_token_alone_no_longer_forces_confirm_auto(self) -> None:
        """#6: token on host + nothing pending → safe_question path is manual."""
        from src.application.ui_guard import resolve_auto_apply_state

        host = SimpleNamespace(_auto_apply_token=_token(), preview_host=_FakePreview(False))
        should_auto, _opaque, tok = resolve_auto_apply_state(host)
        self.assertFalse(should_auto)
        self.assertIsNone(tok)

    def test_bound_token_counts_while_strip_has_pending(self) -> None:
        from src.application.ui_guard import resolve_auto_apply_state

        host = SimpleNamespace(
            _auto_apply_token=_token(), preview_host=_FakePreview(True)
        )
        should_auto, _opaque, _tok = resolve_auto_apply_state(host)
        self.assertTrue(should_auto)

    def test_offer_resolution_still_sees_bound_token(self) -> None:
        """Async offers consume the token at land time — no pending needed."""
        from src.application.ui_guard import resolve_auto_apply_for_offer

        host = SimpleNamespace(_auto_apply_token=_token(), preview_host=_FakePreview(False))
        should_auto, _opaque, _tok = resolve_auto_apply_for_offer(host)
        self.assertTrue(should_auto)

    def test_offer_auto_applies_and_unbinds_host_token(self) -> None:
        from src.backend.experience.auto_apply import (
            bind_auto_apply_token,
            host_auto_apply_token,
        )
        from src.widgets.preview_host import PreviewHost

        win = _TokenHost()
        ph = PreviewHost(win)
        win.preview_host = ph
        applied: list[int] = []
        bind_auto_apply_token(win, _token())

        ph.offer(title="t", summary="s", apply_fn=lambda: applied.append(1))
        self.assertEqual(applied, [1])  # auto-applied, no strip shown
        self.assertFalse(ph.isVisible())
        self.assertIsNone(host_auto_apply_token(win))  # consumed

        # And afterwards manual confirms are manual again (strict resolve).
        from src.application.ui_guard import resolve_auto_apply_state

        should_auto, _o, _t = resolve_auto_apply_state(win)
        self.assertFalse(should_auto)

    def test_manual_discard_also_unbinds(self) -> None:
        from src.backend.experience.auto_apply import (
            bind_auto_apply_token,
            host_auto_apply_token,
        )
        from src.widgets.preview_host import PreviewHost

        win = _TokenHost()
        win.show()  # has_pending() requires a visible ancestor (offscreen ok)
        ph = PreviewHost(win)
        win.preview_host = ph
        # Demoted token: offer lands pending instead of auto-applying.
        from src.backend.experience.auto_apply import bump_auto_apply_generation

        token = _token()
        bump_auto_apply_generation()  # invalidate
        bind_auto_apply_token(win, token)
        ph.offer(title="t", summary="s", apply_fn=lambda: None)
        self.assertTrue(ph.has_pending())
        ph._on_discard()
        self.assertIsNone(host_auto_apply_token(win))

    def tearDown(self) -> None:
        from src.backend.experience.auto_apply import clear_auto_apply_token

        clear_auto_apply_token(None)


class OfferAutoPreviewTest(unittest.TestCase):
    """#7: fill handlers hand AI results to the strip, never a modal, on auto."""

    @classmethod
    def setUpClass(cls) -> None:
        _App.get()

    def test_auto_path_offers_without_modal(self) -> None:
        from src.application.experience_handlers.fill import _offer_auto_preview
        from src.backend.experience.auto_apply import bind_auto_apply_token
        from src.widgets.preview_host import PreviewHost

        win = _TokenHost()
        ph = PreviewHost(win)
        win.preview_host = ph
        bind_auto_apply_token(win, _token())
        applied: list[int] = []

        handed = _offer_auto_preview(
            win,
            title="清待补已生成",
            summary="AI 补全建议",
            apply_fn=lambda: applied.append(1),
        )
        self.assertTrue(handed)
        self.assertEqual(applied, [1])  # consumed by the auto offer
        self.assertFalse(ph.isVisible())  # no strip, no modal

    def test_manual_path_falls_back_to_false(self) -> None:
        from src.application.experience_handlers.fill import _offer_auto_preview
        from src.widgets.preview_host import PreviewHost

        win = _TokenHost()  # no token bound
        win.preview_host = PreviewHost(win)
        handed = _offer_auto_preview(
            win, title="t", summary="s", apply_fn=lambda: None
        )
        self.assertFalse(handed)  # caller shows its interactive preview

    def test_missing_strip_falls_back_to_false(self) -> None:
        from src.application.experience_handlers.fill import _offer_auto_preview

        win = SimpleNamespace(preview_host=None)
        with patch(
            "src.application.ui_guard.resolve_auto_apply_for_offer",
            return_value=(True, False, _token()),
        ):
            handed = _offer_auto_preview(
                win, title="t", summary="s", apply_fn=lambda: None
            )
        self.assertFalse(handed)


class SilentDriveWordingTest(unittest.TestCase):
    """#7: dispatch returning must not claim 已自动 before anything applied."""

    def test_notify_silent_result_reports_in_progress(self) -> None:
        from src.application.presence_drive import _notify_silent_result

        messages: list[str] = []
        host = MagicMock()
        host.statusBar.return_value = MagicMock()
        host.statusBar.return_value.showMessage = (
            lambda msg, ms=0: messages.append(msg)
        )
        _notify_silent_result(
            host, action_id="lesson.fill_empty", title="填充空课", opaque=False, ok=True
        )
        self.assertEqual(len(messages), 1)
        self.assertIn("AI 执行中", messages[0])
        self.assertNotIn("已自动", messages[0])


if __name__ == "__main__":
    unittest.main()
