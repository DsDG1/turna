"""Re-import idempotency for textbook-derived sections (connectplan P0-1).

``build_section_from_chapter`` must produce deterministic structural ids at
every level (unit → lesson → subLesson/stage/phase → item), so importing the
same chapter twice routes through the merge path as *replace* instead of
adding duplicate lessons.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.course_adapter import CourseAdapter  # noqa: E402
from src.backend.knowledge_schema import coerce_knowledge_points  # noqa: E402
from src.backend.markdown_chopper import split_chapters  # noqa: E402
from src.backend.textbook_to_course import build_section_from_chapter  # noqa: E402


def _sample_chapter():
    md = "## 1 Merhaba\nmerhaba means hello\n"
    return split_chapters(md)[0]


def _sample_kp():
    return coerce_knowledge_points(
        {
            "words": [
                {"term": "merhaba", "translation": "hello", "tags": ["greeting"]},
                {"term": "günaydın", "translation": "good morning"},
            ],
            "expressions": [
                {"term": "Selam!", "translation": "Hi!", "tags": ["greeting"]}
            ],
            "grammarPoints": [
                {"title": "Greetings", "explanation": "common greetings"}
            ],
        }
    )


def _structural_ids(node: object, out: list[str]) -> list[str]:
    """Collect every ``id`` under units/lessons/content, in tree order."""
    if isinstance(node, dict):
        for key, value in node.items():
            if key == "id" and isinstance(value, str):
                out.append(value)
            elif key in ("units", "lessons", "subLessons", "stages", "items",
                         "listeningPhases", "content"):
                _structural_ids(value, out)
    elif isinstance(node, list):
        for item in node:
            _structural_ids(item, out)
    return out


class ReimportIdempotencyTest(unittest.TestCase):
    def test_two_builds_are_fully_identical(self) -> None:
        ch = _sample_chapter()
        kp = _sample_kp()
        s1 = build_section_from_chapter(ch, kp, 1)
        s2 = build_section_from_chapter(ch, kp, 1)
        self.assertEqual(s1, s2)

    def test_structural_id_format(self) -> None:
        ch = _sample_chapter()
        kp = _sample_kp()
        section = build_section_from_chapter(ch, kp, 1)
        sid = section["id"]
        unit = section["units"][0]
        lesson = unit["lessons"][0]
        self.assertEqual(unit["id"], f"{sid}-u1")
        self.assertEqual(lesson["id"], f"{sid}-u1-l1")
        sl = lesson["content"]["subLessons"][0]
        self.assertEqual(sl["id"], f"{lesson['id']}-sl1")
        stage = sl["stages"][0]
        self.assertEqual(stage["id"], f"{sl['id']}-st1")
        self.assertEqual(stage["items"][0]["id"], f"{stage['id']}-it1")

    def test_resource_references_not_rewritten(self) -> None:
        ch = _sample_chapter()
        kp = _sample_kp()
        section = build_section_from_chapter(ch, kp, 1)
        word_ids = {w["id"] for w in section["words"]}
        # showWord items must still point at the real word ids.
        item = section["units"][0]["lessons"][0]["content"]["subLessons"][0][
            "stages"
        ][0]["items"][0]
        self.assertIn(item["wordId"], word_ids)

    def test_reimport_merge_plan_replaces_instead_of_adds(self) -> None:
        ch = _sample_chapter()
        kp = _sample_kp()
        first = build_section_from_chapter(ch, kp, 1)
        adapter = CourseAdapter()
        adapter.sections.append(first)

        second = build_section_from_chapter(ch, kp, 1)
        plan = adapter.plan_section_merge(first["id"], second)
        self.assertEqual(len(plan.replaced_units), 1)
        self.assertEqual(plan.added_units, [])
        # The lesson inside the replaced unit is matched by id, not re-added.
        unit_id = second["units"][0]["id"]
        self.assertEqual(len(plan.replaced_lessons_by_unit.get(unit_id, [])), 1)
        self.assertEqual(plan.added_lessons_by_unit.get(unit_id, []), [])

    def test_random_ids_would_have_added_duplicates(self) -> None:
        """Guard the regression: a section with foreign unit/lesson ids is
        planned as add-on-top (the old behaviour we are eliminating)."""
        ch = _sample_chapter()
        kp = _sample_kp()
        first = build_section_from_chapter(ch, kp, 1)
        adapter = CourseAdapter()
        adapter.sections.append(first)

        import copy

        foreign = copy.deepcopy(first)
        foreign["units"][0]["id"] = "u-deadbeef"
        foreign["units"][0]["lessons"][0]["id"] = "l-deadbeef"
        plan = adapter.plan_section_merge(first["id"], foreign)
        self.assertEqual(len(plan.added_units), 1)
        self.assertEqual(plan.replaced_units, [])


if __name__ == "__main__":
    unittest.main()
