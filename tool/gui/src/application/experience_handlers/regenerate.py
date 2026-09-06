"""Regenerate / balance / spiral / reading skill implementations (M7)."""
from __future__ import annotations

from dataclasses import dataclass
from functools import partial
from typing import Any, Callable

from PySide6.QtWidgets import QDialog, QMessageBox

from src.application.commands import MergeAiSectionCommand
from src.application.ui_guard import safe_information, safe_question, safe_warning
from src.infrastructure.telemetry import telemetry
import logging
from src.application.experience_host import ExperienceHost
logger = logging.getLogger(__name__)

def _experience_regenerate(host, scope: dict) -> None:
    """v4.15 K-05: regenerate the selected lesson/unit in place (保 id splice).

    包装 aiEnhance ``regenerate_lesson_in_section`` /
    ``regenerate_unit_in_section``。目标由 scope（kind/id）或当前
    selection 解析；⌘K ``/regenerate`` 与 Dock 共用此入口。LLM 跑在
    section deepcopy 上，仅经 SectionDiffView 人确认 + MergeAiSectionCommand
    入 Undo 才写树（红线：禁止静默写）。结构与 ``_experience_fill_stubs`` 同构。
    """
    import copy

    if not host.course_dir:
        safe_warning(host, "未加载课程目录", "请先打开课程目录。")
        return
    kind = str(scope.get("kind") or "")
    node_id = str(scope.get("id") or "")
    if not kind or not node_id:
        ref = host._current_node_ref
        if ref:
            kind = kind or str(ref[0])
            node_id = node_id or str(ref[1])
    if kind not in ("lesson", "unit") or not node_id:
        host.statusBar().showMessage(
            "请先在课程树选中要重生成的课或单元", 5000
        )
        return
    if host.job_tray.is_busy_ai():
        safe_information(host, "重生成", "当前有 AI 任务进行中，请稍候。")
        return
    try:
        if kind == "lesson":
            section, _unit, _lesson = host.adapter.find_lesson(node_id)
        else:
            section, _unit = host.adapter.find_unit(node_id)
    except KeyError as exc:
        safe_warning(host, "重生成", str(exc))
        return
    label = "重生成课" if kind == "lesson" else "重生成单元"
    host._run_regen_flow(
        action_id=f"{kind}.regenerate",
        kind=kind,
        node_id=node_id,
        section=section,
        job_id=f"regen-{kind}-{node_id}",
        job_label=label,
        instruction=None,
        engine_kind=kind,
    )

handle_regenerate = _experience_regenerate

def _experience_balance_lesson(host, scope: dict) -> None:
    """v4.16 K-07: local balance evaluate → confirm → regenerate (配比指令).

    local 判定先行（零 LLM）：``evaluate_lesson_balance`` 健康则直接提示
    返回。失衡时展示诊断（counts/missing/dominant）确认后复用 K-05 引擎
    ``regenerate_lesson_in_section``（带配比 instruction），同样经
    SectionDiffView 人确认 + MergeAiSectionCommand 入 Undo 才写树。
    """
    if not host.course_dir:
        safe_warning(host, "未加载课程目录", "请先打开课程目录。")
        return
    lesson_id = str(scope.get("lesson_id") or "")
    if not lesson_id:
        ref = host._current_node_ref
        if ref and ref[0] == "lesson":
            lesson_id = str(ref[1])
    if not lesson_id:
        host.statusBar().showMessage("请先在课程树选中要调整配比的课", 5000)
        return
    try:
        section, _unit, lesson = host.adapter.find_lesson(lesson_id)
    except KeyError as exc:
        safe_warning(host, "调整题型配比", str(exc))
        return

    from src.backend.content_quality import evaluate_lesson_balance

    report = evaluate_lesson_balance(lesson)
    if report["balanced"]:
        host.statusBar().showMessage("题型配比健康，无需调整", 4000)
        return
    if host.job_tray.is_busy_ai():
        safe_information(host, "调整题型配比", "当前有 AI 任务进行中，请稍候。"
        )
        return

    counts_text = (
        ", ".join(
            f"{k}×{v}" for k, v in sorted(report["counts"].items())
        )
        or "（无题目）"
    )
    issues_text = "\n".join(f"· {i}" for i in report["issues"])
    if not safe_question(host,
        "调整题型配比",
        f"当前题型分布：{counts_text}\n\n{issues_text}\n\n"
        "用 AI 重生成该课以改善配比？（生成后仍需预览确认）",
        default_yes=False,
        ):
        host.experience_metrics.inc_suggestion("lesson.balance", "rejected")
        return

    parts = ["请改善该课的题型配比：保持全部 id、词汇与主题不变。"]
    parts.append(f"当前题型分布：{counts_text}")
    if report["missing_hint_types"]:
        parts.append(
            "建议补充题型：" + ", ".join(report["missing_hint_types"])
        )
    if report["dominant"]:
        parts.append(f"请减少占比过高的 {report['dominant']['type']} 题型。")
    host._run_regen_flow(
        action_id="lesson.balance",
        kind="lesson",
        node_id=lesson_id,
        section=section,
        job_id=f"balance-{lesson_id}",
        job_label="调整题型配比",
        instruction="\n".join(parts),
        engine_kind="lesson",
    )

