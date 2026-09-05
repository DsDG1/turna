"""Tests for Signal Lifecycle Governance and .connect(lambda) elimination (Phase 8)."""
from __future__ import annotations

import os
import re
import sys
import unittest
from pathlib import Path

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from tests._qtapp import _App  # noqa: E402
from src.backend.course_adapter import CourseAdapter  # noqa: E402


class SignalLifecycleScanTest(unittest.TestCase):
    """Repository-wide static scan verifying zero anonymous lambda connections."""

    def test_no_anonymous_lambdas_in_signal_connections(self) -> None:
        src_dir = _GUI / "src"
        pattern = re.compile(r"\.connect\s*\(\s*(?:\[[^\]]*\]\s*)?lambda\b")
        violations: list[str] = []

        for root, _, files in os.walk(src_dir):
            for file in files:
                if file.endswith(".py"):
                    file_path = Path(root) / file
                    c = file_path.read_text(encoding="utf-8")
                    for m in pattern.finditer(c):
                        line_no = c[:m.start()].count("\n") + 1
                        rel_path = file_path.relative_to(_GUI).as_posix()
                        snippet = c[m.start():c.find("\n", m.start())].strip()
                        violations.append(f"{rel_path}:{line_no}: {snippet}")

        self.assertEqual(
            violations,
            [],
            f"Found {len(violations)} anonymous lambda signal connection(s) in src/:\n"
            + "\n".join(violations),
        )


class SignalLifecycleComponentTest(unittest.TestCase):
    """Component-level tests verifying named slot dispatch and property wiring."""

    def setUp(self) -> None:
        _App.get()
        self.adapter = CourseAdapter()

    def test_functional_lesson_wizard_slot_wiring(self) -> None:
        from src.dialogs.functional_lesson_wizard import FunctionalLessonWizard

        wizard = FunctionalLessonWizard(
            self.adapter, "u-w", None, initial_template="listening", initial_name="L"
        )
        wizard._preset_combo.setCurrentIndex(1)
        wizard._goto_step(1)
        phase0 = wizard._get_phase_by_idx(0)
        self.assertIsNotNone(phase0)
        box = wizard._build_phase_row(0, phase0)
        self.assertIsNotNone(box)
        self.assertIs(wizard._get_phase_by_idx(0), wizard._lesson["content"]["listeningPhases"][0])

        wizard_m = FunctionalLessonWizard(
            self.adapter, "u-w", None, initial_template="mastery", initial_name="M"
        )
        wizard_m._preset_combo.setCurrentIndex(1)
        wizard_m._goto_step(1)
        cb = wizard_m._mastery_checks["multipleChoice"]
        cb.setChecked(False)
        self.assertFalse(any(it.get("runtimeType") == "multipleChoice" for it in wizard_m._lesson["content"]["stages"][0].get("items", [])))
        cb.setChecked(True)
        items = wizard_m._lesson["content"]["stages"][0].get("items", [])
        self.assertTrue(any(it.get("runtimeType") == "multipleChoice" for it in items))
        wizard.deleteLater()
        wizard_m.deleteLater()

    def test_bulk_merge_panel_slot_wiring(self) -> None:
        from src.widgets.bulk_merge_resolve_panel import BulkMergeResolveDialog
        from tests._course_samples import sample_section_from_chapter

        for sid in ("sec-1", "sec-2"):
            self.adapter.sections.append(sample_section_from_chapter(sid))
        plans = [
            self.adapter.plan_section_merge(sid, sample_section_from_chapter(sid))
            for sid in ("sec-1", "sec-2")
        ]
        dlg = BulkMergeResolveDialog(plans)
        dlg._on_merge_all_clicked()
        self.assertTrue(all(d is not None for d in dlg.decisions()))
        dlg._on_skip_all_clicked()
        self.assertTrue(all(d is None for d in dlg.decisions()))
        dlg.deleteLater()

    def test_ambient_banner_mute_slots(self) -> None:
        from src.widgets.ambient_banner import (
            AmbientBanner,
            MUTE_HOURS4,
            MUTE_TODAY,
            MUTE_PERMANENT,
        )

        banner = AmbientBanner()
        emitted_levels: list[str] = []
        banner.mute_changed.connect(emitted_levels.append)

        banner._on_mute_hours4()
        self.assertEqual(emitted_levels[-1], MUTE_HOURS4)
        banner._on_mute_today()
        self.assertEqual(emitted_levels[-1], MUTE_TODAY)
        banner._on_mute_permanent()
        self.assertEqual(emitted_levels[-1], MUTE_PERMANENT)
        banner.deleteLater()


if __name__ == "__main__":
    unittest.main()
