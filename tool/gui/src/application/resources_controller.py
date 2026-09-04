"""Resources / Git library / publish dialog orchestration (S-10 / v4.55).

Duck-types MainWindow. Keeps teacher vocab / resource editor / git library /
publish paths out of ``app.py`` while preserving V-01 selection harvest and
telemetry event names.
"""
from __future__ import annotations

from typing import Any
import logging
from src.application.experience_host import ExperienceHost
logger = logging.getLogger(__name__)


def open_resources(host: ExperienceHost, initial_filter: str = "") -> None:
    """Open local resources: teacher vocab table or full resource editor."""
    from PySide6.QtWidgets import QDialog, QDialogButtonBox, QVBoxLayout

    from src.infrastructure.telemetry import telemetry

    teacher_mode = bool(getattr(host, "teacher_mode", False))
    telemetry.record_event(
        "resources.open",
        payload={
            "teacher_mode": teacher_mode,
            "filter": str(initial_filter or ""),
        },
    )
    if teacher_mode:
        from src.teacher.vocab_table import VocabTableWidget

        dlg = QDialog(host)
        dlg.setWindowTitle("词库")
        dlg.resize(760, 520)
        table = VocabTableWidget(host.adapter, dlg)
        buttons = QDialogButtonBox(QDialogButtonBox.StandardButton.Close)
        buttons.rejected.connect(dlg.reject)
        layout = QVBoxLayout(dlg)
        layout.addWidget(table)
        layout.addWidget(buttons)
        dlg.exec()
        if table.is_dirty():
            try:
                host.statusBar().showMessage("词库已修改，记得保存", 5000)
            except Exception:
                logger.debug("application/resources_controller.py:open_resources best-effort step failed", exc_info=True)
        return

    from src.widgets.resource_editor import ResourceEditorDialog

    dlg = QDialog(host)
    dlg.setWindowTitle("资源编辑")
    dlg.resize(900, 560)
    editor = ResourceEditorDialog(
        host.adapter, dlg, initial_filter=str(initial_filter or "")
    )
    buttons = QDialogButtonBox(QDialogButtonBox.StandardButton.Close)
    buttons.rejected.connect(dlg.reject)
    layout = QVBoxLayout(dlg)
    layout.addWidget(editor)
    layout.addWidget(buttons)
    dlg.exec()

    # V-01: harvest resource (multi-)selection into ExperienceContext.
    try:
        refs = editor.selected_refs()
    except Exception:
        refs = []
    if refs:
        try:
            host.experience.set_surface("resources")
            host.experience.set_selection(
                refs[0], multi=refs if len(refs) > 1 else None
            )
            host._sync_experience_focus()
        except Exception:
            logger.debug("application/resources_controller.py:open_resources best-effort step failed", exc_info=True)

    try:
        if editor.is_dirty():
            host.statusBar().showMessage("资源已修改，记得保存", 5000)
    except Exception:
        logger.debug("application/resources_controller.py:open_resources best-effort step failed", exc_info=True)


def open_git_library(host: ExperienceHost) -> None:
    """Open the Git resource library dialog."""
    from src.dialogs.git_library_dialog import GitLibraryDialog
    from src.infrastructure.telemetry import telemetry

    telemetry.record_event("git_library.open")
    dlg = GitLibraryDialog(
        host.adapter, host, settings=getattr(host, "_settings_obj", None)
    )
    dlg.open_requested.connect(host._open_repo_path)
    dlg.exec()
    clone = dlg.clone_dir()
    if clone is not None and getattr(host, "course_dir", None) == clone:
        try:
            host.statusBar().showMessage(f"已从 Git 资源库加载: {clone}", 5000)
        except Exception:
            logger.debug("application/resources_controller.py:open_git_library best-effort step failed", exc_info=True)


def open_publish(host: ExperienceHost) -> None:
    """Open publish dialog; refresh tree/detail on success."""
    from src.infrastructure.telemetry import telemetry
    from src.widgets.publish_dialog import PublishDialog

    teacher_mode = bool(getattr(host, "teacher_mode", False))
    telemetry.record_event(
        "publish.open", payload={"teacher_mode": teacher_mode}
    )
    dlg = PublishDialog(
        host.adapter, host, teacher_friendly=teacher_mode
    )
    if dlg.exec():
        try:
            host.tree.refresh()
        except Exception:
            logger.debug("application/resources_controller.py:open_publish best-effort step failed", exc_info=True)
        if not teacher_mode and getattr(host, "_current_node_ref", None) is not None:
            try:
                host.detail.show_node(host.adapter, host._current_node_ref)
            except Exception:
                logger.debug("application/resources_controller.py:open_publish best-effort step failed", exc_info=True)
        try:
            host.statusBar().showMessage("发布成功", 5000)
        except Exception:
            logger.debug("application/resources_controller.py:open_publish best-effort step failed", exc_info=True)
