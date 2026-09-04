"""Memory / item migration / diagnose skill implementations (M7)."""
from __future__ import annotations

from typing import Any

from src.application.experience_handlers.util import (
    _find_stage_and_item,
    _validate_course_problems,
)
from src.application.ui_guard import safe_information, safe_question, safe_warning
import logging
logger = logging.getLogger(__name__)

def _experience_why_current(host) -> None:
    """O-06 / ⌘K /why: explain first error for current course (local).

    v4.17 K-02: also considers ``ctx.quality_issues`` (content_quality
    dimensions) when no structural validate problem is available, so
    ``/why`` can explain a quality dimension issue on a structurally
    clean course.
    """
    from src.backend.experience.why import why_explain

    problems = None
    ctx = host.experience.context
    if ctx is not None and ctx.validate_problems:
        problems = list(ctx.validate_problems)
    if not problems and host.course_dir:
        try:
            problems = _validate_course_problems(host.course_dir)
        except Exception as exc:
            safe_information(host, "为何", f"无法取得校验结果：{exc}")
            return
    problems = list(problems or [])
    errors = [p for p in problems if p.get("level") == "error"]
    warnings = [p for p in problems if p.get("level") == "warning"]
    target = errors or warnings
    # K-02: fall back to content_quality issues when structurally clean.
    if not target and ctx is not None and getattr(ctx, "quality_issues", None):
        q_errors = [p for p in ctx.quality_issues if p.get("level") == "error"]
        q_warns = [p for p in ctx.quality_issues if p.get("level") == "warning"]
        target = q_errors or q_warns
    if not target:
        safe_information(host, "为何", "当前没有可解释的校验问题。")
        return
    result = why_explain(target[0])
    extra = ""
    if result.action_id:
        extra = f"\n\n建议动作：{result.action_id}"
    safe_information(host, "为何 · " + result.summary, result.detail + extra
    )
    host._record_experience_event(
        "why",
        result.summary,
        action_id="app.why",
    )

handle_why_current = _experience_why_current

def _experience_clear_author(host, scope: dict | None = None) -> None:
    """M-07: clear AuthorMemory only — privacy control, zero course writes.

    Confirm in-handler (registry needs_confirm=False so observer/budget
    do not block). Headless/offscreen auto-accepts unless host sets
    ``_confirm_clear_memory = False``. Timeline scope is closed-set only.
    """
    mem = getattr(host, "experience_memory", None)
    if mem is None:
        host.statusBar().showMessage("记忆模块不可用", 4000)
        return

    had = False
    try:
        snap = mem.author.snapshot()
        had = snap is not None
    except Exception:
        had = False

    if not had:
        host.statusBar().showMessage("当前无作者画像可清", 4000)
        return

    # Privacy confirm — not an AI write gate.
    confirm = getattr(host, "_confirm_clear_memory", None)
    if confirm is None:
        try:
            from PySide6.QtWidgets import QApplication

            app = QApplication.instance()
            headless = app is None or (
                hasattr(app, "platformName") and app.platformName() == "offscreen"
            )
        except Exception:
            headless = True
        if headless:
            ok = True
        else:
            try:
                from PySide6.QtWidgets import QMessageBox

                reply = QMessageBox.question(
                    host if hasattr(host, "windowTitle") else None,
                    "清除作者画像",
                    "将清除跨课风格提示与语言偏好（内存；若开启落盘则一并删除本地画像文件）。\n"
                    "不删课程文件。此操作不可撤销。继续？",
                )
            except Exception:
                ok = False
    else:
        ok = bool(confirm) if not callable(confirm) else bool(confirm())

    if not ok:
        metrics = getattr(host, "experience_metrics", None)
        if metrics is not None:
            try:
                metrics.inc_suggestion("memory.clear_author", "rejected")
            except Exception:
                logger.debug("application/experience_handlers/memory_nav.py:_experience_clear_author best-effort step failed", exc_info=True)
        host.statusBar().showMessage("已取消清除画像", 3000)
        return

    try:
        mem.clear_author()
    except Exception as exc:
        host.statusBar().showMessage(f"清除画像失败：{exc}", 5000)
        return

    # Refresh Context / Dock.
    sync = getattr(host, "_sync_experience_memory", None)
    if callable(sync):
        try:
            sync()
        except Exception:
            logger.debug("application/experience_handlers/memory_nav.py:_experience_clear_author best-effort step failed", exc_info=True)
    refresh = getattr(host, "_refresh_experience", None)
    if callable(refresh):
        try:
            refresh(immediate=True)
        except Exception:
            logger.debug("application/experience_handlers/memory_nav.py:_experience_clear_author best-effort step failed", exc_info=True)

    # Timeline closed-set — never style_hints text.
    record = getattr(host, "_record_experience_event", None)
    if callable(record):
        try:
            record(
                "memory.clear_author",
                "清除作者画像",
                action_id="memory.clear_author",
                scope={"cleared": True, "layer": "author"},
            )
        except Exception:
            logger.debug("application/experience_handlers/memory_nav.py:_experience_clear_author best-effort step failed", exc_info=True)
    metrics = getattr(host, "experience_metrics", None)
    if metrics is not None:
        try:
            metrics.inc_suggestion("memory.clear_author", "applied")
        except Exception:
            logger.debug("application/experience_handlers/memory_nav.py:_experience_clear_author best-effort step failed", exc_info=True)
    host.statusBar().showMessage("已清除作者画像", 5000)

