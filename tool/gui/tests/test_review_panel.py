"""Tests for ReviewPanel (merge overhaul Phase C)."""
from __future__ import annotations

import os
import sys
import tempfile
import unittest
import unittest.mock
from pathlib import Path

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))
from tests._course_samples import sample_section  # noqa: E402

from PySide6.QtWidgets import QMessageBox  # noqa: E402

from src.backend.ai_generator import AiApiConfig  # noqa: E402
from src.backend.textbook_project_store import TextbookProjectStore  # noqa: E402
from src.dialogs.ai.design_controller import DesignController  # noqa: E402
from src.dialogs.ai.design_panel import DesignPanel  # noqa: E402
from src.dialogs.ai.review_panel import ReviewPanel  # noqa: E402
from tests._qtapp import _App  # noqa: E402


class ReviewPanelTest(unittest.TestCase):
    def setUp(self) -> None:
        _App.get()
        self.tmp = tempfile.TemporaryDirectory()
        self.store = TextbookProjectStore(base_dir=Path(self.tmp.name))
        self.project = self.store.create_project(name="Blank", source_path=None)
        controller = DesignController(
            ai_config_fn=lambda: AiApiConfig(
                base_url="http://localhost", api_key="k", model="m"
            ),
            worker_factory=lambda target, *a, **k: unittest.mock.MagicMock(),
        )
        self.design = DesignPanel(None, None, controller=controller)
        self.design.set_project(self.project, self.store)
        self.review = ReviewPanel(self.design, None)

    def tearDown(self) -> None:
        self.review.deleteLater()
        self.design.deleteLater()
        self.tmp.cleanup()

    def test_refresh_without_draft(self) -> None:
        self.review.refresh()
        self.assertIn("还没有草稿", self.review._hint_label.text())
        self.assertIn("AI 轨道", self.review._hint_label.text())
        for btn in (
            self.review._try_btn,
            self.review._diff_btn,
            self.review._fix_btn,
            self.review._quality_fix_btn,
            self.review._fill_review_btn,
            self.review._import_btn,
        ):
            self.assertFalse(btn.isEnabled())
        self.assertTrue(self.review._quality_label.isHidden())
        self.assertTrue(self.review._summary_browser.isHidden())

    def test_refresh_with_draft(self) -> None:
        self.design._on_draft_ready(sample_section())
        self.review.refresh()
        self.assertIn("1 单元", self.review._hint_label.text())
        self.assertIn("1 课时", self.review._hint_label.text())
        self.assertTrue(self.review._import_btn.isEnabled())
        # Structured preview received the section.
        self.assertEqual(self.review._preview.section()["id"], "greetings")
        # Content quality chips (aiEnhance P2-5). Parent may not be shown in
        # offscreen unit tests, so assert hidden flag + text rather than isVisible().
        self.assertFalse(self.review._quality_label.isHidden())
        self.assertIn("内容质量", self.review._quality_label.text())
        self.assertIsNotNone(self.review._last_quality)
        self.assertTrue(self.review._quality_fix_btn.isEnabled())
        # U0-1 summary card + clickable dimension chips.
        self.assertFalse(self.review._summary_browser.isHidden())
        self.assertIn("生成摘要", self.review._summary_browser.toPlainText())
        self.assertTrue(self.review._dim_buttons["coverage"].isEnabled())

    def test_manual_editor_edits_are_the_truth(self) -> None:
        """B1: the review reads the design editor, not a stale controller."""
        self.design._on_draft_ready(sample_section())
        edited = sample_section()
        edited["name"] = "改过的名字"
        self.design._json_editor.set_json(edited)
        self.review.refresh()
        self.assertIn("改过的名字", self.review._hint_label.text())

    def test_import_delegates_to_design_panel(self) -> None:
        self.design._on_draft_ready(sample_section())
        captured: list = []
        self.design.sections_ready.connect(lambda s, st: captured.append((s, st)))
        from src.dialogs.import_target_dialog import ImportTarget
        with unittest.mock.patch(
            "src.dialogs.import_target_dialog.ImportTargetDialog"
        ) as MockDlg:
            MockDlg.return_value.select.return_value = ImportTarget("new_section")
            self.review._on_import()
        self.assertEqual(len(captured), 1)
        self.assertEqual(captured[0][0][0]["id"], "greetings")
        self.assertEqual(captured[0][1], "merge")

    def test_diff_without_adapter_shows_info(self) -> None:
        self.design._on_draft_ready(sample_section())
        with unittest.mock.patch.object(QMessageBox, "information") as info:
            self.review._on_diff()
        info.assert_called_once()

    def test_confirm_apply_fix_accepts(self) -> None:
        original = sample_section()
        corrected = sample_section()
        corrected["name"] = "Fixed"
        with unittest.mock.patch(
            "src.widgets.diff_view.SectionDiffView"
        ) as MockDiff:
            from PySide6.QtWidgets import QDialog

            MockDiff.return_value.exec.return_value = QDialog.DialogCode.Accepted
            self.assertTrue(self.review._confirm_apply_fix(original, corrected))
            MockDiff.assert_called_once()
            kwargs = MockDiff.call_args.kwargs
            self.assertTrue(kwargs.get("confirm"))

    def test_confirm_apply_fix_rejects(self) -> None:
        original = sample_section()
        corrected = sample_section()
        with unittest.mock.patch(
            "src.widgets.diff_view.SectionDiffView"
        ) as MockDiff:
            from PySide6.QtWidgets import QDialog

            MockDiff.return_value.exec.return_value = QDialog.DialogCode.Rejected
            self.assertFalse(self.review._confirm_apply_fix(original, corrected))

    def test_coverage_line_after_draft(self) -> None:
        self.design._controller.set_resource_pool(
            [{"id": "w-1", "_kind": "word", "term": "merhaba"}]
        )
        self.design._on_draft_ready(sample_section())
        self.review.refresh()
        self.assertNotEqual(self.review._coverage_label.text(), "")
        self.assertIn("池内命中", self.review._coverage_label.text())

    def test_regenerate_requested_calls_controller(self) -> None:
        self.design._on_draft_ready(sample_section())
        with unittest.mock.patch.object(
            self.review,
            "_prompt_regenerate_instruction",
            return_value="加强干扰项",
        ), unittest.mock.patch.object(
            self.design._controller, "regenerate_lesson", return_value=True
        ) as regen:
            self.review._on_regenerate_requested("lesson", "l")
            regen.assert_called_once_with("l", instruction="加强干扰项")

    def test_regenerate_cancel_skips_controller(self) -> None:
        self.design._on_draft_ready(sample_section())
        with unittest.mock.patch.object(
            self.review,
            "_prompt_regenerate_instruction",
            return_value=None,
        ), unittest.mock.patch.object(
            self.design._controller, "regenerate_lesson", return_value=True
        ) as regen:
            self.review._on_regenerate_requested("lesson", "l")
            regen.assert_not_called()


