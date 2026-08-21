"""S-10 v4.55: resources_controller duck-host paths (mock dialogs, no exec UI)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))


class _FakeDlg:
    def __init__(self, *args, **kwargs):
        self._clone = None
        self.open_requested = MagicMock()
        self.open_requested.connect = MagicMock()

    def setWindowTitle(self, *_a):
        pass

    def resize(self, *_a):
        pass

    def exec(self):
        return 0

    def clone_dir(self):
        return self._clone


class OpenResourcesTest(unittest.TestCase):
    def test_teacher_mode_uses_vocab_table(self) -> None:
        from src.application import resources_controller as rc

        status = MagicMock()
        host = SimpleNamespace(
            teacher_mode=True,
            adapter=object(),
            statusBar=MagicMock(return_value=status),
            experience=MagicMock(),
            _sync_experience_focus=MagicMock(),
        )
        table = MagicMock()
        table.is_dirty.return_value = True
        with (
            patch("src.infrastructure.telemetry.telemetry") as tel,
            patch("PySide6.QtWidgets.QDialog") as QDialog,
            patch("PySide6.QtWidgets.QDialogButtonBox") as QBB,
            patch("PySide6.QtWidgets.QVBoxLayout") as QVL,
            patch(
                "src.teacher.vocab_table.VocabTableWidget", return_value=table
            ) as VT,
            patch("src.widgets.resource_editor.ResourceEditorDialog") as RED,
        ):
            dlg = MagicMock()
            QDialog.return_value = dlg
            QBB.return_value = MagicMock()
            QVL.return_value = MagicMock()
            rc.open_resources(host)
            VT.assert_called_once()
            RED.assert_not_called()
            dlg.exec.assert_called_once()
            tel.record_event.assert_called()
            status.showMessage.assert_called()
            host.experience.set_surface.assert_not_called()

    def test_editor_mode_harvests_selection(self) -> None:
        from src.application import resources_controller as rc

        status = MagicMock()
        exp = MagicMock()
        host = SimpleNamespace(
            teacher_mode=False,
            adapter=object(),
            statusBar=MagicMock(return_value=status),
            experience=exp,
            _sync_experience_focus=MagicMock(),
        )
        editor = MagicMock()
        editor.selected_refs.return_value = [
            ("vocab", "w1"),
            ("vocab", "w2"),
        ]
        editor.is_dirty.return_value = False
        with (
            patch("src.infrastructure.telemetry.telemetry") as tel,
            patch("PySide6.QtWidgets.QDialog") as QDialog,
            patch("PySide6.QtWidgets.QDialogButtonBox") as QBB,
            patch("PySide6.QtWidgets.QVBoxLayout") as QVL,
            patch(
                "src.widgets.resource_editor.ResourceEditorDialog",
                return_value=editor,
            ) as RED,
            patch("src.teacher.vocab_table.VocabTableWidget") as VT,
        ):
            QDialog.return_value = MagicMock()
            QBB.return_value = MagicMock()
            QVL.return_value = MagicMock()
            rc.open_resources(host, initial_filter="stub")
            RED.assert_called_once()
            VT.assert_not_called()
            exp.set_surface.assert_called_with("resources")
            exp.set_selection.assert_called_once_with(
                ("vocab", "w1"),
                multi=[("vocab", "w1"), ("vocab", "w2")],
            )
            host._sync_experience_focus.assert_called_once()
            tel.record_event.assert_called()


class OpenGitAndPublishTest(unittest.TestCase):
    def test_git_library_connects_open_and_status(self) -> None:
        from src.application import resources_controller as rc

        status = MagicMock()
        host = SimpleNamespace(
            adapter=object(),
            _settings_obj=object(),
            course_dir=Path("/tmp/clone"),
            _open_repo_path=MagicMock(),
            statusBar=MagicMock(return_value=status),
        )
        dlg = _FakeDlg()
        dlg._clone = Path("/tmp/clone")
        with (
            patch("src.infrastructure.telemetry.telemetry") as tel,
            patch(
                "src.dialogs.git_library_dialog.GitLibraryDialog",
                return_value=dlg,
            ),
        ):
            rc.open_git_library(host)
            dlg.open_requested.connect.assert_called_with(host._open_repo_path)
            tel.record_event.assert_called_with("git_library.open")
            status.showMessage.assert_called()

    def test_publish_success_refreshes_tree(self) -> None:
        from src.application import resources_controller as rc

        status = MagicMock()
        tree = MagicMock()
        detail = MagicMock()
        host = SimpleNamespace(
            adapter=object(),
            teacher_mode=False,
            tree=tree,
            detail=detail,
            _current_node_ref=("lesson", "l1"),
            statusBar=MagicMock(return_value=status),
        )
        dlg = MagicMock()
        dlg.exec.return_value = True
        with (
            patch("src.infrastructure.telemetry.telemetry") as tel,
            patch(
                "src.widgets.publish_dialog.PublishDialog", return_value=dlg
            ),
        ):
            rc.open_publish(host)
            tree.refresh.assert_called_once()
            detail.show_node.assert_called_once_with(
                host.adapter, ("lesson", "l1")
            )
            status.showMessage.assert_called()
            tel.record_event.assert_called()


if __name__ == "__main__":
    unittest.main()
