"""Pure helpers for AI-assisted course correction.

The GUI detects validation/lint problems, packages the affected node JSON plus
context, and asks the model to return a corrected JSON node. This module builds
those prompts and extracts the corrected JSON so the rest of the application
(Qt/undo stack wiring) stays separate and testable.
"""
from __future__ import annotations

import json
from typing import Any


def build_correction_prompt(
    problems: list[dict[str, Any]],
    node_json: dict[str, Any],
    course_context: dict[str, Any],
) -> str:
    """Return a prompt that asks the model to fix ``node_json`` problems.

    ``problems`` are dicts with ``level``, ``message``, and ``path`` keys (the
    same shape produced by ``CourseAdapter.validate_section_json`` and the CLI
    validator). ``course_context`` may include ``language``, ``source_language``,
    ``node_kind`` (section/unit/lesson), and ``existing_resource_ids``.
    """
    lines = [
        "你是一名课程数据修正助手。请修正下面 JSON 节点中的校验问题。",
        "",
        "## 修正要求",
        "1. 只返回修正后的 JSON 对象，不要 markdown 代码块，不要解释。",
        "2. 保持所有 id 不变，包括 section id、unit id、lesson id、stage id、subLesson id、item id。",
        "3. 不要删除未出错的字段。",
        "4. 修正后必须能通过课程结构校验。",
        "5. 如果问题引用了不存在的 wordId / expressionId / grammarPointId，请从顶层资源数组中补充对应的条目，或把引用改为已存在的资源 id。",
        "",
    ]

    lines.append("## 课程上下文")
    for key, value in course_context.items():
        if key == "existing_resource_ids" and isinstance(value, dict):
            lines.append(f"- {key}:")
            for res_type, ids in value.items():
                lines.append(f"  - {res_type}: {len(ids)} 个")
        else:
            lines.append(f"- {key}: {value}")
    lines.append("")

    lines.append("## 校验问题")
    for p in problems:
        level = p.get("level", "error")
        path = p.get("path", "")
        message = p.get("message", "")
        lines.append(f"- [{level}] {path}: {message}")
    lines.append("")

    lines.append("## 需要修正的 JSON 节点")
    lines.append(json.dumps(node_json, ensure_ascii=False, indent=2))
    lines.append("")
    lines.append("请返回修正后的 JSON 对象：")
    return "\n".join(lines)


def extract_json_object(text: str) -> dict[str, Any]:
    """Parse the first JSON object from a model response.

    The model may wrap the JSON in markdown fences or add trailing text; this
    strips common fences and returns the parsed dict. Raises ``ValueError`` if
    no valid object is found.
    """
    text = text.strip()
    # Strip markdown fences if present.
    if text.startswith("```"):
        lines = text.splitlines()
        if lines and lines[0].startswith("```"):
            lines = lines[1:]
        if lines and lines[-1].strip() == "```":
            lines = lines[:-1]
        text = "\n".join(lines).strip()

    # Find the first top-level object by scanning braces.
    depth = 0
    start = -1
    for i, ch in enumerate(text):
        if ch == "{":
            if depth == 0:
                start = i
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0 and start != -1:
                try:
                    return json.loads(text[start : i + 1])
                except json.JSONDecodeError:
                    start = -1
    raise ValueError("响应中未找到有效的 JSON 对象")
