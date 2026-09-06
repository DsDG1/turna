"""Tests for the NodeAiEditDialog edit entry (K-05 tree AI edit path)."""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))
from tests._qtapp import qt_app  # noqa: E402

from PySide6.QtCore import Qt
from PySide6.QtWidgets import QDialog, QDialogButtonBox

from src.backend.ai_generator import AiApiConfig
from src.dialogs.ai.node_edit_dialog import NodeAiEditDialog
from src.dialogs.ai_generator_dialog import AiGeneratorDialog


def _section(sid: str = "sec-1") -> dict:
    return {
        "id": sid,
        "name": "Section One",
        "units": [{"id": "u1", "name": "Unit 1", "lessons": []}],
        "words": [{"id": "w1", "term": "merhaba", "translation": "你好"}],
    }


def _adapter() -> MagicMock:
    adapter = MagicMock()
    adapter.sections = [_section()]
    adapter.index = {"sections": [{"id": "sec-1"}]}
    adapter.validate_section_json.return_value = []
    return adapter


class NodeEditDialogTestCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.app = qt_app()

    def setUp(self) -> None:
        self._dialogs: list[NodeAiEditDialog] = []

    def tearDown(self) -> None:
        # Close and delete top-level dialogs to avoid offscreen segfaults on exit.
        import gc

        for dlg in self._dialogs:
            try:
                dlg.setAttribute(Qt.WidgetAttribute.WA_DeleteOnClose)
                dlg.close()
            except Exception:
                pass
        self._dialogs.clear()
        self.app.processEvents()
        gc.collect()
        self.app.processEvents()

    def _make(self, scope: str = "lesson", sid: str = "sec-1") -> NodeAiEditDialog:
        dlg = NodeAiEditDialog(
            _adapter(),
            scope=scope,
            scope_id="u1",
            existing_section=_section(sid),
        )
        dlg._config = AiApiConfig(
            base_url="https://api.example.com/v1",
            api_key="sk-test",
            model="gpt-test",
        )
        self._dialogs.append(dlg)
        return dlg


class TestNodeAiEditDialogEntry(NodeEditDialogTestCase):
    def test_edit_mode_ui(self) -> None:
        dlg = self._make(scope="unit")
        self.assertEqual(dlg.windowTitle(), "AI 编辑")
        ok = dlg._button_box.button(QDialogButtonBox.StandardButton.Ok)
        self.assertEqual(ok.text(), "应用编辑（Unit）")
        wizard_idx = dlg.normal_tabs.indexOf(dlg._wizard_panel)
        self.assertFalse(dlg.normal_tabs.isTabVisible(wizard_idx))
        self.assertTrue(hasattr(dlg, "edit_instruction_input"))

    def test_facade_no_longer_accepts_edit_mode(self) -> None:
        with self.assertRaises(TypeError):
            AiGeneratorDialog(_adapter(), edit_mode={"scope": "section"})  # type: ignore[call-arg]

    def test_edit_worker_receives_edit_mode_and_instruction(self) -> None:
        dlg = self._make(scope="lesson")
        dlg.edit_instruction_input.setPlainText("增加两个练习题")
        with patch.object(
            dlg._worker_hub, "make_edit_worker", wraps=dlg._worker_hub.make_edit_worker
        ) as mk:
            dlg._make_edit_worker(dlg._current_spec())
        args, kwargs = mk.call_args
        self.assertEqual(args[2]["scope"], "lesson")
        self.assertEqual(args[2]["scope_id"], "u1")
        self.assertEqual(args[2]["existing_section"]["id"], "sec-1")
        self.assertEqual(kwargs["instruction"], "增加两个练习题")

    def test_accept_preserves_existing_id(self) -> None:
        dlg = self._make()
        new_section = _section("sec-1")
        new_section["id"] = "changed-by-ai"
        new_section["name"] = "Edited by AI"
        dlg.json_edit.setPlainText(json.dumps(new_section, ensure_ascii=False))
        dlg._on_accept()
        self.assertEqual(dlg.result(), QDialog.DialogCode.Accepted)
        self.assertEqual(dlg._generated["id"], "sec-1")
        self.assertEqual(dlg.section_json()["name"], "Edited by AI")

    def test_view_diff_uses_existing_section(self) -> None:
        dlg = self._make()
        dlg.json_edit.setPlainText(json.dumps(_section("sec-1"), ensure_ascii=False))
        with patch(
            "src.dialogs.ai_generator_dialog.view_section_diff"
        ) as view_diff:
            dlg._on_view_diff()
        view_diff.assert_called_once()
        existing_arg = view_diff.call_args.args[1]
        self.assertEqual(existing_arg["id"], "sec-1")


if __name__ == "__main__":
    unittest.main()
