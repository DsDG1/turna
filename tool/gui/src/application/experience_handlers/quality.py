"""Quality campaign / soft hygiene skill implementations (M7)."""
from __future__ import annotations

from typing import Any

from PySide6.QtWidgets import QDialog

from src.application.ui_guard import safe_information, safe_question, safe_warning


def handle_quality_campaign(host: Any, scope: dict) -> None:
    """E2.0 K-16: worst-N / empty campaign queue dialog."""
    from src.dialogs.quality_campaign_dialog import (
        QualityCampaignDialog,
        build_campaign_items,
    )

    ctx = host.experience.context
    quality = dict(ctx.quality_by_section) if ctx is not None else {}
    empty = list(ctx.empty_lessons) if ctx is not None else []
    if scope.get("section_id") and scope["section_id"] not in quality:
        quality.setdefault(
            str(scope["section_id"]), float(scope.get("mean") or 0.5)
        )
    items = build_campaign_items(
        quality_by_section=quality,
        empty_lessons=empty,
        sections=getattr(host.adapter, "sections", None) or [],
        worst_n=3,
    )
    if not items:
        safe_information(host, "低质战役", "当前没有空课或低质节需要处理。")
        return
    dlg = QualityCampaignDialog(items, parent=host)
    if dlg.exec() != QDialog.DialogCode.Accepted:
        return
    chosen = dlg.chosen()
    action = dlg.action()
    if not chosen:
        return
    kind = str(chosen.get("kind") or "")
    node_id = str(chosen.get("id") or "")
    host._record_experience_event(
        "quality.campaign",
        str(chosen.get("title") or node_id),
        action_id="quality.campaign_worst_n",
        scope={"kind": kind, "id": node_id, "action": action},
    )
    if action == "locate":
        if kind == "lesson":
            host.tree.select_lesson(node_id)
        elif kind == "section":
            host.tree.select_section(node_id)
        elif kind == "unit":
            host.tree.select_unit(node_id)
        host.statusBar().showMessage(f"已定位 {kind}:{node_id}", 4000)
        return
    # 只读预检：真正的互斥由内层 _on_ai_edit / _experience_fill_empty
    # 自己的 Guard acquire/release 提供；此处不再 hold（旧实现 hold 后委派，
    # 内层以不同 job_id 再 acquire 同节点必被拒，战役 AI 路径走不通）。
    guard_key = f"{kind}:{node_id}"
    if host.conflict_guard.is_busy(guard_key):
        host.experience_metrics.inc_guard("rejected")
        host.statusBar().showMessage(
            f"节点忙碌：{host.conflict_guard.busy_summary()}", 5000
        )
        return
    if kind == "lesson":
        if chosen.get("reason") == "empty":
            host._experience_fill_empty({"first_lesson_id": node_id})
        else:
            host.tree.select_lesson(node_id)
            host._on_ai_edit("lesson", node_id)
    elif kind == "section":
        host.tree.select_section(node_id)
        host._on_ai_edit("section", node_id)
    else:
        host.statusBar().showMessage(f"暂不支持战役处理 {kind}", 4000)


def handle_soft_preview_hygiene(host: Any, scope: dict | None = None) -> None:
    """v4.12 Skill: preview Soft rule fixes, confirm, apply via Undo.

    Zero LLM. Does **not** flip ``experience_soft_autopilot`` default.
    Cancel / empty / error → no write. Metrics: evaluated / applied / skipped.
    """
    from src.application.commands import SoftHygieneCommand
    from src.backend.experience.soft_autopilot import (
        evaluate_soft_fixes,
        summarize_soft_batch,
    )

    try:
        batch = evaluate_soft_fixes(host.adapter)
    except Exception as exc:
        if hasattr(host, "experience_metrics"):
            host.experience_metrics.inc_soft("skipped")
        safe_warning(host, "规则规范化", f"评估失败：{exc}")
        return
    if hasattr(host, "experience_metrics"):
        host.experience_metrics.inc_soft("evaluated")
    if not batch.fixes:
        if hasattr(host, "experience_metrics"):
            host.experience_metrics.inc_soft("skipped")
        host.statusBar().showMessage("没有可规范化的规则项", 4000)
        return
    summary = summarize_soft_batch(batch)
    if not safe_question(host,
        "规则规范化（预览）",
        (summary or f"将规范化 {len(batch)} 项")
        + "\n\n确认应用？可通过 Ctrl+Z 撤销。",
        default_yes=False,
        ):
        if hasattr(host, "experience_metrics"):
            host.experience_metrics.inc_soft("skipped")
        host.statusBar().showMessage("已取消规则规范化", 3000)
        return
    try:
        cmd = SoftHygieneCommand(host.adapter, batch)
        host.undo_stack.push(cmd)
    except Exception as exc:
        if hasattr(host, "experience_metrics"):
            host.experience_metrics.inc_soft("skipped")
        safe_warning(host, "规则规范化", f"应用失败：{exc}")
        return
    if hasattr(host, "experience_metrics"):
        host.experience_metrics.inc_soft("applied")
    host._record_experience_event(
        "soft.preview",
        f"规则规范化 {len(batch)} 项",
        action_id="soft.preview_hygiene",
        scope={"count": len(batch)},
    )
    host._refresh_experience(immediate=True)
    host.statusBar().showMessage(f"已规范化 {len(batch)} 项 · 可 Ctrl+Z 撤销", 5000)

