"""Tests for lesson_content: schema, template switch, new lesson, normalize, builders."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend import api  # noqa: E402
from src.backend.lesson_content import (  # noqa: E402
    ALLOWED_RUNTIME_TYPES,
    INTERACTION_SCHEMA,
    add_item,
    add_listening_phase,
    add_stage,
    add_sub_lesson,
    all_lesson_ids,
    build_intro_lesson,
    build_practice_lesson,
    build_review_lesson,
    default_interaction,
    delete_item,
    delete_listening_phase,
    delete_stage,
    delete_sub_lesson,
    move_item,
    move_listening_phase,
    move_stage,
    move_sub_lesson,
    new_lesson_from_template,
    normalize_item,
    rename_listening_phase,
    rename_stage,
    rename_sub_lesson,
    switch_runtime_type,
    switch_template,
)


class CrudOperationsTest(unittest.TestCase):
    def test_delete_item(self) -> None:
        stage = {"items": [add_item({}, "multipleChoice") for _ in range(3)]}
        item_id = stage["items"][1]["id"]
        self.assertTrue(delete_item(stage, item_id))
        self.assertEqual(len(stage["items"]), 2)
        self.assertFalse(delete_item(stage, "missing"))

    def test_move_item(self) -> None:
        stage = {"items": [add_item({}, "multipleChoice") for _ in range(3)]}
        ids = [i["id"] for i in stage["items"]]
        move_item(stage, 0, 2)
        self.assertEqual([i["id"] for i in stage["items"]], [ids[1], ids[2], ids[0]])

    def test_move_stage(self) -> None:
        sub = {"stages": [add_stage({}, f"Stage {i}") for i in range(3)]}
        ids = [s["id"] for s in sub["stages"]]
        move_stage(sub, 0, 2)
        self.assertEqual([s["id"] for s in sub["stages"]], [ids[1], ids[2], ids[0]])

    def test_move_sub_lesson(self) -> None:
        content = {"subLessons": [add_sub_lesson({}, f"SL {i}") for i in range(3)]}
        ids = [s["id"] for s in content["subLessons"]]
        move_sub_lesson(content, 0, 2)
        self.assertEqual([s["id"] for s in content["subLessons"]], [ids[1], ids[2], ids[0]])

    def test_rename_sub_lesson(self) -> None:
        sub = {"name": "Old"}
        rename_sub_lesson(sub, "New")
        self.assertEqual(sub["name"], "New")

    def test_rename_stage(self) -> None:
        stage = {"name": "Old"}
        rename_stage(stage, "New")
        self.assertEqual(stage["name"], "New")

    def test_delete_stage(self) -> None:
        sub = {"stages": [add_stage({}, f"Stage {i}") for i in range(3)]}
        stage_id = sub["stages"][1]["id"]
        self.assertTrue(delete_stage(sub, stage_id))
        self.assertEqual(len(sub["stages"]), 2)
        self.assertFalse(delete_stage(sub, "missing"))

    def test_delete_sub_lesson(self) -> None:
        content = {"subLessons": [add_sub_lesson({}, f"SL {i}") for i in range(3)]}
        sub_id = content["subLessons"][1]["id"]
        self.assertTrue(delete_sub_lesson(content, sub_id))
        self.assertEqual(len(content["subLessons"]), 2)
        self.assertFalse(delete_sub_lesson(content, "missing"))

    def test_delete_listening_phase(self) -> None:
        lesson = new_lesson_from_template("listening", {})
        phase = add_listening_phase(lesson, "summary", "Summary")
        phase_id = phase["id"]
        self.assertTrue(delete_listening_phase(lesson, phase_id))
        self.assertNotIn(phase_id, [p["id"] for p in lesson["content"]["listeningPhases"]])
        self.assertFalse(delete_listening_phase(lesson, "missing"))

    def test_move_listening_phase(self) -> None:
        lesson = {"template": "listening", "content": {"listeningPhases": []}}
        add_listening_phase(lesson, "wordPairing", "A")
        add_listening_phase(lesson, "dialogue", "B")
        add_listening_phase(lesson, "summary", "C")
        ids = [p["id"] for p in lesson["content"]["listeningPhases"]]
        move_listening_phase(lesson, 0, 2)
        self.assertEqual([p["id"] for p in lesson["content"]["listeningPhases"]], [ids[1], ids[2], ids[0]])

    def test_rename_listening_phase(self) -> None:
        phase = {"name": "Old"}
        rename_listening_phase(phase, "New")
        self.assertEqual(phase["name"], "New")


class RuntimeTypeSwitchTest(unittest.TestCase):
    def test_switch_preserves_common_fields(self) -> None:
        item = {
            "runtimeType": "multipleChoice",
            "id": "mc-1",
            "prompt": "What is the answer?",
            "options": ["A", "B", "C"],
            "correctIndex": 1,
            "grammarPointId": "g-1",
        }
        new_item = switch_runtime_type(item, "readingMcq")
        self.assertEqual(new_item["runtimeType"], "readingMcq")
        self.assertEqual(new_item["id"], "mc-1")
        self.assertEqual(new_item["prompt"], "What is the answer?")
        self.assertEqual(new_item["options"], ["A", "B", "C"])
        self.assertEqual(new_item["correctIndex"], 1)
        self.assertEqual(new_item["grammarPointId"], "g-1")

    def test_switch_resets_incompatible_fields(self) -> None:
        item = default_interaction("multipleChoice")
        item["options"] = ["A", "B"]
        item["correctIndex"] = 0
        new_item = switch_runtime_type(item, "fillBlank")
        self.assertEqual(new_item["runtimeType"], "fillBlank")
        self.assertNotIn("options", new_item)
        self.assertNotIn("correctIndex", new_item)
        self.assertEqual(new_item["sentence"], "")
        self.assertEqual(new_item["answer"], "")

    def test_switch_translates_sentence_to_prompt(self) -> None:
        item = {"runtimeType": "fillBlank", "id": "fb-1", "sentence": "Hello world"}
        new_item = switch_runtime_type(item, "multipleChoice")
        self.assertEqual(new_item["prompt"], "Hello world")

    def test_switch_to_unknown_raises(self) -> None:
        item = {"runtimeType": "multipleChoice"}
        with self.assertRaises(ValueError):
            switch_runtime_type(item, "bogus")


class SchemaTest(unittest.TestCase):
    def test_twelve_runtime_types_have_schema(self) -> None:
        self.assertEqual(len(ALLOWED_RUNTIME_TYPES), 14)
        for rt in ALLOWED_RUNTIME_TYPES:
            self.assertIn(rt, INTERACTION_SCHEMA, f"missing schema for {rt}")

    def test_default_interaction_has_all_fields(self) -> None:
        item = default_interaction("multipleChoice")
        self.assertEqual(item["runtimeType"], "multipleChoice")
        for spec in INTERACTION_SCHEMA["multipleChoice"]:
            self.assertIn(spec.name, item)

    def test_normalize_item_fills_defaults(self) -> None:
        raw = {"runtimeType": "fillBlank", "sentence": "s", "answer": "a"}
        out = normalize_item(raw)
        self.assertEqual(out["hint"], "")
        self.assertEqual(out["grammarPointId"], "")
        self.assertEqual(out["id"], "")

    def test_normalize_item_rejects_unknown_runtime(self) -> None:
        with self.assertRaises(ValueError):
            normalize_item({"runtimeType": "bogus"})

    def test_default_interaction_does_not_share_mutable_defaults(self) -> None:
        first = default_interaction("multipleChoice")
        second = default_interaction("multipleChoice")
        first["options"].append("polluted")
        self.assertEqual(second["options"], [])
        self.assertEqual(
            INTERACTION_SCHEMA["multipleChoice"][2].default, [],
            "schema table default must stay pristine",
        )

    def test_normalize_item_does_not_share_mutable_defaults(self) -> None:
        first = normalize_item({"runtimeType": "translateSentence"})
        second = normalize_item({"runtimeType": "translateSentence"})
        first["hints"].append("polluted")
        self.assertEqual(second["hints"], [])


class TemplateSwitchTest(unittest.TestCase):
    def test_switch_intro_to_listening_drops_sublessons(self) -> None:
        lesson = new_lesson_from_template("intro", {})
        self.assertIn("subLessons", lesson["content"])
        switch_template(lesson, "listening")
        self.assertEqual(lesson["template"], "listening")
        self.assertNotIn("subLessons", lesson["content"])
        self.assertEqual(lesson["content"]["listeningPhases"], [])

    def test_switch_to_reading_adds_empty_passage(self) -> None:
        lesson = new_lesson_from_template("practice", {})
        switch_template(lesson, "reading")
        self.assertIn("readingPassage", lesson["content"])
        self.assertEqual(lesson["content"]["readingPassage"]["paragraphs"], [])

    def test_switch_mastery_keeps_stages(self) -> None:
        lesson = new_lesson_from_template("legacy", {})
        switch_template(lesson, "mastery")
        self.assertIn("stages", lesson["content"])


class NewLessonTest(unittest.TestCase):
    def test_new_lesson_has_unique_id(self) -> None:
        unit: dict = {"lessons": []}
        a = new_lesson_from_template("intro", unit)
        b = new_lesson_from_template("intro", unit)
        self.assertNotEqual(a["id"], b["id"])
        self.assertEqual(len(unit["lessons"]), 2)
        ids = all_lesson_ids([{"units": [unit]}])
        self.assertEqual(ids, {a["id"], b["id"]})

    def test_new_lesson_template_matches(self) -> None:
        for tmpl in ("intro", "practice", "review", "listening", "reading", "mastery"):
            unit: dict = {"lessons": []}
            lesson = new_lesson_from_template(tmpl, unit)
            self.assertEqual(lesson["template"], tmpl)


class ContentTreeTest(unittest.TestCase):
    def test_add_sub_lesson_stage_item(self) -> None:
        lesson = new_lesson_from_template("intro", {})
        sub = add_sub_lesson(lesson["content"], "Words")
        stage = sub["stages"][0]
        item = add_item(stage, "multipleChoice")
        self.assertEqual(item["runtimeType"], "multipleChoice")
        self.assertEqual(len(stage["items"]), 1)

    def test_add_listening_phase_word_pairing(self) -> None:
        lesson = new_lesson_from_template("listening", {})
        before = len(lesson["content"]["listeningPhases"])
        phase = add_listening_phase(lesson, "wordPairing", "Pair")
        self.assertEqual(phase["type"], "wordPairing")
        self.assertEqual(phase["items"], [])
        self.assertEqual(len(lesson["content"]["listeningPhases"]), before + 1)


class LessonBuilderTest(unittest.TestCase):
    def test_build_intro_lesson_validates(self) -> None:
        words = [
            {"id": "w-hello", "term": "hello", "translation": "你好"},
            {"id": "w-thanks", "term": "thanks", "translation": "谢谢"},
        ]
        lesson = build_intro_lesson("问候", "认识问候语", words)
        self.assertEqual(lesson["template"], "intro")
        self.assertEqual(len(lesson["content"]["subLessons"]), 2)

        vocab_ids = {w["id"] for w in words}
        problems = api.validate_lesson(lesson, vocab_ids, set(), set())
        self.assertEqual(problems, [])

    def test_build_practice_lesson_default_mix(self) -> None:
        words = [
            {"id": "w-hello", "term": "hello", "translation": "你好"},
            {"id": "w-thanks", "term": "thanks", "translation": "谢谢"},
        ]
        lesson = build_practice_lesson("练习", "巩固练习", words)
        self.assertEqual(lesson["template"], "practice")
        self.assertEqual(len(lesson["content"]["subLessons"]), 2)

        # Each word becomes one sub-lesson with two stages by default.
        for sub in lesson["content"]["subLessons"]:
            self.assertEqual(len(sub["stages"]), 2)
            rts = {stage["items"][0]["runtimeType"] for stage in sub["stages"]}
            self.assertIn("multipleChoice", rts)
            self.assertIn("fillBlank", rts)

        vocab_ids = {w["id"] for w in words}
        problems = api.validate_lesson(lesson, vocab_ids, set(), set())
        self.assertEqual(problems, [])

    def test_build_practice_lesson_custom_mix(self) -> None:
        words = [{"id": "w-hello", "term": "hello", "translation": "你好"}]
        lesson = build_practice_lesson("练习", "", words, ("translateSentence",))
        sub = lesson["content"]["subLessons"][0]
        self.assertEqual(len(sub["stages"]), 1)
        self.assertEqual(sub["stages"][0]["items"][0]["runtimeType"], "translateSentence")

    def test_build_practice_lesson_fallback_when_empty_mix(self) -> None:
        words = [{"id": "w-hello", "term": "hello", "translation": "你好"}]
        lesson = build_practice_lesson("练习", "", words, ())
        sub = lesson["content"]["subLessons"][0]
        self.assertEqual(sub["stages"][0]["items"][0]["runtimeType"], "fillBlank")

    def test_build_review_lesson_with_words(self) -> None:
        words = [
            {"id": "w-hello", "term": "hello", "translation": "你好"},
            {"id": "w-thanks", "term": "thanks", "translation": "谢谢"},
        ]
        expressions = [{"id": "e-hi", "term": "hi", "translation": "嗨"}]
        lesson = build_review_lesson("复习", "复习本单元", words, expressions)
        self.assertEqual(lesson["template"], "review")
        self.assertEqual(len(lesson["content"]["subLessons"]), 3)

        vocab_ids = {w["id"] for w in words}
        expression_ids = {e["id"] for e in expressions}
        problems = api.validate_lesson(lesson, vocab_ids, expression_ids, set())
        self.assertEqual(problems, [])

    def test_build_review_lesson_empty_inputs(self) -> None:
        lesson = build_review_lesson("复习", "", [])
        self.assertEqual(lesson["template"], "review")
        self.assertEqual(lesson["content"]["subLessons"], [])


class LabelsTest(unittest.TestCase):
    def test_every_runtime_type_has_label(self) -> None:
        from src.backend.lesson_content import CONTENT_BY_TEMPLATE
        from src.i18n import labels

        for rt in ALLOWED_RUNTIME_TYPES:
            self.assertIn(rt, labels.INTERACTION_LABELS, f"missing label for {rt}")
            self.assertTrue(labels.interaction_label(rt))

        for tpl in CONTENT_BY_TEMPLATE:
            self.assertIn(tpl, labels.TEMPLATE_LABELS, f"missing label for {tpl}")
            self.assertTrue(labels.template_label(tpl))

    def test_field_label_and_hidden(self) -> None:
        from src.i18n import labels

        self.assertEqual(labels.field_label("wordId"), "词")
        self.assertEqual(labels.field_label("correctIndex"), "正确答案")
        self.assertEqual(labels.field_label("unknown_field"), "unknown_field")
        self.assertTrue(labels.is_hidden("id"))
        self.assertTrue(labels.is_hidden("runtimeType"))
        self.assertFalse(labels.is_hidden("wordId"))
        self.assertFalse(labels.is_hidden("prompt"))


if __name__ == "__main__":
    unittest.main()
