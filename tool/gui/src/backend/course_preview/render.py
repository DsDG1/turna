from __future__ import annotations

import html
from typing import Any

from .document import PreviewDocument, PreviewItem, PreviewLesson


_CATEGORY_OPTIONS = (
    ("content", "内容错误"),
    ("answer", "答案错误"),
    ("ambiguity", "题意有歧义"),
    ("difficulty", "难度不合适"),
    ("other", "其他建议"),
)


def _e(value: Any) -> str:
    return html.escape(str(value or ""), quote=True)


def _base(base_path: str) -> str:
    if not base_path or base_path == "/":
        return ""
    return "/" + base_path.strip("/")


def preview_url(public_base: str, preview_id: str) -> str:
    return f"{public_base.rstrip('/')}/p/{preview_id}/"


def course_url(public_base: str, course_id: str) -> str:
    return f"{public_base.rstrip('/')}/c/{course_id}/"


def _page(
    *,
    title: str,
    body: str,
    base_path: str,
    preview_id: str = "",
    revision: int = 0,
    home_url: str = "",
    badge: str = "",
    saved: bool = False,
) -> str:
    base = _base(base_path)
    home = home_url or (f"{base}/p/{preview_id}/" if preview_id else f"{base}/")
    badge = badge or (f"第 {revision} 版 · 私有链接" if preview_id else "课程目录")
    notice = '<p class="notice">反馈已保存，谢谢。课程作者会在本地审阅后发布新修订。</p>' if saved else ""
    return f"""<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex,nofollow,noarchive">
<title>{_e(title)} · Turna 课程预览</title>
<link rel="stylesheet" href="{base}/assets/preview.css">
</head>
<body>
<main class="wrap">
<header class="topbar">
<a class="brand" href="{home}">Turna · 课程题目预览</a>
<span class="revision">{_e(badge)}</span>
</header>
{notice}
{body}
<footer class="footer">这是用于审阅题目的静态粗预览，不是正式学习页。获得本链接即可查看和留言，请勿放入敏感信息。</footer>
</main>
</body>
</html>"""


def render_catalog(courses: list[dict[str, Any]], *, base_path: str = "") -> str:
    cards = []
    for course in courses:
        entries = course.get("entries") or []
        published = [entry for entry in entries if entry.get("status") == "published"]
        lessons = sum(int(entry.get("lesson_count") or 0) for entry in published)
        items = sum(int(entry.get("item_count") or 0) for entry in published)
        description = str(course.get("description") or "").strip()
        cards.append(
            f'<section class="card"><h2><a href="{_base(base_path)}/c/{_e(course["course_id"])}/">'
            f'{_e(course.get("title") or course["course_id"])}</a></h2>'
            f'<p class="meta">{len(published)} 个可预览章节 · {lessons} 课时 · {items} 题</p>'
            f'{f"<p>{_e(description)}</p>" if description else ""}</section>'
        )
    body = f"""<h1>课程目录</h1>
<p class="muted">这里只列出作者明确发布的课程。选择课程后可按章节、课时看题并留言。</p>
{''.join(cards) if cards else '<p class="muted">尚未发布课程。</p>'}"""
    return _page(title="课程目录", body=body, base_path=base_path)


def render_course(course: dict[str, Any], *, base_path: str = "") -> str:
    rows = []
    for entry in course.get("entries") or []:
        name = _e(entry.get("name") or entry.get("section_id"))
        description = _e(entry.get("description"))
        details = f'<div class="meta">{description}</div>' if description else ""
        if entry.get("status") == "published" and entry.get("preview_id"):
            label = f'<a href="{_base(base_path)}/p/{_e(entry["preview_id"])}/">{name}</a>'
            stats = (
                f'{int(entry.get("lesson_count") or 0)} 课时 · '
                f'{int(entry.get("item_count") or 0)} 题 · 第 {int(entry.get("current_revision") or 0)} 版'
            )
        else:
            label = f"<span>{name}</span>"
            stats = "待施工"
        rows.append(f'<li><div>{label}{details}</div><span class="meta">{stats}</span></li>')
    description = str(course.get("description") or "").strip()
    body = f"""<p><a href="{_base(base_path)}/">← 返回课程目录</a></p>
<h1>{_e(course.get("title") or course.get("course_id"))}</h1>
{f'<p class="muted">{_e(description)}</p>' if description else ''}
<section class="card"><h2>章节</h2><ul class="lesson-list">{''.join(rows)}</ul></section>"""
    return _page(
        title=str(course.get("title") or course.get("course_id")),
        body=body,
        base_path=base_path,
        badge="已发布课程",
    )


