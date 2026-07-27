"""Resource hygiene / POS / batch / compare skill implementations (M7)."""
from __future__ import annotations

from typing import Any

from src.application.ui_guard import safe_information, safe_question, safe_warning

def _experience_dedupe_suggest(host, scope: dict) -> None:
    """K-20: open resources with a duplicate-aware filter; never auto-delete."""
    n = int(scope.get("count") or 0)
    sample = str(scope.get("sample_term") or "")
    msg = f"发现约 {n} 组重复词条" if n else "打开资源查重"
    if sample:
        msg += f"（例：{sample}）"
    host.statusBar().showMessage(msg + " · 请人工合并，不会自动删除", 7000)
    # Reuse open_hygiene-style entry; filter string is free-text in editor.
    filt = str(scope.get("filter") or sample or "重复")
    host._on_resources(initial_filter=filt)

handle_dedupe_suggest = _experience_dedupe_suggest

def _experience_align_pos(host, scope: dict) -> None:
    """K-21: align POS tags across the vocab pool (LLM propose + batch patch).

    local detect (missing/invalid/conflict) -> QMessageBox confirm (list
    first 12 misaligned terms) -> AiRequestWorker runs ``run_pos_alignment``
    -> parse {word_id: pos} -> one ``FieldPatch`` per word -> single
    ``ApplyBatchPatchCommand`` (preview via Undo stack; no SectionDiffView as
    this is a vocab-field write, mirroring ``_experience_batch_set_template``).
    Red line: needs_confirm + preview + undo; 保 id (field_patch rejects id);
    non-dangerous; closed-set POS; scope closed-set (count, no term/原文,
    §14.5.3); never raises (all failure paths non-modal statusBar).
    """
    from src.backend.experience.pos_skill import (
        ACTION_ID,
        evaluate_pos_alignment,
        run_pos_alignment,
    )

    adapter = getattr(host, "adapter", None)
    if adapter is None:
        host.statusBar().showMessage("请先打开课程", 4000)
        return
    report = evaluate_pos_alignment(adapter)
    misaligned = report.get("misaligned") or []
    if not misaligned:
        host.statusBar().showMessage("词条词性已对齐（无缺失/无效/冲突）", 4000)
        return
    # Confirm: list first 12 misaligned terms (term is UI-only, not telemetry).
    sample_lines: list[str] = []
    vocab = list(getattr(adapter, "vocab", []) or [])
    vocab_by_id = {str(w.get("id") or ""): w for w in vocab}
    for item in misaligned[:12]:
        wid = item["word_id"]
        term = str(vocab_by_id.get(wid, {}).get("term") or "")
        cur = item["current_pos"] or "—"
        issue = {"missing": "缺", "invalid": "无效", "conflict": "冲突"}.get(
            item["issue"], item["issue"]
        )
        sample_lines.append(f"  · {term or wid}（当前 {cur}，{issue}）")
    more = f"\n  … 共 {len(misaligned)} 个" if len(misaligned) > 12 else ""
    if not safe_question(host,
        "对齐词条词性（POS）",
        "将用 AI 为下列词条建议单一词性标签（10 类闭集），确认后入 Undo 栈，可撤销：\n"
        + "\n".join(sample_lines)
        + more,
        default_yes=False,
        ):
        host.experience_metrics.inc_suggestion(ACTION_ID, "rejected")
        return

    config = getattr(host, "_ai_config", None)
    if config is None or not getattr(config, "is_complete", False):
        host.statusBar().showMessage("AI 配置不完整：设置 ▸ AI 填写 Key/Model", 5000)
        return
    # Budget guard (M-08): deny AI write if blocked (mirrors other AI skills).
    deny = getattr(host, "_deny_ai_write_if_blocked", None)
    if callable(deny) and deny(label="词性对齐"):
        return

    lang = "Turkish"
    try:
        lang = str((getattr(adapter, "index", {}) or {}).get("language") or "")
        if lang:
            lang = lang.capitalize()
    except Exception:
        lang = "Turkish"

    job_id = "pos-align"
    tray = getattr(host, "job_tray", None)
    metrics = getattr(host, "experience_metrics", None)
    if tray is not None:
        tray.start(job_id, "词性对齐：正在生成 …", kind="ai")
    if metrics is not None:
        metrics.inc_job("ai", "started")
        metrics.inc_suggestion(ACTION_ID, "accepted")
    if hasattr(host, "_refresh_experience"):
        try:
            host._refresh_experience(immediate=False, focus_only=True)
        except Exception:
            pass

    worker = host._make_ai_worker(
        run_pos_alignment, config, adapter, language=lang
    )

    def _on_ok(mapping: object) -> None:
        try:
            from src.application.commands import ApplyBatchPatchCommand
            from src.backend.experience.patch import field_patch

            steps: list = []
            changed_ids: list[str] = []
            pos_map = mapping if isinstance(mapping, dict) else {}
            for wid, new_pos in pos_map.items():
                wid = str(wid)
                word = vocab_by_id.get(wid)
                if word is None:
                    continue
                if str(word.get("pos") or "") == str(new_pos):
                    continue
                patch = field_patch(
                    word, "pos", new_pos, target_kind="vocab", target_id=wid
                )
                steps.append(("field", word, patch))
                changed_ids.append(wid)
        except Exception:
            steps = []
            changed_ids = []
        if tray is not None:
            tray.finish(job_id)
        if metrics is not None:
            metrics.inc_job("ai", "finished")
        if not steps:
            host.statusBar().showMessage("词性对齐：AI 未给出可用建议", 6000)
            return
        cmd = ApplyBatchPatchCommand(
            steps=steps,
            adapter=host.adapter,
            text=f"对齐词性（POS）（{len(steps)} 词）",
        )
        cmd.signals.changed.connect(host._on_ai_edit_applied)
        host.undo_stack.push(cmd)
        if metrics is not None:
            metrics.inc_suggestion(ACTION_ID, "applied")
        try:
            # §14.5.3: scope closed-set (count), no term/原文.
            host._record_experience_event(
                ACTION_ID,
                f"对齐词性 {len(steps)} 词",
                action_id=ACTION_ID,
                scope={"count": len(steps)},
            )
        except Exception:
            pass
        if hasattr(host, "_refresh_validate_after_ai"):
            try:
                host._refresh_validate_after_ai()
            except Exception:
                pass
        host.statusBar().showMessage(
            f"词性对齐：已更新 {len(steps)} 个词条（可 Ctrl+Z 撤销）", 6000
        )

    def _on_err(msg: str) -> None:
        if tray is not None:
            tray.finish(job_id)
        if metrics is not None:
            metrics.inc_job("ai", "failed")
        host.statusBar().showMessage(f"词性对齐失败：{msg}", 8000)

    worker.result_ready.connect(_on_ok)
    worker.error_occurred.connect(_on_err)
    worker.start()
    host._experience_worker = worker

