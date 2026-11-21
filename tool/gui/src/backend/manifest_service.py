"""Pure-Python reader/writer & consistency auditor for Phase Two manifests.

Covers ``media_manifest.json`` and ``audio_manifest.json`` (ADR 0072):
- Scans the in-memory course (sections + vocab + expressions) for every
  referenced image and audio asset path.
- Audits ``media_manifest.json`` entries against on-disk files and course refs,
  flagging ``missing_file``, ``unused``, and ``unregistered`` refs.
- Audits and persists ``audio_manifest.json`` review statuses and metadata.

Zero Qt dependency so it is unit-testable headless and obeys ``--fail-backend-qt``.
"""
from __future__ import annotations

import json
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from src.backend import api

MEDIA_STRING_IMAGE_KEYS = frozenset({"imageAsset"})
MEDIA_LIST_IMAGE_KEYS = frozenset({"imageAssets", "frontImageAssets", "backImageAssets"})
MEDIA_STRING_AUDIO_KEYS = frozenset({"audioAsset"})
MEDIA_LIST_AUDIO_KEYS = frozenset({"audioAssets", "frontAudioAssets", "backAudioAssets"})

MEDIA_REVIEW_STATUSES = ("pending", "rendered-locally", "approved", "existing-asset", "needs-revision")
AUDIO_REVIEW_STATUSES = ("pending", "generated", "approved", "needs-revision")
FINAL_MEDIA_REVIEW_STATUSES = frozenset({"approved", "existing-asset"})
FINAL_AUDIO_REVIEW_STATUSES = frozenset({"approved"})


def resolve_asset_on_disk(course_dir: Path | None, asset_ref: str) -> Path | None:
    """Resolve ``media/...`` or ``assets/...`` relative to course/workspace/repo root."""
    ref = str(asset_ref or "").strip().replace("\\", "/")
    if not ref or ref.startswith(("anki://", "turnapack://", "http://", "https://")):
        return None
    if course_dir is None:
        return None
    base = Path(course_dir)
    candidates = [base / ref, base.parent / ref]
    for ancestor in base.parents:
        if (ancestor / "pubspec.yaml").is_file() or (ancestor / "assets").is_dir():
            candidates.append(ancestor / ref)
            break
    for cand in candidates:
        if cand.is_file():
            return cand
    return None


def resolve_audio_asset_on_disk(
    course_dir: Path | None, asset_ref: str
) -> Path | None:
    ref = str(asset_ref or "").strip().replace("\\", "/")
    if not ref or "://" in ref:
        return None
    path = api.audio_asset_path(ref, course_dir)
    return path if path.is_file() else None


def collect_course_media_references(adapter: Any) -> tuple[set[str], set[str]]:
    """Return ``(image_refs, audio_refs)`` referenced across the loaded course."""
    images: set[str] = set()
    audios: set[str] = set()

    def _record(val: Any, target: set[str]) -> None:
        if not isinstance(val, str):
            return
        text = val.strip().replace("\\", "/")
        if text and not text.startswith(("anki://", "turnapack://")):
            target.add(text)

    def _walk(node: Any) -> None:
        if isinstance(node, dict):
            for key, value in node.items():
                if key in MEDIA_STRING_IMAGE_KEYS:
                    _record(value, images)
                elif key in MEDIA_LIST_IMAGE_KEYS and isinstance(value, list):
                    for entry in value:
                        _record(entry, images)
                elif key in MEDIA_STRING_AUDIO_KEYS:
                    _record(value, audios)
                elif key in MEDIA_LIST_AUDIO_KEYS and isinstance(value, list):
                    for entry in value:
                        _record(entry, audios)
                else:
                    _walk(value)
        elif isinstance(node, list):
            for item in node:
                _walk(item)

    _walk(getattr(adapter, "sections", []))
    _walk(getattr(adapter, "vocab", []))
    _walk(getattr(adapter, "expressions", []))
    return images, audios


def load_media_manifest(course_dir: Path | None) -> dict[str, Any]:
    default: dict[str, Any] = {
        "version": 1,
        "ota": "json-only; media requires an app release",
        "assets": [],
    }
    if course_dir is None:
        return default
    path = Path(course_dir) / "media_manifest.json"
    if not path.is_file():
        return default
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        return default
    data.setdefault("version", 1)
    data.setdefault("ota", default["ota"])
    if not isinstance(data.get("assets"), list):
        data["assets"] = []
    return data