handle_balance_lesson = _experience_balance_lesson

def _experience_spiral_vocab(host, scope: dict) -> None:
    """v4.37 K-08: local spiral evaluate → confirm → regenerate (追加复现).

    local 判定先行（零 LLM）：``evaluate_unit_spiral`` 在选中所在
    section 复算，若健康（无 unsurfaced）直接 statusBar 返回。有缺口时
    展示未复现词确认，复用 K-05 引擎 ``regenerate_lesson_in_section``
    （带螺旋指令，保 id/词汇/主题，仅追加复现题），同样经
    ``SectionDiffView`` 人确认 + ``MergeAiSectionCommand`` 入 Undo。
    """
    if not host.course_dir:
        safe_warning(host, "补充词汇螺旋复现", "请先打开课程目录。")
        return
    sid = str(scope.get("section_id") or "")
    if not sid:
        ref = host._current_node_ref
        if ref:
            # resolve the section hosting the current selection.
            try:
                kind, nid = ref[0], str(ref[1])
                if kind == "section":
                    sid = nid
                elif kind == "lesson":
                    section, _u, _l = host.adapter.find_lesson(nid)
                    sid = str(section.get("id") or "")
                elif kind == "unit":
                    section, _unit = host.adapter.find_unit(nid)
                    sid = str(section.get("id") or "")
            except Exception:
                sid = ""
    if not sid:
        host.statusBar().showMessage("请先在课程树选中要补螺旋的课/单元/节", 5000)
        return
    try:
        section = host.adapter.find_section(sid)
    except KeyError as exc:
        safe_warning(host, "补充词汇螺旋复现", str(exc))
        return

    from src.backend.content_quality import evaluate_unit_spiral

    spiral = evaluate_unit_spiral(section)
    unsurfaced = list(spiral.get("unsurfaced") or [])
    if not unsurfaced:
        host.statusBar().showMessage("词汇螺旋健康，无未复现词", 4000)
        return
    if host.job_tray.is_busy_ai():
        safe_information(host, "补充词汇螺旋复现", "当前有 AI 任务进行中，请稍候。"
        )
        return

    preview = unsurfaced[:12]
    words_text = "、".join(
        f"{w.get('term') or w.get('word_id')}" for w in preview
    ) or "（无）"
    if not safe_question(host,
        "补充词汇螺旋复现",
        f"以下 {len(unsurfaced)} 个词引入后未在后续课复现：\n{words_text}\n\n"
        "用 AI 在后续课追加复现题？（保持全部 id/词汇/主题不变；生成后仍需预览确认）",
        default_yes=False,
        ):
        host.experience_metrics.inc_suggestion("unit.spiral_vocab", "rejected")
        return

    # 目标课：首个未复现词的引入课（在其之后追加复现最自然）；若无则取该
    # section 的最后一课。两者都落在 section 内，engine_kind=lesson 即可。
    intro_lid = str(preview[0].get("intro_lesson_id") or "") if preview else ""
    if intro_lid:
        try:
            _s, _u, _l = host.adapter.find_lesson(intro_lid)
            target_lid = intro_lid
        except Exception:
            target_lid = ""
    else:
        target_lid = ""
    if not target_lid:
        last_lid = ""
        for unit in section.get("units") or []:
            if not isinstance(unit, dict):
                continue
            for lesson in unit.get("lessons") or []:
                if isinstance(lesson, dict) and lesson.get("id"):
                    last_lid = str(lesson.get("id"))
        target_lid = last_lid

    parts = ["请补充词汇螺旋复现题：保持全部 id、词汇与主题不变。"]
    parts.append(
        "在引入课之后的课里追加复现题（不要改动已有题）；未复现词："
        + ", ".join(f"{w.get('term')}({w.get('word_id')})" for w in preview)
    )
    parts.append(f"涉及 section：{sid}")
    host._run_regen_flow(
        action_id="unit.spiral_vocab",
        kind="lesson",
        node_id=target_lid or sid,
        section=section,
        job_id=f"spiral-{sid}",
        job_label="补充词汇螺旋复现",
        instruction="\n".join(parts),
        engine_kind="lesson",
    )

handle_spiral_vocab = _experience_spiral_vocab

