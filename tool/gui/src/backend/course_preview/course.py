from __future__ import annotations

import copy
import json
import re
from pathlib import Path
from typing import Any

from .document import build_document


_COURSE_ID = re.compile(r"^[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?$")


def validate_course_id(course_id: Any) -> str:
    value = str(course_id or "").strip()
    if not _COURSE_ID.fullmatch(value):
        raise ValueError("课程 id 只能包含小写字母、数字和连字符，最长 64 字符。")
    return value


def _json_object(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as handle:
        value = json.load(handle)
    if not isinstance(value, dict):
        raise ValueError(f"{path.name} 顶层必须是 JSON 对象。")
    return value


def _section_path(course_dir: Path, relative: Any) -> Path:
    if not isinstance(relative, str) or not relative.strip():
        raise ValueError("课程索引中的 section file 必须是非空字符串。")
    path = (course_dir / relative).resolve()
    try:
        path.relative_to(course_dir)
    except ValueError as exc:
        raise ValueError(f"section 路径越出课程目录：{relative}") from exc
    if not path.is_file():
        raise ValueError(f"section 文件不存在：{relative}")
    return path


def _default_title(course_dir: Path, index: dict[str, Any]) -> str:
    for key in ("title", "name"):
        value = index.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()
    manifest_path = course_dir.parent / "manifest.json"
    if manifest_path.is_file():
        try:
            manifest = _json_object(manifest_path)
        except (OSError, ValueError, json.JSONDecodeError):
            manifest = {}
        languages = manifest.get("languages")
        if isinstance(languages, list):
            for language in languages:
                if not isinstance(language, dict) or language.get("dir") != course_dir.name:
                    continue
                for key in ("nativeLabel", "displayName"):
                    value = language.get(key)
                    if isinstance(value, str) and value.strip():
                        return value.strip()
    return course_dir.name


def _with_course_words(section: dict[str, Any], words: list[Any]) -> dict[str, Any]:
    result = copy.deepcopy(section)
    own_words = result.get("words")
    if own_words is not None and not isinstance(own_words, list):
        raise ValueError(f"section {result.get('id') or '?'} 的 words 必须是数组。")
    merged = {
        str(word.get("id")): word
        for word in words
        if isinstance(word, dict) and word.get("id")
    }
    merged.update(
        {
            str(word.get("id")): word
            for word in own_words or []
            if isinstance(word, dict) and word.get("id")
        }
    )
    result["words"] = list(merged.values())
    return result


def validate_course_bundle(value: dict[str, Any]) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ValueError("课程发布内容顶层必须是 JSON 对象。")
    course_id = validate_course_id(value.get("course_id"))
    title = str(value.get("title") or "").strip()
    if not title:
        raise ValueError("课程标题不能为空。")
    raw_entries = value.get("entries")
    if not isinstance(raw_entries, list) or not raw_entries:
        raise ValueError("课程发布内容必须包含 entries 数组。")
    entries = []
    seen: set[str] = set()
    for position, raw in enumerate(raw_entries, start=1):
        if not isinstance(raw, dict):
            raise ValueError(f"课程第 {position} 个章节条目不是对象。")
        section_id = str(raw.get("section_id") or "").strip()
        if not section_id or len(section_id) > 160:
            raise ValueError(f"课程第 {position} 个章节缺少有效 id。")
        if section_id in seen:
            raise ValueError(f"课程包含重复章节 id：{section_id}")
        seen.add(section_id)
        section = raw.get("section")
        if section is not None:
            if not isinstance(section, dict):
                raise ValueError(f"章节 {section_id} 的内容必须是对象或 null。")
            if str(section.get("id") or "") != section_id:
                raise ValueError(f"章节 {section_id} 的索引 id 与文件 id 不一致。")
            build_document(section)
        name = str(raw.get("name") or (section or {}).get("name") or section_id).strip()
        entries.append(
            {
                "section_id": section_id,
                "name": name,
                "description": str(raw.get("description") or "").strip(),
                "level": str(raw.get("level") or "").strip(),
                "section": copy.deepcopy(section),
            }
        )
    return {
        "course_id": course_id,
        "title": title,
        "description": str(value.get("description") or "").strip(),
        "language": str(value.get("language") or "").strip(),
        "entries": entries,
    }


def load_course_bundle(
    course_dir: str | Path,
    *,
    course_id: str = "",
    title: str = "",
) -> dict[str, Any]:
    root = Path(course_dir).resolve()
    if not root.is_dir():
        raise ValueError(f"课程目录不存在：{course_dir}")
    index = _json_object(root / "index.json")
    raw_sections = index.get("sections")
    if not isinstance(raw_sections, list) or not raw_sections:
        raise ValueError("课程 index.json 必须包含非空 sections 数组。")
    vocabulary_path = root / "vocab.json"
    vocabulary = _json_object(vocabulary_path) if vocabulary_path.is_file() else {}
    words = vocabulary.get("words") or []
    if not isinstance(words, list):
        raise ValueError("vocab.json 的 words 必须是数组。")
    entries = []
    seen: set[str] = set()
    for position, raw in enumerate(raw_sections, start=1):
        if not isinstance(raw, dict):
            raise ValueError(f"课程索引第 {position} 个章节不是对象。")
        section_id = str(raw.get("id") or "").strip()
        if not section_id:
            raise ValueError(f"课程索引第 {position} 个章节缺少 id。")
        if section_id in seen:
            raise ValueError(f"课程索引包含重复章节 id：{section_id}")
        seen.add(section_id)
        section = _json_object(_section_path(root, raw.get("file")))
        if str(section.get("id") or "") != section_id:
            raise ValueError(f"章节 {section_id} 的索引 id 与文件 id 不一致。")
        units = section.get("units")
        placeholder = units == []
        if not placeholder:
            section = _with_course_words(section, words)
        entries.append(
            {
                "section_id": section_id,
                "name": str(section.get("name") or raw.get("name") or section_id),
                "description": str(section.get("description") or raw.get("description") or ""),
                "level": str(raw.get("level") or ""),
                "section": None if placeholder else section,
            }
        )
    return validate_course_bundle(
        {
            "course_id": course_id or root.name,
            "title": title or _default_title(root, index),
            "description": index.get("description") or "",
            "language": index.get("language") or "",
            "entries": entries,
        }
    )