handle_clear_author = _experience_clear_author

def _start_experience_diagnose(host) -> None:
    """G1: background local validate right after opening a course (no LLM).

    The result feeds the validate cache so the P0 suggestion appears
    without waiting for a manual save/validate. Stale results (course
    switched mid-flight) are dropped; failures degrade silently.
    """
    if not host.course_dir:
        return
    from src.dialogs.ai.worker import AiRequestWorker

    previous = getattr(host, "_diagnose_worker", None)
    if previous is not None:
        previous.cancel()
    course_dir = host.course_dir
    host.job_tray.start_job(
        "validate-open",
        "本地诊断中 …",
        kind="validate",
    )
    host.experience_metrics.inc_job("validate", "started")
    host._refresh_experience(immediate=False, focus_only=True)
    worker = AiRequestWorker(lambda: _validate_course_problems(course_dir))
    worker.result_ready.connect(
        lambda problems, d=course_dir: host._on_diagnose_problems(d, problems)
    )
    worker.error_occurred.connect(
        lambda msg, d=course_dir: host._on_diagnose_failed(d, msg)
    )
    worker.start()
    host._diagnose_worker = worker

handle_start_experience_diagnose = _start_experience_diagnose

def _on_diagnose_problems(host, course_dir, problems: object) -> None:
    host.job_tray.finish_job("validate-open")
    host.experience_metrics.inc_job("validate", "finished")
    if host.course_dir != course_dir or not isinstance(problems, list):
        return  # stale: the user opened another course mid-flight
    host.experience.set_validate_problems(problems)
    host._refresh_experience(immediate=True)

handle_on_diagnose_problems = _on_diagnose_problems

def _on_diagnose_failed(host, course_dir, message: str) -> None:
    host.job_tray.finish_job("validate-open")
    host.experience_metrics.inc_job("validate", "failed")
    if host.course_dir != course_dir:
        return
    # 打开路径不挟持：诊断失败只留状态行提示，不弹窗。
    host.statusBar().showMessage(f"本地诊断失败：{message}", 5000)
    host._refresh_experience(immediate=False, focus_only=True)

handle_on_diagnose_failed = _on_diagnose_failed

def _experience_to_listening(host, scope: dict) -> None:
    """v4.39 K-13: deterministic migrate selected non-listening item → listening.

    纯 local（零 LLM）：``switch_runtime_type(item, "listenAndPick")`` 保 id、
    语义字段重映射（prompt/sentence→audioAsset 语义组等）→ ``item_patch_from_replace``
    → 人确认（QMessageBox.question）→ ``ApplyItemPatchCommand`` 入 Undo。
    不经 AiRequestWorker/ConflictGuard（确定性瞬时）；红线靠预览+确认+Undo。
    """
    if not host.course_dir:
        safe_warning(host, "迁为听力题", "请先打开课程目录。")
        return
    item_id = str(scope.get("item_id") or "")
    lesson_id = str(scope.get("lesson_id") or "")
    if not item_id:
        ref = host._current_node_ref
        if ref and ref[0] == "item":
            item_id = str(ref[1])
    if not item_id:
        host.statusBar().showMessage("请先在教师模式选中要迁的题", 5000)
        return

    # Resolve lesson (scope lesson_id, else via current lesson selection).
    lesson = None
    if lesson_id:
        try:
            section, _unit, lesson = host.adapter.find_lesson(lesson_id)
        except Exception:
            lesson = None
    if lesson is None:
        ref = host._current_node_ref
        if ref and ref[0] == "lesson":
            try:
                section, _unit, lesson = host.adapter.find_lesson(str(ref[1]))
            except Exception:
                lesson = None
    if lesson is None:
        host.statusBar().showMessage("找不到所属课", 5000)
        return

    stage, item = _find_stage_and_item(lesson, item_id)
    if stage is None or item is None:
        host.statusBar().showMessage(f"找不到题目 id={item_id}", 5000)
        return

    rt = str(item.get("runtimeType") or "")
    if rt in ("listenAndPick", "typeTheWord") or "listen" in rt.lower():
        host.statusBar().showMessage("该题已是听力题", 4000)
        return

    from src.backend.lesson_content import switch_runtime_type
    from src.backend.experience.patch import item_patch_from_replace

    new_item = switch_runtime_type(item, "listenAndPick")
    stage_id = str(stage.get("id") or "")
    patch = item_patch_from_replace(item, new_item, stage_id=stage_id)

    if not safe_question(host,
        "迁为听力题",
        f"将题目 {item_id}（{rt}）迁为 listenAndPick 听力题？\n"
        "id 与语义内容保留；结构按听力题规范化。确认后入 Undo 栈。",
        default_yes=False,
        ):
        host.experience_metrics.inc_suggestion("item.to_listening", "rejected")
        return

    from src.application.commands import ApplyItemPatchCommand

    cmd = ApplyItemPatchCommand(stage, patch)
    cmd.signals.changed.connect(host._on_ai_edit_applied)
    host.undo_stack.push(cmd)
    host.experience_metrics.inc_suggestion("item.to_listening", "applied")
    host._record_experience_event(
        "item.to_listening",
        "迁为听力题已应用",
        action_id="item.to_listening",
        scope={"item_id": item_id, "lesson_id": str(lesson.get("id") or "")},
    )
    host._refresh_validate_after_ai("迁为听力题已应用，记得保存")

