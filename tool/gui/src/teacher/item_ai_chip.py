"""Non-modal chip → AI → PreviewHost → ItemPatch path (E1.5 / R-03 / S-09).

Shared by LinearFlow and template teacher editors so chip clicks never force a
helper dialog. Advanced rewrite still opens ``AiLessonHelperDialog``.
"""
from __future__ import annotations

import logging
logger = logging.getLogger(__name__)


from typing import Any, Callable

from PySide6.QtWidgets import QMessageBox, QWidget

from src.backend.experience.patch import item_patch_from_replace
from src.infrastructure.telemetry import telemetry


def find_main_attr(widget: QWidget, name: str) -> Any:
    """Walk parent chain for an attribute (e.g. preview_host / job_tray)."""
    w: QWidget | None = widget
    while w is not None:
        if hasattr(w, name):
            return getattr(w, name)
        w = w.parentWidget()
    return None


def _notify_timeline(
    owner: QWidget,
    *,
    kind: str,
    summary: str,
    action_id: str = "",
    scope: dict | None = None,
) -> None:
    """Best-effort E1.7 timeline append via MainWindow if present."""
    recorder = find_main_attr(owner, "_record_experience_event")
    if callable(recorder):
        try:
            recorder(kind, summary, action_id=action_id, scope=scope or {})
        except TypeError:
            recorder(kind, summary)


def _ai_generation_kwargs() -> dict[str, Any]:
    try:
        from src.application.runtime_context import current_settings

        s = current_settings()
        return {
            "timeout": float(getattr(s, "ai_timeout", 120.0)),
            "temperature": float(getattr(s, "ai_temperature", 0.7)),
        }
    except Exception:
        return {"timeout": 120.0, "temperature": 0.7}


