"""Unit tests for GeneratorPreviewCoordinator."""
from __future__ import annotations

import unittest
from unittest.mock import MagicMock, patch

from PySide6.QtWidgets import QPushButton, QVBoxLayout, QWidget
from tests._qtapp import qt_app

from src.dialogs.ai.generator_preview_coordinator import (
    GeneratorPreviewCoordinator,
    find_line_for_path,
    confirm_structural_removal,
)
from src.widgets.json_editor import JsonEditor


class TestGeneratorPreviewCoordinator(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = qt_app()

    def test_find_line_for_path(self):
        json_text = '{\n  "id": "my-id",\n  "name": "Course"\n}'
        # Matching path
        line = find_line_for_path(json_text, "id:my-id")
        self.assertEqual(line, 2)

        # Missing id
        self.assertIsNone(find_line_for_path(json_text, "id:other-id"))

        # Non-id path
        self.assertIsNone(find_line_for_path(json_text, "structural:path"))

    def test_confirm_structural_removal_empty(self):
        parent = QWidget()
        res = confirm_structural_removal(parent, {})
        self.assertTrue(res)

    def test_json_window_toggle_and_reparent(self):
        parent = QWidget()
        coordinator = GeneratorPreviewCoordinator(parent)

        host_widget = QWidget()
        host_layout = QVBoxLayout(host_widget)
        editor = JsonEditor()
        host_layout.addWidget(editor)

        btn = QPushButton()
        btn.setCheckable(True)

        # Toggle ON
        coordinator.on_json_window_toggled(
            True,
            editor,
            host_layout,
            [btn],
            on_closed_callback=lambda: coordinator.close_json_window(host_layout),
        )
        self.assertTrue(btn.isChecked())
        self.assertIsNotNone(coordinator.json_window)
        self.assertIs(editor.parent(), coordinator.json_window)

        # Toggle OFF
        coordinator.on_json_window_toggled(
            False,
            editor,
            host_layout,
            [btn],
            on_closed_callback=lambda: None,
        )
        self.assertIsNone(coordinator.json_window)
        self.assertIs(editor.parent(), host_widget)


class GeneratorFlowsDelegationTest(unittest.TestCase):
    """Regression: ``generator_flows.confirm_structural_removal`` must forward
    to the coordinator implementation (a copy-paste slip once made it call
    itself, so node-edit removal confirmation recursed until RecursionError)."""

    def test_confirm_structural_removal_forwards_to_coordinator(self):
        from src.dialogs.ai import generator_flows

        dlg = object()
        diff = {"removed_items": {"i-1"}}
        with patch.object(
            generator_flows, "_confirm_removal_ui", return_value=True
        ) as forward:
            self.assertTrue(generator_flows.confirm_structural_removal(dlg, diff))
        forward.assert_called_once_with(dlg, diff)


if __name__ == "__main__":
    unittest.main()
