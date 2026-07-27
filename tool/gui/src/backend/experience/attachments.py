"""Attachment summary snapshots for ExperienceContext (E4 / M-01).

Pure Python, no Qt. Converts workshop ``AttachmentRecord`` items into a
small JSON-safe closed-shape summary list that the Context Bus can carry.

Red line (experienceai.md §14.5.3): extracted text / base64 NEVER enters
the snapshot — only closed-set scalars (id/name/kind/count/hash). The raw
content stays window-side; consumers must resolve it via ``ref_id`` back
at the workshop, never via Context.
"""
from __future__ import annotations

import hashlib
import os
from typing import Any, Mapping, Sequence


# Closed key set for Context / Dock / telemetry (no free-form blobs).
ATTACHMENT_KEYS = frozenset(
    {
        "ref_id",
        "name",
        "kind",
        "char_count",
        "preview_hash",
        "source",
    }
)

MAX_ATTACHMENTS = 50

_KIND_BY_EXT = {
    ".pdf": "pdf",
    ".doc": "word",
    ".docx": "word",
    ".txt": "text",
    ".md": "text",
}

_KIND_LABELS = {
    "pdf": "PDF",
    "word": "Word",
    "image": "图",
    "text": "文本",
    "other": "其他",
}


def _content_text(content: Mapping[str, Any]) -> str:
    try:
        if content.get("type") == "text":
            return str(content.get("text") or "")
    except Exception:
        pass
    return ""


def _content_fingerprint(content: Mapping[str, Any]) -> str:
    """Stable string to hash for change detection / dedup (never stored)."""
    try:
        ctype = str(content.get("type") or "")
        if ctype == "text":
            return "text:" + str(content.get("text") or "")
        if ctype == "image_url":
            url = content.get("image_url") or {}
            if isinstance(url, Mapping):
                return "image:" + str(url.get("url") or "")
            return "image:" + str(url)
        return ctype
    except Exception:
        return ""


def _kind_of(name: str, content: Mapping[str, Any]) -> str:
    try:
        if content.get("type") == "image_url":
            return "image"
    except Exception:
        pass
    ext = os.path.splitext(name)[1].lower()
    return _KIND_BY_EXT.get(ext, "other")


def _build_one(record: Any, source: str) -> dict[str, Any] | None:
    """Snapshot a single AttachmentRecord-like object; None when unusable."""
    try:
        name = os.path.basename(str(getattr(record, "original_name", "") or "").strip())
        if not name:
            return None
        content = getattr(record, "content", None)
        if not isinstance(content, Mapping):
            return None
        fingerprint = _content_fingerprint(content)
        preview_hash = hashlib.sha256(fingerprint.encode("utf-8", "ignore")).hexdigest()[:12]
        return {
            "ref_id": f"att-{preview_hash}",
            "name": name,
            "kind": _kind_of(name, content),
            "char_count": len(_content_text(content)),
            "preview_hash": preview_hash,
            "source": source,
        }
    except Exception:
        return None


def build_attachment_snapshot(
    records: Sequence[Any] | None,
    *,
    source: str = "workshop",
) -> list[dict[str, Any]]:
    """Build closed-shape summaries from AttachmentRecord items.

    Dedups by ``ref_id``, caps at ``MAX_ATTACHMENTS``, skips broken items,
    and never raises (returns ``[]`` on any failure).
    """
    out: list[dict[str, Any]] = []
    try:
        src = (str(source).strip() if source else "") or "workshop"
        seen: set[str] = set()
        for record in records or []:
            if len(out) >= MAX_ATTACHMENTS:
                break
            snap = _build_one(record, src)
            if snap is None:
                continue
            rid = snap["ref_id"]
            if rid in seen:
                continue
            seen.add(rid)
            out.append(snap)
    except Exception:
        return out
    return out


def _normalize_one(raw: Any, source_default: str) -> dict[str, Any] | None:
    if not isinstance(raw, Mapping):
        return None
    try:
        name = os.path.basename(str(raw.get("name") or "").strip())
        if not name:
            return None
        preview_hash = str(raw.get("preview_hash") or "").strip()
        ref_id = str(raw.get("ref_id") or "").strip()
        if not ref_id:
            if not preview_hash:
                return None
            ref_id = f"att-{preview_hash}"
        if not preview_hash:
            preview_hash = ref_id.removeprefix("att-")
        kind = str(raw.get("kind") or "").strip().lower()
        if kind not in _KIND_LABELS:
            kind = "other"
        source = str(raw.get("source") or "").strip() or source_default
        return {
            "ref_id": ref_id,
            "name": name,
            "kind": kind,
            "char_count": max(0, int(raw.get("char_count") or 0)),
            "preview_hash": preview_hash,
            "source": source,
        }
    except Exception:
        return None


def normalize_attachments(raw: Any) -> list[dict[str, Any]]:
    """Sanitize arbitrary input into the closed summary shape. Never raises."""
    out: list[dict[str, Any]] = []
    try:
        if not isinstance(raw, Sequence) or isinstance(raw, (str, bytes)):
            return []
        seen: set[str] = set()
        for item in raw:
            if len(out) >= MAX_ATTACHMENTS:
                break
            snap = _normalize_one(item, "workshop")
            if snap is None:
                continue
            rid = snap["ref_id"]
            if rid in seen:
                continue
            seen.add(rid)
            out.append(snap)
    except Exception:
        return out
    return out


def format_attachments_line(attachments: Any) -> str:
    """One Dock line for attachment state. Empty when none. Never raises."""
    try:
        items = normalize_attachments(attachments)
        if not items:
            return ""
        counts: dict[str, int] = {}
        for it in items:
            kind = str(it.get("kind") or "other")
            counts[kind] = counts.get(kind, 0) + 1
        parts = []
        for kind in ("pdf", "word", "image", "text", "other"):
            n = counts.get(kind, 0)
            if n:
                parts.append(f"{_KIND_LABELS[kind]}×{n}")
        body = " · ".join(parts)
        return f"附件 {len(items)}" + (f" · {body}" if body else "")
    except Exception:
        return ""
