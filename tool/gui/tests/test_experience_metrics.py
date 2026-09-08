"""C-14 ExperienceMetrics pure model tests + C-15 export helpers (no Qt)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.experience import ExperienceMetrics  # noqa: E402
from src.backend.experience.job_registry import (  # noqa: E402
    JOB_KIND_AI,
    JOB_KIND_LOCAL,
    JOB_KIND_VALIDATE,
)


class ExperienceMetricsTest(unittest.TestCase):
    def test_fresh_starts_zero(self) -> None:
        m = ExperienceMetrics()
        self.assertIsNone(m.interception_rate())
        self.assertIsNone(m.apply_rate())
        self.assertEqual(len(m), 0)
        snap = m.snapshot()
        self.assertEqual(snap["intent"], {"resolved": 0, "fell_through": 0})
        for st in ("shown", "accepted", "applied", "rejected"):
            self.assertEqual(snap["suggestion_totals"][st], 0)

    def test_intent_counts_and_rate(self) -> None:
        m = ExperienceMetrics()
        for _ in range(3):
            m.inc_intent_resolved()
        m.inc_intent_fell_through()
        self.assertEqual(m.interception_rate(), 0.75)
        snap = m.snapshot()
        self.assertAlmostEqual(snap["interception_rate"], 0.75)
        self.assertEqual(snap["intent"], {"resolved": 3, "fell_through": 1})

    def test_interception_rate_none_when_no_data(self) -> None:
        m = ExperienceMetrics()
        m.inc_intent_resolved()
        # only resolved, no fell_through → still a valid rate of 1.0
        self.assertEqual(m.interception_rate(), 1.0)
        m.clear()
        self.assertIsNone(m.interception_rate())

    def test_suggestion_per_action_and_totals(self) -> None:
        m = ExperienceMetrics()
        m.inc_suggestion("resource.fill_stubs", "shown")
        m.inc_suggestion("resource.fill_stubs", "shown")
        m.inc_suggestion("resource.fill_stubs", "accepted")
        m.inc_suggestion("resource.fill_stubs", "applied")
        m.inc_suggestion("listening.fill_gaps", "shown")
        m.inc_suggestion("listening.fill_gaps", "accepted")
        m.inc_suggestion("listening.fill_gaps", "rejected")
        totals = m.suggestion_totals()
        self.assertEqual(totals["shown"], 3)
        self.assertEqual(totals["accepted"], 2)
        self.assertEqual(totals["applied"], 1)
        self.assertEqual(totals["rejected"], 1)
        # apply_rate = applied / accepted across all actions
        self.assertEqual(m.apply_rate(), 0.5)

    def test_apply_rate_none_when_no_accepted(self) -> None:
        m = ExperienceMetrics()
        m.inc_suggestion("resource.fill_stubs", "shown")
        m.inc_suggestion("resource.fill_stubs", "applied")
        # applied but no accepted → denominator 0 → None (no spurious rate)
        self.assertIsNone(m.apply_rate())

    def test_apply_rate_capped_at_one(self) -> None:
        m = ExperienceMetrics()
        m.inc_suggestion("a", "accepted")
        m.inc_suggestion("a", "applied")
        m.inc_suggestion("a", "applied")  # applied > accepted
        self.assertEqual(m.apply_rate(), 1.0)

    def test_ambient_guard_soft_counts(self) -> None:
        m = ExperienceMetrics()
        m.inc_ambient("shown")
        m.inc_ambient("shown")
        m.inc_ambient("muted")
        m.inc_ambient("dismissed")
        m.inc_ambient("accepted")
        m.inc_ambient("deferred")
        m.inc_ambient("resurfaced")
        m.inc_guard("rejected")
        m.inc_guard("released")
        m.inc_soft("evaluated")
        m.inc_soft("applied")
        m.inc_soft("skipped")
        snap = m.snapshot()
        self.assertEqual(
            snap["ambient"],
            {
                "shown": 2,
                "muted": 1,
                "dismissed": 1,
                "accepted": 1,
                "deferred": 1,
                "resurfaced": 1,
            },
        )
        self.assertEqual(snap["guard"], {"rejected": 1, "released": 1})
        self.assertEqual(
            snap["soft"],
            {"evaluated": 1, "applied": 1, "skipped": 1},
        )

    def test_job_kinds(self) -> None:
        m = ExperienceMetrics()
        m.inc_job(JOB_KIND_AI, "started")
        m.inc_job(JOB_KIND_AI, "finished")
        m.inc_job(JOB_KIND_VALIDATE, "started")
        m.inc_job(JOB_KIND_VALIDATE, "finished")
        m.inc_job(JOB_KIND_VALIDATE, "failed")
        m.inc_job(JOB_KIND_LOCAL, "started")
        snap = m.snapshot()
        self.assertEqual(snap["job"]["ai"], {"started": 1, "finished": 1})
        self.assertEqual(
            snap["job"]["validate"],
            {"started": 1, "finished": 1, "failed": 1},
        )
        self.assertEqual(snap["job"]["local"], {"started": 1})

    def test_bad_input_never_raises(self) -> None:
        m = ExperienceMetrics()
        # bad stages / kinds are dropped, not stored
        m.inc_suggestion("resource.fill_stubs", "bogus")
        m.inc_ambient("bogus")
        m.inc_guard("bogus")
        m.inc_job("bogus-kind", "started")
        m.inc_job(JOB_KIND_AI, "bogus")
        m.inc_soft("bogus")
        snap = m.snapshot()
        self.assertEqual(snap["suggestion_totals"], {
            "shown": 0, "accepted": 0, "applied": 0, "rejected": 0,
        })
        self.assertEqual(snap["ambient"], {
            "shown": 0, "muted": 0, "dismissed": 0, "accepted": 0,
            "deferred": 0, "resurfaced": 0,
        })
        self.assertEqual(snap["guard"], {"rejected": 0, "released": 0})
        self.assertEqual(snap["job"], {})
        self.assertEqual(
            snap["soft"], {"evaluated": 0, "applied": 0, "skipped": 0}
        )
        # normalization: falsy action_id coerces to "unknown" bucket
        m.inc_suggestion("", "shown")
        m.inc_suggestion(None, "shown")
        self.assertEqual(m.snapshot()["suggestion_by_action"].get("unknown"), {"shown": 2})

    def test_clear_resets_all(self) -> None:
        m = ExperienceMetrics()
        m.inc_intent_resolved()
        m.inc_suggestion("a", "shown")
        m.inc_ambient("shown")
        m.inc_guard("released")
        m.inc_job(JOB_KIND_AI, "started")
        m.inc_soft("evaluated")
        m.clear()
        self.assertEqual(len(m), 0)
        self.assertIsNone(m.interception_rate())
        self.assertIsNone(m.apply_rate())
        snap = m.snapshot()
        self.assertEqual(snap["intent"], {"resolved": 0, "fell_through": 0})
        self.assertEqual(snap["suggestion_by_action"], {})

    def test_snapshot_is_json_safe_and_independent(self) -> None:
        import json

        m = ExperienceMetrics()
        m.inc_suggestion("a", "shown")
        m.inc_job(JOB_KIND_AI, "started")
        snap = m.snapshot()
        blob = json.dumps(snap, ensure_ascii=False, sort_keys=True)
        self.assertIn("interception_rate", blob)
        # mutating the snapshot must not affect internal state
        snap["intent"]["resolved"] = 999
        snap["job"]["ai"]["started"] = 999
        self.assertEqual(m.snapshot()["intent"]["resolved"], 0)
        self.assertEqual(m.snapshot()["job"]["ai"]["started"], 1)


class ExperienceMetricsC15HelpersTest(unittest.TestCase):
    """C-15 pure helpers: activity gate, course attribution, export, usage map."""

    def test_is_metrics_active_false_when_empty(self) -> None:
        from src.backend.experience.metrics import is_metrics_active

        m = ExperienceMetrics()
        self.assertFalse(is_metrics_active(m.snapshot()))
        self.assertFalse(is_metrics_active(None))
        self.assertFalse(is_metrics_active({}))
        self.assertFalse(is_metrics_active("nope"))

    def test_is_metrics_active_true_on_any_counter(self) -> None:
        from src.backend.experience.metrics import is_metrics_active

        m = ExperienceMetrics()
        m.inc_intent_resolved()
        self.assertTrue(is_metrics_active(m.snapshot()))
        m.clear()
        m.inc_suggestion("a", "shown")
        self.assertTrue(is_metrics_active(m.snapshot()))

    def test_course_attribution_privacy(self) -> None:
        from src.backend.experience.metrics import course_attribution

        home = Path.home() / "secret-user" / "courses" / "turkish-a1"
        attr = course_attribution(home)
        self.assertEqual(attr.get("course_name"), "turkish-a1")
        self.assertEqual(len(attr.get("course_key", "")), 12)
        blob = str(attr)
        self.assertNotIn("secret-user", blob)
        self.assertNotIn(str(Path.home()), blob)
        self.assertEqual(course_attribution(None), {})
        self.assertEqual(course_attribution(""), {})

    def test_export_snapshot_closed_keys(self) -> None:
        from src.backend.experience.metrics import export_snapshot

        m = ExperienceMetrics()
        m.inc_intent_resolved()
        m.inc_suggestion("resource.fill_stubs", "shown")
        raw = m.snapshot()
        raw["api_key"] = "sk-secret"  # must not survive export
        raw["prompt"] = "system full text"
        out = export_snapshot(raw)
        assert out is not None
        self.assertNotIn("api_key", out)
        self.assertNotIn("prompt", out)
        self.assertIn("intent", out)
        self.assertEqual(out["intent"]["resolved"], 1)
        self.assertIsNone(export_snapshot(None))
        self.assertIsNone(export_snapshot("x"))

    def test_usage_today_from_summary(self) -> None:
        from src.backend.experience.metrics import usage_today_from_summary

        summary = {
            "today": {
                "requests": 3,
                "success": 2,
                "failure": 1,
                "prompt_tokens": 100,
                "completion_tokens": 50,
                "total_tokens": 150,
                "estimated_cost": 0.01,
                "currency": "CNY",
            },
            "total": {"requests": 9},
        }
        out = usage_today_from_summary(summary)
        self.assertEqual(out["requests"], 3)
        self.assertEqual(out["total_tokens"], 150)
        self.assertNotIn("estimated_cost", out)
        self.assertNotIn("currency", out)
        self.assertEqual(usage_today_from_summary(None), {})


if __name__ == "__main__":
    unittest.main()