from __future__ import annotations

import copy
import hashlib
import json
import os
import re
import secrets
import threading
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from .course import validate_course_bundle, validate_course_id
from .document import build_document


_PREVIEW_ID = re.compile(r"^[A-Za-z0-9_-]{22,64}$")
_CATEGORIES = frozenset({"content", "answer", "ambiguity", "difficulty", "other"})
MAX_FEEDBACK_CHARS = 4000
MAX_REVIEWER_CHARS = 80


def utc_now() -> str:
    return datetime.now(UTC).isoformat(timespec="seconds")


def content_hash(section: dict[str, Any]) -> str:
    raw = json.dumps(section, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def _atomic_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{secrets.token_hex(4)}.tmp")
    try:
        with temporary.open("w", encoding="utf-8") as handle:
            json.dump(value, handle, ensure_ascii=False, indent=2)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    finally:
        if temporary.exists():
            temporary.unlink()


class PreviewStore:
    def __init__(self, root: str | Path) -> None:
        self.root = Path(root)
        self.root.mkdir(parents=True, exist_ok=True)
        self._locks_guard = threading.Lock()
        self._locks: dict[str, threading.RLock] = {}

    def _lock(self, preview_id: str) -> threading.RLock:
        with self._locks_guard:
            return self._locks.setdefault(preview_id, threading.RLock())

    @staticmethod
    def validate_id(preview_id: str) -> str:
        if not _PREVIEW_ID.fullmatch(str(preview_id or "")):
            raise ValueError("无效的预览 id。")
        return str(preview_id)

    def _dir(self, preview_id: str) -> Path:
        self.validate_id(preview_id)
        return self.root / preview_id

    def _meta_path(self, preview_id: str) -> Path:
        return self._dir(preview_id) / "meta.json"

    def meta(self, preview_id: str) -> dict[str, Any]:
        path = self._meta_path(preview_id)
        if not path.is_file():
            raise KeyError("预览不存在。")
        with path.open(encoding="utf-8") as handle:
            value = json.load(handle)
        if not isinstance(value, dict):
            raise ValueError("预览元数据已损坏。")
        return value

    def publish(
        self,
        section: dict[str, Any],
        preview_id: str | None = None,
        *,
        course_id: str = "",
    ) -> dict[str, Any]:
        build_document(section)
        digest = content_hash(section)
        if course_id:
            course_id = validate_course_id(course_id)
        new_id = preview_id is None
        if new_id:
            preview_id = secrets.token_urlsafe(18)
        assert preview_id is not None
        with self._lock(preview_id):
            if new_id:
                meta = {
                    "preview_id": preview_id,
                    "title": str(section.get("name") or section.get("id") or "课程草稿"),
                    "current_revision": 0,
                    "current_hash": "",
                    "created_at": utc_now(),
                    "updated_at": utc_now(),
                }
            else:
                meta = self.meta(preview_id)
            if course_id and meta.get("course_id") != course_id:
                meta["course_id"] = course_id
                _atomic_json(self._meta_path(preview_id), meta)
            if meta.get("current_hash") == digest and meta.get("current_revision", 0) > 0:
                result = dict(meta)
                result["unchanged"] = True
                return result
            revision = int(meta.get("current_revision") or 0) + 1
            now = utc_now()
            payload = {
                "revision": revision,
                "content_hash": digest,
                "created_at": now,
                "section": copy.deepcopy(section),
            }
            _atomic_json(self._dir(preview_id) / "revisions" / f"{revision}.json", payload)
            meta.update(
                {
                    "title": str(section.get("name") or section.get("id") or "课程草稿"),
                    "current_revision": revision,
                    "current_hash": digest,
                    "updated_at": now,
                }
            )
            _atomic_json(self._meta_path(preview_id), meta)
            result = dict(meta)
            result["unchanged"] = False
            return result

    def _course_path(self, course_id: str) -> Path:
        return self.root / "courses" / f"{validate_course_id(course_id)}.json"

    def course(self, course_id: str) -> dict[str, Any]:
        path = self._course_path(course_id)
        if not path.is_file():
            raise KeyError("课程不存在。")
        with path.open(encoding="utf-8") as handle:
            value = json.load(handle)
        if (
            not isinstance(value, dict)
            or value.get("course_id") != course_id
            or not isinstance(value.get("entries"), list)
        ):
            raise ValueError("课程元数据已损坏。")
        return value

    def courses(self) -> list[dict[str, Any]]:
        directory = self.root / "courses"
        if not directory.is_dir():
            return []
        result = [self.course(path.stem) for path in directory.glob("*.json")]
        return sorted(result, key=lambda item: (str(item.get("title") or ""), item["course_id"]))

    def publish_course(self, value: dict[str, Any]) -> dict[str, Any]:
        bundle = validate_course_bundle(value)
        course_id = bundle["course_id"]
        with self._lock(f"course:{course_id}"):
            path = self._course_path(course_id)
            existing = self.course(course_id) if path.is_file() else None
            previous = {
                str(entry.get("section_id")): entry
                for entry in (existing or {}).get("entries", [])
                if isinstance(entry, dict) and entry.get("section_id")
            }
            preview_ids = {
                str(section_id): str(preview_id)
                for section_id, preview_id in (existing or {}).get("preview_ids", {}).items()
            }
            for section_id, entry in previous.items():
                if entry.get("preview_id"):
                    preview_ids.setdefault(section_id, str(entry["preview_id"]))
            now = utc_now()
            entries = []
            publications = []
            for entry in bundle["entries"]:
                section = entry["section"]
                metadata = {
                    key: entry[key]
                    for key in ("section_id", "name", "description", "level")
                }
                if section is None:
                    metadata["status"] = "placeholder"
                    publications.append({**metadata, "unchanged": True})
                    entries.append(metadata)
                    continue
                preview_id = preview_ids.get(entry["section_id"])
                published = self.publish(section, preview_id=preview_id, course_id=course_id)
                preview_ids[entry["section_id"]] = published["preview_id"]
                document = build_document(section)
                metadata.update(
                    {
                        "status": "published",
                        "preview_id": published["preview_id"],
                        "current_revision": published["current_revision"],
                        "current_hash": published["current_hash"],
                        "lesson_count": len(document.lessons),
                        "item_count": document.item_count,
                    }
                )
                entries.append(metadata)
                publications.append({**metadata, "unchanged": published["unchanged"]})
            meta = {
                "course_id": course_id,
                "title": bundle["title"],
                "description": bundle["description"],
                "language": bundle["language"],
                "created_at": (existing or {}).get("created_at") or now,
                "updated_at": now,
                "preview_ids": preview_ids,
                "entries": entries,
            }
            comparable = {key: item for key, item in meta.items() if key != "updated_at"}
            old_comparable = {
                key: item for key, item in (existing or {}).items() if key != "updated_at"
            }
            unchanged = existing is not None and comparable == old_comparable
            if unchanged:
                meta["updated_at"] = existing["updated_at"]
            else:
                _atomic_json(path, meta)
            return {**meta, "unchanged": unchanged, "publications": publications}

    def revision(self, preview_id: str, revision: int | None = None) -> dict[str, Any]:
        meta = self.meta(preview_id)
        number = int(meta["current_revision"]) if revision is None else int(revision)
        if number < 1 or number > int(meta["current_revision"]):
            raise ValueError("反馈所指的修订不存在。")
        path = self._dir(preview_id) / "revisions" / f"{number}.json"
        with path.open(encoding="utf-8") as handle:
            value = json.load(handle)
        if not isinstance(value, dict) or not isinstance(value.get("section"), dict):
            raise ValueError("预览修订已损坏。")
        return value

    def add_feedback(
        self,
        preview_id: str,
        *,
        revision: int,
        item_key: str = "",
        category: str = "other",
        reviewer: str = "",
        message: str,
    ) -> dict[str, Any]:
        reviewer = str(reviewer or "").strip()
        message = str(message or "").strip()
        category = str(category or "other")
        if category not in _CATEGORIES:
            raise ValueError("无效的反馈分类。")
        if not message:
            raise ValueError("请填写反馈内容。")
        if len(message) > MAX_FEEDBACK_CHARS:
            raise ValueError(f"反馈不能超过 {MAX_FEEDBACK_CHARS} 字。")
        if len(reviewer) > MAX_REVIEWER_CHARS:
            raise ValueError(f"称呼不能超过 {MAX_REVIEWER_CHARS} 字。")
        with self._lock(preview_id):
            payload = self.revision(preview_id, revision)
            document = build_document(payload["section"])
            question = None
            if item_key:
                item = document.item(item_key)
                if item is None:
                    raise ValueError("反馈所指的题目不存在。")
                question = item.snapshot()
            entry = {
                "id": secrets.token_urlsafe(12),
                "preview_id": preview_id,
                "revision": int(payload["revision"]),
                "item_key": item_key,
                "question": question,
                "category": category,
                "reviewer": reviewer,
                "message": message,
                "created_at": utc_now(),
            }
            path = self._dir(preview_id) / "feedback.jsonl"
            path.parent.mkdir(parents=True, exist_ok=True)
            with path.open("a", encoding="utf-8") as handle:
                handle.write(json.dumps(entry, ensure_ascii=False, separators=(",", ":")) + "\n")
                handle.flush()
                os.fsync(handle.fileno())
            return entry

    def feedback(self, preview_id: str) -> list[dict[str, Any]]:
        self.validate_id(preview_id)
        self.meta(preview_id)
        path = self._dir(preview_id) / "feedback.jsonl"
        if not path.is_file():
            return []
        result = []
        with path.open(encoding="utf-8") as handle:
            for line_number, line in enumerate(handle, start=1):
                if not line.strip():
                    continue
                try:
                    value = json.loads(line)
                except json.JSONDecodeError as exc:
                    raise ValueError(f"反馈文件第 {line_number} 行已损坏。") from exc
                if isinstance(value, dict):
                    result.append(value)
        return result