class ResultPreviewHumanizeTest(unittest.TestCase):
    def setUp(self) -> None:
        _App.get()
        from src.widgets.result_preview import ResultPreviewWidget

        class _Adapter:
            def validate_section_json(self, section, **kwargs):
                return [
                    {
                        "level": "error",
                        "message": "dangling wordId xyz",
                        "path": "units/0/lessons/0",
                    }
                ]

        self.preview = ResultPreviewWidget(_Adapter())
        self.preview.show_section(
            {
                "id": "s",
                "name": "S",
                "units": [
                    {
                        "id": "u",
                        "name": "U",
                        "lessons": [{"id": "l", "name": "L", "content": {}}],
                    }
                ],
                "words": [],
            }
        )

    def tearDown(self) -> None:
        self.preview.deleteLater()

    def test_apply_validation_humanizes_chip(self) -> None:
        problems = [
            {
                "level": "error",
                "message": "dangling wordId xyz",
                "path": "units/0/lessons/0",
            }
        ]
        self.preview.apply_validation(problems)
        # Chip container should have one humanized label.
        self.assertEqual(self.preview.chip_row.count(), 1)
        chip = self.preview.chip_row.itemAt(0).widget()
        self.assertIn("不存在的词", chip.text())


if __name__ == "__main__":
    unittest.main()
