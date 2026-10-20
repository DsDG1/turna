"""Application facade for handing a course to the Flutter app.

``src/widgets/publish_dialog.py`` used to import ``src.backend.course_delivery``
directly, which is a layering bypass (the UI reached past the application
facade into the backend). This module is the single entry point the UI uses.

It re-exports the delivery primitives and adds the one piece of orchestration
that belongs at this level: deciding *which* door a course goes through and
applying the language profile before the course is written.
"""
from __future__ import annotations

from pathlib import Path
from typing import Any

from src.backend.course_delivery import (
    DeliveryError,
    apply_profile,
    default_repo_root,
    deliver_builtin,
    deliver_pack,
    find_manifest_entry,
    repo_course_dir_name,
    resolve_profile,
)

__all__ = [
    "DeliveryError",
    "apply_profile",
    "default_repo_root",
    "deliver_builtin",
    "deliver_pack",
    "find_manifest_entry",
    "is_in_repo_course",
    "prepare_delivery_profile",
    "repo_course_dir_name",
    "resolve_profile",
]


def is_in_repo_course(course_path: Path, repo_root: Path) -> bool:
    """True when ``course_path`` lives under ``<repo_root>/assets/courses``."""
    return repo_course_dir_name(course_path, repo_root) is not None


def prepare_delivery_profile(index: dict[str, Any], repo_root: Path) -> dict[str, Any]:
    """Resolve and apply the language profile for ``index``.

    Returns the resolved profile so the caller can report what was written.
    The in-memory ``index`` is mutated in place (the profile's language code
    and CEFR level are the ones the app reads back).
    """
    code = str(index.get("language") or "")
    entry = find_manifest_entry(repo_root, code)
    profile = resolve_profile(index, manifest_entry=entry)
    apply_profile(index, profile)
    return profile
