"""Unit tests for modular theme QSS generation and style builders."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.theme import _build_qss, _opaque  # noqa: E402
from src.theme_styles.builder import build_qss, opaque  # noqa: E402
from src.theme_styles.buttons import build_button_qss  # noqa: E402
from src.theme_styles.containers import build_container_qss  # noqa: E402
from src.theme_styles.core import build_core_qss  # noqa: E402
from src.theme_styles.inputs import build_input_qss  # noqa: E402
from src.theme_styles.views import build_view_qss  # noqa: E402
from src.theme_tokens import VALID_THEMES, palette_for  # noqa: E402


class ThemeQssGenerationTest(unittest.TestCase):
    """Verify QSS generation across all supported themes."""

    def test_build_qss_all_themes_non_empty(self) -> None:
        for theme in VALID_THEMES:
            palette = palette_for(theme)
            qss = build_qss(palette, 14, theme)
            self.assertIsInstance(qss, str)
            self.assertGreater(len(qss), 5000, f"QSS for {theme} suspiciously short")

    def test_facade_backward_compatibility(self) -> None:
        """src.theme._build_qss and _opaque must delegate transparently."""
        for theme in VALID_THEMES:
            pal = palette_for(theme)
            direct = build_qss(pal, 14, theme)
            facade = _build_qss(pal, 14, theme)
            self.assertEqual(direct, facade)

        self.assertEqual(
            _opaque("#80FFFFFF", "#000000"),
            opaque("#80FFFFFF", "#000000"),
        )

    def test_key_selectors_present(self) -> None:
        palette = palette_for("dark")
        qss = build_qss(palette, 14, "dark")

        expected_selectors = [
            "QWidget {",
            "QMainWindow {",
            "QToolBar {",
            "QPushButton {",
            "QPushButton#dangerButton {",
            "QPushButton#secondaryButton {",
            "QToolButton {",
            "QLineEdit,",
            "QComboBox::drop-down {",
            "QAbstractSpinBox::up-button,",
            "QCheckBox {",
            "QRadioButton {",
            "QListWidget,",
            "QTreeWidget {",
            "QHeaderView::section {",
            "QTableView,",
            "QGroupBox {",
            "QLabel#titleLabel {",
            "QStatusBar {",
            "QMenu {",
            "QSplitter::handle {",
            "QScrollBar:vertical {",
            "QProgressBar {",
            "QSlider::groove:horizontal {",
            "QTabWidget::pane {",
            "QTabBar::tab {",
        ]
        for sel in expected_selectors:
            self.assertIn(sel, qss, f"Selector missing from QSS: {sel}")

    def test_high_contrast_border_and_focus_width(self) -> None:
        dark_pal = palette_for("dark")
        hc_pal = palette_for("high-contrast-dark")

        dark_qss = build_qss(dark_pal, 14, "dark")
        hc_qss = build_qss(hc_pal, 14, "high-contrast-dark")

        # In dark theme, standard borders are 1px, focus ring is 2px
        self.assertIn("border: 1px solid", dark_qss)
        self.assertIn("border: 2px solid", dark_qss)

        # In high contrast theme, standard borders become 2px, focus ring becomes 2.5px
        self.assertIn("border: 2px solid", hc_qss)
        self.assertIn("border: 2.5px solid", hc_qss)

    def test_font_scaling_reflection(self) -> None:
        palette = palette_for("dark")
        qss_12 = build_qss(palette, 12, "dark")
        qss_18 = build_qss(palette, 18, "dark")

        self.assertIn("font-size: 12px;", qss_12)
        self.assertIn("font-size: 18px;", qss_18)

    def test_opaque_blending_math(self) -> None:
        # Full alpha (FF) -> should be purely foreground
        self.assertEqual(opaque("#FF102030", "#AABBCC"), "#102030")
        # Zero alpha (00) -> should be purely background
        self.assertEqual(opaque("#00102030", "#AABBCC"), "#AABBCC")
        # 50% alpha blending between black and white
        blended = opaque("#80000000", "#FFFFFF")
        # #80 is 128/255 = ~0.50196 -> 255 * (1 - 0.50196) = 127 = 0x7F
        self.assertEqual(blended, "#7F7F7F")


class SubModuleQssTest(unittest.TestCase):
    """Test individual style builder submodules."""

    def setUp(self) -> None:
        self.pal = palette_for("dark")

    def test_build_core_qss(self) -> None:
        core = build_core_qss(self.pal, 14, "1px")
        self.assertIn("QWidget {", core)
        self.assertIn("QMainWindow {", core)
        self.assertIn("QToolBar {", core)
        self.assertIn("font-size: 14px;", core)

    def test_build_button_qss(self) -> None:
        buttons = build_button_qss(self.pal, "1px", "dark")
        self.assertIn("QPushButton {", buttons)
        self.assertIn("QPushButton#dangerButton {", buttons)
        self.assertIn("QPushButton#secondaryButton {", buttons)

    def test_build_input_qss(self) -> None:
        inputs = build_input_qss(self.pal, "1px", "2px")
        self.assertIn("QLineEdit,", inputs)
        self.assertIn("border: 2px solid", inputs)
        self.assertIn("QCheckBox {", inputs)
        self.assertIn("QRadioButton {", inputs)

    def test_build_view_qss(self) -> None:
        views = build_view_qss(self.pal, "1px", "#123456")
        self.assertIn("QTreeWidget {", views)
        self.assertIn("QTableView,", views)
        self.assertIn("background-color: #123456;", views)

    def test_build_container_qss(self) -> None:
        containers = build_container_qss(self.pal, "1px", "border: 1px solid #333333;", 14)
        self.assertIn("QGroupBox {", containers)
        self.assertIn("font-size: 13px;", containers)  # base_font_px - 1
        self.assertIn("QTabWidget::pane {", containers)
        self.assertIn("QScrollBar:vertical {", containers)


if __name__ == "__main__":
    unittest.main()
