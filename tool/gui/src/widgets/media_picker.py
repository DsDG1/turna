"""File dialog that copies a picked image or audio file into course ``media/``."""
from __future__ import annotations

from pathlib import Path

from PySide6.QtWidgets import QFileDialog, QMessageBox, QWidget

from src.backend.course_media import (
    AUDIO_EXTENSIONS,
    IMAGE_EXTENSIONS,
    MediaPathError,
    copy_into_course_media,
)


def _filter_for(kind: str) -> str:
    if kind == "image":
        exts = " ".join(f"*{ext}" for ext in sorted(IMAGE_EXTENSIONS))
        return f"Images ({exts})"
    if kind == "audio":
        exts = " ".join(f"*{ext}" for ext in sorted(AUDIO_EXTENSIONS))
        return f"Audio ({exts})"
    exts = " ".join(f"*{ext}" for ext in sorted(IMAGE_EXTENSIONS | AUDIO_EXTENSIONS))
    return f"Media ({exts})"


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
        return copy_into_course_media(Path(course_dir), Path(path))
    except MediaPathError as exc:
        QMessageBox.warning(parent, "选择文件", str(exc))
        return None
