"""Handler map for Experience skills (M7).

Entries resolve *live* attributes on handler modules so tests can
``unittest.mock.patch("…handlers.fill.handle_fill_empty")`` and still
intercept dispatch (bound function objects would freeze the pre-patch ref).
"""
from __future__ import annotations

from typing import Any, Callable

from src.application.experience_handlers import (
    edit,
    fill,
    memory_nav,
    multimodal,
    outline,
    quality,
    regenerate,
    resources,
    textbook,
)

Handler = Callable[..., None]
HANDLERS: dict[str, Handler] = {}


def _status(msg: str) -> Handler:
    def _h(host: Any, scope: dict) -> None:
        host.statusBar().showMessage(msg, 5000)
    return _h


def _publish(host: Any, scope: dict) -> None:
    pub = getattr(host, "_on_publish", None)
    if callable(pub):
        pub()
    else:
        host.statusBar().showMessage("发布入口不可用", 4000)


def _open_hygiene(host: Any, scope: dict) -> None:
    filt = str(scope.get("filter") or "待补")
    host._on_resources(initial_filter=filt)


def _goal(fn_name: str) -> Handler:
    def _h(host: Any, scope: dict) -> None:
        from src.application import goal_controller as gc
        getattr(gc, fn_name)(host, scope)
    return _h


def _mod(module: Any, name: str, *, pass_scope: bool = True, **fixed) -> Handler:
    """Lazy getattr so monkeypatches on the module hit dispatch."""

    def _h(host: Any, scope: dict) -> None:
        fn = getattr(module, name)
        if fixed:
            if pass_scope:
                fn(host, scope, **fixed)
            else:
                fn(host, **fixed)
            return
        if pass_scope:
            fn(host, scope)
        else:
            fn(host)

    return _h


def _screenshot(host: Any, scope: dict) -> None:
    from src.application.screenshot_controller import explain_current
    explain_current(host)


def _git(action_id: str) -> Handler:
    def _h(host: Any, scope: dict) -> None:
        multimodal.handle_git_skill(host, action_id)
    return _h


def register_all() -> dict[str, Handler]:
    HANDLERS.clear()
    HANDLERS.update({
        "validate.open_and_fix": _mod(fill, "handle_validate_and_fix", pass_scope=False),
        "lesson.fill_empty": _mod(fill, "handle_fill_empty"),
        "resource.fill_stubs": _mod(fill, "handle_fill_stubs", pass_scope=False),
        "listening.fill_gaps": _mod(fill, "handle_fill_listening_gaps"),
        "listening.transcript_gap": _mod(
            fill, "handle_fill_listening_gaps",
            action_id="listening.transcript_gap",
        ),
        "quality.campaign_worst_n": _mod(quality, "handle_quality_campaign"),
        "soft.preview_hygiene": _mod(quality, "handle_soft_preview_hygiene"),
        "resource.open_hygiene": _open_hygiene,
        "attachment.open_in_workshop": lambda h, s: h._on_workshop(),
        "lesson.regenerate": _mod(regenerate, "handle_regenerate"),
        "unit.regenerate": _mod(regenerate, "handle_regenerate"),
        # v4.61 K-05: wrap AiEditMixin._on_ai_edit (dialog + generate_edit).
        "section.edit": _mod(edit, "handle_node_edit"),
        "unit.edit": _mod(edit, "handle_node_edit"),
        "lesson.edit": _mod(edit, "handle_node_edit"),
        "lesson.balance": _mod(regenerate, "handle_balance_lesson"),
        "unit.spiral_vocab": _mod(regenerate, "handle_spiral_vocab"),
        "reading.passages_gen": _mod(regenerate, "handle_reading_gen"),
        "lesson.batch_set_template": _mod(resources, "handle_batch_set_template"),
        "lesson.batch_regenerate": _mod(regenerate, "handle_batch_regenerate"),
        "unit.batch_regenerate": _mod(
            regenerate, "handle_batch_regenerate_units"
        ),
        "goal.plan": _goal("experience_goal_plan"),
        "goal.expand": _goal("experience_goal_expand"),
        "goal.run": _goal("experience_goal_run"),
        "publish.brief": _publish,
        "resource.dedupe_suggest": _mod(resources, "handle_dedupe_suggest"),
        "resource.align_pos_tags": _mod(resources, "handle_align_pos"),
        "resource.batch_polish": _mod(resources, "handle_batch_polish"),
        "resource.fill_stubs_batch": _mod(resources, "handle_fill_stubs_batch"),
        "resource.resolve_term_conflicts": _mod(
            resources, "handle_resolve_term_conflicts"
        ),
        "course.compare_sections": _mod(resources, "handle_compare_sections"),
        # v4.63 M-02: 大纲 bullet -> 课壳（零 LLM 解析 + 预览确认 + Undo）。
        "course.outline_shells": _mod(outline, "handle_outline_shells"),
        "git.commit_message": _git("git.commit_message"),
        "git.explain_diff": _git("git.explain_diff"),
        "app.screenshot_explain": _screenshot,
        "textbook.ocr_suggest": _mod(multimodal, "handle_ocr"),
        "textbook.open_workshop": _mod(textbook, "handle_open_workshop"),
        "textbook.import_draft": _mod(textbook, "handle_import_draft"),
        "textbook.grounded_fill": _mod(textbook, "handle_grounded_fill"),
        "item.rewrite": _status("请在教师模式选中题卡后点芯片改题（PreviewHost 确认）"),
        "item.similar": _mod(memory_nav, "handle_item_similar"),
        "item.distractor_boost": _status(
            "请在教师模式选中题卡后点「换干扰」芯片（PreviewHost 确认）"
        ),
        "item.to_listening": _mod(memory_nav, "handle_to_listening"),
        "memory.clear_author": _mod(memory_nav, "handle_clear_author"),
    })
    return HANDLERS


register_all()
