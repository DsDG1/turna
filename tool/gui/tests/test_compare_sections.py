"""K-03 course.compare_sections pure + resolve + format tests."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path
from types import SimpleNamespace

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.experience.compare_sections import (  # noqa: E402
    compare_sections,
    format_compare_report,
    resolve_compare_pair,
    snapshot_section,
)
from src.backend.experience.context_bus import NodeRef  # noqa: E402
from src.backend.experience.intent_router import route_intent  # noqa: E402


def _lesson(lid: str, *, empty: bool = False, terms: list[str] | None = None) -> dict:
    if empty:
        return {"id": lid, "title": lid, "content": {}}
    items = []
    for i, t in enumerate(terms or []):
        items.append(
            {
                "id": f"{lid}-i{i}",
                "runtimeType": "showWord",
                "word": t,
            }
        )
    if not items:
        items = [{"id": f"{lid}-mcq", "runtimeType": "multipleChoice", "prompt": "x"}]
    return {
        "id": lid,
        "title": lid,
        "content": {"stages": [{"id": "st1", "items": items}]},
    }


def _section(
    sid: str,
    *,
    level: str = "A1",
    lessons: list[dict] | None = None,
    words: list[dict] | None = None,
) -> dict:
    return {
        "id": sid,
        "name": f"Section {sid}",
        "level": level,
        "words": words or [],
        "units": [{"id": f"{sid}-u1", "name": "u", "lessons": lessons or []}],
    }


class SnapshotAndCompareTest(unittest.TestCase):
    def test_identical_sections_full_overlap(self) -> None:
        words = [{"id": "w1", "term": "Merhaba"}, {"id": "w2", "term": "Günaydın"}]
        a = _section(
            "s1",
            words=words,
            lessons=[_lesson("l1", terms=["merhaba"])],
        )
        b = _section(
            "s2",
            words=list(words),
            lessons=[_lesson("l2", terms=["merhaba"])],
        )
        adapter = SimpleNamespace(sections=[a, b])
        r = compare_sections(adapter, "s1", "s2")
        self.assertTrue(r.ok)
        self.assertGreater(r.overlap_ratio, 0.5)
        self.assertIn("merhaba", r.overlap_terms)
        self.assertEqual(r.a.lesson_count, 1)
        self.assertEqual(r.b.lesson_count, 1)

    def test_no_overlap(self) -> None:
        a = _section(
            "s1",
            words=[{"id": "w1", "term": "one"}],
            lessons=[_lesson("l1", terms=["alpha"])],
        )
        b = _section(
            "s2",
            words=[{"id": "w2", "term": "two"}],
            lessons=[_lesson("l2", terms=["beta"])],
        )
        r = compare_sections(SimpleNamespace(sections=[a, b]), "s1", "s2")
        self.assertTrue(r.ok)
        self.assertEqual(r.overlap_ratio, 0.0)
        self.assertEqual(len(r.overlap_terms), 0)
        self.assertIn("one", r.only_a)
        self.assertIn("two", r.only_b)

    def test_empty_lesson_counts(self) -> None:
        a = _section("s1", lessons=[_lesson("l1", empty=True), _lesson("l2", terms=["x"])])
        b = _section("s2", lessons=[_lesson("l3", empty=True)])
        r = compare_sections(SimpleNamespace(sections=[a, b]), "s1", "s2")
        self.assertTrue(r.ok)
        self.assertEqual(r.a.empty_lesson_count, 1)
        self.assertEqual(r.a.lesson_count, 2)
        self.assertEqual(r.b.empty_lesson_count, 1)

    def test_missing_section(self) -> None:
        a = _section("s1", lessons=[_lesson("l1")])
        r = compare_sections(SimpleNamespace(sections=[a]), "s1", "missing")
        self.assertFalse(r.ok)
        self.assertIn("missing", r.error or "")

    def test_same_id_rejected(self) -> None:
        a = _section("s1")
        r = compare_sections(SimpleNamespace(sections=[a]), "s1", "s1")
        self.assertFalse(r.ok)

    def test_format_report_contains_headers(self) -> None:
        a = _section(
            "s1",
            level="A1",
            words=[{"id": "w1", "term": "hello"}],
            lessons=[_lesson("l1", terms=["hello"])],
        )
        b = _section(
            "s2",
            level="A2",
            words=[{"id": "w2", "term": "hello"}],
            lessons=[_lesson("l2", terms=["world"])],
        )
        r = compare_sections(SimpleNamespace(sections=[a, b]), "s1", "s2")
        text = format_compare_report(r)
        self.assertIn("对比：", text)
        self.assertIn("Jaccard", text)
        self.assertIn("hello", text)

    def test_snapshot_runtime_types(self) -> None:
        sec = _section(
            "s1",
            lessons=[
                _lesson("l1", terms=["a"]),
                {
                    "id": "l2",
                    "content": {
                        "stages": [
                            {
                                "items": [
                                    {"id": "i1", "runtimeType": "multipleChoice"},
                                    {"id": "i2", "runtimeType": "multipleChoice"},
                                ]
                            }
                        ]
                    },
                },
            ],
        )
        snap = snapshot_section(sec)
        self.assertGreaterEqual(snap.runtime_types.get("showWord", 0), 1)
        self.assertEqual(snap.runtime_types.get("multipleChoice"), 2)


class ResolvePairTest(unittest.TestCase):
    def test_scope_section_ids(self) -> None:
        pair = resolve_compare_pair({"section_ids": ["s1", "s2", "s3"]})
        self.assertEqual(pair, ("s1", "s2"))

    def test_scope_a_b_keys(self) -> None:
        pair = resolve_compare_pair({"section_id_a": "a", "section_id_b": "b"})
        self.assertEqual(pair, ("a", "b"))

    def test_multi_selection(self) -> None:
        multi = [NodeRef("section", "x"), NodeRef("section", "y")]
        pair = resolve_compare_pair({}, multi_selection=multi)
        self.assertEqual(pair, ("x", "y"))

    def test_selection_plus_pin(self) -> None:
        pair = resolve_compare_pair(
            {},
            selection=NodeRef("section", "s1"),
            pinned_refs=[NodeRef("section", "s9")],
        )
        self.assertEqual(pair, ("s1", "s9"))

    def test_insufficient(self) -> None:
        self.assertIsNone(resolve_compare_pair({}))
        self.assertIsNone(
            resolve_compare_pair({}, selection=NodeRef("lesson", "l1"))
        )


class RouteAndDispatchTest(unittest.TestCase):
    def test_slash_compare(self) -> None:
        intent = route_intent("/compare")
        self.assertIsNotNone(intent)
        assert intent is not None
        self.assertEqual(intent.action_id, "course.compare_sections")
        self.assertEqual(intent.confidence, 1.0)

    def test_keyword_compare(self) -> None:
        intent = route_intent("对比两节内容")
        self.assertIsNotNone(intent)
        assert intent is not None
        self.assertEqual(intent.action_id, "course.compare_sections")

    def test_dispatch_non_modal(self) -> None:
        from src.application.experience_skills_mixin import ExperienceSkillsMixin
        from src.backend.experience.metrics import ExperienceMetrics

        a = _section(
            "s1",
            words=[{"id": "w1", "term": "hi"}],
            lessons=[_lesson("l1", terms=["hi"])],
        )
        b = _section(
            "s2",
            words=[{"id": "w2", "term": "hi"}],
            lessons=[_lesson("l2", terms=["bye"])],
        )

        class Host(ExperienceSkillsMixin):
            def __init__(self) -> None:
                self.adapter = SimpleNamespace(sections=[a, b])
                self.experience = SimpleNamespace(context=None)
                self.experience_metrics = ExperienceMetrics()
                self._settings_obj = None
                self._compare_sections_non_modal = True
                self._status: list[str] = []
                self._events: list = []

            def statusBar(self):  # noqa: N802
                host = self

                class SB:
                    def showMessage(self, msg, _ms=0):  # noqa: N802
                        host._status.append(msg)

                return SB()

            def _record_experience_event(self, *a, **k):
                self._events.append((a, k))

            def _resolve_experience_policy(self, action_id=None):
                from src.backend.experience.policy import resolve_policy

                return resolve_policy(None, action_id=action_id)

        host = Host()
        host._on_experience_suggestion(
            {
                "action_id": "course.compare_sections",
                "scope": {"section_ids": ["s1", "s2"]},
            }
        )
        self.assertTrue(hasattr(host, "_last_compare_report"))
        self.assertIn("对比", host._last_compare_report)
        # Must not mutate sections.
        self.assertEqual(a["words"][0]["term"], "hi")


if __name__ == "__main__":
    unittest.main()
