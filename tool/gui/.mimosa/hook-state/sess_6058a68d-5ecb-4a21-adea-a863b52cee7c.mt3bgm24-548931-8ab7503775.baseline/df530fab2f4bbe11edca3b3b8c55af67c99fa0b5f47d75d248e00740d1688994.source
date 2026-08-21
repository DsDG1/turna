"""T-06 rule-first semantic lesson search."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.semantic_search import (  # noqa: E402
    SEMANTIC_RULES,
    filter_lessons_query,
    filter_lessons_semantic,
    lesson_has_missing_transcript,
    lesson_has_stub_markers,
    match_semantic_rule,
)
from src.backend.overview_stats import lesson_is_empty  # noqa: E402


def _sections_fixture() -> list[dict]:
    return [
        {
            "id": "s1",
            "name": "S1",
            "units": [
                {
                    "id": "u1",
                    "name": "U1",
                    "lessons": [
                        {
                            "id": "l-empty",
                            "name": "Placeholder",
                            "template": "intro",
                            "content": {"subLessons": []},
                        },
                        {
                            "id": "l-full",
                            "name": "Greetings",
                            "template": "intro",
                            "content": {
                                "subLessons": [
                                    {
                                        "id": "sl1",
                                        "stages": [
                                            {
                                                "id": "st1",
                                                "items": [
                                                    {
                                                        "id": "q1",
                                                        "runtimeType": "showWord",
                                                        "wordId": "w1",
                                                    }
                                                ],
                                            }
                                        ],
                                    }
                                ]
                            },
                        },
                        {
                            "id": "l-listen",
                            "name": "Listen",
                            "template": "listening",
                            "content": {
                                "listeningPhases": [
                                    {
                                        "id": "p1",
                                        "items": [
                                            {
                                                "id": "q-l",
                                                "runtimeType": "listenAndPick",
                                                # missing audioAsset + transcript
                                            }
                                        ],
                                    }
                                ]
                            },
                        },
                        {
                            "id": "l-stub",
                            "name": "待补课",
                            "template": "practice",
                            "description": "TODO placeholder",
                            "content": {"stages": [{"id": "st", "items": []}]},
                        },
                    ],
                }
            ],
        }
    ]


class MatchRuleTest(unittest.TestCase):
    def test_empty_query(self) -> None:
        self.assertIsNone(match_semantic_rule(""))
        self.assertIsNone(match_semantic_rule("   "))

    def test_name_query_no_rule(self) -> None:
        # Pure lesson names should not hit a rule.
        self.assertIsNone(match_semantic_rule("Greetings"))

    def test_empty_keywords(self) -> None:
        r = match_semantic_rule("空课")
        self.assertIsNotNone(r)
        assert r is not None
        self.assertEqual(r.rule_id, "empty")

    def test_transcript_keywords(self) -> None:
        r = match_semantic_rule("缺 transcript")
        self.assertIsNotNone(r)
        assert r is not None
        self.assertEqual(r.rule_id, "missing_transcript")

    def test_stub_keywords(self) -> None:
        r = match_semantic_rule("待补")
        self.assertIsNotNone(r)
        assert r is not None
        self.assertEqual(r.rule_id, "stub")

    def test_rules_nonempty(self) -> None:
        self.assertGreaterEqual(len(SEMANTIC_RULES), 3)


class PredicateTest(unittest.TestCase):
    def test_empty_detection(self) -> None:
        sections = _sections_fixture()
        empty = sections[0]["units"][0]["lessons"][0]
        full = sections[0]["units"][0]["lessons"][1]
        self.assertTrue(lesson_is_empty(empty))
        self.assertFalse(lesson_is_empty(full))

    def test_missing_transcript(self) -> None:
        sections = _sections_fixture()
        listen = sections[0]["units"][0]["lessons"][2]
        full = sections[0]["units"][0]["lessons"][1]
        self.assertTrue(lesson_has_missing_transcript(listen))
        self.assertFalse(lesson_has_missing_transcript(full))

    def test_stub_markers(self) -> None:
        sections = _sections_fixture()
        stub = sections[0]["units"][0]["lessons"][3]
        full = sections[0]["units"][0]["lessons"][1]
        self.assertTrue(lesson_has_stub_markers(stub))
        self.assertFalse(lesson_has_stub_markers(full))


class FilterTest(unittest.TestCase):
    def test_filter_empty(self) -> None:
        sections = _sections_fixture()
        rule = match_semantic_rule("empty")
        assert rule is not None
        hits = filter_lessons_semantic(sections, rule)
        ids = {l["id"] for _s, _u, l in hits}
        self.assertIn("l-empty", ids)
        self.assertNotIn("l-full", ids)

    def test_filter_query_semantic(self) -> None:
        sections = _sections_fixture()
        matches, rule = filter_lessons_query(sections, text="听力缺口")
        self.assertIsNotNone(rule)
        ids = {l["id"] for _s, _u, l in matches}
        self.assertIn("l-listen", ids)

    def test_filter_query_name_fallback(self) -> None:
        sections = _sections_fixture()
        matches, rule = filter_lessons_query(sections, text="Greetings")
        self.assertIsNone(rule)
        ids = {l["id"] for _s, _u, l in matches}
        self.assertEqual(ids, {"l-full"})

    def test_safe_empty_sections(self) -> None:
        matches, rule = filter_lessons_query([], text="空课")
        self.assertEqual(matches, [])
        self.assertIsNotNone(rule)


if __name__ == "__main__":
    unittest.main()
