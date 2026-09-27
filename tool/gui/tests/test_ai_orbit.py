"""AiOrbitWidget: horizontal param band + wrapping chip row (T1).

The old layout stacked the params in three rows and clamped the chip strip to
36-48 px, so the design chat had to fight the orbit for vertical space. These
tests pin the *layout* contract (not pixels): one param row, a wrapping chip
layout, no height clamp, and a compact round core button — plus the public
control names, which the workshop canvas and its tests address directly.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from PySide6.QtCore import Qt
from PySide6.QtWidgets import QScrollBar

from src.widgets.ai_orbit import _CORE_BTN_SIZE, AiOrbitWidget
from src.widgets.ui.flow_layout import FlowLayout
from tests._qtapp import _App


def _entry(term: str) -> dict:
    return {"term": term, "meaning": f"{term} 的释义"}


class OrbitParamBandTest(unittest.TestCase):
    def setUp(self) -> None:
        _App.get()
        self.orbit = AiOrbitWidget()

    def test_all_params_live_in_one_row(self) -> None:
        """Topic and whisper used to sit on their own rows above a second
        parameter row; the band is now a single horizontal row."""
        row = self.orbit._params_row
        for widget in (
            self.orbit.topic_edit,
            self.orbit.level_combo,
            self.orbit.unit_spin,
            self.orbit.lessons_spin,
            self.orbit.template_combo,
            self.orbit.gen_mode_combo,
            self.orbit.whisper_edit,
        ):
            self.assertGreaterEqual(row.indexOf(widget), 0, widget)

    def test_params_round_trip(self) -> None:
        params = {
            "topic": "机场问路",
            "level": "A2",
            "unit_count": 2,
            "lessons_per_unit": 4,
            "template": "listening",
            "extra_instructions": "第三节改听力",
            "generation_mode": "phased",
        }
        self.orbit.apply_params(params)
        self.assertEqual(self.orbit.params_dict(), params)

    def test_refine_mode_maps_onto_phased(self) -> None:
        self.orbit.apply_params({"generation_mode": "refine"})
        self.assertEqual(self.orbit.gen_mode_combo.currentData(), "phased")

    def test_focus_summary_stays_one_line(self) -> None:
        # A wrapping summary label stole vertical space from the chat.
        self.assertFalse(self.orbit.focus_summary.wordWrap())
        self.orbit.set_focus_summary("将使用 12 / 48 个知识点")
        # isVisible() stays False until the parent is shown; isHidden() is the
        # "explicitly collapsed" signal set_focus_summary toggles.
        self.assertFalse(self.orbit.focus_summary.isHidden())


class OrbitChipRowTest(unittest.TestCase):
    def setUp(self) -> None:
        _App.get()
        self.orbit = AiOrbitWidget()

    def test_chip_row_uses_a_wrapping_layout(self) -> None:
        self.assertIsInstance(self.orbit.bubbles_layout, FlowLayout)

    def test_chip_row_is_not_height_clamped(self) -> None:
        """The 36/48 px min/max clamp is what forced the orbit to be tall."""
        self.assertGreater(self.orbit.scroll_area.maximumHeight(), 1000)
        self.assertEqual(self.orbit.scroll_area.minimumHeight(), 0)
        self.assertEqual(
            self.orbit.scroll_area.horizontalScrollBarPolicy(),
            Qt.ScrollBarPolicy.ScrollBarAlwaysOff,
        )
        self.assertEqual(
            self.orbit.scroll_area.verticalScrollBarPolicy(),
            Qt.ScrollBarPolicy.ScrollBarAsNeeded,
        )

    def test_orbit_zone_has_no_minimum_height(self) -> None:
        self.assertEqual(self.orbit.orbit_zone.minimumHeight(), 0)

    def test_chips_land_in_the_flow_layout(self) -> None:
        self.orbit.add_knowledge_point(_entry("airport"), "word")
        self.orbit.add_knowledge_point(_entry("boarding pass"), "word")
        self.assertEqual(self.orbit.bubbles_layout.count(), 2)
        self.assertEqual(len(self.orbit.dropped_items), 2)
        self.assertIn("已投入 2 个知识点", self.orbit.prompt_label.text())

    def test_duplicate_entry_is_ignored(self) -> None:
        self.orbit.add_knowledge_point(_entry("airport"), "word")
        self.orbit.add_knowledge_point(_entry("airport"), "word")
        self.assertEqual(len(self.orbit.dropped_items), 1)

    def test_clear_orbit_empties_the_row(self) -> None:
        self.orbit.add_knowledge_point(_entry("airport"), "word")
        self.orbit.clear_orbit()
        self.assertEqual(self.orbit.dropped_items, [])
        self.assertIn("留空则用整池", self.orbit.prompt_label.text())

    def test_drop_target_is_the_orbit(self) -> None:
        self.assertTrue(self.orbit.acceptDrops())


class OrbitCoreButtonTest(unittest.TestCase):
    def setUp(self) -> None:
        _App.get()
        self.orbit = AiOrbitWidget()

    def test_core_button_is_a_compact_round_button(self) -> None:
        size = self.orbit.core_btn.size()
        self.assertEqual(size.width(), _CORE_BTN_SIZE)
        self.assertEqual(size.height(), _CORE_BTN_SIZE)
        self.assertIn(
            f"border-radius: {_CORE_BTN_SIZE // 2}px;",
            self.orbit.core_btn.styleSheet(),
        )

    def test_core_button_shares_a_row_with_chat(self) -> None:
        # Both sit on the same action row: the chat entry point is no longer
        # stranded below a 110 px button.
        zone_layout = self.orbit.orbit_zone.layout()
        rows = [
            zone_layout.itemAt(i).layout()
            for i in range(zone_layout.count())
            if zone_layout.itemAt(i).layout() is not None
        ]
        self.assertTrue(
            any(
                row.indexOf(self.orbit.core_btn) >= 0
                and row.indexOf(self.orbit.chat_btn) >= 0
                for row in rows
            )
        )

    def test_busy_state_disables_and_relabels(self) -> None:
        self.orbit.set_busy(True, "生成中…")
        self.assertFalse(self.orbit.core_btn.isEnabled())
        self.assertIn("AI 生成中", self.orbit.core_btn.text())
        self.assertFalse(self.orbit.progress_bar.isHidden())
        self.orbit.set_busy(False)
        self.assertTrue(self.orbit.core_btn.isEnabled())
        self.assertIn("AI 核心", self.orbit.core_btn.text())
        self.assertTrue(self.orbit.progress_bar.isHidden())

    def test_chat_button_requests_the_chat(self) -> None:
        seen: list[bool] = []
        self.orbit.chat_requested.connect(lambda: seen.append(True))
        self.orbit.chat_btn.click()
        self.assertEqual(seen, [True])

    def test_generate_shortcuts_still_fire_generate_requested(self) -> None:
        seen: list[bool] = []
        self.orbit.generate_requested.connect(lambda: seen.append(True))
        self.orbit.core_btn.click()
        self.assertEqual(seen, [True])
        self.orbit._gen_shortcut.activated.emit()
        self.assertEqual(seen, [True, True])


if __name__ == "__main__":
    unittest.main()
