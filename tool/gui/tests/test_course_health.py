"""P0-1: course health audit + repair worklist (pure Python)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.application.course_health_service import CourseHealthService
from src.backend.course_health import audit_course, build_repair_plan
from src.backend.experience.actions import ACTIONS


def _show_word(lesson_id: str, word_id: str) -> dict:
    return {
        "id": lesson_id,
        "name": lesson_id,
        "template": "intro",
        "content": {
            "subLessons": [
                {
                    "id": f"{lesson_id}-sub",
                    "stages": [
                        {
                            "id": f"{lesson_id}-stage",
                            "items": [
                                {
                                    "id": f"{lesson_id}-item",
                                    "runtimeType": "showWord",
                                    "wordId": word_id,
                                }
                            ],
                        }
                    ],
                }
            ]
        },
    }


def _section(section_id: str = "s1") -> dict:
    return {
        "id": section_id,
        "name": "Basics",
        "level": "A1",
        "words": [{"id": "w1", "term": "kitap", "translation": "书"}],
        "grammarPoints": [{"id": "g1", "title": "复数"}],
        "units": [
            {
                "id": "u1",
                "name": "Unit 1",
                "lessons": [
                    {
                        "id": "l-empty",
                        "name": "空课",
                        "template": "practice",
                        "content": {},
                    },
                    _show_word("l-intro", "w1"),
                    {
                        "id": "l-read",
                        "name": "阅读",
                        "template": "reading",
                        "content": {},
                    },
                    {
                        "id": "l-listen",
                        "name": "听力",
                        "template": "listening",
                        "content": {
                            "listeningPhases": [
                                {
                                    "id": "p1",
                                    "type": "wordPairing",
                                    "items": [
                                        {
                                            "id": "i1",
                                            "runtimeType": "listenAndPick",
                                        }
                                    ],
                                }
                            ]
                        },
                    },
                ],
            }
        ],
    }


class _Adapter:
    def __init__(self, sections: list[dict]) -> None:
        self.sections = sections
        self.vocab = []
        self.expressions = []
        self.grammar_points = []
        self.index = {"level": "A1"}

    @staticmethod
    def detect_duplicates() -> list[dict]:
        return []


class AuditCourseTest(unittest.TestCase):
    def test_finds_structural_gaps(self) -> None:
        findings = audit_course([_section()], default_level="A1")
        kinds = {f.kind for f in findings}

        self.assertIn("empty_lesson", kinds)
        self.assertIn("spiral_gap", kinds)
        self.assertIn("reading_empty", kinds)
        self.assertIn("listening_audio_gap", kinds)
        self.assertIn("grammar_uncovered", kinds)

    def test_empty_lesson_scope_and_action(self) -> None:
        findings = audit_course([_section()], default_level="A1")
        empty = next(f for f in findings if f.kind == "empty_lesson")

        self.assertEqual(empty.action_id, "lesson.fill_empty")
        self.assertEqual(empty.scope["lesson_id"], "l-empty")
        self.assertEqual(empty.scope["section_id"], "s1")
        self.assertEqual(empty.severity, "warning")

    def test_findings_are_deterministic(self) -> None:
        first = [f.finding_id for f in audit_course([_section()], default_level="A1")]
        second = [f.finding_id for f in audit_course([_section()], default_level="A1")]

        self.assertEqual(first, second)

    def test_malformed_course_never_raises(self) -> None:
        findings = audit_course(
            [None, {}, {"id": "x", "units": "not-a-list"}],  # type: ignore[list-item]
            default_level="A1",
        )

        self.assertIsInstance(findings, list)

    def test_duplicate_and_conflict_findings(self) -> None:
        findings = audit_course(
            [_section()],
            default_level="A1",
            duplicates=[{"term": "kitap"}],
            term_conflicts={"count": 2, "conflicts": []},
        )
        kinds = {f.kind for f in findings}

        self.assertIn("duplicate_term", kinds)
        self.assertIn("term_conflict", kinds)


class RepairPlanTest(unittest.TestCase):
    def test_plan_maps_to_existing_actions(self) -> None:
        steps = build_repair_plan(audit_course([_section()], default_level="A1"))

        self.assertTrue(steps)
        self.assertEqual(
            [s.step_id for s in steps],
            [f"step-{i:02d}" for i in range(1, len(steps) + 1)],
        )
        for step in steps:
            self.assertIn(step.action_id, ACTIONS)
            self.assertTrue(step.needs_confirm)

    def test_same_action_and_scope_is_grouped(self) -> None:
        findings = audit_course([_section()], default_level="A1")
        empty = [f for f in findings if f.kind == "empty_lesson"]
        self.assertGreaterEqual(len(empty), 1)

        steps = build_repair_plan([empty[0], empty[0]])
        matching = [s for s in steps if s.action_id == "lesson.fill_empty"]
        self.assertEqual(len(matching), 1)
        self.assertEqual(len(matching[0].finding_ids), 2)

    def test_limit_caps_steps(self) -> None:
        steps = build_repair_plan(
            audit_course([_section()], default_level="A1"), limit=2
        )

        self.assertLessEqual(len(steps), 2)

    def test_local_only_findings_are_not_planned(self) -> None:
        findings = audit_course([_section()], default_level="A1")
        grammar = next(f for f in findings if f.kind == "grammar_uncovered")
        self.assertEqual(grammar.action_id, "")

        steps = build_repair_plan(findings)
        self.assertNotIn("grammar_uncovered", [s.action_id for s in steps])


class CourseHealthServiceTest(unittest.TestCase):
    def test_report_shape_and_action_titles(self) -> None:
        report = CourseHealthService(_Adapter([_section()])).build_report()

        self.assertIn("findings", report)
        self.assertIn("steps", report)
        self.assertIn("counts", report)
        self.assertGreater(report["counts"]["warning"], 0)
        self.assertTrue(report["findings"])
        for step in report["steps"]:
            self.assertTrue(step["action_title"])

    def test_empty_course_reports_clean(self) -> None:
        report = CourseHealthService(_Adapter([])).build_report()

        self.assertEqual(report["findings"], [])
        self.assertEqual(report["steps"], [])


if __name__ == "__main__":
    unittest.main()
