"""UI fit: FlowLayout wrapping, screen clamping, and no clipped buttons."""
from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from PySide6.QtWidgets import (
    QApplication,
    QDialog,
    QPushButton,
    QWidget,
)

from src.infrastructure.screen_fit import install_screen_clamp
from src.widgets.ui.flow_layout import FlowLayout
from tests._qtapp import _App


def _mk_qsettings():
    store: dict = {"recent_repos": "[]"}
    qs = MagicMock()
    qs.value = lambda key, default=None: store.get(key, default)
    qs.contains = lambda key: key in store
    qs.remove = lambda key: store.pop(key, None)
    qs.setValue = lambda key, value: store.__setitem__(key, value)
    return qs


class FlowLayoutTest(unittest.TestCase):
    def test_many_buttons_wrap_instead_of_squeezing(self) -> None:
        app = _App.get()
        host = QWidget()
        lay = FlowLayout(hspacing=8, vspacing=8)
        buttons = [QPushButton(f"按钮编号{i}") for i in range(6)]
        for btn in buttons:
            lay.addWidget(btn)
        host.setLayout(lay)
        host.resize(320, 400)
        host.show()
        app.processEvents()

        # Every button keeps at least its size-hint width: no clipped text.
        for btn in buttons:
            self.assertGreaterEqual(
                btn.width(), btn.sizeHint().width() - 1,
                f"{btn.text()} squeezed: {btn.width()} < {btn.sizeHint().width()}",
            )
        # And the row actually wrapped (more than one visual line).
        ys = {btn.y() for btn in buttons}
        self.assertGreater(len(ys), 1)
        host.hide()

    def test_minimum_width_is_one_item_not_the_sum(self) -> None:
        host = QWidget()
        lay = FlowLayout()
        widths = []
        for i in range(6):
            btn = QPushButton(f"按钮编号{i}")
            lay.addWidget(btn)
            widths.append(btn.sizeHint().width())
        host.setLayout(lay)
        self.assertLessEqual(lay.minimumSize().width(), max(widths) + 16)


class ScreenClampTest(unittest.TestCase):
    def setUp(self) -> None:
        app = _App.get()
        self._guard = install_screen_clamp(app)
        self.addCleanup(app.removeEventFilter, self._guard)

    def _avail(self):
        app = QApplication.instance()
        return app.primaryScreen().availableGeometry()

    def test_oversized_dialog_is_clamped_on_show(self) -> None:
        app = _App.get()
        dlg = QDialog()
        dlg.resize(2000, 1500)
        dlg.show()
        app.processEvents()
        avail = self._avail()
        self.assertLessEqual(dlg.width(), avail.width())
        self.assertLessEqual(dlg.height(), avail.height())
        self.assertTrue(avail.contains(dlg.geometry()))
        dlg.hide()

    def test_fitting_dialog_keeps_size(self) -> None:
        app = _App.get()
        dlg = QDialog()
        dlg.resize(300, 200)
        dlg.show()
        app.processEvents()
        self.assertEqual((dlg.width(), dlg.height()), (300, 200))
        dlg.hide()

    def test_offscreen_position_is_nudged_back(self) -> None:
        app = _App.get()
        dlg = QDialog()
        dlg.resize(300, 200)
        dlg.move(-150, -150)
        dlg.show()
        app.processEvents()
        avail = self._avail()
        self.assertGreaterEqual(dlg.x(), avail.left())
        self.assertGreaterEqual(dlg.y(), avail.top())
        dlg.hide()


class DialogMinWidthRegressionTest(unittest.TestCase):
    """Small screens must stay reachable: min widths shrink, buttons intact."""

    def test_textbook_library_fits_narrow_and_does_not_clip(self) -> None:
        app = _App.get()
        from src.dialogs.textbook_library_dialog import TextbookLibraryDialog

        with patch("src.app.QSettings", return_value=_mk_qsettings()):
            dlg = TextbookLibraryDialog(store=None, embedded=True)
        self.addCleanup(dlg.deleteLater)
        # One long hint label + six buttons must no longer force ~840px.
        self.assertLess(dlg.minimumSizeHint().width(), 700)
        dlg.resize(560, 420)
        dlg.show()
        app.processEvents()
        for btn in dlg.findChildren(QPushButton):
            if btn.isVisibleTo(dlg):
                self.assertGreaterEqual(
                    btn.width(), btn.sizeHint().width() - 1,
                    f"{btn.text()} clipped: {btn.width()} < {btn.sizeHint().width()}",
                )
        dlg.hide()

    def test_settings_dialog_min_width_fits_small_screens(self) -> None:
        _App.get()
        from src.application.settings import Settings
        from src.dialogs.settings_dialog import SettingsDialog

        with patch("src.app.QSettings", return_value=_mk_qsettings()):
            settings = Settings.load_from_qsettings(_mk_qsettings())
        with patch("src.dialogs.settings_dialog.QSettings", return_value=_mk_qsettings()):
            dlg = SettingsDialog(settings)
        self.addCleanup(dlg.deleteLater)
        # The log-filter row previously pushed this to ~890px.
        self.assertLess(dlg.minimumSizeHint().width(), 700)


if __name__ == "__main__":
    unittest.main()
