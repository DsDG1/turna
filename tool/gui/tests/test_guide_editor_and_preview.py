"""Tests for GuideEditor, GuideTeacherWidget, GuidePreviewWidget, and full Phase Two UI parity."""
from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.course_adapter import CourseAdapter
from src.backend.course_preview.document import build_document
from src.backend.lesson_content import (
    add_guide_block,
    add_guide_page,
    clone_lesson_with_fresh_ids,
    default_guide_block,
)
from src.teacher.guide_preview import GuidePreviewWidget
from src.teacher.preview_window import LessonPreviewWidget, _PreviewCard
from src.teacher.question_cards import QuestionCard
from src.teacher.template_editors import GuideTeacherWidget
from src.widgets.detail_panel import build_teacher_widget
from src.widgets.guide_editor import GuideEditor
from src.widgets.lesson_blueprint import LessonBlueprint
from tests._qtapp import _App as _TestApp


def _sample_guide_lesson() -> dict:
    return {
        "id": "l-guide-1",
        "name": "土耳其语初识",
        "template": "guide",
        "type": "normal",
        "content": {
            "pages": [
                {
                    "id": "p-1",
                    "title": "元音和谐",
                    "kicker": "入门",
                    "intro": "先感受两类元音。",
                    "blocks": [
                        default_guide_block("text"),
                        default_guide_block("terms"),
                        default_guide_block("classification"),
                        default_guide_block("suffixBuilder"),
                        default_guide_block("wordOrder"),
                    ],
                }
            ]
        },
    }


class GuideAndPhaseTwoParityTest(unittest.TestCase):
    def setUp(self) -> None:
        _TestApp.get()
        self.adapter = CourseAdapter()
        self.adapter.vocab = [
            {"id": "w-cay", "term": "çay", "translation": "茶"},
        ]

    def test_clone_guide_lesson_regenerates_all_nested_ids(self) -> None:
        original = _sample_guide_lesson()
        cloned = clone_lesson_with_fresh_ids(original)
        self.assertNotEqual(cloned["id"], original["id"])
        orig_page = original["content"]["pages"][0]
        new_page = cloned["content"]["pages"][0]
        self.assertNotEqual(new_page["id"], orig_page["id"])
        orig_cls = orig_page["blocks"][2]
        new_cls = new_page["blocks"][2]
        self.assertNotEqual(new_cls["id"], orig_cls["id"])
        new_cat_ids = {c["id"] for c in new_cls["categories"]}
        orig_cat_ids = {c["id"] for c in orig_cls["categories"]}
        self.assertTrue(new_cat_ids.isdisjoint(orig_cat_ids))
        for card in new_cls["cards"]:
            self.assertIn(card["categoryId"], new_cat_ids)

    def test_guide_editor_and_teacher_dispatch(self) -> None:
        lesson = _sample_guide_lesson()
        section = {"id": "s-1", "name": "S1", "units": []}
        unit = {"id": "u-1", "name": "U1", "lessons": [lesson]}
        widget = build_teacher_widget(self.adapter, section, unit, lesson, None, None, None)
        self.assertIsInstance(widget, GuideTeacherWidget)

        editor = GuideEditor(self.adapter, lesson, read_only=False)
        self.assertEqual(editor.page_list.count(), 1)
        add_guide_page(lesson["content"], "第二页")
        add_guide_block(lesson["content"]["pages"][1], "terms")
        self.assertEqual(len(lesson["content"]["pages"]), 2)

        bp = LessonBlueprint(self.adapter, lesson, read_only=False)
        self.assertIsNotNone(bp)

    def test_guide_preview_and_web_preview_document(self) -> None:
        lesson = _sample_guide_lesson()
        gp = GuidePreviewWidget(lesson)
        self.assertEqual(len(gp.pages), 1)

        pw = LessonPreviewWidget(self.adapter, lesson)
        self.assertIsNotNone(pw)

        section = {
            "id": "s-1",
            "name": "S1",
            "units": [{"id": "u-1", "name": "U1", "lessons": [lesson]}],
        }
        doc = build_document(section)
        self.assertEqual(doc.item_count, 5)
        self.assertEqual(doc.lessons[0].items[0].runtime_type, "guide:text")
        self.assertEqual(doc.lessons[0].items[2].runtime_type, "guide:classification")

    def test_fill_blank_question_card_uses_hint_and_choices(self) -> None:
        item = {
            "runtimeType": "fillBlank",
            "id": "fb-1",
            "sentence": "Bir ____ lütfen.",
            "answer": "çay",
            "hint": "热茶",
            "choices": ["çay", "su"],
            "grammarPointId": "",
        }
        card = QuestionCard(self.adapter, item)
        self.assertIsNotNone(card)
        self.assertNotIn("translation", item)
        self.assertNotIn("hints", item)
        self.assertEqual(item["hint"], "热茶")
        self.assertEqual(item["choices"], ["çay", "su"])

    def test_preview_cards_render_all_new_types(self) -> None:
        for item in (
            {"runtimeType": "listenOnly", "id": "lo-1", "audioAsset": "", "transcript": "Merhaba!"},
            {"runtimeType": "reorderSentence", "id": "rs-1", "prompt": "一杯茶", "scrambled": ["çay", "Bir"], "correct": ["Bir", "çay"], "acceptedAnswers": ["bir cay"]},
            {"runtimeType": "imageRecall", "id": "ir-1", "imageAssets": ["media/cay.svg"], "answerText": "çay"},
            {"runtimeType": "dictation", "id": "dc-1", "audioAssets": ["media/cay.mp3"], "expected": "çay"},
            {"runtimeType": "ankiCard", "id": "ac-1", "front": "çay", "back": "茶", "frontImageAssets": ["media/cay.svg"]},
        ):
            card = _PreviewCard(self.adapter, item)
            self.assertIsNotNone(card)

    def test_blueprint_dialogue_and_flat_review(self) -> None:
        dialogue = {
            "id": "l-dlg",
            "name": "咖啡馆点单",
            "template": "dialogue",
            "content": {
                "dialogueScene": {
                    "id": "sc-1",
                    "title": "咖啡馆",
                    "characters": [{"id": "ayse", "name": "Ayşe", "imageAsset": ""}],
                    "turns": [{"id": "t-1", "speakerId": "ayse", "text": "Merhaba!"}],
                },
                "stages": [{"id": "st-1", "name": "Responses", "items": []}],
            },
        }
        bp_d = LessonBlueprint(self.adapter, dialogue, read_only=False)
        self.assertIsNotNone(bp_d)

        review = {
            "id": "l-rev",
            "name": "单元复习",
            "template": "review",
            "content": {
                "reviewPolicy": {"minItems": 2, "maxItems": 4, "typeWeights": {"fillBlank": 1.0}},
                "stages": [
                    {
                        "id": "st-r1",
                        "name": "题池",
                        "items": [
                            {"runtimeType": "fillBlank", "id": "fb-r1", "sentence": "Bir ____", "answer": "çay"},
                            {"runtimeType": "fillBlank", "id": "fb-r2", "sentence": "Bir ____", "answer": "su"},
                        ],
                    }
                ],
            },
        }
        bp_r = LessonBlueprint(self.adapter, review, read_only=False)
        self.assertIsNotNone(bp_r)


if __name__ == "__main__":
    unittest.main()
