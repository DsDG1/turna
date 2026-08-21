"""E1 actions registry: ids aligned with local_suggestions, confirm guards."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.experience import ACTIONS, ActionSpec, get_action  # noqa: E402
from src.backend.experience import APP_BUILTIN_PREFIX  # noqa: E402
from src.backend.experience.context_bus import local_suggestions  # noqa: E402
from src.backend.experience.context_bus import build_experience_context  # noqa: E402


def _adapter(*, sections=None, index=None):
    class _A:
        pass

    a = _A()
    a.sections = sections or []
    a.vocab = []
    a.expressions = []
    a.grammar_points = []
    a.index = index or {"language": "tr"}
    a.course_dir = None
    return a


class ActionRegistryTest(unittest.TestCase):
    def test_core_actions_registered(self) -> None:
        for action_id in (
            "validate.open_and_fix",
            "lesson.fill_empty",
            "resource.fill_stubs",
            "soft.preview_hygiene",
            "resource.open_hygiene",
        ):
            spec = get_action(action_id)
            self.assertIsNotNone(spec, action_id)
            self.assertTrue(spec.implemented, action_id)

    def test_campaign_worst_n_implemented_e2(self) -> None:
        spec = get_action("quality.campaign_worst_n")
        self.assertIsNotNone(spec)
        self.assertTrue(spec.implemented)

    def test_unknown_action_returns_none(self) -> None:
        self.assertIsNone(get_action("no.such.action"))
        self.assertIsNone(get_action(""))

    def test_write_actions_require_confirmation(self) -> None:
        # 红线：任何会写树的 AI action 都不允许静默写盘。
        # app.* 内建命令（save/undo/why/pin/help）是用户显式点击的窗口命令，
        # 不是 AI 写树 action，排除在红线之外。
        # 仅打开编辑器 / 导航、零写盘的 skill：needs_confirm=False。
        open_only = frozenset({
            "resource.open_hygiene",
            "resource.dedupe_suggest",  # K-20：查重建议 → 开资源，不自动删
            "help.fix",  # K-25：可点导览，零写盘
            "course.compare_sections",  # K-03：只读对比
            "goal.plan",  # E3-A：local 规划只读展示（不写树）
            "goal.expand",  # E3-B1：加深规划同上
            "publish.brief",  # K-04：打开发布对话框，结构红仍由发布路径阻断
            "git.commit_message",  # K-24：只读预览 + 剪贴板
            "git.explain_diff",  # K-24：同上
            "attachment.open_in_workshop",  # M-01：打开/聚焦工坊，零写盘
            "textbook.ocr_suggest",  # M-03：只读 OCR 图片附件转文本附件（不写课程树）
            "textbook.open_workshop",  # K-22：打开工坊，零写盘
            "memory.clear_author",  # M-07：清本地画像，不写课程树；handler 内隐私确认
        })
        for spec in ACTIONS.values():
            if spec.action_id.startswith(APP_BUILTIN_PREFIX):
                self.assertFalse(
                    spec.needs_confirm, spec.action_id
                )  # 显式命令无需二次确认
                continue
            if spec.action_id in open_only:
                self.assertFalse(spec.needs_confirm, spec.action_id)
                continue
            self.assertTrue(spec.needs_confirm, spec.action_id)

    def test_app_builtins_registered(self) -> None:
        # app.* 内建命令进入 registry 作为可枚举真源（S-08/S-10）。
        for action_id in ("app.save", "app.undo", "app.help", "app.pin", "app.why"):
            spec = get_action(action_id)
            self.assertIsNotNone(spec, action_id)
            self.assertTrue(spec.implemented, action_id)
            self.assertFalse(spec.needs_confirm, action_id)

    def test_suggestion_action_ids_are_registered(self) -> None:
        # local_suggestions 产出的每个 action_id 都必须能在注册表查到。
        section = {
            "id": "s1",
            "name": "s1",
            "level": "A1",
            "units": [
                {
                    "id": "s1-u1",
                    "name": "u",
                    "lessons": [{"id": "l1", "title": "空课", "stages": []}],
                }
            ],
        }
        ctx = build_experience_context(
            _adapter(sections=[section]),
            validate_problems=[{"level": "error", "message": "x", "path": ""}],
        )
        suggestions = local_suggestions(ctx)
        self.assertTrue(suggestions)
        for sug in suggestions:
            self.assertIsInstance(
                get_action(sug.get("action_id")), ActionSpec, sug.get("action_id")
            )


class DangerousSkillSwitchTest(unittest.TestCase):
    """C-20: dangerous-skill switch ships off; accessor is observer-safe."""

    def test_dangerous_actions_are_the_six_structural_rewrites(self) -> None:
        # v4.69: six structural-rewrite actions are dangerous (C-20 retarget);
        # everything else is not.
        dangerous = frozenset(aid for aid, spec in ACTIONS.items() if spec.dangerous)
        expected = frozenset(
            {
                "lesson.regenerate",
                "lesson.batch_regenerate",
                "unit.regenerate",
                "unit.batch_regenerate",
                "lesson.batch_set_template",
                "course.outline_shells",
            }
        )
        self.assertEqual(dangerous, expected)
        for aid, spec in ACTIONS.items():
            if aid in expected:
                self.assertTrue(spec.dangerous, aid)
            else:
                self.assertFalse(spec.dangerous, aid)

    def test_dangerous_set_closed_and_matches_derived(self) -> None:
        from src.backend.experience import DANGEROUS_ACTION_IDS

        derived = frozenset(aid for aid, spec in ACTIONS.items() if spec.dangerous)
        self.assertEqual(DANGEROUS_ACTION_IDS, derived)
        self.assertEqual(len(DANGEROUS_ACTION_IDS), 6)

    def test_is_dangerous_unknown_and_safe(self) -> None:
        from src.backend.experience import is_dangerous

        self.assertFalse(is_dangerous("validate.open_and_fix"))
        self.assertFalse(is_dangerous("no.such.action"))
        self.assertFalse(is_dangerous(""))

    def test_accessor_default_off(self) -> None:
        from src.application.settings import Settings
        from src.backend.experience import is_dangerous_skill_allowed

        self.assertFalse(is_dangerous_skill_allowed(Settings()))

    def test_accessor_flag_on_copilot_allowed(self) -> None:
        from src.application.settings import Settings
        from src.backend.experience import is_dangerous_skill_allowed

        s = Settings(experience_allow_dangerous_skills=True, experience_mode="copilot")
        self.assertTrue(is_dangerous_skill_allowed(s))

    def test_accessor_flag_off_blocks(self) -> None:
        from src.application.settings import Settings
        from src.backend.experience import is_dangerous_skill_allowed

        s = Settings(experience_allow_dangerous_skills=False, experience_mode="copilot")
        self.assertFalse(is_dangerous_skill_allowed(s))

    def test_accessor_observer_blocks_even_when_flag_on(self) -> None:
        # S-15 parity: observer 模式零危险侧效应，即使开关开启也判 False。
        from src.application.settings import Settings
        from src.backend.experience import is_dangerous_skill_allowed

        s = Settings(experience_allow_dangerous_skills=True, experience_mode="observer")
        self.assertFalse(is_dangerous_skill_allowed(s))


class DangerousDispatchGateTest(unittest.TestCase):
    """C-20: _on_experience_suggestion gates dangerous skills at the C-14 funnel."""

    def setUp(self) -> None:
        from tests._mainwindow_fixture import build_main_window

        self.win = build_main_window()

    def _with_dangerous(self, action_id: str):
        """Temporarily mark an action dangerous; return a restore closure."""
        from src.backend.experience import actions as actions_mod

        orig = actions_mod.ACTIONS[action_id]
        actions_mod.ACTIONS[action_id] = ActionSpec(action_id, orig.title, dangerous=True)

        def restore():
            actions_mod.ACTIONS[action_id] = orig

        return restore

    def _configure(self, *, allow: bool, mode: str) -> None:
        self.win._settings_obj.experience_allow_dangerous_skills = allow
        self.win._settings_obj.experience_mode = mode

    def test_dangerous_blocked_when_switch_off(self) -> None:
        restore = self._with_dangerous("validate.open_and_fix")
        self._configure(allow=False, mode="copilot")
        try:
            # M7: HANDLERS call handler modules (lazy), not host wrappers.
            with patch("src.app.QMessageBox.information") as dlg, patch(
                "src.application.experience_handlers.fill.handle_validate_and_fix"
            ) as handler:
                self.win._on_experience_suggestion(
                    {"action_id": "validate.open_and_fix", "scope": {}}
                )
        finally:
            restore()
        handler.assert_not_called()  # gated, not dispatched
        self.assertTrue(dlg.called)  # lock dialog shown

    def test_dangerous_allowed_when_switch_on(self) -> None:
        restore = self._with_dangerous("validate.open_and_fix")
        self._configure(allow=True, mode="copilot")
        try:
            with patch("src.app.QMessageBox.information") as dlg, patch(
                "src.application.experience_handlers.fill.handle_validate_and_fix"
            ) as handler:
                self.win._on_experience_suggestion(
                    {"action_id": "validate.open_and_fix", "scope": {}}
                )
        finally:
            restore()
        handler.assert_called_once()  # dispatched
        self.assertFalse(dlg.called)

    def test_dangerous_blocked_in_observer_even_when_flag_on(self) -> None:
        restore = self._with_dangerous("validate.open_and_fix")
        self._configure(allow=True, mode="observer")
        try:
            with patch("src.app.QMessageBox.information") as dlg, patch(
                "src.application.experience_handlers.fill.handle_validate_and_fix"
            ) as handler:
                self.win._on_experience_suggestion(
                    {"action_id": "validate.open_and_fix", "scope": {}}
                )
        finally:
            restore()
        handler.assert_not_called()  # observer blocks despite flag on
        self.assertTrue(dlg.called)


if __name__ == "__main__":
    unittest.main()
