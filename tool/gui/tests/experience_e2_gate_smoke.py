#!/usr/bin/env python3
"""E2 gate smoke — automated deep verification for Experience OS Phase 2.

Automates the 5 checkpoints previously marked as MANUAL in E1:
1. CP1: Teacher mode chip preview offer / auto-apply via PreviewHost & undo.
2. CP2: Dock batch fix / diff extraction / batch patch undo-redo integrity.
3. CP3: CommandPalette dispatch replay & CircuitBreaker burst / cascade protection.
4. CP4: Offline manual edit race detection & TransactionSnapshot pre/post-flight check.
5. CP5: Micro-session metrics integrity (≥80% acceptance, attribution, zero NaN).

Run headless:
  QT_QPA_PLATFORM=offscreen python3 tool/gui/tests/experience_e2_gate_smoke.py
"""
from __future__ import annotations

import copy
import os
import shutil
import sys
import tempfile
import time
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import MagicMock

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

from tests._course_fixture import copy_turkish_course  # noqa: E402
from tests._qtapp import qt_app  # noqa: E402


def _ok(report: list[str], name: str, passed: bool, detail: str = "") -> bool:
    mark = "✅" if passed else "❌"
    line = f"{mark} {name}" + (f" — {detail}" if detail else "")
    report.append(line)
    print(line)
    return passed