def run_item_chip(
    owner: QWidget,
    *,
    adapter: Any,
    stage: dict[str, Any],
    item: dict[str, Any],
    instruction: str,
    undo_stack: Any,
    on_applied: Callable[[], None] | None = None,
    lesson_id: str | None = None,
) -> None:
    """Generate an item rewrite and offer it on the main PreviewHost.

    Main clicks for the happy path: chip (this call) + Enter on PreviewHost.
    R-07: when ``lesson_id`` is given, applied instructions are remembered in
    the session ExperienceMemory and prior same-lesson styles are appended to
    the worker instruction (「本课已用风格：…」).
    """
    from src.application.runtime_context import current_ai_config
    from src.backend.ai import request_item_transform
    from src.application.ai_request_worker import AiRequestWorker

    instruction = (instruction or "").strip()
    if not instruction:
        return
    item_id = str(item.get("id") or "")
    if not item_id:
        return

    preview = find_main_attr(owner, "preview_host")
    job_tray = find_main_attr(owner, "job_tray")
    if preview is None:
        # Fallback: old modal path if shell not wired.
        from src.dialogs.ai_lesson_helper_dialog import AiLessonHelperDialog
        from PySide6.QtWidgets import QDialog

        dialog = AiLessonHelperDialog(
            adapter,
            item,
            mode="item",
            parent=owner,
            initial_instruction=instruction,
            ai_config=find_main_attr(owner, "_ai_config"),
            settings_fn=lambda: find_main_attr(owner, "_settings_obj"),
        )
        if dialog.exec() != QDialog.DialogCode.Accepted:
            return
        result = dialog.result()
        if result is None:
            return
        apply_item_result(
            stage, item, result, undo_stack=undo_stack, on_applied=on_applied
        )
        return

    config = current_ai_config()
    if not getattr(config, "is_complete", False):
        QMessageBox.warning(
            owner,
            "配置不完整",
            "请先点击工具栏「设置」，在「AI 配置」中填写 Base URL、API Key 和 Model。",
        )
        return

    # M-08: daily budget / observer gate (statusBar, no modal hang).
    deny = find_main_attr(owner, "_deny_ai_write_if_blocked")
    if callable(deny) and deny(label="芯片改题"):
        return

    # E2.0 ConflictGuard: one AI rewrite per item at a time.
    guard = find_main_attr(owner, "conflict_guard")
    metrics = find_main_attr(owner, "experience_metrics")

    def _inc(method: str, *args: object) -> None:
        fn = getattr(metrics, method, None)
        if callable(fn):
            try:
                fn(*args)
            except Exception:
                logger.debug("teacher/item_ai_chip.py:134 best-effort step failed", exc_info=True)

    guard_key = f"item:{item_id}"
    job_id = f"chip-{item_id}"
    if guard is not None and not guard.try_acquire(guard_key, job_id, label="芯片改题"):
        _inc("inc_guard", "rejected")
        QMessageBox.information(
            owner,
            "忙碌中",
            f"该题正在被 AI 处理：{guard.busy_summary()}",
        )
        return
    sync_ring = getattr(owner, "_sync_focus_ring", None)
    if callable(sync_ring):
        sync_ring()

    # Cancel any previous chip worker owned by this flow.
    previous = getattr(owner, "_chip_worker", None)
    if previous is not None and previous.isRunning():
        previous.cancel()

    if job_tray is not None:
        start = getattr(job_tray, "start_job", None)
        if callable(start):
            start(
                job_id,
                "AI 改题中 …",
                kind="ai",
                node_key=guard_key,
            )
        else:
            job_tray.set_busy("AI 改题中 …")
    _inc("inc_job", "ai", "started")
    preview.set_busy("正在按芯片指令改写题目…")
    telemetry.record_event("experience.chip.start", payload={"item_id": item_id})

    vocab_ids = {w.get("id", "") for w in getattr(adapter, "vocab", []) or []}
    expression_ids = {
        e.get("id", "") for e in getattr(adapter, "expressions", []) or []
    }
    grammar_ids = {
        g.get("id", "") for g in getattr(adapter, "grammar_points", []) or []
    }
    kwargs = _ai_generation_kwargs()
    # Snapshot item for patch; stage is live reference for apply.
    old_item = dict(item)

    # R-07: same-lesson Surgeon style memory (session-only, best-effort).
    memory = find_main_attr(owner, "experience_memory")
    worker_instruction = instruction
    if lesson_id and memory is not None:
        hints_fn = getattr(memory, "lesson_style_hints", None)
        if callable(hints_fn):
            try:
                prior = [
                    h
                    for h in hints_fn(str(lesson_id))
                    if h and h not in instruction
                ]
            except Exception:
                prior = []
            if prior:
                suffix = "本课已用风格：" + "；".join(prior)
                if len(suffix) > 120:
                    suffix = suffix[:119] + "…"
                worker_instruction = f"{instruction}\n{suffix}"

    worker = AiRequestWorker(
        request_item_transform,
        config,
        item,
        worker_instruction,
        vocab_ids,
        expression_ids,
        grammar_ids,
        **kwargs,
    )
    owner._chip_worker = worker  # type: ignore[attr-defined]

    def _done_busy(stage: str = "finished") -> None:
        if job_tray is not None:
            finish = getattr(job_tray, "finish_job", None)
            if callable(finish):
                finish(job_id)
            else:
                job_tray.set_idle()
        _inc("inc_job", "ai", stage)
        if guard is not None:
            guard.release(guard_key, job_id)
            _inc("inc_guard", "released")
        if callable(sync_ring):
            sync_ring()

    def _on_result(result: object) -> None:
        _done_busy()
        if not isinstance(result, dict):
            preview.clear()
            QMessageBox.warning(owner, "AI 改题失败", "模型未返回题目 JSON。")
            return
        try:
            patch = item_patch_from_replace(
                old_item, result, stage_id=str(stage.get("id") or "")
            )
        except Exception as exc:
            preview.clear()
            QMessageBox.warning(owner, "AI 改题失败", str(exc))
            return

        def _apply() -> None:
            _push_item_patch(
                stage, patch, undo_stack=undo_stack, on_applied=on_applied
            )
            # R-07: applied chip instruction becomes this lesson's style memory.
            if lesson_id and memory is not None:
                rec = getattr(memory, "record_lesson_style", None)
                if callable(rec):
                    try:
                        rec(str(lesson_id), instruction)
                    except Exception:
                        logger.debug("teacher/item_ai_chip.py:253 best-effort step failed", exc_info=True)
            telemetry.record_event(
                "experience.chip.applied", payload={"item_id": item_id}
            )
            _notify_timeline(
                owner,
                kind="chip.apply",
                summary=f"芯片改题 {item_id}",
                action_id="item.rewrite",
                scope={"item_id": item_id, "stage_id": str(stage.get("id") or "")},
            )

        def _discard() -> None:
            telemetry.record_event(
                "experience.chip.discarded", payload={"item_id": item_id}
            )
            _notify_timeline(
                owner,
                kind="chip.discard",
                summary=f"丢弃改题 {item_id}",
                scope={"item_id": item_id},
            )

        from src.backend.experience.patch import field_diff_lines

        preview.offer(
            title="AI 改题预览",
            summary=patch.summary() + "　·　Enter 应用 / Esc 丢弃",
            apply_fn=_apply,
            discard_fn=_discard,
            payload=patch,
            details=field_diff_lines([patch]),
        )

    def _on_error(msg: str) -> None:
        _done_busy("failed")
        preview.clear()
        QMessageBox.warning(owner, "AI 改题失败", msg or "请求失败")
        telemetry.record_event(
            "experience.chip.error", payload={"item_id": item_id, "error": msg}
        )

    worker.result_ready.connect(_on_result)
    worker.error_occurred.connect(_on_error)
    worker.start()


def _push_item_patch(
    stage: dict[str, Any],
    patch: Any,
    *,
    undo_stack: Any,
    on_applied: Callable[[], None] | None,
) -> None:
    if undo_stack is not None:
        from src.application.commands import ApplyItemPatchCommand

        cmd = ApplyItemPatchCommand(stage, patch)
        if on_applied is not None:
            cmd.signals.changed.connect(on_applied)
        undo_stack.push(cmd)
    else:
        from src.backend.experience.patch import apply_item_patch

        apply_item_patch(stage, patch)
        if on_applied is not None:
            on_applied()


def apply_item_result(
    stage: dict[str, Any],
    old_item: dict[str, Any],
    result: dict[str, Any],
    *,
    undo_stack: Any,
    on_applied: Callable[[], None] | None,
) -> None:
    """Apply a free-form helper-dialog result via ItemPatch (shared with chips)."""
    patch = item_patch_from_replace(
        old_item, result, stage_id=str(stage.get("id") or "")
    )
    _push_item_patch(stage, patch, undo_stack=undo_stack, on_applied=on_applied)


# Back-compat alias used by early call sites.
_apply_item_result = apply_item_result
