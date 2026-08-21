"""K-24 git commit_message + explain_diff skill (pure Python, no Qt).

Read-only Experience skill: feeds the current working-tree diff to the chat
model via ``request_chat`` and returns plain text (a commit message or a
natural-language explanation of the diff). Never writes the course tree, no
ConflictGuard, no sandbox, no ``dangerous`` flag. Diff bodies stay local —
only the short summary is recorded to Timeline/telemetry (§14.5.3).

红线：
* 纯函数构造 messages / 抽取回复；无 IO、无 Qt、不写树。
* diff 超长截断（防 token 爆炸）；不记原文到 telemetry。
"""
from __future__ import annotations

from typing import Any

# Max chars of diff text sent to the model. Commit messages are shorter, so
# the commit path caps tighter; explain_diff is more generous.
COMMIT_DIFF_MAX_CHARS = 12000
EXPLAIN_DIFF_MAX_CHARS = 16000

_COMMIT_SYSTEM = (
    "你是提交信息生成器。基于给定的 git diff，生成一条符合 Conventional Commits "
    "规范的提交信息：首行形如 `type: 简述`（type ∈ feat/fix/refactor/docs/chore/"
    "test/perf），其后可附一段简短中文 body 说明动机。只输出提交信息文本，"
    "不要额外解释。"
)
_EXPLAIN_SYSTEM = (
    "你是代码改动审阅助手。基于给定的 git diff，用自然语言简述这组改动的意图、"
    "涉及范围与潜在影响，分点说明。不要逐行复述 diff。"
)


def _truncate(diff_text: str, limit: int) -> str:
    text = str(diff_text or "")
    if len(text) <= limit:
        return text
    half = limit // 2
    return (
        text[:half]
        + f"\n\n…（已截断，原 {len(text)} 字符）…\n\n"
        + text[-half:]
    )


def build_commit_message_messages(
    diff_text: str, *, max_diff_chars: int = COMMIT_DIFF_MAX_CHARS
) -> list[dict[str, Any]]:
    """Build chat messages for commit-message generation. Never raises."""
    body = _truncate(diff_text, max_diff_chars)
    return [
        {"role": "system", "content": _COMMIT_SYSTEM},
        {"role": "user", "content": f"git diff HEAD:\n\n{body}" if body else "（空 diff）"},
    ]


def build_explain_diff_messages(
    diff_text: str, *, max_diff_chars: int = EXPLAIN_DIFF_MAX_CHARS
) -> list[dict[str, Any]]:
    """Build chat messages for diff explanation. Never raises."""
    body = _truncate(diff_text, max_diff_chars)
    return [
        {"role": "system", "content": _EXPLAIN_SYSTEM},
        {"role": "user", "content": f"git diff HEAD:\n\n{body}" if body else "（空 diff）"},
    ]


def run_git_skill(
    config: Any,
    action_id: str,
    diff_text: str,
) -> str:
    """Run the git skill via ``request_chat``; return plain-text reply.

    Raises ``RuntimeError`` on network/parse failure (propagated by the worker
    as ``error_occurred``). ``action_id`` selects the message builder.
    """
    from src.backend.ai_generator import content_text, request_chat

    if action_id == "git.commit_message":
        messages = build_commit_message_messages(diff_text)
    elif action_id == "git.explain_diff":
        messages = build_explain_diff_messages(diff_text)
    else:
        raise ValueError(f"未知 git skill: {action_id}")
    body = request_chat(config, messages, temperature=0.4)
    choices = (body or {}).get("choices") or []
    if not choices:
        return ""
    msg = (choices[0].get("message") or {}).get("content")
    return content_text(msg)


def gather_diff_text(git_lib: Any, local_dir: Any) -> tuple[str, str]:
    """Return ``(diff_text, error)``. Empty/error → diff_text="" + non-empty error.

    ``git_lib`` duck-types ``GitLibrary``: only ``diff_working_vs_head`` is used.
    No Qt, never raises.
    """
    if git_lib is None:
        return "", "无 Git 库实例"
    if not local_dir:
        return "", "未打开课程/Git 仓库"
    try:
        diff = git_lib.diff_working_vs_head(local_dir)
    except Exception as exc:  # noqa: BLE001
        return "", f"读取 diff 失败：{exc.__class__.__name__}"
    diff = str(diff or "")
    if not diff.strip():
        return "", "工作树无改动"
    return diff, ""