def _experience_reading_gen(host, scope: dict) -> None:
    """v4.39 K-18: local reading-passage gap → confirm → regenerate (阅读指令).

    local 判定先行（零 LLM）：``evaluate_reading_passage`` 健康则 statusBar 返回；
    空/占位时确认后复用 K-05 引擎 ``regenerate_lesson_in_section``（带 reading
    指令，保 id/词汇/主题，生成 readingPassage 段落），同样经
    ``SectionDiffView`` 人确认 + ``MergeAiSectionCommand`` 入 Undo。
    """
    if not host.course_dir:
        safe_warning(host, "生成阅读段落", "请先打开课程目录。")
        return
    lesson_id = str(scope.get("lesson_id") or "")
    if not lesson_id:
        ref = host._current_node_ref
        if ref and ref[0] == "lesson":
            lesson_id = str(ref[1])
    if not lesson_id:
        host.statusBar().showMessage("请先在课程树选中要生成段落的阅读课", 5000)
        return
    try:
        section, _unit, lesson = host.adapter.find_lesson(lesson_id)
    except KeyError as exc:
        safe_warning(host, "生成阅读段落", str(exc))
        return

    from src.backend.content_quality import evaluate_reading_passage

    rp = evaluate_reading_passage(lesson)
    if not rp.get("empty"):
        host.statusBar().showMessage("阅读段落已就绪，无需生成", 4000)
        return
    if host.job_tray.is_busy_ai():
        safe_information(host, "生成阅读段落", "当前有 AI 任务进行中，请稍候。"
        )
        return

    reason = str(rp.get("reason") or "空/占位")
    if not safe_question(host,
        "生成阅读段落",
        f"阅读课 {lesson_id} 的 readingPassage 为空/占位（{reason}）。\n\n"
        "用 AI 为该课生成阅读段落？（保持全部 id/词汇/主题不变；生成后仍需预览确认）",
        default_yes=False,
        ):
        host.experience_metrics.inc_suggestion("reading.passages_gen", "rejected")
        return

    parts = ["请为该阅读课生成 readingPassage 段落：保持全部 id、词汇与主题不变。"]
    parts.append(f"缺口原因：{reason}")
    parts.append("请产出 readingPassage（含 title 与多段 paragraphs）并保留原有题型。")
    host._run_regen_flow(
        action_id="reading.passages_gen",
        kind="lesson",
        node_id=lesson_id,
        section=section,
        job_id=f"reading-{lesson_id}",
        job_label="生成阅读段落",
        instruction="\n".join(parts),
        engine_kind="lesson",
    )

handle_reading_gen = _experience_reading_gen

@dataclass
class _RegenSession:
    """Shared state of one single-node regeneration flow (P2 split)."""

    host: ExperienceHost
    action_id: str
    kind: str
    node_id: str
    section: dict
    sid: str
    job_id: str
    job_label: str
    guard_key: str
    tx_snap: Any


def _run_regen_flow(
    host,
    *,
    action_id: str,
    kind: str,
    node_id: str,
    section: dict,
    job_id: str,
    job_label: str,
    instruction: str | None,
    engine_kind: str,
) -> None:
    """Shared regenerate tail: Guard → job → worker → Diff → undo (v4.16).

    ``engine_kind`` selects ``regenerate_lesson_in_section`` /
    ``regenerate_unit_in_section``; ``instruction`` is forwarded to the
    engine (None = engine default instruction).
    """
    import copy

    deny = getattr(host, "_deny_ai_write_if_blocked", None)
    if callable(deny) and deny(label=job_label):
        return

    sid = str(section.get("id") or "section")
    guard_key = f"{kind}:{node_id}"

    from src.backend.experience.transaction import (
        create_transaction_snapshot,
        verify_transaction_integrity,
    )

    tx_snap = create_transaction_snapshot(host.adapter, action_id, [guard_key])
    node_fp = tx_snap.node_fingerprints.get(guard_key, "")

    if not host.conflict_guard.try_acquire(
        guard_key, job_id, label=job_label, fingerprint=node_fp
    ):
        host.experience_metrics.inc_guard("rejected")
        safe_information(host, job_label, f"节点忙碌：{host.conflict_guard.busy_summary()}"
        )
        return
    host._sync_focus_ring()

    from src.backend.ai_generator import (
        AiCourseSpec,
        regenerate_lesson_in_section,
        regenerate_unit_in_section,
    )
    from src.application.ai_request_worker import AiRequestWorker

    config = host._ai_config
    spec = AiCourseSpec()
    draft = copy.deepcopy(section)
    host.job_tray.start_job(
        job_id,
        f"{job_label}：正在生成 …",
        kind="ai",
        node_key=guard_key,
    )
    host.experience_metrics.inc_job("ai", "started")
    host._refresh_experience(immediate=False, focus_only=True)

    def _target() -> dict:
        if engine_kind == "lesson":
            return regenerate_lesson_in_section(
                config, spec, draft, node_id, instruction=instruction
            )
        return regenerate_unit_in_section(
            config, spec, draft, node_id, instruction=instruction
        )

    worker = AiRequestWorker(_target)

    session = _RegenSession(
        host=host,
        action_id=action_id,
        kind=kind,
        node_id=node_id,
        section=section,
        sid=sid,
        job_id=job_id,
        job_label=job_label,
        guard_key=guard_key,
        tx_snap=tx_snap,
    )

    worker.result_ready.connect(partial(_regen_on_ok, session))
    worker.error_occurred.connect(partial(_regen_on_err, session))
    worker.start()
    host._experience_worker = worker

handle_run_regen_flow = _run_regen_flow