def _feedback_form(
    *,
    preview_id: str,
    revision: int,
    base_path: str,
    item: PreviewItem | None = None,
) -> str:
    base = _base(base_path)
    suffix = item.anchor if item is not None else "section"
    key_field = "" if item is None else f'<input type="hidden" name="item_key" value="{_e(item.key)}">'
    title = "反馈这道题" if item is not None else "给整节课程留言"
    options = "".join(f'<option value="{value}">{label}</option>' for value, label in _CATEGORY_OPTIONS)
    return f"""<details>
<summary>{title}</summary>
<form method="post" action="{base}/p/{preview_id}/feedback">
<input type="hidden" name="revision" value="{revision}">
{key_field}
<div class="hp" aria-hidden="true"><label>网站<input type="text" name="website" tabindex="-1" autocomplete="off"></label></div>
<label for="category-{suffix}">反馈类型</label>
<select id="category-{suffix}" name="category">{options}</select>
<label for="reviewer-{suffix}">称呼（可选）</label>
<input id="reviewer-{suffix}" name="reviewer" maxlength="80" autocomplete="nickname">
<label for="message-{suffix}">具体建议（必填）</label>
<textarea id="message-{suffix}" name="message" maxlength="4000" required placeholder="例如：第二个选项和正确答案也成立，建议改成……"></textarea>
<button type="submit">提交反馈</button>
</form>
</details>"""


def _warnings(document: PreviewDocument) -> str:
    if not document.warnings:
        return ""
    items = "".join(f"<li>{_e(warning)}</li>" for warning in document.warnings[:12])
    return f'<aside class="warning"><strong>草稿有可读性警告，仍按粗预览展示：</strong><ul>{items}</ul></aside>'


def _course_home(meta: dict[str, Any], base_path: str) -> str:
    course_id = str(meta.get("course_id") or "")
    return f"{_base(base_path)}/c/{_e(course_id)}/" if course_id else ""


def render_outline(
    document: PreviewDocument,
    meta: dict[str, Any],
    *,
    base_path: str = "",
    feedback_count: int = 0,
    saved: bool = False,
) -> str:
    preview_id = str(meta["preview_id"])
    revision = int(meta["current_revision"])
    description = f'<p class="muted">{_e(document.description)}</p>' if document.description else ""
    units = []
    for unit in document.units:
        lessons = "".join(
            f'<li><a href="{_base(base_path)}/p/{preview_id}/lesson/{lesson.ref}">{_e(lesson.name)}</a>'
            f'<span class="meta">{len(lesson.items)} 题</span></li>'
            for lesson in unit.lessons
        )
        units.append(f'<section class="card"><h3>{_e(unit.name)}</h3><ul class="lesson-list">{lessons}</ul></section>')
    body = f"""<h1>{_e(document.name)}</h1>
<p class="meta">{len(document.lessons)} 课时 · {document.item_count} 题 · 已收到 {feedback_count} 条反馈</p>
{description}
{_warnings(document)}
<h2>选择课时看题</h2>
{''.join(units)}
<section class="card"><h3>整体意见</h3>{_feedback_form(preview_id=preview_id, revision=revision, base_path=base_path)}</section>"""
    return _page(
        title=document.name,
        body=body,
        preview_id=preview_id,
        revision=revision,
        base_path=base_path,
        home_url=_course_home(meta, base_path),
        badge=f"第 {revision} 版 · 课程预览" if meta.get("course_id") else "",
        saved=saved,
    )


def _render_item(item: PreviewItem, *, preview_id: str, revision: int, base_path: str) -> str:
    options = ""
    if item.options:
        values = "".join(f"<li>{_e(option)}</li>" for option in item.options)
        options = f'<ol class="options">{values}</ol>'
    context = "".join(f'<div class="context">{_e(value)}</div>' for value in item.context)
    answer = f'<details><summary>查看参考答案</summary><div class="answer">{_e(item.answer)}</div></details>' if item.answer else ""
    notes = f'<p class="notes">{_e("；".join(item.notes))}</p>' if item.notes else ""
    return f"""<article class="card anchor" id="{item.anchor}">
<div class="meta">{_e(item.type_label)} · {_e(item.location)}</div>
<div class="prompt">{_e(item.prompt)}</div>
{context}
{options}
{answer}
{notes}
{_feedback_form(preview_id=preview_id, revision=revision, base_path=base_path, item=item)}
</article>"""


def render_lesson(
    document: PreviewDocument,
    lesson: PreviewLesson,
    meta: dict[str, Any],
    *,
    base_path: str = "",
    saved: bool = False,
) -> str:
    preview_id = str(meta["preview_id"])
    revision = int(meta["current_revision"])
    unit = next((candidate for candidate in document.units if candidate.unit_id == lesson.unit_id), None)
    context = "".join(f'<div class="raw-context">{_e(value)}</div>' for value in lesson.context)
    reading = f'<section class="card"><h3>课时材料</h3>{context}</section>' if context else ""
    items = "".join(
        _render_item(item, preview_id=preview_id, revision=revision, base_path=base_path)
        for item in lesson.items
    )
    if not items:
        items = '<p class="warning">这一课没有可展开的题目。</p>'
    body = f"""<p><a href="{_base(base_path)}/p/{preview_id}/">← 返回章节目录</a></p>
<div class="meta">{_e(unit.name if unit else lesson.unit_id)} · {_e(lesson.template)}</div>
<h1>{_e(lesson.name)}</h1>
<p class="meta">共 {len(lesson.items)} 题，可展开答案并逐题留言。</p>
{reading}
{items}"""
    return _page(
        title=lesson.name,
        body=body,
        preview_id=preview_id,
        revision=revision,
        base_path=base_path,
        home_url=_course_home(meta, base_path),
        badge=f"第 {revision} 版 · 课程预览" if meta.get("course_id") else "",
        saved=saved,
    )