handle_align_pos = _experience_align_pos

def _experience_resolve_term_conflicts(host, scope: dict) -> None:
    """V-06: unify vocab↔expression term conflicts (zero LLM, batch patch).

    local detect (same normalized term, different normalized translation)
    -> confirm (list first 12 conflict pairs; term/translation UI-only)
    -> human picks one direction (统一为 vocab 释义 / 统一为 expression 释义)
    -> one ``FieldPatch(translation)`` per touched side -> single
    ``ApplyBatchPatchCommand`` (preview + confirm + Undo). 保 id
    (field_patch rejects id); scope closed-set ``{count}`` (§14.5.3, no
    term/原文 in telemetry); never raises (failure paths non-modal statusBar).
    """
    from src.backend.experience.term_conflict_skill import (
        ACTION_ID,
        evaluate_term_conflicts,
    )

    adapter = getattr(host, "adapter", None)
    if adapter is None:
        host.statusBar().showMessage("请先打开课程", 4000)
        return
    report = evaluate_term_conflicts(adapter)
    conflicts = report.get("conflicts") or []
    if not conflicts:
        host.statusBar().showMessage("无词条冲突（同 term 异译）", 4000)
        return
    metrics = getattr(host, "experience_metrics", None)
    vocab_by_id = {
        str(w.get("id") or ""): w
        for w in (getattr(adapter, "vocab", None) or [])
        if isinstance(w, dict)
    }
    expr_by_id = {
        str(e.get("id") or ""): e
        for e in (getattr(adapter, "expressions", None) or [])
        if isinstance(e, dict)
    }
    # Confirm: list first 12 conflict pairs (term/translation UI-only).
    sample_lines: list[str] = []
    for c in conflicts[:12]:
        w = vocab_by_id.get(c["vocab_id"], {})
        e = expr_by_id.get(c["expression_id"], {})
        term = str(w.get("term") or e.get("term") or c["vocab_id"])
        sample_lines.append(
            f"  · {term}：vocab「{w.get('translation') or '—'}」"
            f" vs expression「{e.get('translation') or '—'}」"
        )
    more = f"\n  … 共 {len(conflicts)} 对" if len(conflicts) > 12 else ""
    text = (
        "下列 vocab 与 expression 词条 term 相同但释义不同，"
        "将统一释义（入 Undo 栈，可撤销）：\n" + "\n".join(sample_lines) + more
    )
    # 二选一方向：先问 vocab；否则再问 expression；都否则取消。
    if safe_question(
        host, "统一词条冲突释义", text + "\n\n统一为 vocab 释义？",
        default_yes=False,
    ):
        direction = "vocab"
    elif safe_question(
        host, "统一词条冲突释义", "改为统一为 expression 释义？",
        default_yes=False,
    ):
        direction = "expression"
    else:
        if metrics is not None:
            metrics.inc_suggestion(ACTION_ID, "rejected")
        return

    from src.application.commands import ApplyBatchPatchCommand
    from src.backend.experience.patch import field_patch

    steps: list = []
    for c in conflicts:
        w = vocab_by_id.get(c["vocab_id"])
        e = expr_by_id.get(c["expression_id"])
        if w is None or e is None:
            continue
        if direction == "vocab":
            new_val = w.get("translation")
            if e.get("translation") == new_val:
                continue
            patch = field_patch(
                e, "translation", new_val,
                target_kind="expressions", target_id=c["expression_id"],
            )
            steps.append(("field", e, patch))
        else:
            new_val = e.get("translation")
            if w.get("translation") == new_val:
                continue
            patch = field_patch(
                w, "translation", new_val,
                target_kind="vocab", target_id=c["vocab_id"],
            )
            steps.append(("field", w, patch))
    if not steps:
        host.statusBar().showMessage("词条冲突：无需修改", 4000)
        return
    cmd = ApplyBatchPatchCommand(
        steps=steps,
        adapter=adapter,
        text=f"统一词条冲突释义（{len(steps)} 处）",
    )
    cmd.signals.changed.connect(host._on_ai_edit_applied)
    host.undo_stack.push(cmd)
    if metrics is not None:
        metrics.inc_suggestion(ACTION_ID, "applied")
    try:
        # §14.5.3: scope closed-set (count), no term/原文.
        host._record_experience_event(
            ACTION_ID,
            f"统一词条冲突 {len(steps)} 处",
            action_id=ACTION_ID,
            scope={"count": len(steps)},
        )
    except Exception:
        pass
    if hasattr(host, "_refresh_validate_after_ai"):
        try:
            host._refresh_validate_after_ai()
        except Exception:
            pass
    host.statusBar().showMessage(
        f"词条冲突：已统一 {len(steps)} 处释义（可 Ctrl+Z 撤销）", 6000
    )