def _regen_on_ok(s: "_RegenSession", result: object) -> None:
    from src.backend.experience.transaction import verify_transaction_integrity

    s.host.job_tray.finish_job(s.job_id)
    s.host.experience_metrics.inc_job("ai", "finished")
    s.host.conflict_guard.release(s.guard_key, s.job_id)
    s.host.experience_metrics.inc_guard("released")
    s.host._sync_focus_ring()
    if not isinstance(result, dict):
        safe_warning(s.host, s.job_label, "AI 返回了无法识别的结果。")
        return
    if result == s.section:
        s.host.statusBar().showMessage("生成结果与原内容一致", 4000)
        return

    ok, reason = verify_transaction_integrity(s.host.adapter, s.tx_snap)
    if not ok:
        logger.warning("Transaction integrity check failed: %s", reason)
        safe_warning(s.host, f"{s.job_label}已被取消", f"未能安全应用变更：{reason}")
        s.host.experience_metrics.inc_suggestion(s.action_id, "rejected")
        return

    from src.widgets.diff_view import SectionDiffView

    dlg = SectionDiffView(
        s.section,
        result,
        s.host,
        confirm=True,
        title=f"{s.job_label}预览 — 确认后应用",
    )
    if dlg.exec() != QDialog.DialogCode.Accepted:
        s.host.experience_metrics.inc_suggestion(s.action_id, "rejected")
        return
    focus_ids: set[str] | None = None
    if s.kind == "lesson" and s.node_id:
        focus_ids = {s.node_id}
    applied = apply_regen_result(
        s.host,
        s.section,
        result,
        section_id=s.sid,
        focus_lesson_ids=focus_ids,
        action_id=s.action_id,
        job_label=s.job_label,
        scope={"kind": s.kind, "id": s.node_id, "section_id": s.sid},
    )
    if not applied:
        s.host.experience_metrics.inc_suggestion(s.action_id, "rejected")
    else:
        try:
            from src.backend.experience.circuit_breaker import get_circuit_breaker

            get_circuit_breaker().record_success(s.action_id)
        except Exception:
            logger.debug(
                "experience_handlers/regenerate.py:_on_ok best-effort cb record_success failed",
                exc_info=True,
            )



def _regen_on_err(s: "_RegenSession", msg: str) -> None:
    s.host.job_tray.finish_job(s.job_id)
    s.host.experience_metrics.inc_job("ai", "failed")
    s.host.conflict_guard.release(s.guard_key, s.job_id)
    s.host.experience_metrics.inc_guard("released")
    s.host._sync_focus_ring()
    try:
        from src.backend.experience.circuit_breaker import get_circuit_breaker

        get_circuit_breaker().record_failure(s.action_id, msg)
    except Exception:
        logger.debug(
            "experience_handlers/regenerate.py:_on_err best-effort cb record_failure failed",
            exc_info=True,
        )
    safe_warning(s.host, f"{s.job_label}失败", msg)





def apply_regen_result(
    host: ExperienceHost,
    old_section: dict,
    new_section: dict,
    *,
    section_id: str,
    focus_lesson_ids: set[str] | None = None,
    action_id: str = "lesson.regenerate",
    job_label: str = "重生成",
    scope: dict | None = None,
) -> bool:
    """C-08 / v4.57: prefer LessonPatch batch; fall back to section merge.

    Returns True when a command was pushed (applied), False when nothing
    applied (should not happen after Diff accept unless extraction empty and
    merge fails).
    """
    from src.application.commands import (
        ApplyBatchPatchCommand,
        ApplyLessonPatchCommand,
    )
    from src.backend.experience.patch import (
        batch_patch,
        lesson_patches_from_section_diff,
    )

    sid = str(section_id or old_section.get("id") or "")
    patches = lesson_patches_from_section_diff(
        old_section,
        new_section,
        only_lesson_ids=focus_lesson_ids,
    )
    # If caller scoped to specific lessons but extraction empty, try full diff.
    if not patches and focus_lesson_ids:
        patches = lesson_patches_from_section_diff(old_section, new_section)

    try:
        if len(patches) == 1:
            cmd = ApplyLessonPatchCommand(host.adapter, patches[0])
        elif len(patches) > 1:
            cmd = ApplyBatchPatchCommand(
                adapter=host.adapter,
                batch=batch_patch(patches, label=job_label),
                text=job_label,
            )
        else:
            # C-08 v4.58: full section body + resource merge via SectionPatch.
            try:
                from src.application.commands import ApplySectionPatchCommand
                from src.backend.experience.patch import section_patch_from_replace

                sp = section_patch_from_replace(old_section, new_section)
                cmd = ApplySectionPatchCommand(host.adapter, sp)
            except Exception:
                plan = host.adapter.plan_section_merge(sid, new_section)
                cmd = MergeAiSectionCommand(host.adapter, plan)
        if hasattr(cmd, "signals") and hasattr(host, "_on_ai_edit_applied"):
            try:
                cmd.signals.changed.connect(host._on_ai_edit_applied)
            except Exception:
                logger.debug("application/experience_handlers/regenerate.py:apply_regen_result best-effort step failed", exc_info=True)
        host.undo_stack.push(cmd)
        host.experience_metrics.inc_suggestion(action_id, "applied")
        host._record_experience_event(
            action_id,
            f"{job_label}已应用",
            action_id=action_id,
            scope=dict(scope or {"section_id": sid, "count": len(patches)}),
        )
        host._refresh_validate_after_ai(f"{job_label}已应用，记得保存")
        return True
    except Exception as exc:
        safe_warning(host, job_label, f"应用失败：{exc}")
        return False



