"""Application facade for course media picking and path validation.

The UI layer (``src/widgets/media_picker.py``, ``src/widgets/interaction_forms.py``)
used to import ``src.backend.course_media`` directly. That is a layering
bypass: the UI layer reached past the application facade into the backend.
This module is the single place the UI is allowed to ask for media help.

It owns no state — it is a thin, Qt-free orchestration over the pure backend
helpers so the facade itself stays unit-testable without a display.
"""
from __future__ import annotations

from pathlib import Path

from src.backend.course_media import (
    ALLOWED_MEDIA_EXTENSIONS,
    AUDIO_EXTENSIONS,
    IMAGE_EXTENSIONS,
    MediaPathError,
    copy_into_course_media,
    reject_unsafe_media_value,
    safe_filename,
)

__all__ = [
    "ALLOWED_MEDIA_EXTENSIONS",
    "AUDIO_EXTENSIONS",
    "IMAGE_EXTENSIONS",
    "MediaPathError",
    "copy_into_course_media",
    "media_filter_for",
    "reject_unsafe_media_value",
    "safe_filename",
]


def media_filter_for(kind: str) -> str:
    """Return the QFileDialog filter string for a media ``kind``.

    ``kind`` is one of ``"image"`` / ``"audio"``; anything else means "any
    media file". Kept here (not in the widget) so the allowed-extension
    vocabulary has exactly one owner — the backend module that defines it.
    """
    if kind == "image":
        exts = " ".join(f"*{ext}" for ext in sorted(IMAGE_EXTENSIONS))
        return f"Images ({exts})"
    if kind == "audio":
        exts = " ".join(f"*{ext}" for ext in sorted(AUDIO_EXTENSIONS))
        return f"Audio ({exts})"
    exts = " ".join(f"*{ext}" for ext in sorted(IMAGE_EXTENSIONS | AUDIO_EXTENSIONS))
    return f"Media ({exts})"


def pick_media_into_course(
    course_dir: Path | None, source: Path
) -> str:
    """Copy ``source`` into ``<course_dir>/media`` and return the stored ref.

    Raises :class:`MediaPathError` when the course directory is missing or the
    file cannot be stored. The widget layer owns the error dialog; this
    function owns the path rules.
    """
    if course_dir is None:
        raise MediaPathError("请先打开课程目录。")
    return copy_into_course_media(Path(course_dir), Path(source))