handle_resolve_term_conflicts = _experience_resolve_term_conflicts


def _experience_compare_sections(host, scope: dict) -> None:
    """K-03: local two-section compare (term overlap / empty / types). Read-only."""
    from src.backend.experience.compare_sections import (
        compare_sections,
        format_compare_report,
        resolve_compare_pair,
    )

    adapter = getattr(host, "adapter", None)
    if adapter is None:
        host.statusBar().showMessage("请先打开课程", 4000)
        return

    selection = None
    multi = None
    pins = None
    try:
        ctx = host.experience.context
        if ctx is not None:
            selection = ctx.selection
            multi = getattr(ctx, "multi_selection", None)
            pins = getattr(ctx, "pinned_refs", None)
    except Exception:
        pass
    if selection is None:
        selection = getattr(host, "_current_node_ref", None)

    pair = resolve_compare_pair(
        scope,
        selection=selection,
        multi_selection=multi,
        pinned_refs=pins,
    )
    if pair is None:
        host.statusBar().showMessage(
            "请多选两个 section，或在 scope 中指定 section_ids 后再 /compare",
            6000,
        )
        return

    result = compare_sections(adapter, pair[0], pair[1])
    report = format_compare_report(result)
    if not result.ok:
        host.statusBar().showMessage(report, 6000)
        return

    try:
        host._record_experience_event(
            "compare_sections",
            f"对比 {pair[0]} vs {pair[1]}",
            action_id="course.compare_sections",
            scope={"section_ids": list(pair)},
        )
    except Exception:
        pass

    # Non-modal preferred in tests; production still shows a simple dialog.
    if getattr(host, "_compare_sections_non_modal", False):
        host._last_compare_report = report  # type: ignore[attr-defined]
        host.statusBar().showMessage(report.split("\n")[0], 8000)
        return
    safe_information(host, "对比两节课", report)

