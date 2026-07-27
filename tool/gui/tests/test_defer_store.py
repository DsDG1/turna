"""A3 ② DeferStore - cooldown + resurface (v4.66 P2). Pure, no Qt."""
from __future__ import annotations

import sys
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.experience.defer_store import (  # noqa: E402
    COOLDOWN_BASE,
    MAX_DISMISS,
    STORE_CAP,
    DeferRecord,
    DeferStore,
)

NOW = datetime(2026, 7, 24, 12, 0, tzinfo=timezone.utc)


class DeferStoreTest(unittest.TestCase):
    def test_add_escalating_cooldown(self) -> None:
        s = DeferStore()
        r1 = s.add("p1", "validate.open_and_fix", now=NOW)
        self.assertEqual(r1.dismiss_count, 1)
        self.assertFalse(s.is_cooled_down("p1", now=NOW))
        # 15min base: not cooled at +14m, cooled at +16m.
        self.assertFalse(s.is_cooled_down("p1", now=NOW + timedelta(minutes=14)))
        self.assertTrue(s.is_cooled_down("p1", now=NOW + timedelta(minutes=16)))
        # Second defer -> 30min cooldown from the new now.
        r2 = s.add("p1", now=NOW + timedelta(hours=1))
        self.assertEqual(r2.dismiss_count, 2)
        self.assertFalse(s.is_cooled_down("p1", now=NOW + timedelta(hours=1, minutes=29)))
        self.assertTrue(s.is_cooled_down("p1", now=NOW + timedelta(hours=1, minutes=31)))

    def test_is_cooled_down_unknown_and_permanent(self) -> None:
        s = DeferStore()
        self.assertFalse(s.is_cooled_down("nope", now=NOW))
        s.add("p1", "a", now=NOW)
        self.assertIsNotNone(s.get("p1"))

    def test_dismiss_max_permits_permanent_archive(self) -> None:
        s = DeferStore()
        s.add("p1", "a", now=NOW)
        s.add("p1", now=NOW)
        r3 = s.add("p1", now=NOW)  # dismiss_count == 3 -> permanent
        self.assertEqual(r3.dismiss_count, MAX_DISMISS)
        self.assertEqual(r3.re_surface_after_iso, "")  # permanent marker
        # Permanent record removed from the store (caller moves to session archive).
        self.assertIsNone(s.get("p1"))
        self.assertFalse(s.is_cooled_down("p1", now=NOW))

    def test_resurface_candidates_only_current_and_cooled(self) -> None:
        s = DeferStore()
        s.add("p1", "a", now=NOW)              # cools at +15m
        s.add("p2", "b", now=NOW)              # cools at +15m
        # At +16m both cooled, both still current -> both resurface.
        cand = s.resurface_candidates({"p1", "p2"}, now=NOW + timedelta(minutes=16))
        self.assertEqual(set(cand), {"p1", "p2"})
        # p2 resolved (not in current) -> only p1 resurfaces.
        cand = s.resurface_candidates({"p1"}, now=NOW + timedelta(minutes=16))
        self.assertEqual(cand, ["p1"])
        # Before cooldown -> none.
        self.assertEqual(s.resurface_candidates({"p1", "p2"}, now=NOW), [])

    def test_purge_resolved_drops_missing(self) -> None:
        s = DeferStore()
        s.add("p1", "a", now=NOW)
        s.add("p2", "b", now=NOW)
        s.purge_resolved({"p1"})
        self.assertIsNotNone(s.get("p1"))
        self.assertIsNone(s.get("p2"))

    def test_cap_fifo(self) -> None:
        s = DeferStore()
        for i in range(STORE_CAP + 5):
            s.add(f"p{i}", "a", now=NOW)
        self.assertEqual(len(s), STORE_CAP)
        # Oldest evicted, newest retained.
        self.assertIsNone(s.get("p0"))
        self.assertIsNotNone(s.get(f"p{STORE_CAP + 4}"))

    def test_never_raises_on_garbage(self) -> None:
        s = DeferStore()
        s.add("", "a", now=NOW)              # empty id
        s.add(None, "a", now=NOW)            # type: ignore[arg-type]
        s.is_cooled_down(None, now=NOW)      # type: ignore[arg-type]
        s.resurface_candidates(None, now=NOW)  # type: ignore[arg-type]
        s.purge_resolved(None)               # type: ignore[arg-type]
        s2 = DeferStore.from_dict({"records": [{"garbage": True}, "notadict", None]})
        self.assertIsInstance(s2, DeferStore)
        s3 = DeferStore.from_dict(None)
        self.assertIsInstance(s3, DeferStore)
        # Round-trip survives bad input.
        self.assertEqual(s3.to_dict(), {"records": []})

    def test_closed_set_no_raw_content(self) -> None:
        s = DeferStore()
        s.add("p1", "validate.open_and_fix", now=NOW)
        blob = s.to_dict()
        self.assertEqual(blob["records"][0].keys(), set(DeferRecord.__dataclass_fields__.keys()))
        # No title / body / raw scope / prompt anywhere in the persisted blob.
        import json

        flat = json.dumps(blob, ensure_ascii=False)
        for forbidden in ("title", "body", "prompt", "options", "expected"):
            self.assertNotIn(forbidden, flat)


if __name__ == "__main__":
    unittest.main()