# Cap for T-04 AI multi-lesson batch (budget / UX).
BATCH_REGEN_CAP = 5


def _batch_regen_lesson_ids(host: ExperienceHost, scope: dict | None) -> list[str]:
    """Resolve ordered unique lesson ids from scope or multi_selection."""
    ids: list[str] = []
    seen: set[str] = set()
    scope = scope or {}
    raw = scope.get("lesson_ids") or scope.get("ids") or []
    if isinstance(raw, (list, tuple)):
        for x in raw:
            lid = str(x or "").strip()
            if lid and lid not in seen:
                seen.add(lid)
                ids.append(lid)
    if not ids:
        multi = []
        try:
            ctx = getattr(host.experience, "context", None)
            multi = list(getattr(ctx, "multi_selection", None) or [])
        except Exception:
            multi = []
        if not multi:
            multi = list(getattr(host.experience, "_multi", None) or [])
        for ref in multi:
            kind = getattr(ref, "kind", None)
            rid = getattr(ref, "id", None)
            if kind is None and isinstance(ref, (tuple, list)) and len(ref) >= 2:
                kind, rid = ref[0], ref[1]
            if str(kind) == "lesson":
                lid = str(rid or "").strip()
                if lid and lid not in seen:
                    seen.add(lid)
                    ids.append(lid)
    if not ids:
        ref = getattr(host, "_current_node_ref", None)
        if ref and ref[0] == "lesson":
            ids.append(str(ref[1]))
    return ids[:BATCH_REGEN_CAP]


@dataclass(frozen=True)
class _BatchRegenSpec:
    """Per-kind configuration for the shared batch-regeneration flow."""

    action_id: str                     # suggestion / metric id
    title: str                         # 批量重生成 / 批量重生成单元
    noun: str                          # 课 / 单元
    unit_word: str                     # counting phrase suffix: "3 课" / "3 个单元"
    cap: int
    job_id: str
    node_prefix: str                   # lesson / unit (job tray node_key)
    select_hint: str                   # empty multi-selection hint
    resolve_ids: Callable[[ExperienceHost, dict | None], list[str]]
    find: Callable[[Any, str], tuple[dict, str]]          # -> (section, display name)
    regen: Callable[..., dict]                            # (config, spec, draft, id)
    extract: Callable[[dict, dict, str], list]            # -> lesson patches
    apply_question: Callable[[int, int], str]             # (n_patches, n_items)
    cmd_texts: Callable[[int, int], tuple[str, str]]      # -> (batch label, undo text)
    applied_msg: Callable[[int, int], str]
    event_scope: Callable[[int, int], dict]
    after_msg: Callable[[int, int], str]


def _find_lesson_target(adapter: Any, lid: str) -> tuple[dict, str]:
    section, _unit, lesson = adapter.find_lesson(lid)
    return section, (lesson.get("name") or lid)


def _find_unit_target(adapter: Any, uid: str) -> tuple[dict, str]:
    section, unit = adapter.find_unit(uid)
    return section, (unit.get("name") or uid)


def _regen_lesson_target(config: Any, ai_spec: Any, draft: dict, lid: str) -> dict:
    from src.backend.ai_generator import regenerate_lesson_in_section

    return regenerate_lesson_in_section(config, ai_spec, draft, lid, instruction=None)


def _regen_unit_target(config: Any, ai_spec: Any, draft: dict, uid: str) -> dict:
    from src.backend.ai_generator import regenerate_unit_in_section

    return regenerate_unit_in_section(config, ai_spec, draft, uid, instruction=None)


def _extract_lesson_patches(old_sec: dict, new_sec: dict, lid: str) -> list:
    from src.backend.experience.patch import lesson_patches_from_section_diff

    # Each AI result is a full section with one lesson rewritten;
    # extract only that lesson against the pre-batch snapshot.
    return lesson_patches_from_section_diff(old_sec, new_sec, only_lesson_ids={lid})


def _extract_unit_patches(old_sec: dict, new_sec: dict, uid: str) -> list:
    from src.backend.experience.patch import lesson_patches_from_section_diff

    only = _lesson_ids_in_unit(old_sec, uid) or _lesson_ids_in_unit(new_sec, uid)
    patches = lesson_patches_from_section_diff(
        old_sec, new_sec, only_lesson_ids=only or None
    )
    if not patches:
        patches = lesson_patches_from_section_diff(old_sec, new_sec)
    return patches


def _lesson_batch_spec() -> _BatchRegenSpec:
    return _BatchRegenSpec(
        action_id="lesson.batch_regenerate",
        title="批量重生成",
        noun="课",
        unit_word="课",
        cap=BATCH_REGEN_CAP,
        job_id="batch-regen",
        node_prefix="lesson",
        select_hint="请先多选课时，或用 ⌘K /batch-regen 时已有选中",
        resolve_ids=_batch_regen_lesson_ids,
        find=_find_lesson_target,
        regen=_regen_lesson_target,
        extract=_extract_lesson_patches,
        apply_question=lambda n, _n_items: (
            f"将应用 {n} 课变更（一个 Undo）。是否继续？"
        ),
        cmd_texts=lambda n, _n_items: (f"批量重生成 {n} 课", f"批量重生成 {n} 课"),
        applied_msg=lambda n, _n_items: f"批量重生成已应用 {n} 课",
        event_scope=lambda n, _n_items: {"count": n},
        after_msg=lambda n, _n_items: f"批量重生成已应用 {n} 课，记得保存",
    )


