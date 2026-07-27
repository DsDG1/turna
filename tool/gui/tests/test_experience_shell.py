"""E0 shell: ExperienceShell rebuild + status line (Qt light)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.application.experience_shell import (  # noqa: E402
    ExperienceShell,
    format_health_status_line,
)
from src.backend.experience import ExperienceContext  # noqa: E402
from tests._qtapp import _App as _TestApp  # noqa: E402


def _adapter(*, sections=None, vocab=None, index=None):
    class _A:
        pass

    a = _A()
    a.sections = sections or []
    a.vocab = vocab or []
    a.expressions = []
    a.grammar_points = []
    a.index = index or {"language": "tr"}
    a.course_dir = None
    return a


def _section(sid: str, lessons: list[dict]) -> dict:
    return {
        "id": sid,
        "name": sid,
        "level": "A1",
        "units": [{"id": f"{sid}-u1", "name": "u", "lessons": lessons}],
    }


class FormatStatusLineTest(unittest.TestCase):
    def test_none(self) -> None:
        self.assertIn("未加载", format_health_status_line(None))

    def test_healthy(self) -> None:
        ctx = ExperienceContext(healthy=True, lesson_count=3, section_count=1)
        self.assertIn("健康", format_health_status_line(ctx))

    def test_empty_and_errors(self) -> None:
        ctx = ExperienceContext(
            healthy=False,
            empty_lesson_count=2,
            validate_error_count=1,
            hygiene={"placeholder_count": 4},
        )
        line = format_health_status_line(ctx)
        self.assertIn("空课 2", line)
        self.assertIn("错 1", line)
        self.assertIn("待补 4", line)


class ExperienceShellRebuildTest(unittest.TestCase):
    def setUp(self) -> None:
        _TestApp.get()
        empty = {
            "id": "s1-l1",
            "name": "Empty",
            "template": "intro",
            "content": {"subLessons": []},
        }
        self.adapter = _adapter(sections=[_section("section1", [empty])])
        self.shell = ExperienceShell(debounce_ms=0)

    def test_rebuild_empty_course(self) -> None:
        self.shell.set_adapter(self.adapter)
        ctx = self.shell.rebuild_now()
        self.assertIsNotNone(ctx)
        assert ctx is not None
        self.assertEqual(ctx.empty_lesson_count, 1)
        self.assertFalse(ctx.healthy)
        sugs = self.shell.suggestions
        self.assertTrue(any(s["action_id"] == "lesson.fill_empty" for s in sugs))

    def test_selection_updates(self) -> None:
        self.shell.set_adapter(self.adapter)
        self.shell.set_selection(("lesson", "s1-l1"))
        ctx = self.shell.rebuild_now()
        assert ctx is not None
        self.assertIsNotNone(ctx.selection)
        self.assertEqual(ctx.selection.id, "s1-l1")

    def test_status_signal(self) -> None:
        lines: list[str] = []
        self.shell.status_line_changed.connect(lines.append)
        self.shell.set_adapter(self.adapter)
        self.shell.rebuild_now()
        self.assertTrue(lines)
        self.assertIn("空课", lines[-1])

    def test_clear_adapter(self) -> None:
        self.shell.set_adapter(self.adapter)
        self.shell.rebuild_now()
        self.shell.set_adapter(None)
        self.assertIsNone(self.shell.context)

    def test_pin_survives_selection_change(self) -> None:
        """S-14: pinned refs stay across rebuild when selection moves."""
        from src.backend.experience import NodeRef

        self.shell.set_adapter(self.adapter)
        self.shell.set_selection(("lesson", "s1-l1"))
        self.assertTrue(self.shell.toggle_pin_selection())
        self.shell.set_selection(("section", "section1"))
        ctx = self.shell.rebuild_now()
        assert ctx is not None
        self.assertEqual(len(ctx.pinned_refs), 1)
        self.assertEqual(ctx.pinned_refs[0].id, "s1-l1")
        # Unpin
        self.shell.set_selection(NodeRef("lesson", "s1-l1"))
        self.assertFalse(self.shell.toggle_pin_selection())
        ctx2 = self.shell.rebuild_now()
        assert ctx2 is not None
        self.assertEqual(ctx2.pinned_refs, [])

    def test_set_adapter_none_clears_pin(self) -> None:
        self.shell.set_adapter(self.adapter)
        self.shell.set_selection(("lesson", "s1-l1"))
        self.shell.toggle_pin_selection()
        self.shell.set_adapter(None)
        self.assertEqual(self.shell.pinned_refs, [])

    def test_invalidate_focus_mutates_ctx_in_place(self) -> None:
        """C-03: focus-only path mutates the retained ctx, skips full rebuild."""
        self.shell.set_adapter(self.adapter)
        self.shell.set_selection(("lesson", "s1-l1"))
        ctx0 = self.shell.rebuild_now()
        assert ctx0 is not None
        struct_empty = ctx0.empty_lesson_count
        struct_hygiene = dict(ctx0.hygiene)
        struct_quality = dict(ctx0.quality_by_section)
        struct_validate = ctx0.validate_error_count
        struct_badges = dict(ctx0.node_badges)

        # Move selection to the section; focus-only refresh.
        self.shell.set_selection(("section", "section1"))
        events: list = []
        self.shell.context_changed.connect(events.append)
        self.shell.invalidate_focus()
        ctx1 = self.shell.context
        self.assertIs(ctx1, ctx0, "focus-only must mutate the same ctx object")
        assert ctx1 is not None
        self.assertIsNotNone(ctx1.selection)
        self.assertEqual(ctx1.selection.id, "section1")
        # Structure-derived fields preserved (not rescanned).
        self.assertEqual(ctx1.empty_lesson_count, struct_empty)
        self.assertEqual(ctx1.hygiene, struct_hygiene)
        self.assertEqual(ctx1.quality_by_section, struct_quality)
        self.assertEqual(ctx1.validate_error_count, struct_validate)
        self.assertEqual(ctx1.node_badges, struct_badges)
        # Signals still fire.
        self.assertTrue(events)
        self.assertIs(events[-1], ctx1)

    def test_invalidate_focus_does_not_call_build_experience_context(self) -> None:
        """C-03: focus-only must skip the full build pipeline."""
        self.shell.set_adapter(self.adapter)
        self.shell.set_selection(("lesson", "s1-l1"))
        self.shell.rebuild_now()
        import src.backend.experience.context_bus as cb

        original = cb.build_experience_context
        called = {"n": 0}

        def _boom(*a, **k):
            called["n"] += 1
            raise AssertionError("focus-only must not call build_experience_context")

        cb.build_experience_context = _boom
        try:
            self.shell.set_selection(("section", "section1"))
            self.shell.invalidate_focus()
            ctx = self.shell.context
            assert ctx is not None
            self.assertEqual(ctx.selection.id, "section1")
        finally:
            cb.build_experience_context = original
        self.assertEqual(called["n"], 0)

    def test_invalidate_focus_falls_back_when_no_ctx(self) -> None:
        """C-03: with no retained ctx, focus-only falls back to full rebuild."""
        self.shell.set_adapter(self.adapter)
        # No rebuild yet — ctx is None. invalidate_focus must build.
        events: list = []
        self.shell.context_changed.connect(events.append)
        self.shell.set_selection(("lesson", "s1-l1"))
        self.shell.invalidate_focus()
        self.assertIsNotNone(self.shell.context)
        self.assertTrue(events)

    def test_workshop_draft_injected_and_cleared(self) -> None:
        """E5/M3: set_workshop_draft flows into Context; adapter null clears it."""
        self.shell.set_adapter(self.adapter)
        self.shell.set_workshop_draft(
            {
                "open": True,
                "project_id": "wp1",
                "project_name": "Demo",
                "has_draft": True,
                "draft_section_count": 1,
            }
        )
        ctx = self.shell.rebuild_now()
        self.assertIsNotNone(ctx)
        assert ctx is not None
        self.assertIsNotNone(ctx.workshop_draft)
        assert ctx.workshop_draft is not None
        self.assertEqual(ctx.workshop_draft["project_id"], "wp1")
        # Focus-only path also mirrors draft.
        self.shell.set_workshop_draft(
            {"open": True, "project_id": "wp2", "project_name": "B"}
        )
        self.shell.invalidate_focus()
        assert self.shell.context is not None
        self.assertEqual(self.shell.context.workshop_draft["project_id"], "wp2")
        # Null adapter clears draft retention.
        self.shell.set_adapter(None)
        self.shell.set_adapter(self.adapter)
        ctx2 = self.shell.rebuild_now()
        assert ctx2 is not None
        self.assertIsNone(ctx2.workshop_draft)

    def test_recent_intents_injected(self) -> None:
        """C-13: set_recent_intents appears on Context full + focus rebuild."""
        self.shell.set_adapter(self.adapter)
        intents = [
            {
                "action_id": "app.why",
                "label": "为何",
                "ts": 1.0,
                "scope_keys": [],
                "source": "palette",
            }
        ]
        self.shell.set_recent_intents(intents)
        ctx = self.shell.rebuild_now()
        assert ctx is not None
        self.assertEqual(ctx.recent_intents[0]["action_id"], "app.why")
        self.shell.set_recent_intents(
            intents + [{"action_id": "app.pin", "label": "钉", "ts": 2.0, "scope_keys": [], "source": "x"}]
        )
        self.shell.invalidate_focus()
        assert self.shell.context is not None
        self.assertEqual(len(self.shell.context.recent_intents), 2)


class ExperienceShellStaleTest(unittest.TestCase):
    """A3 ③: content-stale flag + mark_stale()."""

    def setUp(self) -> None:
        _TestApp.get()

    def test_stale_defaults_false(self) -> None:
        shell = ExperienceShell(debounce_ms=0)
        self.assertFalse(shell._content_stale)

    def test_mark_stale_sets_flag_with_debounce(self) -> None:
        # Non-zero debounce -> mark_stale sets the flag and starts the timer
        # without an immediate rebuild (timer does not fire without an event loop).
        shell = ExperienceShell(debounce_ms=100)
        shell.set_adapter(self._adapter())
        shell.mark_stale()
        self.assertTrue(shell._content_stale)

    def test_rebuild_clears_stale(self) -> None:
        shell = ExperienceShell(debounce_ms=0)
        shell.set_adapter(self._adapter())
        shell._content_stale = True
        shell.rebuild_now()
        self.assertFalse(shell._content_stale)

    def _adapter(self):
        empty = {
            "id": "s1-l1",
            "name": "Empty",
            "template": "intro",
            "content": {"subLessons": []},
        }
        return _adapter(sections=[_section("section1", [empty])])


class ExperienceDockSmokeTest(unittest.TestCase):
    def setUp(self) -> None:
        _TestApp.get()

    def test_apply_context(self) -> None:
        from src.widgets.experience_dock import ExperienceDock

        dock = ExperienceDock()
        ctx = ExperienceContext(
            healthy=False,
            section_count=1,
            unit_count=1,
            lesson_count=2,
            empty_lesson_count=2,
            empty_lessons=["a", "b"],
            language="tr",
            cefr_hint="A1",
        )
        dock.apply_context_and_suggestions(
            ctx,
            [{"priority": 1, "title": "填充 2 节空课", "action_id": "lesson.fill_empty"}],
        )
        self.assertIn("空课", dock._metrics.text())

    def test_workshop_draft_line(self) -> None:
        from src.widgets.experience_dock import ExperienceDock

        dock = ExperienceDock()
        ctx = ExperienceContext(
            healthy=True,
            lesson_count=1,
            section_count=1,
            workshop_draft={
                "open": True,
                "project_id": "p",
                "project_name": "工坊演示",
                "has_material": True,
                "has_knowledge": False,
                "has_draft": True,
                "has_imported": False,
                "draft_section_count": 2,
                "imported_section_ids": [],
                "ui_stage": 1,
            },
        )
        dock.apply_context(ctx)
        self.assertIn("工坊", dock._metrics.text())
        self.assertIn("工坊演示", dock._metrics.text())

    def test_recent_intents_line(self) -> None:
        from src.widgets.experience_dock import ExperienceDock

        dock = ExperienceDock()
        ctx = ExperienceContext(
            healthy=True,
            lesson_count=1,
            recent_intents=[
                {
                    "action_id": "lesson.fill_empty",
                    "label": "填充空课",
                    "ts": 1.0,
                    "scope_keys": [],
                    "source": "dock",
                }
            ],
        )
        dock.apply_context(ctx)
        self.assertIn("最近意图", dock._metrics.text())
        self.assertIn("填充空课", dock._metrics.text())

    def test_suggestion_signal(self) -> None:
        from src.widgets.experience_dock import ExperienceDock
        from PySide6.QtTest import QTest
        from PySide6.QtCore import Qt

        dock = ExperienceDock()
        received: list[dict] = []
        dock.suggestion_clicked.connect(received.append)
        dock.apply_suggestions(
            [{"priority": 0, "title": "修错误", "action_id": "validate.open_and_fix"}]
        )
        # Find the button and click it.
        btn = None
        for i in range(dock._sug_layout.count()):
            w = dock._sug_layout.itemAt(i).widget()
            if w is not None and hasattr(w, "text") and w.text() == "修错误":
                btn = w
                break
        self.assertIsNotNone(btn)
        QTest.mouseClick(btn, Qt.MouseButton.LeftButton)
        self.assertEqual(len(received), 1)
        self.assertEqual(received[0]["action_id"], "validate.open_and_fix")

    def test_timeline_set_and_click(self) -> None:
        from src.widgets.experience_dock import ExperienceDock
        from PySide6.QtTest import QTest
        from PySide6.QtCore import Qt

        dock = ExperienceDock()
        received: list[dict] = []
        dock.timeline_clicked.connect(received.append)
        dock.set_timeline(
            [
                {
                    "kind": "chip.apply",
                    "summary": "改写了题目 q1",
                    "action_id": "item.rewrite",
                    "scope": {"item_id": "q1"},
                    "undo_hint": "Ctrl+Z",
                }
            ]
        )
        btn = None
        for i in range(dock._tl_layout.count()):
            w = dock._tl_layout.itemAt(i).widget()
            if w is not None and hasattr(w, "text") and "q1" in w.text():
                btn = w
                break
        self.assertIsNotNone(btn)
        QTest.mouseClick(btn, Qt.MouseButton.LeftButton)
        self.assertEqual(len(received), 1)
        self.assertEqual(received[0]["kind"], "chip.apply")


class MainWindowExperienceWireTest(unittest.TestCase):
    """Shared MainWindow for wire tests (construction is the suite bottleneck)."""

    @classmethod
    def setUpClass(cls) -> None:
        from tests._mainwindow_fixture import build_main_window

        cls.win = build_main_window()

    def setUp(self) -> None:
        from tests._mainwindow_fixture import reset_main_window

        reset_main_window(self.win)

    def test_dock_and_shell_exist(self) -> None:
        self.assertTrue(hasattr(self.win, "experience"))
        self.assertTrue(hasattr(self.win, "experience_dock_widget"))
        self.assertTrue(hasattr(self.win, "job_tray"))
        self.assertTrue(hasattr(self.win, "_health_status_label"))

    def test_refresh_after_open_updates_status(self) -> None:
        empty = {
            "id": "s1-l1",
            "name": "Empty",
            "template": "intro",
            "content": {"subLessons": []},
        }
        self.win.adapter.sections = [
            {
                "id": "section1",
                "name": "S1",
                "level": "A1",
                "units": [{"id": "u1", "name": "U", "lessons": [empty]}],
            }
        ]
        self.win.adapter.index = {"language": "tr"}
        self.win.adapter.vocab = []
        self.win.adapter.expressions = []
        self.win.adapter.grammar_points = []
        self.win.course_dir = Path("/tmp/fake-course-exp")
        self.win._refresh_experience(immediate=True)
        self.assertIsNotNone(self.win.experience.context)
        self.assertIn("空课", self.win._health_status_label.text())

    def test_suggestion_fill_empty_no_course_dir_no_modal(self) -> None:
        """P10 T-03: missing course_dir uses statusBar, never QMessageBox hang."""
        from unittest.mock import MagicMock, patch

        self.win.course_dir = None
        self.win.tree.select_lesson = MagicMock()
        self.win._on_ai_edit = MagicMock()
        self.win._run_fill_lesson_patch_flow = MagicMock()
        with patch("src.application.experience_skills_mixin.QMessageBox") as mb:
            self.win._on_experience_suggestion(
                {
                    "action_id": "lesson.fill_empty",
                    "scope": {"first_lesson_id": "s1-l1"},
                }
            )
            mb.warning.assert_not_called()
            mb.information.assert_not_called()
        self.win.tree.select_lesson.assert_called_once_with("s1-l1")
        self.win._on_ai_edit.assert_not_called()
        self.win._run_fill_lesson_patch_flow.assert_not_called()
        self.assertIn("课程目录", self.win.statusBar().currentMessage())

    def test_suggestion_fill_empty_incomplete_ai_falls_back_to_editor(self) -> None:
        """Without complete AI config, keep legacy ``_on_ai_edit`` path."""
        from pathlib import Path
        from unittest.mock import MagicMock

        self.win.course_dir = Path("/tmp/fake-course-exp")
        # Incomplete config (no api key / incomplete).
        self.win._ai_config = MagicMock()
        self.win._ai_config.is_complete = False
        self.win.tree.select_lesson = MagicMock()
        self.win._on_ai_edit = MagicMock()
        self.win._run_fill_lesson_patch_flow = MagicMock()
        self.win._on_experience_suggestion(
            {
                "action_id": "lesson.fill_empty",
                "scope": {"first_lesson_id": "s1-l1"},
            }
        )
        self.win.tree.select_lesson.assert_called_once_with("s1-l1")
        self.win._on_ai_edit.assert_called_once_with("lesson", "s1-l1")
        self.win._run_fill_lesson_patch_flow.assert_not_called()

    def test_suggestion_fill_empty_complete_ai_uses_lesson_patch_flow(self) -> None:
        """With course + complete AI config, dispatch LessonPatch fill flow."""
        from pathlib import Path
        from unittest.mock import MagicMock

        empty = {
            "id": "s1-l1",
            "name": "Empty",
            "template": "intro",
            "content": {"subLessons": []},
        }
        section = {
            "id": "section1",
            "name": "S1",
            "level": "A1",
            "units": [{"id": "u1", "name": "U", "lessons": [empty]}],
        }
        self.win.adapter.sections = [section]
        self.win.adapter.invalidate_node_index()
        self.win.course_dir = Path("/tmp/fake-course-exp")
        self.win._ai_config = MagicMock()
        self.win._ai_config.is_complete = True
        self.win.tree.select_lesson = MagicMock()
        self.win._on_ai_edit = MagicMock()
        self.win._run_fill_lesson_patch_flow = MagicMock()
        self.win._on_experience_suggestion(
            {
                "action_id": "lesson.fill_empty",
                "scope": {"first_lesson_id": "s1-l1"},
            }
        )
        self.win.tree.select_lesson.assert_called_once_with("s1-l1")
        self.win._on_ai_edit.assert_not_called()
        self.win._run_fill_lesson_patch_flow.assert_called_once()
        kwargs = self.win._run_fill_lesson_patch_flow.call_args.kwargs
        self.assertEqual(kwargs.get("lesson_id"), "s1-l1")
        self.assertEqual(kwargs.get("section"), section)

    def test_suggestion_campaign_opens_dialog(self) -> None:
        """E2.0: quality.campaign_worst_n dispatches to handler (no modal hang)."""
        from unittest.mock import MagicMock, patch

        # HANDLERS call the handler module directly (M7), not host wrappers.
        with patch(
            "src.application.experience_handlers.quality.handle_quality_campaign"
        ) as m:
            self.win._on_experience_suggestion(
                {
                    "action_id": "quality.campaign_worst_n",
                    "scope": {"section_id": "section1"},
                }
            )
        m.assert_called_once()
        host, scope = m.call_args[0]
        self.assertIs(host, self.win)
        self.assertEqual(scope.get("section_id"), "section1")

    def test_suggestion_unknown_action_no_crash(self) -> None:
        self.win._on_experience_suggestion({"action_id": "no.such.action"})

    def test_fill_stubs_requires_course_dir(self) -> None:
        from unittest.mock import patch

        self.win.course_dir = None
        # Should warn (mocked: modal would block offscreen) and return
        # without touching the job tray.
        with patch(
            "src.application.experience_handlers.fill.safe_warning"
        ) as warn:
            self.win._experience_fill_stubs()
        warn.assert_called_once()
        self.assertFalse(self.win.job_tray.is_busy())

    def _open_fake_course(self) -> None:
        empty = {
            "id": "s1-l1",
            "name": "Empty",
            "template": "intro",
            "content": {"subLessons": []},
        }
        self.win.adapter.sections = [
            {
                "id": "section1",
                "name": "S1",
                "level": "A1",
                "units": [{"id": "u1", "name": "U", "lessons": [empty]}],
            }
        ]
        self.win.course_dir = Path("/tmp/fake-course-exp")

    def test_diagnose_problems_applied_when_current(self) -> None:
        self._open_fake_course()
        problems = [{"level": "error", "message": "坏引用", "path": ""}]
        self.win._on_diagnose_problems(self.win.course_dir, problems)
        ctx = self.win.experience.context
        self.assertIsNotNone(ctx)
        self.assertEqual(ctx.validate_error_count, 1)
        self.assertFalse(self.win.job_tray.is_busy())
        # P0 suggestion now appears without a manual validate (G1).
        sugs = self.win.experience.suggestions
        self.assertTrue(
            any(s["action_id"] == "validate.open_and_fix" for s in sugs)
        )

    def test_diagnose_stale_result_dropped(self) -> None:
        self._open_fake_course()
        old = [{"level": "warning", "message": "旧缓存", "path": ""}]
        self.win.experience.set_validate_problems(old)
        self.win._on_diagnose_problems(
            Path("/tmp/other-course"), [{"level": "error", "message": "x"}]
        )
        # 过期结果不得覆盖缓存（G1 stale guard）。
        self.assertEqual(self.win.experience._validate_problems, old)

    def test_resource_change_invalidates_experience(self) -> None:
        from unittest.mock import MagicMock

        self._open_fake_course()
        self.win.experience.set_validate_problems(None)
        self.win.experience.mark_stale = MagicMock()
        self.win._on_experience_resources_changed()
        # A3 ③: resource edits mark the context stale (debounced rebuild).
        self.win.experience.mark_stale.assert_called_once_with()


if __name__ == "__main__":
    unittest.main()
