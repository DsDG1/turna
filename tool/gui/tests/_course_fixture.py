"""Shared course fixture helper for tests.

Copies the built-in ``assets/courses/turkish`` course into a destination
directory (the caller's tmp dir). Centralizes the ``shutil.copytree`` pattern
that was duplicated across ~14 test files.
"""
from __future__ import annotations

import shutil
import tempfile
from pathlib import Path

from src.backend.course_adapter import CourseAdapter

# tool/gui/tests/_course_fixture.py -> tool/gui -> repo root
_REPO = Path(__file__).resolve().parents[3]
COURSE_SRC = _REPO / "assets" / "courses" / "turkish"


def copy_turkish_course(dst: Path) -> Path:
    """Copy the built-in turkish course tree into ``dst`` and return ``dst``.

    ``dst``'s parent must exist (callers typically pass ``tmp / "turkish"``).
    Runtime backup dirs (``.varnamala-backup``) are excluded so save-atomicity
    tests are not polluted by local editor leftovers.
    """
    shutil.copytree(
        COURSE_SRC,
        dst,
        ignore=shutil.ignore_patterns(".varnamala-backup", "__pycache__"),
    )
    return dst


def real_adapter_with_course(prefix: str = "turna_course_"):
    """Build a real ``CourseAdapter`` loaded from the Turkish course.

    Returns ``(adapter, tmp_path)``. The caller is responsible for cleaning up
    ``tmp_path`` (typically via ``tearDown``).
    """
    tmp = Path(tempfile.mkdtemp(prefix=prefix))
    course_dir = tmp / "turkish"
    copy_turkish_course(course_dir)
    adapter = CourseAdapter()
    adapter.load(course_dir)
    return adapter, tmp