def _unit_batch_spec() -> _BatchRegenSpec:
    return _BatchRegenSpec(
        action_id="unit.batch_regenerate",
        title="批量重生成单元",
        noun="单元",
        unit_word="个单元",
        cap=UNIT_BATCH_REGEN_CAP,
        job_id="unit-batch-regen",
        node_prefix="unit",
        select_hint="请先多选单元，或用 ⌘K /unit-batch-regen 时已有选中",
        resolve_ids=_batch_regen_unit_ids,
        find=_find_unit_target,
        regen=_regen_unit_target,
        extract=_extract_unit_patches,
        apply_question=lambda n, n_items: (
            f"将应用 {n_items} 单元共 {n} 课变更（一个 Undo）。是否继续？"
        ),
        cmd_texts=lambda n, n_items: (
            f"批量重生成 {n_items} 单元",
            f"批量重生成 {n_items} 单元（{n} 课）",
        ),
        applied_msg=lambda n, n_items: f"批量重生成单元已应用 {n_items} 单元/{n} 课",
        event_scope=lambda n, n_items: {"count": n, "units": n_items},
        after_msg=lambda n, n_items: f"批量重生成单元已应用 {n_items} 单元，记得保存",
    )


@dataclass
class _BatchRegenSession:
    """Shared mutable state of one sequential batch-regeneration walk."""

    host: ExperienceHost
    spec: "_BatchRegenSpec"
    targets: list[tuple[str, str, dict]]
    section_snaps: dict[str, dict]
    tx_snap: Any
    chain: list[tuple[str, str, dict]]
    results: list[tuple[str, str, dict]]
    job_id: str
    config: Any
    ai_spec: Any


def _batch_regen_prepare(
    host: ExperienceHost, spec: "_BatchRegenSpec", scope: dict
) -> list[tuple[str, str, dict]] | None:
    """Guards + target resolution + confirmation. None = user aborted."""
    if not host.course_dir:
        safe_warning(host, "未加载课程目录", "请先打开课程目录。")
        return None
    ids = spec.resolve_ids(host, scope)
    if len(ids) < 1:
        host.statusBar().showMessage(spec.select_hint, 5000)
        return None
    if host.job_tray.is_busy_ai():
        safe_information(host, spec.title, "当前有 AI 任务进行中，请稍候。")
        return None
    deny = getattr(host, "_deny_ai_write_if_blocked", None)
    if callable(deny) and deny(label=spec.title):
        return None

    # Resolve (item_id, section_id, section_dict) triples.
    targets: list[tuple[str, str, dict]] = []
    for iid in ids:
        try:
            section, _name = spec.find(host.adapter, iid)
            targets.append((iid, str(section.get("id") or ""), section))
        except KeyError:
            continue
    if not targets:
        safe_warning(host, spec.title, f"选中的{spec.noun}无法在课程中定位。")
        return None

    names = []
    for iid, _sid, _sec in targets[:12]:
        try:
            _s, display = spec.find(host.adapter, iid)
            names.append(f"· {display}（{iid}）")
        except Exception:
            names.append(f"· {iid}")
    more = "" if len(targets) <= 12 else f"\n…共 {len(targets)} {spec.noun}"
    if not safe_question(
        host,
        spec.title,
        f"将顺序 AI 重生成 {len(targets)} {spec.unit_word}（上限 {spec.cap}），"
        f"确认后预览再一批应用（可 Undo）：\n"
        + "\n".join(names)
        + more
        + f"\n\n失败的{spec.noun}会跳过，不中止整批。",
        default_yes=False,
    ):
        host.experience_metrics.inc_suggestion(spec.action_id, "rejected")
        return None
    return targets


