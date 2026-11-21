#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT / "tool"))

from course_quality_report import (  # type: ignore
    build_quality_report,
    render_quality_markdown,
)


class CourseQualityReportTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.report = build_quality_report(
            PROJECT_ROOT / "assets" / "courses" / "nouveau-turkish"
        )

    def test_real_course_has_playable_node_and_answer_position_metrics(self) -> None:
        self.assertGreater(self.report["playable_nodes"], 0)
        self.assertTrue(self.report["interaction_counts"])
        self.assertTrue(self.report["answer_positions"])
        self.assertTrue(self.report["sublesson_lengths"])

    def test_media_existence_uses_the_real_asset_path(self) -> None:
        ayse = next(
            row for row in self.report["media"] if row["asset"] == "assets/images/ayse.png"
        )
        self.assertEqual(ayse["kind"], "image")
        self.assertTrue(ayse["exists"])

    def test_bare_audio_uses_the_canonical_language_directory(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp)
            course = repo / "assets" / "courses" / "nouveau-turkish"
            (course / "sections").mkdir(parents=True)
            (course / "index.json").write_text(
                json.dumps(
                    {
                        "language": "tr",
                        "sections": [{"id": "s1", "file": "sections/s1.json"}],
                    }
                ),
                encoding="utf-8",
            )
            (course / "vocab.json").write_text('{"words": []}', encoding="utf-8")
            (course / "sections" / "s1.json").write_text(
                json.dumps(
                    {
                        "id": "s1",
                        "units": [
                            {
                                "id": "u1",
                                "lessons": [
                                    {
                                        "id": "l1",
                                        "name": "Listen",
                                        "template": "listening",
                                        "content": {
                                            "listeningPhases": [
                                                {
                                                    "id": "p1",
                                                    "name": "Summary",
                                                    "type": "summary",
                                                    "audioAsset": "l-pilot",
                                                    "transcript": "Merhaba",
                                                }
                                            ]
                                        },
                                    }
                                ],
                            }
                        ],
                    }
                ),
                encoding="utf-8",
            )
            target = (
                repo
                / "assets"
                / "sounds"
                / "turkish"
                / "listening"
                / "l-pilot.mp3"
            )
            target.parent.mkdir(parents=True)
            target.write_bytes(b"mp3")

            report = build_quality_report(course)
            row = next(row for row in report["media"] if row["asset"] == "l-pilot")
            self.assertTrue(row["exists"])

    def test_vocabulary_production_and_later_recurrence_are_reported(self) -> None:
        merhaba = self.report["words"]["nt-w-merhaba"]
        self.assertTrue(merhaba["first"])
        self.assertTrue(merhaba["production"])
        self.assertTrue(merhaba["review"])

    def test_markdown_discloses_missing_learning_data(self) -> None:
        rendered = render_quality_markdown(self.report)
        self.assertIn("Course Quality Metrics", rendered)
        self.assertIn("未导入经学习者同意的真实记录", rendered)
        self.assertIn("Media existence", rendered)


if __name__ == "__main__":
    unittest.main()
