"""Unit tests for content_quality scoring (aiEnhance Phase 2 / second gun)."""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.content_quality import (  # noqa: E402
    build_quality_fix_hint,
    format_quality_line,
    score_section,
)

_GOLDENS = Path(__file__).resolve().parent / "ai_goldens"


def _load_golden(name: str) -> dict:
    data = json.loads((_GOLDENS / name).read_text(encoding="utf-8"))
    if isinstance(data, dict) and "section" in data:
        return data["section"]
    return data


class ContentQualityTest(unittest.TestCase):
    def test_clean_greetings_scores_high(self) -> None:
        section = _load_golden("a1_greetings_clean.json")
        report = score_section(section, level="A1")
        self.assertGreaterEqual(report.mean, 0.75)
        self.assertEqual(report.badge(), "ok")
        self.assertGreaterEqual(report.scores["coverage"], 0.5)
        self.assertGreaterEqual(report.scores["distractor"], 0.9)
        self.assertGreaterEqual(report.scores["resource_hygiene"], 0.9)
        self.assertIn("质量=", format_quality_line(report))

    def test_placeholders_lower_resource_hygiene(self) -> None:
        clean = score_section(_load_golden("a1_greetings_clean.json"))
        stub = score_section(_load_golden("a1_with_placeholders.json"))
        self.assertLess(
            stub.scores["resource_hygiene"], clean.scores["resource_hygiene"]
        )
        self.assertTrue(
            any(i.dimension == "resource_hygiene" for i in stub.issues)
        )
        dims = stub.low_dimensions(0.9)
        self.assertIn("resource_hygiene", dims)

    def test_dangling_refs_error_badge(self) -> None:
        section = _load_golden("a1_dangling_refs.json")
        report = score_section(section)
        self.assertEqual(report.badge(), "error")
        self.assertGreater(report.error_count, 0)
        self.assertLess(report.scores["resource_hygiene"], 0.8)
        self.assertTrue(
            any("悬空" in i.message for i in report.issues)
        )

    def test_mcq_dup_lowers_distractor(self) -> None:
        section = _load_golden("mcq_dup_options.json")
        report = score_section(section)
        self.assertLessEqual(report.scores["distractor"], 0.5)
        self.assertTrue(any(i.dimension == "distractor" for i in report.issues))
        self.assertTrue(any(i.level == "error" for i in report.issues if i.dimension == "distractor"))

    def test_listening_audio_ready_flags_empty_phases(self) -> None:
        section = _load_golden("listening_phases.json")
        report = score_section(section)
        self.assertLess(report.scores["audio_ready"], 1.0)
        self.assertTrue(any(i.dimension == "audio_ready" for i in report.issues))

    def test_grounded_pool_hygiene_ok(self) -> None:
        data = json.loads((_GOLDENS / "a1_grounded_pool.json").read_text(encoding="utf-8"))
        section = data["section"]
        pool = data["pool"]
        report = score_section(section, resource_pool=pool)
        self.assertGreaterEqual(report.scores["resource_hygiene"], 0.8)
        self.assertIn("coverage_ratio", report.hygiene)

    def test_invalid_section(self) -> None:
        report = score_section(None)
        self.assertEqual(report.mean, 0.0)
        self.assertEqual(report.badge(), "error")

    def test_to_problem_dicts_and_fix_hint(self) -> None:
        section = _load_golden("a1_with_placeholders.json")
        report = score_section(section)
        problems = report.to_problem_dicts(dimensions=["resource_hygiene"])
        self.assertTrue(problems)
        self.assertTrue(all(p.get("dimension") == "resource_hygiene" for p in problems))
        hint = build_quality_fix_hint(report)
        self.assertIn("质量维度", hint)

    def test_coverage_flags_unpracticed_word(self) -> None:
        section = {
            "id": "s",
            "words": [
                {"id": "w1", "term": "Merhaba", "translation": "hi"},
                {"id": "w2", "term": "Günaydın", "translation": "morning"},
            ],
            "units": [
                {
                    "id": "u1",
                    "lessons": [
                        {
                            "id": "l1",
                            "template": "intro",
                            "content": {
                                "stages": [
                                    {
                                        "id": "st1",
                                        "items": [
                                            {
                                                "runtimeType": "showWord",
                                                "id": "i1",
                                                "wordId": "w1",
                                            },
                                            {
                                                "runtimeType": "multipleChoice",
                                                "id": "i2",
                                                "prompt": "hi?",
                                                "options": [
                                                    "Merhaba",
                                                    "x",
                                                    "y",
                                                    "z",
                                                ],
                                                "correctIndex": 0,
                                            },
                                        ],
                                    }
                                ]
                            },
                        }
                    ],
                }
            ],
        }
        report = score_section(section, level="A1")
        self.assertLess(report.scores["coverage"], 1.0)
        self.assertTrue(
            any("Günaydın" in i.message or "w2" in i.message for i in report.issues)
        )


if __name__ == "__main__":
    unittest.main()