def save_media_manifest(course_dir: Path, data: dict[str, Any]) -> Path:
    path = Path(course_dir) / "media_manifest.json"
    tmp = path.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.replace(tmp, path)
    return path


def load_audio_manifest_doc(course_dir: Path | None) -> dict[str, Any]:
    default: dict[str, Any] = {
        "version": 1,
        "status": "pending-generation-and-human-review",
        "provider": "MiniMax",
        "model": "configured-by-tool/generate_audio.py",
        "assets": [],
    }
    if course_dir is None:
        return default
    path = Path(course_dir) / "audio_manifest.json"
    if not path.is_file():
        return default
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        return default
    data.setdefault("version", 1)
    if not isinstance(data.get("assets"), list):
        data["assets"] = []
    return data


def save_audio_manifest_doc(course_dir: Path, data: dict[str, Any]) -> Path:
    path = Path(course_dir) / "audio_manifest.json"
    tmp = path.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.replace(tmp, path)
    return path


@dataclass(frozen=True)
class MediaAuditSummary:
    registered_count: int
    missing_files: tuple[str, ...]
    missing_referenced_refs: tuple[str, ...]
    unregistered_refs: tuple[str, ...]
    unused_entries: tuple[str, ...]
    pending_review_count: int
    pending_review_refs: tuple[str, ...]

    def to_dict(self) -> dict[str, Any]:
        return {
            "registered_count": self.registered_count,
            "missing_files": list(self.missing_files),
            "missing_referenced_refs": list(self.missing_referenced_refs),
            "unregistered_refs": list(self.unregistered_refs),
            "unused_entries": list(self.unused_entries),
            "pending_review_count": self.pending_review_count,
            "pending_review_refs": list(self.pending_review_refs),
        }


def audit_media_manifest(adapter: Any) -> MediaAuditSummary:
    course_dir = getattr(adapter, "course_dir", None)
    doc = load_media_manifest(course_dir)
    entries = [e for e in (doc.get("assets") or []) if isinstance(e, dict)]
    referenced_images, _audios = collect_course_media_references(adapter)
    registered_paths = {
        str(e.get("asset") or "").strip().replace("\\", "/")
        for e in entries
        if e.get("asset")
    }

    missing_files: list[str] = []
    missing_references: list[str] = []
    unused_entries: list[str] = []
    pending_references: list[str] = []
    pending = 0
    for entry in entries:
        asset = str(entry.get("asset") or "").strip().replace("\\", "/")
        if not asset:
            continue
        missing = resolve_asset_on_disk(course_dir, asset) is None
        if missing:
            missing_files.append(asset)
            if asset in referenced_images:
                missing_references.append(asset)
        if asset not in referenced_images:
            unused_entries.append(asset)
        status = str(entry.get("reviewStatus") or "pending").strip().lower()
        if status not in FINAL_MEDIA_REVIEW_STATUSES:
            pending += 1
            if asset in referenced_images:
                pending_references.append(asset)

    unregistered = sorted(ref for ref in referenced_images if ref not in registered_paths)
    return MediaAuditSummary(
        registered_count=len(entries),
        missing_files=tuple(sorted(missing_files)),
        missing_referenced_refs=tuple(sorted(missing_references)),
        unregistered_refs=tuple(unregistered),
        unused_entries=tuple(sorted(unused_entries)),
        pending_review_count=pending,
        pending_review_refs=tuple(sorted(pending_references)),
    )


def register_missing_media_entries(adapter: Any, doc: dict[str, Any]) -> int:
    """Append placeholder entries in *doc* for referenced images absent from ``media_manifest.json``."""
    referenced_images, _audios = collect_course_media_references(adapter)
    assets = doc.setdefault("assets", [])
    existing = {
        str(e.get("asset") or "").strip().replace("\\", "/")
        for e in assets
        if isinstance(e, dict)
    }
    added = 0
    for ref in sorted(referenced_images):
        if ref in existing:
            continue
        assets.append(
            {
                "asset": ref,
                "kind": "image",
                "alt": "",
                "source": "author-added",
                "generatedBy": "manual",
                "reviewStatus": "pending",
            }
        )
        added += 1
    return added


