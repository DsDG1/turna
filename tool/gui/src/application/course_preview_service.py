from __future__ import annotations

import copy
from typing import Any

from src.backend.ai import request_correction
from src.backend.ai_fixer import build_correction_prompt
from src.backend.course_preview.client import SshPreviewClient
from src.backend.course_preview.store import content_hash


_CATEGORY_LABELS = {
    "content": "内容错误",
    "answer": "答案错误",
    "ambiguity": "题意有歧义",
    "difficulty": "难度不合适",
    "other": "其他建议",
}


def section_hash(section: dict[str, Any]) -> str:
    return content_hash(section)


def normalize_preview_state(value: dict[str, Any] | None) -> dict[str, Any]:
    value = value if isinstance(value, dict) else {}
    result = {
        "preview_id": str(value.get("preview_id") or ""),
        "url": str(value.get("url") or ""),
        "published_revision": int(value.get("published_revision") or 0),
        "published_hash": str(value.get("published_hash") or ""),
        "handled_feedback_ids": sorted(
            {str(item) for item in value.get("handled_feedback_ids") or [] if str(item)}
        ),
        "pending_feedback_ids": sorted(
            {str(item) for item in value.get("pending_feedback_ids") or [] if str(item)}
        ),
    }
    if value.get("last_published_at"):
        result["last_published_at"] = str(value["last_published_at"])
    return result


def apply_publication_state(
    current: dict[str, Any],
    result: dict[str, Any],
    handled_ids: set[str] | None = None,
) -> dict[str, Any]:
    state = normalize_preview_state(current)
    preview_id = str(result.get("preview_id") or "")
    if not preview_id:
        raise ValueError("发布结果缺少 preview_id。")
    state.update(
        {
            "preview_id": preview_id,
            "url": str(result.get("url") or state["url"]),
            "published_revision": int(result.get("current_revision") or 0),
            "published_hash": str(result.get("current_hash") or ""),
            "last_published_at": str(result.get("updated_at") or ""),
        }
    )
    handled = set(state["handled_feedback_ids"])
    handled.update(handled_ids or set())
    pending = set(state["pending_feedback_ids"])
    pending.difference_update(handled_ids or set())
    state["handled_feedback_ids"] = sorted(handled)
    state["pending_feedback_ids"] = sorted(pending)
    return state


def feedback_to_problem(entry: dict[str, Any], current_revision: int) -> dict[str, Any]:
    revision = int(entry.get("revision") or 0)
    question = entry.get("question") if isinstance(entry.get("question"), dict) else None
    location = str((question or {}).get("location") or "整节课程")
    path = str(entry.get("item_key") or "section:whole")
    category = _CATEGORY_LABELS.get(str(entry.get("category") or "other"), "其他建议")
    old = f"（旧修订 r{revision}，当前 r{current_revision}）" if revision != current_revision else ""
    lines = [f"网页反馈{old} · {category} · {location}", str(entry.get("message") or "").strip()]
    if question:
        lines.extend(
            [
                f"题目：{question.get('prompt') or '（无题干）'}",
                f"提交时参考答案：{question.get('answer') or '（无）'}",
            ]
        )
    reviewer = str(entry.get("reviewer") or "").strip()
    if reviewer:
        lines.append(f"审阅人：{reviewer}")
    return {
        "level": "warning",
        "path": path,
        "message": "\n".join(line for line in lines if line),
        "feedback_id": str(entry.get("id") or ""),
        "feedback_revision": revision,
    }


def request_feedback_revision(
    config: Any,
    problems: list[dict[str, Any]],
    draft: dict[str, Any],
    course_context: dict[str, Any],
    instruction: str,
    *,
    timeout: float = 120.0,
    temperature: float = 0.2,
) -> dict[str, Any]:
    prompt = build_correction_prompt(
        problems,
        draft,
        course_context,
        user_hint=instruction,
    )
    return request_correction(
        config,
        prompt,
        timeout=timeout,
        temperature=temperature,
    )


class CoursePreviewService:
    def __init__(self, ssh_target: str = "turna", *, client: Any = None) -> None:
        self._client = client or SshPreviewClient(ssh_target)

    def publish(self, section: dict[str, Any], preview_id: str = "") -> dict[str, Any]:
        return self._client.publish(section, preview_id=preview_id)

    def feedback(self, preview_id: str) -> list[dict[str, Any]]:
        return self._client.feedback(preview_id)


def copy_preview_state(state: dict[str, Any]) -> dict[str, Any]:
    return copy.deepcopy(normalize_preview_state(state))