handle_compare_sections = _experience_compare_sections

def _experience_batch_set_template(host, scope: dict) -> None:
    """T-04 / P11: set ``template`` on many lessons via Batch FieldPatch (zero LLM).

    Scope keys:
    * ``lesson_ids``: list[str] (required, ≥1)
    * ``template``: str (required; must be a known template key)

    Confirms before writing (``needs_confirm`` red line). Under immersive
    full-auto ``safe_question`` auto-returns Yes via ``auto_confirm_scope``.
    """
    from src.application.commands import ApplyBatchPatchCommand
    from src.backend.experience.patch import field_patch
    from src.backend.lesson_content import TEMPLATE_LABELS

    raw_ids = scope.get("lesson_ids") or []
    if not raw_ids and scope.get("first_lesson_id"):
        raw_ids = [scope.get("first_lesson_id")]
    # Fall back to Context multi_selection / selection.
    if not raw_ids:
        try:
            ctx = host.experience.context
            if ctx is not None:
                for ref in list(getattr(ctx, "multi_selection", None) or []):
                    kind = getattr(ref, "kind", None) or (
                        ref[0] if isinstance(ref, (tuple, list)) else None
                    )
                    rid = getattr(ref, "id", None) or (
                        ref[1] if isinstance(ref, (tuple, list)) and len(ref) > 1 else None
                    )
                    if kind == "lesson" and rid:
                        raw_ids.append(str(rid))
                if not raw_ids and ctx.selection is not None and ctx.selection.kind == "lesson":
                    raw_ids = [ctx.selection.id]
        except Exception:
            pass
    lesson_ids = [str(x) for x in raw_ids if str(x)]
    template = str(scope.get("template") or "").strip()
    if not lesson_ids:
        # F9 v4.47: honest guidance for ⌘K /batch-template without multi-select.
        host.statusBar().showMessage(
            "批量课型：请先在课程树多选课时，或用树右键「批量设置课型」"
            "（⌘K /batch-template 需已有选中）",
            7000,
        )
        return
    if not template or template not in TEMPLATE_LABELS:
        host.statusBar().showMessage(
            f"批量课型：请指定 template（当前「{template or '空'}」无效；"
            f"可选：{', '.join(TEMPLATE_LABELS)}）。"
            "可在树菜单选择课型后批量应用。",
            7000,
        )
        return
    steps: list = []
    changed: list[str] = []
    for lid in lesson_ids:
        try:
            _s, _u, lesson = host.adapter.find_lesson(lid)
        except KeyError:
            continue
        if str(lesson.get("template") or "legacy") == template:
            continue
        patch = field_patch(
            lesson, "template", template, target_kind="lesson", target_id=lid
        )
        steps.append(("field", lesson, patch))
        changed.append(lid)
    if not steps:
        host.statusBar().showMessage("批量课型：无需修改（已是目标课型）", 4000)
        return
    if not safe_question(
        host,
        "批量设置课型",
        f"将把 {len(steps)} 节课的 template 设为"
        f"「{TEMPLATE_LABELS.get(template, template)}」"
        "（零 LLM，保 id，入 Undo 栈可 Ctrl+Z 撤销）。",
        default_yes=False,
    ):
        host.experience_metrics.inc_suggestion("lesson.batch_set_template", "rejected")
        return
    cmd = ApplyBatchPatchCommand(
        steps=steps,
        adapter=host.adapter,
        text=f"批量课型 → {template}（{len(steps)}）",
    )
    cmd.signals.changed.connect(host._on_ai_edit_applied)
    host.undo_stack.push(cmd)
    host.experience_metrics.inc_suggestion("lesson.batch_set_template", "applied")
    host._record_experience_event(
        "lesson.batch_set_template",
        f"批量课型 {len(steps)} 节 → {template}",
        action_id="lesson.batch_set_template",
        scope={"template": template, "count": len(steps), "lesson_ids": changed},
    )
    host.statusBar().showMessage(
        f"已批量设置课型 {TEMPLATE_LABELS.get(template, template)}（{len(steps)} 节，可 Ctrl+Z）",
        6000,
    )
    try:
        host.tree.refresh_incremental()
    except Exception:
        pass

