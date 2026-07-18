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

from PySide6.QtWidgets import QApplication, QMessageBox  # noqa: E402

from src.backend.ai_generator import AiApiConfig  # noqa: E402
from src.backend.textbook_project_store import TextbookProjectStore  # noqa: E402
from src.dialogs.ai.design_controller import DesignController  # noqa: E402
from src.dialogs.ai.design_panel import DesignPanel  # noqa: E402
from src.dialogs.ai.review_panel import ReviewPanel  # noqa: E402


class _App:
    _app = None

    @classmethod
    def get(cls) -> QApplication:
        if cls._app is None:
            cls._app = QApplication.instance() or QApplication([])
        return cls._app


def _section() -> dict:
    return {
        "id": "greetings",
        "name": "Greetings",
        "units": [{"id": "u", "name": "U1", "lessons": [
            {"id": "l", "name": "L1", "template": "intro",
             "content": {"subLessons": []}},
        ]}],
        "words": [{"id": "w-1", "term": "merhaba", "translation": "hello"}],
    }


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
        for btn in (
            self.review._try_btn,
            self.review._diff_btn,
            self.review._fix_btn,
            self.review._import_btn,
        ):
            self.assertFalse(btn.isEnabled())

    def test_refresh_with_draft(self) -> None:
        self.design._on_draft_ready(_section())
        self.review.refresh()
        self.assertIn("1 单元", self.review._hint_label.text())
        self.assertIn("1 课时", self.review._hint_label.text())
        self.assertTrue(self.review._import_btn.isEnabled())
        # Structured preview received the section.
        self.assertEqual(self.review._preview.section()["id"], "greetings")

    def test_manual_editor_edits_are_the_truth(self) -> None:
        """B1: the review reads the design editor, not a stale controller."""
        self.design._on_draft_ready(_section())
        edited = _section()
        edited["name"] = "改过的名字"
        self.design._json_editor.set_json(edited)
        self.review.refresh()
        self.assertIn("改过的名字", self.review._hint_label.text())

    def test_import_delegates_to_design_panel(self) -> None:
        self.design._on_draft_ready(_section())
        captured: list = []
        self.design.sections_ready.connect(lambda s, st: captured.append((s, st)))
        self.review._on_import()
        self.assertEqual(len(captured), 1)
        self.assertEqual(captured[0][0][0]["id"], "greetings")
        self.assertEqual(captured[0][1], "merge")

    def test_diff_without_adapter_shows_info(self) -> None:
        self.design._on_draft_ready(_section())
        with unittest.mock.patch.object(QMessageBox, "information") as info:
            self.review._on_diff()
        info.assert_called_once()


if __name__ == "__main__":
    unittest.main()
