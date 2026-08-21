"""C-13 Experience Memory: session / project / author (pure, no Qt)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path
from types import SimpleNamespace

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.experience.memory import (  # noqa: E402
    AuthorMemory,
    ExperienceMemory,
    ProjectMemory,
    SessionMemory,
    assert_no_secrets,
    format_author_profile_line,
)
from src.backend.experience import build_experience_context, get_action  # noqa: E402
from src.backend.experience.intent_router import match_commands, route_intent  # noqa: E402


class SessionMemoryTest(unittest.TestCase):
    def test_record_and_ring(self) -> None:
        s = SessionMemory(maxlen=3)
        for i in range(5):
            s.record_intent(f"a{i}", label=f"L{i}", source="palette")
        self.assertEqual(len(s), 3)
        ids = [r.action_id for r in s.recent_intents()]
        self.assertEqual(ids, ["a2", "a3", "a4"])

    def test_empty_action_skipped(self) -> None:
        s = SessionMemory()
        self.assertIsNone(s.record_intent(""))
        self.assertEqual(len(s), 0)

    def test_clear(self) -> None:
        s = SessionMemory()
        s.record_intent("app.help")
        s.set_last_surface("teacher")
        s.clear()
        self.assertEqual(len(s), 0)
        self.assertEqual(s.last_surface, "")
        self.assertEqual(s.recent_intent_dicts(), [])

    def test_scope_keys_only_ids(self) -> None:
        s = SessionMemory()
        s.record_intent(
            "lesson.fill_empty",
            scope={
                "first_lesson_id": "s1-l1",
                "prompt": "secret long body should not dump",
                "api_key": "sk-leak",
            },
        )
        d = s.recent_intent_dicts()[0]
        keys = d["scope_keys"]
        self.assertTrue(any("first_lesson_id" in k for k in keys))
        blob = str(d)
        self.assertNotIn("sk-leak", blob.lower())
        self.assertNotIn("secret long body", blob)
        self.assertTrue(assert_no_secrets(d))

    def test_redact_forbidden_label(self) -> None:
        s = SessionMemory()
        s.record_intent("x", label="Bearer abc.api_key=1")
        self.assertEqual(s.recent_intents()[0].label, "[redacted]")

    def test_snapshot_shape(self) -> None:
        s = SessionMemory()
        s.record_intent("app.why", label="为何")
        snap = s.snapshot()
        self.assertEqual(snap["count"], 1)
        self.assertEqual(snap["recent_intents"][0]["action_id"], "app.why")
        self.assertTrue(assert_no_secrets(snap))


class LessonStyleMemoryTest(unittest.TestCase):
    """R-07 (v4.51): per-lesson Surgeon style memory on the session layer."""

    def test_record_and_read_per_lesson(self) -> None:
        s = SessionMemory()
        s.record_lesson_style("l1", "更口语化")
        s.record_lesson_style("l1", "选项更短")
        self.assertEqual(s.lesson_style_hints("l1"), ["更口语化", "选项更短"])
        self.assertEqual(s.lesson_style_hints("l2"), [])

    def test_dedupe_moves_to_end_and_limit(self) -> None:
        s = SessionMemory()
        for h in ["a", "b", "c", "d", "a", "e"]:
            s.record_lesson_style("l1", h)
        # dedupe re-appends "a"; ring capped at default limit=4
        self.assertEqual(s.lesson_style_hints("l1"), ["c", "d", "a", "e"])

    def test_clear_wipes_lesson_styles(self) -> None:
        s = SessionMemory()
        s.record_lesson_style("l1", "x")
        s.clear()
        self.assertEqual(s.lesson_style_hints("l1"), [])

    def test_redaction_and_empty_inputs_skipped(self) -> None:
        s = SessionMemory()
        s.record_lesson_style("l1", "set api_key=sk-123 in the prompt")
        s.record_lesson_style("", "x")
        s.record_lesson_style("l1", "")
        self.assertEqual(s.lesson_style_hints("l1"), [])

    def test_facade_passthrough_and_session_clear(self) -> None:
        m = ExperienceMemory()
        m.record_lesson_style("l1", "hint")
        self.assertEqual(m.lesson_style_hints("l1"), ["hint"])
        m.clear_session()
        self.assertEqual(m.lesson_style_hints("l1"), [])


class ProjectAuthorMemoryTest(unittest.TestCase):
    def test_project_bind_and_skills(self) -> None:
        p = ProjectMemory()
        p.bind("course-aaa")
        p.record_skill("lesson.balance")
        p.record_skill("lesson.fill_empty")
        p.record_skill("lesson.balance")
        snap = p.snapshot()
        assert snap is not None
        self.assertEqual(snap["course_key"], "course-aaa")
        # de-dupe move-to-end
        self.assertEqual(snap["recent_skills"][-1], "lesson.balance")
        p.bind("course-bbb")
        self.assertEqual(p.snapshot()["recent_skills"], [])
        p.bind("course-aaa")
        self.assertIn("lesson.fill_empty", p.snapshot()["recent_skills"])

    def test_author_clear(self) -> None:
        a = AuthorMemory()
        a.add_style_hint("prefer short stems")
        a.set_language_pref("target", "tr")
        self.assertIsNotNone(a.snapshot())
        a.clear()
        self.assertIsNone(a.snapshot())


class ExperienceMemoryFacadeTest(unittest.TestCase):
    def test_record_intent_updates_session_and_project(self) -> None:
        m = ExperienceMemory()
        m.bind_course("/tmp/demo-course")
        m.record_intent("validate.open_and_fix", label="修错", source="dock")
        self.assertEqual(len(m.session), 1)
        fields = m.context_fields()
        self.assertEqual(fields["recent_intents"][0]["action_id"], "validate.open_and_fix")
        proj = m.project.snapshot()
        self.assertIsNotNone(proj)
        assert proj is not None
        self.assertIn("validate.open_and_fix", proj["recent_skills"])

    def test_clear_session_keeps_project(self) -> None:
        m = ExperienceMemory()
        m.bind_course("/tmp/c")
        m.record_intent("app.pin")
        m.author.add_style_hint("x")
        m.clear_session()
        self.assertEqual(len(m.session), 0)
        self.assertIsNotNone(m.project.snapshot())
        self.assertIsNotNone(m.author.snapshot())

    def test_clear_all(self) -> None:
        m = ExperienceMemory()
        m.bind_course("/tmp/c")
        m.record_intent("app.help")
        m.author.add_style_hint("y")
        m.clear_all()
        self.assertEqual(len(m.session), 0)
        self.assertIsNone(m.project.snapshot())
        self.assertIsNone(m.author.snapshot())

    def test_clear_author_keeps_session_and_project(self) -> None:
        m = ExperienceMemory()
        m.bind_course("/tmp/c")
        m.record_intent("app.pin")
        m.author.add_style_hint("prefer short")
        m.author.set_language_pref("target", "tr")
        self.assertTrue(m.clear_author())
        self.assertIsNone(m.author.snapshot())
        self.assertEqual(len(m.session), 1)
        self.assertIsNotNone(m.project.snapshot())
        # Second clear with empty profile → False
        self.assertFalse(m.clear_author())

    def test_format_author_profile_line_counts_only(self) -> None:
        self.assertEqual(format_author_profile_line(None), "")
        self.assertEqual(format_author_profile_line({}), "")
        line = format_author_profile_line(
            {"style_hints": ["prefer short stems", "no formal"], "language_prefs": {"target": "tr"}}
        )
        self.assertIn("画像", line)
        self.assertIn("2 条风格提示", line)
        self.assertIn("1 项语言偏好", line)
        # Redaction: never dump hint text
        self.assertNotIn("prefer short", line)
        self.assertNotIn("formal", line)


class ClearAuthorActionTest(unittest.TestCase):
    def test_action_registered_not_dangerous(self) -> None:
        spec = get_action("memory.clear_author")
        self.assertIsNotNone(spec)
        assert spec is not None
        self.assertTrue(spec.implemented)
        self.assertFalse(spec.needs_confirm)  # privacy confirm in handler
        self.assertFalse(spec.dangerous)

    def test_slash_and_keyword(self) -> None:
        i = route_intent("/clear-profile")
        self.assertIsNotNone(i)
        assert i is not None
        self.assertEqual(i.action_id, "memory.clear_author")
        self.assertEqual(i.confidence, 1.0)
        kw = route_intent("清除画像")
        self.assertIsNotNone(kw)
        assert kw is not None
        self.assertEqual(kw.action_id, "memory.clear_author")
        matched = match_commands("/clear-profile")
        self.assertTrue(any(m.action_id == "memory.clear_author" for m in matched))


class ClearAuthorDispatchTest(unittest.TestCase):
    def test_dispatch_clears_and_records_closed_scope(self) -> None:
        from src.application.experience_skills_mixin import ExperienceSkillsMixin
        from src.backend.experience.metrics import ExperienceMetrics

        class Host(ExperienceSkillsMixin):
            def __init__(self) -> None:
                self.experience_memory = ExperienceMemory()
                self.experience_memory.author.add_style_hint("secret style body")
                self.experience_metrics = ExperienceMetrics()
                self._settings_obj = None
                self._status: list[str] = []
                self._events: list = []
                self._synced = False
                self._refreshed = False
                self._confirm_clear_memory = True

            def statusBar(self):  # noqa: N802
                host = self

                class SB:
                    def showMessage(self, msg, ms=0):  # noqa: N802
                        host._status.append(msg)

                return SB()

            def _record_experience_event(self, *a, **k):
                self._events.append((a, k))

            def _sync_experience_memory(self) -> None:
                self._synced = True

            def _refresh_experience(self, immediate=False, focus_only=False):
                self._refreshed = True

            def _resolve_experience_policy(self, *, action_id=None):
                from src.backend.experience.policy import resolve_policy

                return resolve_policy(None, action_id=action_id)

        host = Host()
        host._on_experience_suggestion(
            {"action_id": "memory.clear_author", "scope": {}}
        )
        self.assertIsNone(host.experience_memory.author.snapshot())
        self.assertTrue(host._synced)
        self.assertTrue(host._refreshed)
        self.assertTrue(any("已清除" in m for m in host._status))
        self.assertEqual(len(host._events), 1)
        _a, kwargs = host._events[0]
        scope = kwargs.get("scope") or {}
        self.assertEqual(scope.get("layer"), "author")
        self.assertTrue(scope.get("cleared"))
        blob = str(host._events)
        self.assertNotIn("secret style", blob)

    def test_cancel_keeps_profile(self) -> None:
        from src.application.experience_skills_mixin import ExperienceSkillsMixin
        from src.backend.experience.metrics import ExperienceMetrics

        class Host(ExperienceSkillsMixin):
            def __init__(self) -> None:
                self.experience_memory = ExperienceMemory()
                self.experience_memory.author.add_style_hint("keep me")
                self.experience_metrics = ExperienceMetrics()
                self._settings_obj = None
                self._status: list[str] = []
                self._confirm_clear_memory = False

            def statusBar(self):  # noqa: N802
                host = self

                class SB:
                    def showMessage(self, msg, ms=0):  # noqa: N802
                        host._status.append(msg)

                return SB()

            def _resolve_experience_policy(self, *, action_id=None):
                from src.backend.experience.policy import resolve_policy

                return resolve_policy(None, action_id=action_id)

        host = Host()
        host._on_experience_suggestion(
            {"action_id": "memory.clear_author", "scope": {}}
        )
        self.assertIsNotNone(host.experience_memory.author.snapshot())
        self.assertTrue(any("取消" in m for m in host._status))

    def test_empty_profile_status(self) -> None:
        from src.application.experience_skills_mixin import ExperienceSkillsMixin
        from src.backend.experience.metrics import ExperienceMetrics

        class Host(ExperienceSkillsMixin):
            def __init__(self) -> None:
                self.experience_memory = ExperienceMemory()
                self.experience_metrics = ExperienceMetrics()
                self._settings_obj = None
                self._status: list[str] = []
                self._confirm_clear_memory = True

            def statusBar(self):  # noqa: N802
                host = self

                class SB:
                    def showMessage(self, msg, ms=0):  # noqa: N802
                        host._status.append(msg)

                return SB()

            def _resolve_experience_policy(self, *, action_id=None):
                from src.backend.experience.policy import resolve_policy

                return resolve_policy(None, action_id=action_id)

        host = Host()
        host._on_experience_suggestion(
            {"action_id": "memory.clear_author", "scope": {}}
        )
        self.assertTrue(any("无可清" in m or "无作者" in m for m in host._status))


class DockProfileUiTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        import os

        os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
        from tests._qtapp import qt_app

        qt_app()

    def test_clear_button_visibility(self) -> None:
        from src.backend.experience.context_bus import ExperienceContext
        from src.widgets.experience_dock import ExperienceDock

        dock = ExperienceDock()
        ctx = ExperienceContext(
            course_dir="/tmp/x",
            language="tr",
            author_profile={"style_hints": ["a"], "language_prefs": {}},
        )
        dock.apply_context(ctx)
        self.assertFalse(dock._clear_profile_btn.isHidden())
        self.assertIn("画像", dock._profile_label.text())
        # clear profile line after empty context
        ctx2 = ExperienceContext(course_dir="/tmp/x", language="tr", author_profile=None)
        dock.apply_context(ctx2)
        self.assertTrue(dock._clear_profile_btn.isHidden())


class ContextInjectionTest(unittest.TestCase):
    def test_build_context_carries_intents(self) -> None:
        adapter = SimpleNamespace(
            sections=[],
            vocab=[],
            expressions=[],
            grammar_points=[],
            index={"language": "tr"},
            course_dir=None,
        )
        intents = [{"action_id": "app.why", "label": "为何", "ts": 1.0, "scope_keys": [], "source": "palette"}]
        ctx = build_experience_context(
            adapter,
            include_quality=False,
            include_hygiene=False,
            recent_intents=intents,
            author_profile={"style_hints": ["short"]},
        )
        self.assertEqual(ctx.recent_intents[0]["action_id"], "app.why")
        self.assertEqual(ctx.author_profile["style_hints"], ["short"])


if __name__ == "__main__":
    unittest.main()