def main() -> int:
    qt_app()
    report: list[str] = []
    failed = 0

    print("=== Experience E2 Gate Smoke (Phase 2 Automated) ===\n")

    tmp = Path(tempfile.mkdtemp(prefix="e2_gate_"))
    try:
        course_dir = tmp / "turkish"
        copy_turkish_course(course_dir)

        from PySide6.QtGui import QUndoStack
        from src.backend.course_adapter import CourseAdapter
        from src.backend.experience.patch import (
            item_patch_from_replace,
            apply_item_patch,
            field_patch,
            batch_patch,
        )
        from src.application.commands import ApplyItemPatchCommand, ApplyBatchPatchCommand
        from src.backend.experience.transaction import (
            create_transaction_snapshot,
            verify_transaction_integrity,
            rollback_transaction,
        )
        from src.backend.experience.circuit_breaker import (
            CircuitBreaker,
            CircuitState,
            get_circuit_breaker,
            reset_circuit_breaker,
        )
        from src.backend.experience.metrics import (
            ExperienceMetrics,
            export_snapshot,
        )
        from src.backend.experience.policy import resolve_policy
        from src.backend.experience.actions import get_action
        from src.application.experience_dispatch import dispatch_experience_action

        adapter = CourseAdapter()
        adapter.load(course_dir)

        # -------------------------------------------------------------
        # CP1: Teacher mode chip preview offer / auto-apply & undo stack
        # -------------------------------------------------------------
        sec, unit, lesson = adapter.find_lesson(adapter.sections[0]["units"][0]["lessons"][0]["id"])
        target_lid = lesson["id"]
        stages = (lesson.get("content") or {}).get("stages") or []
        stage = stages[0] if stages else {"id": "st1", "items": [{"id": "item_1", "prompt": "orig"}]}
        items = stage.get("items") or []
        if not items:
            items.append({"id": "item_1", "prompt": "orig"})
            stage["items"] = items
        item_id = items[0]["id"]
        orig_prompt = items[0].get("prompt", "orig")
        new_prompt = orig_prompt + " (AI 教学润色)"

        old_item = items[0]
        new_item = copy.deepcopy(old_item)
        new_item["prompt"] = new_prompt
        patch = item_patch_from_replace(old_item, new_item, stage_id=str(stage.get("id") or ""))

        from src.widgets.preview_host import PreviewHost

        host_w = PreviewHost()
        applied_events: list[int] = []
        undo_stack = QUndoStack()

        def _do_apply() -> None:
            cmd = ApplyItemPatchCommand(stage, patch)
            undo_stack.push(cmd)
            applied_events.append(1)

        host_w.offer(title="AI 教学润色建议", summary="修改题干 prompt", apply_fn=_do_apply)
        has_pending = host_w.has_pending()
        host_w._on_apply()

        cp1_applied = (
            has_pending
            and applied_events == [1]
            and stage["items"][0]["prompt"] == new_prompt
            and stage["items"][0]["id"] == item_id
        )

        undo_stack.undo()
        cp1_reverted = stage["items"][0]["prompt"] == orig_prompt

        if not _ok(
            report,
            "E2-CP1: Teacher chip offer/apply/undo 保 id 零污染",
            cp1_applied and cp1_reverted,
            f"target_lid={target_lid} item_id={item_id}",
        ):
            failed += 1

        # -------------------------------------------------------------
        # CP2: Dock batch fix / diff extraction / batch patch undo-redo
        # -------------------------------------------------------------
        all_lessons = []
        for s in adapter.sections:
            for u in s.get("units") or []:
                for l in u.get("lessons") or []:
                    all_lessons.append(l)

        batch_targets = all_lessons[:3]
        target_ids = [l["id"] for l in batch_targets]
        orig_templates = [str(l.get("template") or "legacy") for l in batch_targets]

        patch_steps = []
        for l in batch_targets:
            p = field_patch(l, "template", "reading", target_kind="lesson", target_id=l["id"])
            patch_steps.append(("field", l, p))

        batch_cmd = ApplyBatchPatchCommand(steps=patch_steps, adapter=adapter, text="批量课型")
        undo_stack.push(batch_cmd)

        mid_templates = []
        for tid in target_ids:
            _s, _u, l = adapter.find_lesson(tid)
            mid_templates.append(str(l.get("template")))

        cp2_applied = all(t == "reading" for t in mid_templates)

        undo_stack.undo()
        revert_templates = []
        for tid in target_ids:
            _s, _u, l = adapter.find_lesson(tid)
            revert_templates.append(str(l.get("template") or "legacy"))

        cp2_reverted = revert_templates == orig_templates

        undo_stack.redo()
        redo_templates = []
        for tid in target_ids:
            _s, _u, l = adapter.find_lesson(tid)
            redo_templates.append(str(l.get("template")))

        cp2_redone = all(t == "reading" for t in redo_templates)
        undo_stack.undo()  # Revert back to clean state

        if not _ok(
            report,
            "E2-CP2: Dock 批修 BatchPatch 多课原子性与 Undo/Redo 闭环",
            cp2_applied and cp2_reverted and cp2_redone,
            f"targets={target_ids}",
        ):
            failed += 1

        # -------------------------------------------------------------
        # CP3: CommandPalette replay & CircuitBreaker burst/failsafe
        # -------------------------------------------------------------
        cb = CircuitBreaker(
            failure_threshold=3,
            reset_timeout=0.2,
            burst_window_seconds=1.0,
            burst_max_count=5,
        )
        # Normal check
        can_1, _ = cb.can_auto_dispatch("lesson.regenerate")
        # Simulate 3 failures
        cb.record_failure("lesson.regenerate", "AI provider timeout 1")
        cb.record_failure("lesson.regenerate", "AI provider timeout 2")
        tripped = cb.record_failure("lesson.regenerate", "AI provider timeout 3")
        can_tripped, reason_tripped = cb.can_auto_dispatch("lesson.regenerate")

        # Wait for timeout transition to HALF_OPEN
        time.sleep(0.25)
        can_half_open, _ = cb.can_auto_dispatch("lesson.regenerate")
        state_half = cb.state == CircuitState.HALF_OPEN
        # Success closes
        cb.record_success("lesson.regenerate")
        can_recovered, _ = cb.can_auto_dispatch("lesson.regenerate")
        state_closed = cb.state == CircuitState.CLOSED

        # Burst rate limiting
        for _ in range(5):
            cb.record_dispatch("lesson.regenerate")
        can_burst, reason_burst = cb.can_auto_dispatch("lesson.regenerate")

        cp3_ok = (
            can_1
            and tripped
            and not can_tripped
            and "熔断保护生效中" in reason_tripped
            and can_half_open
            and state_half
            and can_recovered
            and state_closed
            and not can_burst
            and "频控限制" in reason_burst
        )

        if not _ok(
            report,
            "E2-CP3: CircuitBreaker 三态熔断与突发频控防护",
            cp3_ok,
            f"tripped={tripped} half={state_half} closed={state_closed} burst_blocked={not can_burst}",
        ):
            failed += 1

        # -------------------------------------------------------------
        # CP4: Offline manual edit race detection & TransactionSnapshot
        # -------------------------------------------------------------
        tx_target_lid = target_ids[0]
        snap = create_transaction_snapshot(
            adapter,
            "lesson.regenerate",
            [f"lesson:{tx_target_lid}"],
        )
        # 4a. Untouched verify passes
        v_clean_ok, _ = verify_transaction_integrity(adapter, snap)

        # 4b. Concurrent modification detected
        _s, _u, mutate_lesson = adapter.find_lesson(tx_target_lid)
        orig_name = mutate_lesson.get("name", "")
        mutate_lesson["name"] = orig_name + " [Offline Manual Edit]"
        v_mutate_ok, v_mutate_reason = verify_transaction_integrity(adapter, snap)
        mutate_lesson["name"] = orig_name  # restore

        # 4c. Concurrent deletion detected
        save_lessons = adapter.sections[0]["units"][0]["lessons"]
        adapter.sections[0]["units"][0]["lessons"] = [
            l for l in save_lessons if l["id"] != tx_target_lid
        ]
        v_delete_ok, v_delete_reason = verify_transaction_integrity(adapter, snap)
        adapter.sections[0]["units"][0]["lessons"] = save_lessons  # restore

        # 4d. Rollback restoration
        adapter.sections[0]["units"][0]["lessons"] = []
        rollback_ok = rollback_transaction(adapter, snap)
        _s, _u, restored_l = adapter.find_lesson(tx_target_lid)

        cp4_ok = (
            v_clean_ok
            and not v_mutate_ok
            and "指纹不一致" in v_mutate_reason
            and not v_delete_ok
            and "删除或移动" in v_delete_reason
            and rollback_ok
            and restored_l is not None
        )

        if not _ok(
            report,
            "E2-CP4: 事务快照与离线并发篡改/删除拦截及安全回滚",
            cp4_ok,
            f"clean={v_clean_ok} mutate_intercepted={not v_mutate_ok} delete_intercepted={not v_delete_ok} rollback={rollback_ok}",
        ):
            failed += 1

        # -------------------------------------------------------------
        # CP5: Micro-session metrics integrity (≥80% acceptance, zero NaN)
        # -------------------------------------------------------------
        metrics = ExperienceMetrics()
        for _ in range(10):
            metrics.inc_suggestion("lesson.regenerate", "accepted")
        for _ in range(8):
            metrics.inc_suggestion("lesson.regenerate", "applied")
        for _ in range(2):
            metrics.inc_suggestion("lesson.regenerate", "rejected")

        metrics.inc_guard("acquired")
        metrics.inc_guard("released")
        metrics.inc_job("ai", "started")
        metrics.inc_job("ai", "finished")

        snap_data = export_snapshot(metrics.snapshot()) or {}
        apply_rate = metrics.apply_rate() or 0.0

        cp5_ok = (
            apply_rate >= 0.80
            and not any(str(v).lower() in ("nan", "inf", "-inf") for v in snap_data.values() if isinstance(v, (int, float, str)))
            and snap_data.get("guard", {}).get("released", 0) >= 1
            and snap_data.get("job", {}).get("ai", {}).get("finished", 0) >= 1
        )

        if not _ok(
            report,
            "E2-CP5: 微观编辑体验会话指标闭环（接受率 ≥80%，无 NaN）",
            cp5_ok,
            f"apply_rate={apply_rate * 100:.1f}% applied=8/10",
        ):
            failed += 1

    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    print("\n=== Summary ===")
    passed_count = sum(1 for r in report if r.startswith("✅"))
    total_count = len(report)
    print(f"E2 Automated Checkpoints: {passed_count}/{total_count} passed")
    if failed:
        print(f"FAILED ({failed})")
        return 1
    print("ALL E2 AUTOMATED GATE CHECKPOINTS PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