handle_to_listening = _experience_to_listening


# v4.62 P2: parallel similar-item rewrite (same chip pipeline; keep id).
SIMILAR_ITEM_INSTRUCTION = (
    "在保留 id、runtimeType 与正确答案语义的前提下，改写成考查点相同的平行相似题："
    "换情境或换说法，勿改题型，勿改 id，勿改正确选项含义。"
)


def _locate_item_in_course(
    adapter: Any, item_id: str, *, lesson_id: str = ""
) -> tuple[dict | None, dict | None, str]:
    """Return (stage, item, lesson_id). Never raises."""
    iid = str(item_id or "").strip()
    if not iid or adapter is None:
        return None, None, ""
    try:
        if lesson_id:
            try:
                _s, _u, lesson = adapter.find_lesson(lesson_id)
                st, it = _find_stage_and_item(lesson, iid)
                if st is not None and it is not None:
                    return st, it, str(lesson.get("id") or lesson_id)
            except Exception:
                logger.debug("application/experience_handlers/memory_nav.py:_locate_item_in_course best-effort step failed", exc_info=True)
        for sec in list(getattr(adapter, "sections", None) or []):
            if not isinstance(sec, dict):
                continue
            for unit in sec.get("units") or []:
                if not isinstance(unit, dict):
                    continue
                for les in unit.get("lessons") or []:
                    if not isinstance(les, dict):
                        continue
                    st, it = _find_stage_and_item(les, iid)
                    if st is not None and it is not None:
                        return st, it, str(les.get("id") or "")
    except Exception:
        return None, None, ""
    return None, None, ""


def _experience_item_similar(host, scope: dict | None = None) -> None:
    """K-10 后半 / P2: 相似题 — 固定指令走 run_item_chip（PreviewHost + Undo）。"""
    scope = scope if isinstance(scope, dict) else {}
    if not getattr(host, "course_dir", None):
        try:
            host.statusBar().showMessage("请先打开课程目录", 5000)
        except Exception:
            logger.debug("application/experience_handlers/memory_nav.py:_experience_item_similar best-effort step failed", exc_info=True)
        return

    item_id = str(scope.get("item_id") or scope.get("id") or "").strip()
    lesson_id = str(scope.get("lesson_id") or "").strip()
    if not item_id:
        ref = getattr(host, "_current_node_ref", None)
        if ref and ref[0] == "item":
            item_id = str(ref[1] or "")
    if not item_id:
        try:
            host.statusBar().showMessage("请先在教师模式选中题目", 5000)
        except Exception:
            logger.debug("application/experience_handlers/memory_nav.py:_experience_item_similar best-effort step failed", exc_info=True)
        return
    if not lesson_id:
        ref = getattr(host, "_current_node_ref", None)
        if ref and ref[0] == "lesson":
            lesson_id = str(ref[1] or "")

    stage, item, resolved_lid = _locate_item_in_course(
        getattr(host, "adapter", None), item_id, lesson_id=lesson_id
    )
    lesson_id = resolved_lid or lesson_id
    if stage is None or item is None:
        try:
            host.statusBar().showMessage(f"找不到题目 id={item_id}", 5000)
        except Exception:
            logger.debug("application/experience_handlers/memory_nav.py:_experience_item_similar best-effort step failed", exc_info=True)
        return

    from src.teacher.item_ai_chip import run_item_chip

    try:
        run_item_chip(
            host,
            adapter=host.adapter,
            stage=stage,
            item=item,
            instruction=SIMILAR_ITEM_INSTRUCTION,
            undo_stack=host.undo_stack,
            on_applied=getattr(host, "_on_ai_edit_applied", None),
            lesson_id=lesson_id or None,
        )
    except Exception as exc:
        try:
            host.statusBar().showMessage(f"相似题失败：{exc}", 5000)
        except Exception:
            logger.debug("application/experience_handlers/memory_nav.py:_experience_item_similar best-effort step failed", exc_info=True)
        return

    record = getattr(host, "_record_experience_event", None)
    if callable(record):
        try:
            record(
                "item.similar",
                "相似题改写已启动",
                action_id="item.similar",
                scope={"item_id": item_id, "lesson_id": lesson_id or ""},
            )
        except Exception:
            logger.debug("application/experience_handlers/memory_nav.py:_experience_item_similar best-effort step failed", exc_info=True)


handle_item_similar = _experience_item_similar