def audit_audio_manifest_doc(course_dir: Path | None) -> dict[str, Any]:
    doc = load_audio_manifest_doc(course_dir)
    entries = [e for e in (doc.get("assets") or []) if isinstance(e, dict)]
    pending = sum(
        1
        for e in entries
        if str(e.get("reviewStatus") or "pending").strip().lower()
        not in FINAL_AUDIO_REVIEW_STATUSES
    )
    approved = sum(
        1
        for e in entries
        if str(e.get("reviewStatus") or "").strip().lower()
        in FINAL_AUDIO_REVIEW_STATUSES
    )
    return {
        "total": len(entries),
        "pending_count": pending,
        "approved_count": approved,
        "status": str(doc.get("status") or ""),
    }


@dataclass(frozen=True)
class AudioAuditSummary:
    total_count: int
    referenced_count: int
    approved_count: int
    pending_count: int
    missing_files: tuple[str, ...]
    unregistered_refs: tuple[str, ...]
    unused_entries: tuple[str, ...]
    pending_review_refs: tuple[str, ...]
    status: str

    def to_dict(self) -> dict[str, Any]:
        return {
            "total": self.total_count,
            "referenced_count": self.referenced_count,
            "approved_count": self.approved_count,
            "pending_count": self.pending_count,
            "missing_files": list(self.missing_files),
            "unregistered_refs": list(self.unregistered_refs),
            "unused_entries": list(self.unused_entries),
            "pending_review_refs": list(self.pending_review_refs),
            "status": self.status,
        }


def audit_audio_manifest(adapter: Any) -> AudioAuditSummary:
    course_dir = getattr(adapter, "course_dir", None)
    doc = load_audio_manifest_doc(course_dir)
    entries = [e for e in (doc.get("assets") or []) if isinstance(e, dict)]
    _images, referenced_audio = collect_course_media_references(adapter)
    tts_ids = {
        str(entry.get("id") or "")
        for pool_name in ("vocab", "expressions")
        for entry in (getattr(adapter, pool_name, []) or [])
        if isinstance(entry, dict) and entry.get("id")
    }
    referenced = {
        ref for ref in referenced_audio if ref not in tts_ids and "://" not in ref
    }
    by_ref = {
        str(entry.get("asset") or "").strip().replace("\\", "/"): entry
        for entry in entries
        if entry.get("asset")
    }

    missing: list[str] = []
    unregistered: list[str] = []
    pending_references: list[str] = []
    for ref in sorted(referenced):
        if resolve_audio_asset_on_disk(course_dir, ref) is None:
            missing.append(ref)
        entry = by_ref.get(ref)
        if entry is None:
            unregistered.append(ref)
            continue
        status = str(entry.get("reviewStatus") or "pending").strip().lower()
        if status not in FINAL_AUDIO_REVIEW_STATUSES:
            pending_references.append(ref)

    pending = sum(
        1
        for entry in entries
        if str(entry.get("reviewStatus") or "pending").strip().lower()
        not in FINAL_AUDIO_REVIEW_STATUSES
    )
    approved = sum(
        1
        for entry in entries
        if str(entry.get("reviewStatus") or "").strip().lower()
        in FINAL_AUDIO_REVIEW_STATUSES
    )
    return AudioAuditSummary(
        total_count=len(entries),
        referenced_count=len(referenced),
        approved_count=approved,
        pending_count=pending,
        missing_files=tuple(missing),
        unregistered_refs=tuple(unregistered),
        unused_entries=tuple(sorted(set(by_ref) - referenced)),
        pending_review_refs=tuple(pending_references),
        status=str(doc.get("status") or ""),
    )


def build_media_gate(
    media: MediaAuditSummary, audio: AudioAuditSummary
) -> dict[str, Any]:
    blockers: list[dict[str, str]] = []

    def add(code: str, refs: tuple[str, ...], label: str) -> None:
        for ref in refs:
            blockers.append({"code": code, "message": f"{label}：{ref}"})

    add("image_missing", media.missing_referenced_refs, "图片文件缺失")
    add("image_unregistered", media.unregistered_refs, "图片尚未登记到媒体清单")
    add("image_review", media.pending_review_refs, "图片尚未完成人工审校")
    add("audio_missing", audio.missing_files, "音频文件缺失")
    add("audio_unregistered", audio.unregistered_refs, "音频尚未登记到审校清单")
    add("audio_review", audio.pending_review_refs, "音频尚未完成人工审校")
    return {"ok": not blockers, "blockers": blockers}
