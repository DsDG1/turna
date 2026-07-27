"""O-13: save atomicity + AI mid-failure dirty-disk guards (§13.6 matrix).

Full adversarial map (D1–D20) lives in ``test_adversarial_matrix.py``.
This file owns O-13 save/job/guard edges plus residual D1/D6 anchors:

| ID | Scenario | Covered by |
|----|----------|------------|
| D1 | Patch 换题改 id | ``test_experience_patch`` + this file residual |
| D2 | 无 preview merge | ``test_adversarial_matrix`` + registry |
| D5 | Soft 不改 id | ``test_soft_autopilot`` |
| D6 | finish 错误 job_id | this file + ``test_job_registry`` |
| O13-batch | batch 中途失败全回滚 | ``test_experience_patch.BatchPatchTest`` |
| O13-disk | replace 失败不脏盘 | ``test_save_atomicity`` |
| O13-soft | Soft 抛错不挡保存 | ``test_save_pipeline`` + this file edge |
| O13-ai | AI 失败 finish+release | this file host simulation |

Does not construct MainWindow. Prefer pure / duck-typed hosts.
"""
from __future__ import annotations

import sys
import unittest
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.application.save_pipeline import (  # noqa: E402
    REASON_MENU,
    SaveRequest,
    run_save_pipeline,
)
from src.backend.experience.conflict_guard import ConflictGuard  # noqa: E402
from src.backend.experience.job_registry import JOB_KIND_AI, JobRegistry  # noqa: E402
from src.backend.experience.patch import (  # noqa: E402
    LessonPatch,
    PatchError,
    apply_resolved_batch,
    field_patch,
    item_patch_from_replace,
)


@dataclass
class _FakeSaveResult:
    ok: bool
    message: str = ""
    errors: list[dict[str, Any]] = field(default_factory=list)


class SoftPlusSaveEdgeTest(unittest.TestCase):
    def test_soft_error_then_validation_failure_still_fails(self) -> None:
        """Soft boom must not mask structural red: after_failure + soft_error."""
        soft_errs: list[str] = []
        failures: list = []

        outcome = run_save_pipeline(
            SaveRequest(reason=REASON_MENU, run_soft=True),
            do_save=lambda: _FakeSaveResult(
                ok=False,
                message="校验失败，已回滚",
                errors=[{"level": "error", "message": "bad"}],
            ),
            apply_soft=lambda: (_ for _ in ()).throw(RuntimeError("soft boom")),
            on_soft_error=lambda e: soft_errs.append(str(e)),
            after_success=lambda o: self.fail("must not succeed"),
            after_failure=lambda o: failures.append(o),
        )
        self.assertFalse(outcome.ok)
        self.assertEqual(outcome.blocked_reason, "validation")
        self.assertIn("soft boom", outcome.soft_error or "")
        self.assertEqual(len(failures), 1)
        self.assertEqual(len(soft_errs), 1)


class JobAndGuardFailureTest(unittest.TestCase):
    def test_finish_wrong_job_id_does_not_clear_others(self) -> None:
        """D6: finish(wrong) → false; sibling jobs remain."""
        reg = JobRegistry()
        reg.start("chip-1", "改题", kind=JOB_KIND_AI, node_key="item:q1")
        reg.start("chip-2", "改题2", kind=JOB_KIND_AI, node_key="item:q2")
        self.assertFalse(reg.finish("chip-missing"))
        self.assertEqual(reg.count(), 2)
        self.assertTrue(reg.is_busy_ai())
        self.assertTrue(reg.finish("chip-1"))
        self.assertEqual(reg.count(), 1)

    def test_ai_worker_failure_path_finishes_job_and_releases_guard(self) -> None:
        """Simulates chip/worker finally: finish_job + release even on error."""
        reg = JobRegistry()
        guard = ConflictGuard()
        node_key = "item:q1"
        job_id = "chip-q1"
        self.assertTrue(guard.try_acquire(node_key, job_id, label="改题"))
        self.assertTrue(reg.start(job_id, "改题", kind=JOB_KIND_AI, node_key=node_key))

        worker_error: Exception | None = RuntimeError("LLM 4xx")
        try:
            if worker_error:
                raise worker_error
        except Exception:
            pass
        finally:
            reg.finish(job_id)
            guard.release(node_key, job_id)

        self.assertEqual(reg.count(), 0)
        self.assertFalse(reg.is_busy_ai())
        # Node free for next job.
        self.assertTrue(guard.try_acquire(node_key, "chip-q1-retry", label="retry"))
        guard.release(node_key, "chip-q1-retry")

    def test_guard_reject_second_job_same_node(self) -> None:
        guard = ConflictGuard()
        self.assertTrue(guard.try_acquire("lesson:l1", "job-a"))
        self.assertFalse(guard.try_acquire("lesson:l1", "job-b"))
        guard.release("lesson:l1", "job-a")
        self.assertTrue(guard.try_acquire("lesson:l1", "job-b"))


class BatchAndIdGuardsTest(unittest.TestCase):
    def test_batch_field_mid_failure_rolls_back(self) -> None:
        """Complement lesson-batch rollback with field step failure."""
        lesson = {"id": "l1", "name": "A", "template": "intro"}
        fp_ok = field_patch(lesson, "name", "B", target_kind="lesson")
        unit = {"id": "u1", "lessons": [lesson]}
        lp_bad = LessonPatch(
            lesson_id="nope",
            old_lesson={"id": "nope"},
            new_lesson={"id": "nope", "name": "x"},
        )
        with self.assertRaises(PatchError):
            apply_resolved_batch(
                [
                    ("field", lesson, fp_ok),
                    ("lesson", unit, lp_bad),
                ]
            )
        self.assertEqual(lesson["name"], "A")

    def test_item_patch_forces_id(self) -> None:
        """D1 residual: item_patch_from_replace keeps original id."""
        item = {"id": "q1", "runtimeType": "multipleChoice", "prompt": "old"}
        patch = item_patch_from_replace(
            item,
            {"id": "HACKED", "runtimeType": "multipleChoice", "prompt": "new"},
        )
        self.assertEqual(patch.item_id, "q1")
        self.assertEqual(patch.new_item.get("id"), "q1")


if __name__ == "__main__":
    unittest.main()