def _finish_batch(s: "_BatchRegenSession") -> None:
    s.host.job_tray.finish_job(s.job_id)
    s.host.experience_metrics.inc_job("ai", "finished")
    if not s.results:
        try:
            from src.backend.experience.circuit_breaker import get_circuit_breaker

            get_circuit_breaker().record_failure(s.spec.action_id, "batch generated no s.results")
        except Exception:
            logger.debug("experience_handlers/regenerate.py:_finish_batch best-effort cb failed", exc_info=True)
        safe_warning(s.host, s.spec.title, f"没有成功生成任何{s.spec.noun}。")
        return
    from src.backend.experience.transaction import verify_transaction_integrity
    from src.backend.experience.patch import batch_patch
    from src.application.commands import ApplyBatchPatchCommand

    all_patches = []
    for iid, sid, new_sec in s.results:
        old_sec = s.section_snaps.get(sid) or {}
        all_patches.extend(s.spec.extract(old_sec, new_sec, iid))
    if not all_patches:
        safe_warning(s.host, s.spec.title, "生成结果无法抽取课级补丁。")
        return

    ok, reason = verify_transaction_integrity(s.host.adapter, s.tx_snap)
    if not ok:
        logger.warning("Batch transaction integrity check failed: %s", reason)
        safe_warning(s.host, f"{s.spec.title}已被取消", f"未能安全应用批量变更：{reason}")
        s.host.experience_metrics.inc_suggestion(s.spec.action_id, "rejected")
        try:
            from src.backend.experience.circuit_breaker import get_circuit_breaker

            get_circuit_breaker().record_failure(s.spec.action_id, reason)
        except Exception:
            logger.debug("experience_handlers/regenerate.py:_finish_batch best-effort cb failed", exc_info=True)
        return

    n = len(all_patches)
    n_items = len(s.results)
    if not safe_question(
        s.host,
        f"确认应用{s.spec.title}",
        s.spec.apply_question(n, n_items),
        default_yes=True,
    ):
        s.host.experience_metrics.inc_suggestion(s.spec.action_id, "rejected")
        return
    try:
        batch_label, cmd_text = s.spec.cmd_texts(n, n_items)
        cmd = ApplyBatchPatchCommand(
            adapter=s.host.adapter,
            batch=batch_patch(all_patches, label=batch_label),
            text=cmd_text,
        )
        if hasattr(cmd, "signals") and hasattr(s.host, "_on_ai_edit_applied"):
            try:
                cmd.signals.changed.connect(s.host._on_ai_edit_applied)
            except Exception:
                logger.debug("application/experience_handlers/regenerate.py:_finish_batch best-effort step failed", exc_info=True)
        s.host.undo_stack.push(cmd)
        s.host.experience_metrics.inc_suggestion(s.spec.action_id, "applied")
        try:
            from src.backend.experience.circuit_breaker import get_circuit_breaker

            get_circuit_breaker().record_success(s.spec.action_id)
        except Exception:
            logger.debug("experience_handlers/regenerate.py:_finish_batch best-effort cb failed", exc_info=True)
        s.host._record_experience_event(
            s.spec.action_id,
            s.spec.applied_msg(n, n_items),
            action_id=s.spec.action_id,
            scope=s.spec.event_scope(n, n_items),
        )
        s.host._refresh_validate_after_ai(s.spec.after_msg(n, n_items))
    except Exception as exc:
        try:
            from src.backend.experience.circuit_breaker import get_circuit_breaker

            get_circuit_breaker().record_failure(s.spec.action_id, str(exc))
        except Exception:
            logger.debug("experience_handlers/regenerate.py:_finish_batch best-effort cb failed", exc_info=True)
        safe_warning(s.host, s.spec.title, f"应用失败：{exc}")



def _run_next(s: "_BatchRegenSession") -> None:
    import copy

    if not s.chain:
        _finish_batch(s)
        return
    iid, sid, section = s.chain.pop(0)
    s.host.job_tray.start_job(
        s.job_id,
        f"{s.spec.title}：{iid}（剩余 {len(s.chain)}）…",
        kind="ai",
        node_key=f"{s.spec.node_prefix}:{iid}",
    )
    draft = copy.deepcopy(s.section_snaps.get(sid) or section)

    def _target() -> dict:
        return s.spec.regen(s.config, s.ai_spec, draft, iid)

    # Test/offscreen hook: run the AI target inline (no QThread).
    if getattr(s.host, "_batch_regen_inline", False):
        try:
            result = _target()
            if isinstance(result, dict) and result != draft:
                s.results.append((iid, sid, result))
        except Exception as exc:
            try:
                s.host.statusBar().showMessage(f"跳过 {iid}：{exc}", 4000)
            except Exception:
                logger.debug("application/experience_handlers/regenerate.py:_run_next best-effort step failed", exc_info=True)
        _run_next(s)
        return

    w = AiRequestWorker(_target)

    def _ok(result: object) -> None:
        if isinstance(result, dict) and result != draft:
            s.results.append((iid, sid, result))
        _run_next(s)

    def _err(msg: str) -> None:
        try:
            s.host.statusBar().showMessage(f"跳过 {iid}：{msg}", 4000)
        except Exception:
            logger.debug("application/experience_handlers/regenerate.py:_err best-effort step failed", exc_info=True)
        _run_next(s)

    w.result_ready.connect(_ok)
    w.error_occurred.connect(_err)
    w.start()
    s.host._experience_worker = w


def _run_batch_regen_flow(
    host: ExperienceHost, scope: dict, spec: _BatchRegenSpec
) -> None:
    """Shared sequential batch regeneration: guard → confirm → AI chain → patch.

    Lessons (T-04 / v4.57) and units (v4.59) run the identical skeleton; all
    per-kind behaviour lives in *spec*. Results are collected per item, then
    applied as one ApplyBatchPatchCommand (single Undo) after a preview
    question.
    """
    import copy

    from src.backend.ai_generator import AiCourseSpec
    from src.backend.experience.transaction import create_transaction_snapshot

    targets = _batch_regen_prepare(host, spec, scope)
    if targets is None:
        return

    config = host._ai_config
    ai_spec = AiCourseSpec()
    # Per-section original snapshot for patch extraction.
    section_snaps: dict[str, dict] = {}
    for _iid, sid, section in targets:
        if sid not in section_snaps:
            section_snaps[sid] = copy.deepcopy(section)

    node_keys = [f"{spec.node_prefix}:{iid}" for iid, _sid, _sec in targets]
    tx_snap = create_transaction_snapshot(host.adapter, spec.action_id, node_keys)

    session = _BatchRegenSession(
        host=host,
        spec=spec,
        targets=targets,
        section_snaps=section_snaps,
        tx_snap=tx_snap,
        chain=list(targets),
        results=[],
        job_id=spec.job_id,
        config=config,
        ai_spec=ai_spec,
    )
    host.experience_metrics.inc_job("ai", "started")
    host.job_tray.start_job(
        session.job_id, f"{spec.title} 0/{len(targets)} …", kind="ai", node_key=""
    )
    _run_next(session)