handle_batch_set_template = _experience_batch_set_template


def _batch_polish_pairs(host, scope: dict) -> list[tuple[str, str]]:
    """Resolve (kind, id) pairs from scope, else Context multi_selection.

    Accepts ``scope["entries"]`` (list of (kind, id) pairs) and
    ``scope["entry_ids"]`` (list of "kind:id" strings, e.g. from the Dock
    suggestion). Falls back to ``ctx.multi_selection`` (V-01 wiring). Only
    vocab / expressions kinds survive; order-preserving dedupe.
    """
    pairs: list[tuple[str, str]] = []
    for e in list(scope.get("entries") or []):
        if isinstance(e, (tuple, list)) and len(e) >= 2:
            pairs.append((str(e[0] or ""), str(e[1] or "")))
    for s in list(scope.get("entry_ids") or []):
        if isinstance(s, str) and ":" in s:
            k, i = s.split(":", 1)
            pairs.append((k, i))
    if not pairs:
        try:
            ctx = host.experience.context
            for ref in list(getattr(ctx, "multi_selection", None) or []):
                kind = getattr(ref, "kind", None)
                rid = getattr(ref, "id", None)
                if kind is None and isinstance(ref, (tuple, list)) and len(ref) >= 2:
                    kind, rid = ref[0], ref[1]
                if kind and rid:
                    pairs.append((str(kind), str(rid)))
        except Exception:
            pass
    out: list[tuple[str, str]] = []
    for k, i in pairs:
        if k in ("vocab", "expressions") and i and (k, i) not in out:
            out.append((k, i))
    return out


