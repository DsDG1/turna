"""File dialog that copies a picked image or audio file into course ``media/``."""
from __future__ import annotations

from pathlib import Path

from PySide6.QtWidgets import QFileDialog, QMessageBox, QWidget

from src.application.media_service import (
    MediaPathError,
    media_filter_for,
    pick_media_into_course,
)


def _filter_for(kind: str) -> str:
    return media_filter_for(kind)


def pick_course_media(parent: QWidget, course_dir: Path | None, *, kind: str) -> str | None:
    """Copy a chosen file into ``course_dir/media`` and return ``media/<name>``.

    Returns None when the user cancels. Shows a message when the course
    directory is missing or the file cannot be stored.
    """
    if course_dir is None:
        QMessageBox.warning(parent, "选择文件", "请先打开课程目录。")
        return None
    path, _selected = QFileDialog.getOpenFileName(
        parent, "选择文件", "", _filter_for(kind)
    )
    if not path:
        return None
    try:
        return pick_media_into_course(course_dir, Path(path))
    except MediaPathError as exc:
        QMessageBox.warning(parent, "选择文件", str(exc))
        return None
