"""Tests for Phase Two course_delivery ID rewriting and SVG media packaging."""
from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.course_delivery import build_pack_payload, rewrite_ids
from src.backend.course_media import IMAGE_EXTENSIONS, copy_into_course_media


class CourseDeliveryPhaseTwoTest(unittest.TestCase):
    def test_svg_allowed_in_course_media(self) -> None:
        self.assertIn(".svg", IMAGE_EXTENSIONS)
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            svg = root / "cay.svg"
            svg.write_text('<svg xmlns="http://www.w3.org/2000/svg"></svg>', encoding="utf-8")
            course = root / "course"
            course.mkdir()
            ref = copy_into_course_media(course, svg)
            self.assertEqual(ref, "media/cay.svg")
            self.assertTrue((course / "media" / "cay.svg").is_file())

    def test_rewrite_ids_covers_phase_two_references(self) -> None:
        doc = {
            "vocab.json": {
                "words": [
                    {
                        "id": "w-ev",
                        "term": "ev",
                        "translation": "家",
                        "introducedInLessonId": "l-intro-1",
                    }
                ]
            },
            "sections/s1.json": {
                "id": "s-1",
                "units": [
                    {
                        "id": "u-1",
                        "lessons": [
                            {
                                "id": "l-guide-1",
                                "template": "guide",
                                "content": {
                                    "pages": [
                                        {
                                            "id": "p-1",
                                            "title": "导览",
                                            "nextLessonId": "l-intro-1",
                                            "nextSubLessonId": "sl-1",
                                            "blocks": [
                                                {
                                                    "runtimeType": "classification",
                                                    "id": "b-1",
                                                    "categories": [{"id": "cat-front", "label": "前"}],
                                                    "cards": [{"id": "c-1", "text": "ev", "categoryId": "cat-front"}],
                                                }
                                            ],
                                        }
                                    ]
                                },
                            },
                            {
                                "id": "l-intro-1",
                                "template": "reading",
                                "content": {
                                    "readingPassage": {
                                        "title": "T",
                                        "paragraphs": ["evimde"],
                                        "wordFormMap": {"evimde": "w-ev"},
                                        "imageAsset": "media/story.svg",
                                        "imageAlt": "家",
                                    },
                                    "dialogueScene": {
                                        "id": "sc-1",
                                        "characters": [{"id": "host", "name": "Ayşe"}],
                                        "turns": [
                                            {"id": "t-1", "speakerId": "host", "interactionId": "it-1"}
                                        ],
                                    },
                                    "stages": [
                                        {
                                            "id": "st-1",
                                            "items": [{"id": "it-1", "runtimeType": "fillBlank"}],
                                        }
                                    ],
                                },
                            },
                        ],
                    }
                ],
            },
        }
        out = rewrite_ids(doc, "es")
        self.assertEqual(
            out["vocab.json"]["words"][0]["introducedInLessonId"], "ll-es-l-intro-1"
        )
        page = out["sections/s1.json"]["units"][0]["lessons"][0]["content"]["pages"][0]
        self.assertEqual(page["nextLessonId"], "ll-es-l-intro-1")
        self.assertEqual(page["nextSubLessonId"], "ll-es-sl-1")
        cls_block = page["blocks"][0]
        self.assertEqual(cls_block["cards"][0]["categoryId"], "ll-es-cat-front")

        lesson2 = out["sections/s1.json"]["units"][0]["lessons"][1]["content"]
        self.assertEqual(lesson2["readingPassage"]["wordFormMap"]["evimde"], "ll-es-w-ev")
        turn = lesson2["dialogueScene"]["turns"][0]
        self.assertEqual(turn["speakerId"], "ll-es-host")
        self.assertEqual(turn["interactionId"], "ll-es-it-1")

    def test_pack_payload_bundles_svg_media(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            course = Path(tmp)
            (course / "sections").mkdir()
            (course / "media").mkdir()
            (course / "media" / "cay.svg").write_text("<svg/>", encoding="utf-8")
            (course / "index.json").write_text(
                json.dumps(
                    {
                        "language": "es",
                        "displayName": "Spanish",
                        "sections": [{"id": "s1", "file": "sections/s1.json"}],
                    }
                ),
                encoding="utf-8",
            )
            (course / "vocab.json").write_text(
                json.dumps({"words": [{"id": "w1", "term": "té", "translation": "茶"}]}),
                encoding="utf-8",
            )
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
                                        "content": {
                                            "stages": [
                                                {
                                                    "id": "st1",
                                                    "items": [
                                                        {
                                                            "id": "i1",
                                                            "runtimeType": "showWord",
                                                            "wordId": "w1",
                                                            "imageAsset": "media/cay.svg",
                                                        }
                                                    ],
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
            pack, media_map, _sub = build_pack_payload(course)
            self.assertEqual(pack["format"], "turnapack/2")
            self.assertIn("media/cay.svg", media_map)


if __name__ == "__main__":
    unittest.main()