def _experience_batch_polish(host, scope: dict) -> None:
    """V-02: batch polish selected resource entries (LLM propose + batch patch).

    scope entries / ctx.multi_selection (V-01 surface=resources) -> resolve
    live entries from the global pools -> safe_question confirm (list first
    12 terms, UI-only) -> budget guard -> AiRequestWorker runs
    ``run_batch_polish`` -> parse {(id, field): value} -> one ``FieldPatch``
    per (id, field) -> single ``ApplyBatchPatchCommand`` (preview + confirm
    + Undo). Red lines: needs_confirm + undo; 保 id (field_patch rejects id);
    field whitelist closed (translation/pronunciation/pos; pos vocab-only);
    scope closed-set ``{count}`` (§14.5.3, no term/原文 in telemetry); never
    raises (no selection / no config / LLM failure -> non-modal statusBar).
    """
    from src.backend.experience.resource_batch_skill import (
        ACTION_ID,
        run_batch_polish,
    )

    adapter = getattr(host, "adapter", None)
    if adapter is None:
        host.statusBar().showMessage("请先打开课程", 4000)
        return
    pairs = _batch_polish_pairs(host, scope or {})
    if not pairs:
        host.statusBar().showMessage(
            "批量润色：请先在资源编辑器多选词条（vocab / expressions），"
            "或用 ⌘K /polish 时已有选中",
            7000,
        )
        return
    vocab_by_id = {
        str(w.get("id") or ""): w
        for w in (getattr(adapter, "vocab", None) or [])
        if isinstance(w, dict)
    }
    expr_by_id = {
        str(e.get("id") or ""): e
        for e in (getattr(adapter, "expressions", None) or [])
        if isinstance(e, dict)
    }
    entries: list[dict] = []
    kind_by_id: dict[str, str] = {}
    for kind, rid in pairs:
        pool = vocab_by_id if kind == "vocab" else expr_by_id
        entry = pool.get(rid)
        if entry is None:
            continue
        kind_by_id[rid] = kind
        entries.append(
            {
                "id": rid,
                "kind": kind,
                "term": str(entry.get("term") or ""),
                "translation": str(entry.get("translation") or ""),
                "pronunciation": str(entry.get("pronunciation") or ""),
                "pos": str(entry.get("pos") or "") if kind == "vocab" else "",
            }
        )
    if not entries:
        host.statusBar().showMessage("批量润色：选中词条已不存在", 5000)
        return
    # Confirm: list first 12 terms (term is UI-only, not telemetry).
    sample_lines = [f"  · {e['term'] or e['id']}（{e['kind']}）" for e in entries[:12]]
    more = f"\n  … 共 {len(entries)} 个" if len(entries) > 12 else ""
    if not safe_question(host,
        "批量润色选中词条",
        "将用 AI 批量补全/润色下列词条的 translation / pronunciation / pos"
        "（字段白名单封闭，保 id，入 Undo 栈可撤销）：\n"
        + "\n".join(sample_lines)
        + more,
        default_yes=False,
        ):
        host.experience_metrics.inc_suggestion(ACTION_ID, "rejected")
        return

    config = getattr(host, "_ai_config", None)
    if config is None or not getattr(config, "is_complete", False):
        host.statusBar().showMessage("AI 配置不完整：设置 ▸ AI 填写 Key/Model", 5000)
        return
    # Budget guard (M-08): deny AI write if blocked (mirrors other AI skills).
    deny = getattr(host, "_deny_ai_write_if_blocked", None)
    if callable(deny) and deny(label="批量润色"):
        return

    lang = "Turkish"
    try:
        lang = str((getattr(adapter, "index", {}) or {}).get("language") or "")
        if lang:
            lang = lang.capitalize()
    except Exception:
        lang = "Turkish"

    job_id = "resource-batch-polish"
    tray = getattr(host, "job_tray", None)
    metrics = getattr(host, "experience_metrics", None)
    if tray is not None:
        tray.start(job_id, "批量润色：正在生成 …", kind="ai")
    if metrics is not None:
        metrics.inc_job("ai", "started")
        metrics.inc_suggestion(ACTION_ID, "accepted")
    if hasattr(host, "_refresh_experience"):
        try:
            host._refresh_experience(immediate=False, focus_only=True)
        except Exception:
            pass

    worker = host._make_ai_worker(
        run_batch_polish, config, entries, language=lang
    )

    def _on_ok(mapping: object) -> None:
        try:
            from src.application.commands import ApplyBatchPatchCommand
            from src.backend.experience.patch import field_patch

            steps: list = []
            patches = mapping if isinstance(mapping, dict) else {}
            for (rid, field), value in patches.items():
                rid = str(rid)
                field = str(field)
                kind = kind_by_id.get(rid)
                if kind is None:
                    continue
                if field == "pos" and kind != "vocab":
                    continue  # expressions 无 pos
                pool = vocab_by_id if kind == "vocab" else expr_by_id
                entry = pool.get(rid)
                if entry is None:
                    continue
                if str(entry.get(field) or "") == str(value):
                    continue
                patch = field_patch(
                    entry, field, value, target_kind=kind, target_id=rid
                )
                steps.append(("field", entry, patch))
        except Exception:
            steps = []
        if tray is not None:
            tray.finish(job_id)
        if metrics is not None:
            metrics.inc_job("ai", "finished")
        if not steps:
            host.statusBar().showMessage("批量润色：AI 未给出可用建议", 6000)
            return
        cmd = ApplyBatchPatchCommand(
            steps=steps,
            adapter=host.adapter,
            text=f"批量润色词条（{len(steps)} 处）",
        )
        cmd.signals.changed.connect(host._on_ai_edit_applied)
        host.undo_stack.push(cmd)
        if metrics is not None:
            metrics.inc_suggestion(ACTION_ID, "applied")
        try:
            # §14.5.3: scope closed-set (count), no term/原文.
            host._record_experience_event(
                ACTION_ID,
                f"批量润色 {len(steps)} 处",
                action_id=ACTION_ID,
                scope={"count": len(steps)},
            )
        except Exception:
            pass
        if hasattr(host, "_refresh_validate_after_ai"):
            try:
                host._refresh_validate_after_ai()
            except Exception:
                pass
        host.statusBar().showMessage(
            f"批量润色：已更新 {len(steps)} 处字段（可 Ctrl+Z 撤销）", 6000
        )

    def _on_err(msg: str) -> None:
        if tray is not None:
            tray.finish(job_id)
        if metrics is not None:
            metrics.inc_job("ai", "failed")
        host.statusBar().showMessage(f"批量润色失败：{msg}", 8000)

    worker.result_ready.connect(_on_ok)
    worker.error_occurred.connect(_on_err)
    worker.start()
    host._experience_worker = worker

