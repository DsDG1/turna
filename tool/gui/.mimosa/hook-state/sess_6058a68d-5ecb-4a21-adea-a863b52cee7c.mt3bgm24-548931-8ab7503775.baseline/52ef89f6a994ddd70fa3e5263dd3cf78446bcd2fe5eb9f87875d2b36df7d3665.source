"""Wave 0: ExperienceContext assembly (empty / error / healthy). No Qt."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest.mock import patch

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.experience import (  # noqa: E402
    ExperienceContext,
    NodeRef,
    build_experience_context,
    local_suggestions,
)
from src.backend.experience.context_bus import _problem_level  # noqa: E402


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


def _empty_lesson(lid: str = "s1-l1") -> dict:
    return {
        "id": lid,
        "name": f"Empty {lid}",
        "template": "intro",
        "content": {"subLessons": []},
    }


def _filled_lesson(lid: str = "s1-l1") -> dict:
    return {
        "id": lid,
        "name": f"Filled {lid}",
        "template": "intro",
        "content": {
            "subLessons": [
                {
                    "id": f"{lid}-sub1",
                    "stages": [
                        {
                            "id": f"{lid}-st1",
                            "items": [
                                {
                                    "id": f"{lid}-i1",
                                    "runtimeType": "showWord",
                                    "wordId": "w1",
                                }
                            ],
                        }
                    ],
                }
            ]
        },
    }


def _adapter(
    *,
    sections=None,
    vocab=None,
    expressions=None,
    grammar_points=None,
    index=None,
    course_dir=None,
):
    class _A:
        pass

    a = _A()
    a.sections = sections if sections is not None else []
    a.vocab = vocab if vocab is not None else []
    a.expressions = expressions if expressions is not None else []
    a.grammar_points = grammar_points if grammar_points is not None else []
    a.index = index if index is not None else {"language": "tr", "displayName": "Turkish"}
    a.course_dir = course_dir
    return a


def _section(sid: str, lessons: list[dict], *, level: str = "A1") -> dict:
    return {
        "id": sid,
        "name": f"Section {sid}",
        "level": level,
        "units": [
            {
                "id": f"{sid}-u1",
                "name": "Unit 1",
                "lessons": lessons,
            }
        ],
    }


# ---------------------------------------------------------------------------
# Three course states
# ---------------------------------------------------------------------------


class EmptyCourseStateTest(unittest.TestCase):
    def setUp(self) -> None:
        self.adapter = _adapter(
            sections=[_section("section1", [_empty_lesson("s1-l1"), _empty_lesson("s1-l2")])],
            vocab=[{"id": "w1", "term": "merhaba", "translation": "hello"}],
        )

    def test_empty_lesson_count(self) -> None:
        ctx = build_experience_context(self.adapter, include_quality=False)
        self.assertEqual(ctx.empty_lesson_count, 2)
        self.assertEqual(ctx.empty_lessons, ["s1-l1", "s1-l2"])
        self.assertEqual(ctx.lesson_count, 2)
        self.assertEqual(ctx.section_count, 1)
        self.assertFalse(ctx.healthy)

    def test_suggestions_include_fill(self) -> None:
        ctx = build_experience_context(self.adapter, include_quality=False)
        suggestions = local_suggestions(ctx, limit=3)
        action_ids = [s["action_id"] for s in suggestions]
        self.assertIn("lesson.fill_empty", action_ids)
        fill = next(s for s in suggestions if s["action_id"] == "lesson.fill_empty")
        self.assertEqual(fill["priority"], 1)
        self.assertEqual(fill["scope"]["empty_count"], 2)


class ErrorCourseStateTest(unittest.TestCase):
    def setUp(self) -> None:
        self.adapter = _adapter(
            sections=[_section("section1", [_filled_lesson("s1-l1")])],
            vocab=[{"id": "w1", "term": "merhaba", "translation": "hello"}],
        )
        self.problems = [
            {
                "level": "error",
                "message": "duplicate lesson id",
                "path": "sections/section1",
            },
            {
                "level": "warning",
                "message": "style nits",
                "path": "sections/section1",
            },
        ]

    def test_validate_counts(self) -> None:
        ctx = build_experience_context(
            self.adapter,
            validate_problems=self.problems,
            include_quality=False,
        )
        self.assertEqual(ctx.validate_error_count, 1)
        self.assertEqual(ctx.validate_warning_count, 1)
        self.assertEqual(len(ctx.validate_problems), 2)
        self.assertFalse(ctx.healthy)

    def test_suggestions_include_validate(self) -> None:
        ctx = build_experience_context(
            self.adapter,
            validate_problems=self.problems,
            include_quality=False,
        )
        suggestions = local_suggestions(ctx, limit=3)
        self.assertTrue(suggestions)
        self.assertEqual(suggestions[0]["action_id"], "validate.open_and_fix")
        self.assertEqual(suggestions[0]["priority"], 0)


class HealthyCourseStateTest(unittest.TestCase):
    def setUp(self) -> None:
        self.adapter = _adapter(
            sections=[_section("section1", [_filled_lesson("s1-l1")])],
            vocab=[
                {"id": "w1", "term": "merhaba", "translation": "hello"},
                {"id": "w2", "term": "teşekkürler", "translation": "thanks"},
            ],
        )

    def test_healthy_flag(self) -> None:
        ctx = build_experience_context(
            self.adapter,
            validate_problems=[],
            include_quality=False,
        )
        self.assertEqual(ctx.empty_lesson_count, 0)
        self.assertEqual(ctx.validate_error_count, 0)
        self.assertEqual(ctx.hygiene.get("placeholder_count"), 0)
        self.assertEqual(ctx.hygiene.get("needs_review_count"), 0)
        self.assertTrue(ctx.healthy)

    def test_suggestions_no_p0_p1_p2(self) -> None:
        ctx = build_experience_context(
            self.adapter,
            validate_problems=[],
            include_quality=False,
        )
        suggestions = local_suggestions(ctx, limit=3)
        action_ids = {s["action_id"] for s in suggestions}
        self.assertNotIn("validate.open_and_fix", action_ids)
        self.assertNotIn("lesson.fill_empty", action_ids)
        self.assertNotIn("resource.fill_stubs", action_ids)


# ---------------------------------------------------------------------------
# Selection / hygiene / no-CLI / quality
# ---------------------------------------------------------------------------


class SelectionNormalizeTest(unittest.TestCase):
    def setUp(self) -> None:
        self.adapter = _adapter(
            sections=[_section("section1", [_filled_lesson("s1-l1")])],
        )

    def test_tuple_selection(self) -> None:
        ctx = build_experience_context(
            self.adapter,
            selection=("lesson", "s1-l1"),
            include_quality=False,
            include_hygiene=False,
        )
        self.assertIsNotNone(ctx.selection)
        assert ctx.selection is not None
        self.assertEqual(ctx.selection.kind, "lesson")
        self.assertEqual(ctx.selection.id, "s1-l1")
        self.assertEqual(ctx.selection.label, "Filled s1-l1")

    def test_noderef_selection(self) -> None:
        ref = NodeRef(kind="section", id="section1", label="")
        ctx = build_experience_context(
            self.adapter,
            selection=ref,
            include_quality=False,
            include_hygiene=False,
        )
        assert ctx.selection is not None
        self.assertEqual(ctx.selection.label, "Section section1")

    def test_multi_and_surface(self) -> None:
        ctx = build_experience_context(
            self.adapter,
            multi_selection=[("lesson", "s1-l1"), ("section", "section1")],
            surface="teacher",
            include_quality=False,
            include_hygiene=False,
        )
        self.assertEqual(ctx.surface, "teacher")
        self.assertEqual(len(ctx.multi_selection), 2)


class HygieneTest(unittest.TestCase):
    def test_placeholder_count(self) -> None:
        adapter = _adapter(
            sections=[_section("section1", [_filled_lesson()])],
            vocab=[
                {"id": "w1", "term": "[待补]", "translation": "hello"},
                {
                    "id": "w2",
                    "term": "x",
                    "translation": "y",
                    "tags": ["needs-review"],
                },
            ],
            expressions=[
                {"id": "e1", "term": "a", "translation": "[待补]"},
            ],
        )
        ctx = build_experience_context(
            adapter,
            validate_problems=[],
            include_quality=False,
        )
        self.assertGreaterEqual(ctx.hygiene["placeholder_count"], 2)
        self.assertGreaterEqual(ctx.hygiene["needs_review_count"], 1)
        self.assertFalse(ctx.healthy)

        suggestions = local_suggestions(ctx, limit=3)
        self.assertIn("resource.fill_stubs", [s["action_id"] for s in suggestions])


class ValidateRefreshGuardTest(unittest.TestCase):
    def test_no_cli_when_refresh_false(self) -> None:
        adapter = _adapter(
            sections=[_section("section1", [_filled_lesson()])],
            course_dir="/tmp/fake-course",
        )
        with patch("src.backend.api.validate_course_dir") as mock_val:
            ctx = build_experience_context(
                adapter,
                refresh_validate=False,
                include_quality=False,
            )
            mock_val.assert_not_called()
            self.assertEqual(ctx.validate_error_count, 0)

    def test_refresh_calls_api(self) -> None:
        adapter = _adapter(
            sections=[_section("section1", [_filled_lesson()])],
            course_dir="/tmp/fake-course",
        )

        class _R:
            problems = [
                {"level": "error", "message": "boom", "path": "x"},
            ]

        with (
            patch("src.backend.api.validate_course_dir", return_value=_R()) as mock_val,
            patch("src.backend.api.lint_course_dir", return_value=[]),
        ):
            ctx = build_experience_context(
                adapter,
                refresh_validate=True,
                include_quality=False,
            )
            mock_val.assert_called_once()
            self.assertEqual(ctx.validate_error_count, 1)


class LanguageAndMetaTest(unittest.TestCase):
    def test_language_and_cefr_from_index_and_section(self) -> None:
        adapter = _adapter(
            sections=[_section("section1", [_filled_lesson()], level="A2")],
            index={"language": "tr", "displayName": "Turkish"},
        )
        ctx = build_experience_context(
            adapter,
            include_quality=False,
            include_hygiene=False,
        )
        self.assertEqual(ctx.language, "tr")
        self.assertEqual(ctx.cefr_hint, "A2")

    def test_quality_optional(self) -> None:
        adapter = _adapter(sections=[_section("section1", [_filled_lesson()])])
        ctx = build_experience_context(adapter, include_quality=True, include_hygiene=False)
        # score_section may return a mean; just ensure key exists or empty without crash
        self.assertIsInstance(ctx.quality_by_section, dict)
        if ctx.quality_by_section:
            self.assertIn("section1", ctx.quality_by_section)


class ProblemLevelTest(unittest.TestCase):
    def test_levels(self) -> None:
        self.assertEqual(_problem_level({"level": "error"}), "error")
        self.assertEqual(_problem_level({"level": "warning"}), "warning")
        self.assertEqual(_problem_level({"level": "warn"}), "warning")
        self.assertEqual(_problem_level({}), "error")


def _listening_lesson(lid: str = "s1-l1") -> dict:
    """A lesson with one listening item missing audio + one empty phase."""
    return {
        "id": lid,
        "name": f"Listen {lid}",
        "template": "listening",
        "content": {
            "stages": [
                {
                    "id": f"{lid}-st1",
                    "items": [
                        {
                            "id": f"{lid}-i1",
                            "runtimeType": "listenAndPick",
                            "prompt": "?",
                            "items": [],
                        }
                    ],
                }
            ],
            "listeningPhases": [
                {"id": f"{lid}-p1", "items": []},
            ],
        },
    }


class ListeningGapsTest(unittest.TestCase):
    """E2.1: content_quality audio_ready gaps surface into Context + suggestions."""

    def setUp(self) -> None:
        self.adapter = _adapter(
            sections=[_section("section1", [_listening_lesson("s1-l1")])],
            vocab=[],
        )
        # quality cache is module-level; clear so prior tests don't leak.
        from src.backend.experience.context_bus import _QUALITY_CACHE
        _QUALITY_CACHE.clear()

    def test_listening_gaps_collected(self) -> None:
        ctx = build_experience_context(self.adapter, include_quality=True, include_hygiene=False)
        self.assertTrue(ctx.listening_gaps, "expected audio_ready gaps")
        kinds = {g["kind"] for g in ctx.listening_gaps}
        self.assertIn("missing_audio", kinds)
        for g in ctx.listening_gaps:
            self.assertEqual(g["section_id"], "section1")
            self.assertTrue(g["lesson_id"])

    def test_suggestion_includes_listening_fill(self) -> None:
        ctx = build_experience_context(self.adapter, include_quality=True, include_hygiene=False)
        suggestions = local_suggestions(ctx, limit=5)
        ids = [s["action_id"] for s in suggestions]
        self.assertIn("listening.fill_gaps", ids)
        sug = next(s for s in suggestions if s["action_id"] == "listening.fill_gaps")
        self.assertEqual(sug["priority"], 2)
        self.assertGreater(sug["scope"]["gap_count"], 0)
        self.assertEqual(sug["scope"]["section_id"], "section1")
        self.assertTrue(sug["scope"]["gaps"])

    def test_quality_cache_returns_gaps_too(self) -> None:
        from src.backend.experience.context_bus import _QUALITY_CACHE

        ctx1 = build_experience_context(self.adapter, include_quality=True, include_hygiene=False)
        n1 = len(ctx1.listening_gaps)
        # second build hits the fingerprint cache; gaps must still be present.
        ctx2 = build_experience_context(self.adapter, include_quality=True, include_hygiene=False)
        self.assertEqual(len(ctx2.listening_gaps), n1)
        self.assertTrue(_QUALITY_CACHE["section1"][2])


class LocalSuggestionsLimitTest(unittest.TestCase):
    def test_limit_and_sort(self) -> None:
        ctx = ExperienceContext(
            empty_lessons=["a", "b"],
            empty_lesson_count=2,
            validate_error_count=3,
            hygiene={"placeholder_count": 1, "needs_review_count": 0},
        )
        s = local_suggestions(ctx, limit=2)
        self.assertEqual(len(s), 2)
        self.assertEqual(s[0]["priority"], 0)
        self.assertEqual(s[1]["priority"], 1)


class QualityCacheTest(unittest.TestCase):
    """G2: unchanged sections reuse the memoized quality mean."""

    def test_second_build_uses_cache(self) -> None:
        import src.backend.content_quality as content_quality

        section = _section(
            "s-cache",
            [
                {
                    "id": "s-cache-l1",
                    "name": "L",
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
                                                "id": "i1",
                                                "runtimeType": "showWord",
                                                "word": "ev",
                                            }
                                        ],
                                    }
                                ],
                            }
                        ]
                    },
                }
            ],
        )
        adapter = _adapter(sections=[section])
        ctx1 = build_experience_context(adapter, include_quality=True)
        self.assertIn("s-cache", ctx1.quality_by_section)

        original = content_quality.score_section

        def _boom(*_a, **_k):
            raise RuntimeError("score_section must not recompute")

        content_quality.score_section = _boom
        try:
            ctx2 = build_experience_context(adapter, include_quality=True)
        finally:
            content_quality.score_section = original
        self.assertEqual(ctx2.quality_by_section, ctx1.quality_by_section)


class NodeBadgesTest(unittest.TestCase):
    """T-01: ctx.node_badges aggregates empty lessons + weak sections."""

    def test_empty_lessons_get_empty_badge(self) -> None:
        adapter = _adapter(
            sections=[_section("section1", [_empty_lesson("s1-l1"), _empty_lesson("s1-l2")])],
            vocab=[{"id": "w1", "term": "merhaba", "translation": "hello"}],
        )
        ctx = build_experience_context(adapter, include_quality=False)
        self.assertEqual(ctx.node_badges.get("s1-l1"), {"empty": 1})
        self.assertEqual(ctx.node_badges.get("s1-l2"), {"empty": 1})

    def test_healthy_course_has_no_badges(self) -> None:
        adapter = _adapter(
            sections=[_section("section1", [_filled_lesson("s1-l1")])],
            vocab=[{"id": "w1", "term": "merhaba", "translation": "hello"}],
        )
        ctx = build_experience_context(adapter, include_quality=False)
        self.assertEqual(ctx.node_badges, {})

    def test_weak_section_badge_only_when_quality_low(self) -> None:
        # Two sections, one with an empty lesson (low quality) — only the
        # empty lesson gets a badge; section "weak" depends on score_section.
        adapter = _adapter(
            sections=[
                _section("section1", [_empty_lesson("s1-l1")]),
                _section("section2", [_filled_lesson("s2-l1")]),
            ],
            vocab=[{"id": "w1", "term": "merhaba", "translation": "hello"}],
        )
        ctx = build_experience_context(adapter, include_quality=True)
        # The empty lesson is always badged.
        self.assertIn("empty", ctx.node_badges.get("s1-l1", {}))
        # Whatever quality produced, badges dict only contains known kinds.
        for counts in ctx.node_badges.values():
            self.assertTrue(
                set(counts.keys()).issubset({"empty", "weak", "errors"})
            )

    def test_error_badges_from_validate_problems(self) -> None:
        adapter = _adapter(
            sections=[_section("section1", [_filled_lesson("s1-l1")])],
            vocab=[{"id": "w1", "term": "merhaba", "translation": "hello"}],
        )
        problems = [
            {
                "level": "error",
                "message": "dup",
                "path": "section:section1/unit:u1/lesson:s1-l1",
            },
            {
                "level": "error",
                "message": "other",
                "path": "section:section1/unit:u1/lesson:s1-l1",
            },
            {
                "level": "warning",
                "message": "warn",
                "path": "section:section1/unit:u1/lesson:s1-l1",
            },
            {
                "level": "error",
                "message": "sec",
                "path": "section:section1",
            },
        ]
        ctx = build_experience_context(
            adapter,
            include_quality=False,
            validate_problems=problems,
        )
        self.assertEqual(ctx.node_badges.get("s1-l1", {}).get("errors"), 2)
        self.assertEqual(ctx.node_badges.get("section1", {}).get("errors"), 1)
        # Warnings never create ·错.
        self.assertNotIn("warning", str(ctx.node_badges))

    def test_empty_lessons_among_helper(self) -> None:
        from src.backend.experience import empty_lessons_among

        self.assertEqual(
            empty_lessons_among(["a", "b", "c"], ["b", "c", "d"]),
            ["b", "c"],
        )
        self.assertEqual(empty_lessons_among(["a"], ["b"]), [])
        self.assertEqual(empty_lessons_among(None, ["a"]), [])

    def test_badges_default_empty(self) -> None:
        ctx = ExperienceContext()
        self.assertEqual(ctx.node_badges, {})


class DedupeSuggestionTest(unittest.TestCase):
    """K-20: hygiene.duplicate_count → local suggestion + /dedupe route."""

    def test_hygiene_counts_duplicates(self) -> None:
        from src.backend.experience.context_bus import _course_hygiene

        class _A:
            vocab = [
                {"id": "w1", "term": "Merhaba"},
                {"id": "w2", "term": "merhaba"},
            ]
            expressions = []
            grammar_points = []

            def detect_duplicates(self):
                return [
                    {
                        "type": "vocab",
                        "id": "w2",
                        "term": "merhaba",
                        "duplicate_in": "vocab:w1",
                    }
                ]

        h = _course_hygiene(_A())
        self.assertEqual(h["duplicate_count"], 1)

    def test_local_suggestions_include_dedupe(self) -> None:
        from src.backend.experience.context_bus import ExperienceContext, local_suggestions

        ctx = ExperienceContext(
            hygiene={
                "duplicate_count": 3,
                "placeholder_count": 0,
                "needs_review_count": 0,
            },
            empty_lesson_count=0,
            validate_error_count=0,
        )
        sugs = local_suggestions(ctx, limit=3)
        ids = [s["action_id"] for s in sugs]
        self.assertIn("resource.dedupe_suggest", ids)

    def test_action_and_intent(self) -> None:
        from src.backend.experience.actions import get_action
        from src.backend.experience.intent_router import route_intent

        spec = get_action("resource.dedupe_suggest")
        self.assertIsNotNone(spec)
        assert spec is not None
        self.assertFalse(spec.needs_confirm)
        i = route_intent("/dedupe")
        self.assertIsNotNone(i)
        assert i is not None
        self.assertEqual(i.action_id, "resource.dedupe_suggest")


if __name__ == "__main__":
    unittest.main()
