"""Copy author-picked media into a course ``media/`` directory.

Stored values are always ``media/<safe name>``. Absolute paths, drive
letters, and ``..`` are rejected. Extensions match ``.turnapack`` v2.
"""
from __future__ import annotations

import shutil
from pathlib import Path

IMAGE_EXTENSIONS = frozenset({".jpg", ".jpeg", ".png", ".webp", ".gif"})
AUDIO_EXTENSIONS = frozenset({".mp3", ".ogg", ".wav", ".m4a", ".aac", ".opus"})
ALLOWED_MEDIA_EXTENSIONS = IMAGE_EXTENSIONS | AUDIO_EXTENSIONS


class MediaPathError(ValueError):
    """A media path cannot be stored on a course."""


def safe_filename(original_name: str) -> str:
    """Return a single path segment with an allowed extension."""
    name = Path(original_name).name
    if not name or name in {".", ".."}:
        raise MediaPathError("文件名无效")
    suffix = Path(name).suffix.lower()
    if suffix not in ALLOWED_MEDIA_EXTENSIONS:
        raise MediaPathError(f"不支持的扩展名 {suffix or '(无)'}")
    stem = Path(name).stem
    cleaned: list[str] = []
    for ch in stem:
        if ch.isalnum() or ch in "-_":
            cleaned.append(ch)
        else:
            cleaned.append("_")
    safe_stem = "".join(cleaned).strip("._") or "file"
    return f"{safe_stem}{suffix}"


def reject_unsafe_media_value(value: str) -> None:
    """Reject absolute paths, drive letters, and ``..`` in a stored ref.

    ``anki://``, ``turnapack://``, ``media/…``, ``assets/…``, and bare word
    ids stay allowed. Empty is allowed.
    """
    text = value.replace("\\", "/").strip()
    if not text:
        return
    if text.startswith("anki://") or text.startswith("turnapack://"):
        return
    if text.startswith("/") or (len(text) >= 2 and text[1] == ":"):
        raise MediaPathError("不能使用绝对路径或盘符")
    if any(part == ".." for part in text.split("/")):
        raise MediaPathError("路径不能包含 ..")


def copy_into_course_media(course_dir: Path, source: Path) -> str:
    """Copy ``source`` into ``<course_dir>/media/`` and return the stored ref."""
    if not source.is_file():
        raise MediaPathError("找不到所选文件")
    dest_name = safe_filename(source.name)
    media_dir = Path(course_dir) / "media"
    media_dir.mkdir(parents=True, exist_ok=True)
    dest = media_dir / dest_name
    if dest.exists():
        if dest.is_file() and dest.read_bytes() == source.read_bytes():
            return f"media/{dest_name}"
        stem = Path(dest_name).stem
        suffix = Path(dest_name).suffix
        for n in range(2, 1000):
            candidate = media_dir / f"{stem}-{n}{suffix}"
            if not candidate.exists():
                dest = candidate
                dest_name = candidate.name
                break
        else:
            raise MediaPathError("无法生成不冲突的文件名")
    shutil.copy2(source, dest)
    stored = f"media/{dest_name}"
    reject_unsafe_media_value(stored)
    return stored