handle_batch_polish = _experience_batch_polish


def _experience_fill_stubs_batch(host, scope: dict) -> None:
    """v4.65 B1+B2: global batch fill of stub (待补) entries via FieldPatch.

    Unlike ``resource.fill_stubs`` (whole-section merge) and
    ``resource.batch_polish`` (user multi-selection), this selects entries by
    the stub predicate (``select_stub_entries`` over the adapter's global
    vocab/expressions pools) and reuses the ``run_batch_polish`` LLM layer to
    fill translation (+pronunciation/pos). Stub tags (needs-review/auto-fix)
    are stripped after a successful fill, each via its own FieldPatch so the
    removal is Undo-able. Red lines: needs_confirm + confirm + Undo; 保 id
    (field_patch rejects id); whitelist closed; scope closed-set ``{count}``
    (§14.5.3, no term/原文); never raises (no stubs / no config / LLM failure
    -> non-modal statusBar).
    """
    # NOTE: use the fill_stubs_batch action id for metrics/events, NOT
    # resource_batch_skill.ACTION_ID (that would record resource.batch_polish).
    from src.backend.experience.resource_batch_skill import run_batch_polish
    from src.backend.experience.resource_stub_select import (
        ACTION_ID,
        select_stub_entries,
        without_stub_tags,
    )

    adapter = getattr(host, "adapter", None)
    if adapter is None:
        host.statusBar().showMessage("请先打开课程", 4000)
        return
    try:
        stubs = select_stub_entries(
            getattr(adapter, "vocab", None),
            getattr(adapter, "expressions", None),
            getattr(adapter, "grammar_points", None),
            include_grammar=False,
        )
    except Exception:
        stubs = []
    if not stubs:
        # 能 local 不 LLM: no stubs -> nothing to do, no confirm, no LLM.
        host.statusBar().showMessage("没有待补词条（translation 均已成稿）", 5000)
        return

    vocab_by_id = {
        str(w.get("id") or ""): w
        for w in (getattr(adapter, "vocab", None) or [])
        if isinstance(w, dict)
    }
    expr_by_id = {
        str(e.get("id") or ""): e
        for e in (getattr(adapter, "expressions", None) or [])
        if isinstance(e, dict)
    }
    kind_by_id = {str(s.get("id")): str(s.get("kind")) for s in stubs}

    sample_lines = [f"  · {s['term'] or s['id']}（{s['kind']}）" for s in stubs[:12]]
    more = f"\n  … 共 {len(stubs)} 个" if len(stubs) > 12 else ""
    if not safe_question(host,
        "AI 补全待补词条",
        "将用 AI 批量补全下列待补词条的 translation（vocab 顺带 "
        "pronunciation/pos），成功后剥掉 needs-review/auto-fix 标签"
        "（字段白名单封闭，保 id，入 Undo 栈可撤销）：\n"
        + "\n".join(sample_lines)
        + more,
        default_yes=False,
        ):
        host.experience_metrics.inc_suggestion(ACTION_ID, "rejected")
        return

    config = getattr(host, "_ai_config", None)
    if config is None or not getattr(config, "is_complete", False):
        host.statusBar().showMessage("AI 配置不完整：设置 ▸ AI 填写 Key/Model", 5000)
        return
    deny = getattr(host, "_deny_ai_write_if_blocked", None)
    if callable(deny) and deny(label="补全待补"):
        return

    lang = "Turkish"
    try:
        lang = str((getattr(adapter, "index", {}) or {}).get("language") or "")
        if lang:
            lang = lang.capitalize()
    except Exception:
        lang = "Turkish"

    job_id = "resource-fill-stubs-batch"
    tray = getattr(host, "job_tray", None)
    metrics = getattr(host, "experience_metrics", None)
    if tray is not None:
        tray.start(job_id, "补全待补：正在生成 …", kind="ai")
    if metrics is not None:
        metrics.inc_job("ai", "started")
        metrics.inc_suggestion(ACTION_ID, "accepted")
    if hasattr(host, "_refresh_experience"):
        try:
            host._refresh_experience(immediate=False, focus_only=True)
        except Exception:
            pass

    worker = host._make_ai_worker(run_batch_polish, config, stubs, language=lang)

    def _on_ok(mapping: object) -> None:
        try:
            from src.application.commands import ApplyBatchPatchCommand
            from src.backend.experience.patch import field_patch

            steps: list = []
            filled_ids: set[str] = set()
            patches = mapping if isinstance(mapping, dict) else {}
            for (rid, field), value in patches.items():
                rid = str(rid)
                field = str(field)
                kind = kind_by_id.get(rid)
                if kind is None:
                    continue
                if field == "pos" and kind != "vocab":
                    continue  # expressions 无 pos
                pool = vocab_by_id if kind == "vocab" else expr_by_id
                entry = pool.get(rid)
                if entry is None:
                    continue
                if str(entry.get(field) or "") == str(value):
                    continue
                patch = field_patch(
                    entry, field, value, target_kind=kind, target_id=rid
                )
                steps.append(("field", entry, patch))
                filled_ids.add(rid)
            # Strip stub tags on filled entries (Undo-able via FieldPatch).
            # without_stub_tags is pure: field_patch captures the pre-strip
            # old tags so undo restores them.
            for rid in filled_ids:
                kind = kind_by_id.get(rid)
                pool = vocab_by_id if kind == "vocab" else expr_by_id
                entry = pool.get(rid)
                if entry is None:
                    continue
                new_tags = without_stub_tags(entry)
                if new_tags is not None:
                    tag_patch = field_patch(
                        entry, "tags", new_tags,
                        target_kind=kind, target_id=rid,
                    )
                    steps.append(("field", entry, tag_patch))
        except Exception:
            steps = []
        if tray is not None:
            tray.finish(job_id)
        if metrics is not None:
            metrics.inc_job("ai", "finished")
        if not steps:
            host.statusBar().showMessage("补全待补：AI 未给出可用建议", 6000)
            return
        cmd = ApplyBatchPatchCommand(
            steps=steps,
            adapter=host.adapter,
            text=f"补全待补词条（{len(steps)} 处）",
        )
        cmd.signals.changed.connect(host._on_ai_edit_applied)
        host.undo_stack.push(cmd)
        if metrics is not None:
            metrics.inc_suggestion(ACTION_ID, "applied")
        try:
            # §14.5.3: scope closed-set (count), no term/原文.
            host._record_experience_event(
                ACTION_ID,
                f"补全待补 {len(steps)} 处",
                action_id=ACTION_ID,
                scope={"count": len(steps)},
            )
        except Exception:
            pass
        if hasattr(host, "_refresh_validate_after_ai"):
            try:
                host._refresh_validate_after_ai()
            except Exception:
                pass
        host.statusBar().showMessage(
            f"补全待补：已更新 {len(steps)} 处字段（可 Ctrl+Z 撤销）", 6000
        )

    def _on_err(msg: str) -> None:
        if tray is not None:
            tray.finish(job_id)
        if metrics is not None:
            metrics.inc_job("ai", "failed")
        host.statusBar().showMessage(f"补全待补失败：{msg}", 8000)

    worker.result_ready.connect(_on_ok)
    worker.error_occurred.connect(_on_err)
    worker.start()
    host._experience_worker = worker

handle_fill_stubs_batch = _experience_fill_stubs_batch