def _experience_batch_regenerate(host: ExperienceHost, scope: dict) -> None:
    """T-04 AI / v4.57: sequential multi-lesson regenerate → one Batch Undo."""
    _run_batch_regen_flow(host, scope, _lesson_batch_spec())


handle_batch_regenerate = _experience_batch_regenerate


# Cap for multi-unit batch (heavier than lesson batch: each unit may hold many lessons).
UNIT_BATCH_REGEN_CAP = 3


def _batch_regen_unit_ids(host: ExperienceHost, scope: dict | None) -> list[str]:
    """Resolve ordered unique unit ids from scope or multi_selection."""
    ids: list[str] = []
    seen: set[str] = set()
    scope = scope or {}
    raw = scope.get("unit_ids") or scope.get("ids") or []
    if isinstance(raw, (list, tuple)):
        for x in raw:
            uid = str(x or "").strip()
            if uid and uid not in seen:
                seen.add(uid)
                ids.append(uid)
    if not ids:
        multi = []
        try:
            ctx = getattr(host.experience, "context", None)
            multi = list(getattr(ctx, "multi_selection", None) or [])
        except Exception:
            multi = []
        if not multi:
            multi = list(getattr(host.experience, "_multi", None) or [])
        for ref in multi:
            kind = getattr(ref, "kind", None)
            rid = getattr(ref, "id", None)
            if kind is None and isinstance(ref, (tuple, list)) and len(ref) >= 2:
                kind, rid = ref[0], ref[1]
            if str(kind) == "unit":
                uid = str(rid or "").strip()
                if uid and uid not in seen:
                    seen.add(uid)
                    ids.append(uid)
    if not ids:
        ref = getattr(host, "_current_node_ref", None)
        if ref and ref[0] == "unit":
            ids.append(str(ref[1]))
    return ids[:UNIT_BATCH_REGEN_CAP]


def _lesson_ids_in_unit(section: dict, unit_id: str) -> set[str]:
    """Lesson ids under *unit_id* in *section* (never raises)."""
    out: set[str] = set()
    try:
        for u in section.get("units") or []:
            if not isinstance(u, dict) or str(u.get("id") or "") != unit_id:
                continue
            for les in u.get("lessons") or []:
                if isinstance(les, dict) and les.get("id"):
                    out.add(str(les["id"]))
            break
    except Exception:
        logger.debug("application/experience_handlers/regenerate.py:_lesson_ids_in_unit best-effort step failed", exc_info=True)
    return out


def _experience_batch_regenerate_units(host: ExperienceHost, scope: dict) -> None:
    """v4.59: sequential multi-unit regenerate → one Batch Undo."""
    _run_batch_regen_flow(host, scope, _unit_batch_spec())


handle_batch_regenerate_units = _experience_batch_regenerate_units


def _refresh_validate_after_ai(host, success_message: str) -> None:
    """O-05: re-validate **in-memory** sections after AI apply + refresh Dock.

    Disk ``validate_course_dir`` still reflects the last save; AI patches
    live only in the adapter until the author saves. Section-level
    validate on live JSON is the correct source for post-fix counters.

    Failures degrade to a status message only — never block the apply that
    already succeeded (保存不挟持 / 校验回流).
    """
    problems: list[dict] = []
    try:
        for section in getattr(host.adapter, "sections", None) or []:
            if not isinstance(section, dict):
                continue
            for p in host.adapter.validate_section_json(
                section, check_existing_ids=True
            ):
                if isinstance(p, dict):
                    problems.append(p)
    except Exception as exc:
        host.statusBar().showMessage(
            f"{success_message}（回流校验失败：{exc}）", 6000
        )
        host._refresh_experience(immediate=True)
        return
    host.experience.set_validate_problems(problems)
    host._refresh_experience(immediate=True)
    errors = sum(1 for p in problems if p.get("level") == "error")
    warnings = sum(1 for p in problems if p.get("level") == "warning")
    suffix = f" · 回流校验 错{errors}/警{warnings}"
    host.statusBar().showMessage(success_message + suffix, 6000)
    # O-05: brief Dock pulse so authors notice counter refresh without re-click.
    if hasattr(host, "experience_dock_widget"):
        pulse = getattr(host.experience_dock_widget, "pulse_metrics", None)
        if callable(pulse):
            pulse()

handle_refresh_validate_after_ai = _refresh_validate_after_ai

