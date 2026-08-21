"""V-04 (v4.52): resource reference graph + replacement mapping (pure)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path
from types import SimpleNamespace

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.experience.patch import (  # noqa: E402
    apply_resolved_batch,
    revert_resolved_batch,
)
from src.backend.experience.resource_refs import (  # noqa: E402
    build_replacement_steps,
    find_replacement_candidates,
    find_resource_refs,
)


def _section(sid, lessons):
    return {"id": sid, "units": [{"id": f"{sid}-u1", "lessons": lessons}]}


def _lesson(lid, *, stages=None, sub_lessons=None, phases=None):
    content: dict = {}
    if stages is not None:
        content["stages"] = stages
    if sub_lessons is not None:
        content["subLessons"] = sub_lessons
    if phases is not None:
        content["listeningPhases"] = phases
    return {"id": lid, "content": content}


def _adapter(*, sections=None, vocab=None, expressions=None, grammar_points=None):
    return SimpleNamespace(
        sections=sections or [],
        vocab=vocab or [],
        expressions=expressions or [],
        grammar_points=grammar_points or [],
    )


class FindRefsTest(unittest.TestCase):
    def test_scalar_word_id(self):
        item = {"id": "i1", "runtimeType": "showWord", "wordId": "w1"}
        a = _adapter(sections=[_section("s1", [_lesson("l1", stages=[{"id": "st1", "items": [item]}])])])
        r = find_resource_refs(a, "vocab", "w1")
        self.assertEqual(r["count"], 1)
        self.assertEqual(
            r["refs"][0],
            {"section_id": "s1", "lesson_id": "l1", "item_id": "i1", "field": "wordId"},
        )

    def test_list_fields(self):
        items = [
            {"id": "i1", "wordIds": ["w1", "w2"]},
            {"id": "i2", "correctWordIds": ["w2"]},
            {"id": "i3", "linkedWordIds": ["w3", "w2"]},
            {"id": "i4", "wordIds": ["w9"]},
        ]
        a = _adapter(sections=[_section("s1", [_lesson("l1", stages=[{"items": items}])])])
        r = find_resource_refs(a, "vocab", "w2")
        self.assertEqual(r["count"], 3)
        self.assertEqual(
            {(x["item_id"], x["field"]) for x in r["refs"]},
            {("i1", "wordIds"), ("i2", "correctWordIds"), ("i3", "linkedWordIds")},
        )

    def test_all_containers(self):
        lesson = _lesson(
            "l1",
            stages=[{"items": [{"id": "a", "wordId": "w1"}]}],
            sub_lessons=[{"stages": [{"items": [{"id": "b", "wordId": "w1"}]}]}],
            phases=[{"id": "p1", "items": [{"id": "c", "wordId": "w1"}]}],
        )
        a = _adapter(sections=[_section("s1", [lesson])])
        r = find_resource_refs(a, "vocab", "w1")
        self.assertEqual({x["item_id"] for x in r["refs"]}, {"a", "b", "c"})

    def test_multiple_sections(self):
        a = _adapter(
            sections=[
                _section("s1", [_lesson("l1", stages=[{"items": [{"id": "a", "wordId": "w1"}]}])]),
                _section("s2", [_lesson("l2", stages=[{"items": [{"id": "b", "wordId": "w1"}]}])]),
            ]
        )
        r = find_resource_refs(a, "vocab", "w1")
        self.assertEqual(r["count"], 2)
        self.assertEqual({x["section_id"] for x in r["refs"]}, {"s1", "s2"})

    def test_expression_refs_include_grammar_examples(self):
        lesson = _lesson("l1", stages=[{"items": [{"id": "i1", "runtimeType": "showExpression", "expressionId": "e1"}]}])
        a = _adapter(
            sections=[_section("s1", [lesson])],
            grammar_points=[{"id": "g1", "exampleExpressionIds": ["e1", "e2"]}],
        )
        r = find_resource_refs(a, "expressions", "e1")
        self.assertEqual(r["count"], 2)
        by_field = {x["field"]: x for x in r["refs"]}
        self.assertEqual(by_field["expressionId"]["item_id"], "i1")
        self.assertEqual(by_field["exampleExpressionIds"]["item_id"], "g1")
        self.assertEqual(by_field["exampleExpressionIds"]["section_id"], "")

    def test_grammar_point_refs(self):
        lesson = _lesson("l1", stages=[{"items": [{"id": "i1", "grammarPointId": "g1"}]}])
        a = _adapter(sections=[_section("s1", [lesson])])
        r = find_resource_refs(a, "grammar_points", "g1")
        self.assertEqual(r["count"], 1)
        self.assertEqual(r["refs"][0]["field"], "grammarPointId")

    def test_abnormal_inputs_closed_empty(self):
        self.assertEqual(find_resource_refs(None, "vocab", "w1"), {"count": 0, "refs": []})
        self.assertEqual(find_resource_refs(_adapter(), "bogus", "w1"), {"count": 0, "refs": []})
        self.assertEqual(find_resource_refs(_adapter(), "vocab", ""), {"count": 0, "refs": []})
        # broken shapes inside sections must not raise
        a = _adapter(sections=[{"id": "s1", "units": [{"lessons": [{"id": "l1", "content": None}, "junk"]}]}])
        self.assertEqual(find_resource_refs(a, "vocab", "w1"), {"count": 0, "refs": []})

    def test_closed_set_no_term_in_return(self):
        item = {"id": "i1", "wordId": "w1", "prompt": "secret-term"}
        a = _adapter(sections=[_section("s1", [_lesson("l1", stages=[{"items": [item]}])])])
        blob = str(find_resource_refs(a, "vocab", "w1"))
        self.assertNotIn("secret-term", blob)
        self.assertIn("i1", blob)

    def test_count_matches_refs(self):
        items = [{"id": f"i{k}", "wordId": "w1"} for k in range(5)]
        a = _adapter(sections=[_section("s1", [_lesson("l1", stages=[{"items": items}])])])
        r = find_resource_refs(a, "vocab", "w1")
        self.assertEqual(r["count"], len(r["refs"]))


class ReplacementStepsTest(unittest.TestCase):
    def _adapter_with_refs(self):
        item1 = {"id": "i1", "runtimeType": "showWord", "wordId": "w1"}
        item2 = {"id": "i2", "wordIds": ["w1", "w3"]}
        stage = {"id": "st1", "items": [item1, item2]}
        a = _adapter(
            sections=[_section("s1", [_lesson("l1", stages=[stage])])],
            vocab=[
                {"id": "w1", "term": "merhaba", "translation": "你好"},
                {"id": "w2", "term": "Merhaba ", "translation": "您好"},
            ],
        )
        return a, stage, item1, item2

    def test_apply_repoints_refs_preserving_item_id(self):
        a, stage, _item1, _item2 = self._adapter_with_refs()
        steps = build_replacement_steps(a, "vocab", "w1", "w2")
        self.assertEqual(len(steps), 2)
        apply_resolved_batch(steps)
        # ItemPatch 语义：容器内整题替换（非原地改字段），保 item id
        item1, item2 = stage["items"][0], stage["items"][1]
        self.assertEqual(item1["wordId"], "w2")
        self.assertEqual(item2["wordIds"], ["w2", "w3"])
        # 红线：item id 不变
        self.assertEqual(item1["id"], "i1")
        self.assertEqual(item2["id"], "i2")

    def test_revert_restores(self):
        a, stage, _item1, _item2 = self._adapter_with_refs()
        steps = build_replacement_steps(a, "vocab", "w1", "w2")
        apply_resolved_batch(steps)
        revert_resolved_batch(steps)
        item1, item2 = stage["items"][0], stage["items"][1]
        self.assertEqual(item1["wordId"], "w1")
        self.assertEqual(item2["wordIds"], ["w1", "w3"])

    def test_expression_grammar_field_patch(self):
        gp = {"id": "g1", "exampleExpressionIds": ["e1", "e2"]}
        item = {"id": "i1", "expressionId": "e1"}
        stage = {"id": "st1", "items": [item]}
        a = _adapter(
            sections=[_section("s1", [_lesson("l1", stages=[stage])])],
            grammar_points=[gp],
        )
        steps = build_replacement_steps(a, "expressions", "e1", "e9")
        kinds = sorted(k for k, _h, _p in steps)
        self.assertEqual(kinds, ["field", "item"])
        apply_resolved_batch(steps)
        self.assertEqual(stage["items"][0]["expressionId"], "e9")
        self.assertEqual(gp["exampleExpressionIds"], ["e9", "e2"])
        revert_resolved_batch(steps)
        self.assertEqual(stage["items"][0]["expressionId"], "e1")
        self.assertEqual(gp["exampleExpressionIds"], ["e1", "e2"])

    def test_bad_inputs_empty(self):
        a, _s, _i1, _i2 = self._adapter_with_refs()
        self.assertEqual(build_replacement_steps(a, "vocab", "w1", "w1"), [])
        self.assertEqual(build_replacement_steps(a, "vocab", "", "w2"), [])
        self.assertEqual(build_replacement_steps(None, "vocab", "w1", "w2"), [])
        self.assertEqual(build_replacement_steps(a, "bogus", "w1", "w2"), [])

    def test_candidates_same_term_or_translation(self):
        a = self._adapter_with_refs()[0]
        # w2 shares normalized term with w1 ("merhaba")
        self.assertEqual(find_replacement_candidates(a, "vocab", "w1"), ["w2"])
        a.vocab.append({"id": "w3", "term": "selam", "translation": "你好"})
        # w3 shares normalized translation with w1 ("你好")
        self.assertEqual(
            find_replacement_candidates(a, "vocab", "w1"), ["w2", "w3"]
        )
        # self excluded / no match / unknown id
        self.assertEqual(find_replacement_candidates(a, "vocab", "nope"), [])
        self.assertEqual(find_replacement_candidates(a, "bogus", "w1"), [])


if __name__ == "__main__":
    unittest.main()
