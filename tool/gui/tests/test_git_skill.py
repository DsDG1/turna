"""K-24: git.commit_message + git.explain_diff skill (pure + dispatch)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from typing import Any
from unittest.mock import MagicMock

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.experience.actions import (  # noqa: E402
    DANGEROUS_ACTION_IDS,
    get_action,
)
from src.backend.experience.git_skill import (  # noqa: E402
    build_commit_message_messages,
    build_explain_diff_messages,
    gather_diff_text,
    run_git_skill,
)
from src.backend.experience.intent_router import route_intent  # noqa: E402


class MessageBuilderTest(unittest.TestCase):
    def test_commit_messages_structure(self) -> None:
        msgs = build_commit_message_messages("diff --git a/x b/x\n+feat")
        self.assertEqual(len(msgs), 2)
        self.assertEqual(msgs[0]["role"], "system")
        self.assertEqual(msgs[1]["role"], "user")
        self.assertIn("diff", msgs[1]["content"])

    def test_explain_messages_structure(self) -> None:
        msgs = build_explain_diff_messages("diff --git a/x b/x")
        self.assertEqual(msgs[0]["role"], "system")
        self.assertIn("改动", msgs[0]["content"])

    def test_truncates_long_diff(self) -> None:
        long_diff = "x" * 20000
        msgs = build_commit_message_messages(long_diff, max_diff_chars=12000)
        self.assertLessEqual(len(msgs[1]["content"]), 13000)
        self.assertIn("截断", msgs[1]["content"])

    def test_empty_diff_marked(self) -> None:
        msgs = build_commit_message_messages("")
        self.assertIn("空 diff", msgs[1]["content"])


class RunGitSkillTest(unittest.TestCase):
    def test_extracts_plain_text(self) -> None:
        import src.backend.ai_generator as ai_gen

        orig = ai_gen.request_chat

        def fake_chat(config, messages, temperature=0.4, **kw):
            return {"choices": [{"message": {"content": "feat: 问候课补全"}}]}

        ai_gen.request_chat = fake_chat
        try:
            out = run_git_skill(SimpleNamespace(), "git.commit_message", "diff body")
            self.assertEqual(out, "feat: 问候课补全")
        finally:
            ai_gen.request_chat = orig

    def test_explain_diff_routes_to_explain_builder(self) -> None:
        import src.backend.ai_generator as ai_gen

        orig = ai_gen.request_chat
        seen: dict = {}

        def fake_chat(config, messages, temperature=0.4, **kw):
            seen["system"] = messages[0]["content"]
            return {"choices": [{"message": {"content": "这组改动补充了空课"}}]}

        ai_gen.request_chat = fake_chat
        try:
            out = run_git_skill(SimpleNamespace(), "git.explain_diff", "diff body")
            self.assertIn("补充", out)
            self.assertIn("审阅", seen["system"])  # explain system prompt
        finally:
            ai_gen.request_chat = orig

    def test_unknown_action_raises(self) -> None:
        with self.assertRaises(ValueError):
            run_git_skill(SimpleNamespace(), "git.bogus", "diff")

    def test_empty_choices_returns_empty(self) -> None:
        import src.backend.ai_generator as ai_gen

        orig = ai_gen.request_chat
        ai_gen.request_chat = lambda *a, **k: {"choices": []}
        try:
            self.assertEqual(run_git_skill(SimpleNamespace(), "git.commit_message", "d"), "")
        finally:
            ai_gen.request_chat = orig


class GatherDiffTextTest(unittest.TestCase):
    def test_returns_diff_when_dirty(self) -> None:
        lib = SimpleNamespace(diff_working_vs_head=lambda d: "diff --git a b")
        diff, err = gather_diff_text(lib, Path("/tmp/repo"))
        self.assertEqual(diff, "diff --git a b")
        self.assertEqual(err, "")

    def test_empty_diff_error(self) -> None:
        lib = SimpleNamespace(diff_working_vs_head=lambda d: "   ")
        diff, err = gather_diff_text(lib, Path("/tmp/repo"))
        self.assertEqual(diff, "")
        self.assertIn("无改动", err)

    def test_exception_error(self) -> None:
        def boom(_d):
            raise RuntimeError("no git")

        lib = SimpleNamespace(diff_working_vs_head=boom)
        diff, err = gather_diff_text(lib, Path("/tmp/repo"))
        self.assertEqual(diff, "")
        self.assertIn("RuntimeError", err)

    def test_no_lib(self) -> None:
        diff, err = gather_diff_text(None, Path("/tmp/repo"))
        self.assertEqual(diff, "")
        self.assertIn("Git 库", err)

    def test_no_dir(self) -> None:
        lib = SimpleNamespace(diff_working_vs_head=lambda d: "x")
        diff, err = gather_diff_text(lib, None)
        self.assertEqual(diff, "")
        self.assertIn("未打开", err)


class ActionRegistryTest(unittest.TestCase):
    def test_git_actions_registered_read_only(self) -> None:
        for aid in ("git.commit_message", "git.explain_diff"):
            spec = get_action(aid)
            self.assertIsNotNone(spec, aid)
            assert spec is not None
            self.assertTrue(spec.implemented, aid)
            self.assertFalse(spec.needs_confirm, aid)
            self.assertFalse(spec.dangerous, aid)

    def test_dangerous_set_excludes_git_skills(self) -> None:
        # git.* skills are read-only (commit message / diff explain); never dangerous.
        self.assertNotIn("git.commit_message", DANGEROUS_ACTION_IDS)
        self.assertNotIn("git.explain_diff", DANGEROUS_ACTION_IDS)


class SlashRoutingTest(unittest.TestCase):
    def test_slash_routes(self) -> None:
        self.assertEqual(route_intent("/commit-message").action_id, "git.commit_message")
        self.assertEqual(route_intent("/explain-diff").action_id, "git.explain_diff")
        self.assertEqual(route_intent("/commit-message").confidence, 1.0)

    def test_keyword_routes(self) -> None:
        self.assertEqual(route_intent("生成提交信息").action_id, "git.commit_message")
        self.assertEqual(route_intent("解释 diff").action_id, "git.explain_diff")


def _make_signal():
    sig = MagicMock()

    def connect(handler):
        sig._handlers.append(handler)

    sig._handlers = []
    sig.connect = connect
    return sig


def _fake_worker_factory(captured: dict):
    """Returns a factory producing inline workers; records started workers."""

    def factory(target, *args, **kwargs):
        w = SimpleNamespace()
        w.result_ready = _make_signal()
        w.error_occurred = _make_signal()

        def start(*a, **k):
            try:
                result = target(*args, **kwargs)
            except Exception as exc:  # noqa: BLE001
                for cb in list(w.error_occurred._handlers):
                    cb(str(exc))
            else:
                for cb in list(w.result_ready._handlers):
                    cb(result)

        w.start = start
        captured["target_args"] = (args, kwargs)
        return w

    return factory


class _Status:
    def __init__(self, host):
        self._host = host

    def showMessage(self, msg, _ms=0):  # noqa: N802
        self._host._status.append(msg)


class GitSkillDispatchTest(unittest.TestCase):
    def _make_host(self, *, diff, ai_complete=True, has_dir=True, request_chat=None):
        from src.backend.experience.metrics import ExperienceMetrics
        from src.backend.experience.conflict_guard import ConflictGuard
        from src.backend.experience.job_registry import JobRegistry
        from src.application.experience_skills_mixin import ExperienceSkillsMixin

        class Host(ExperienceSkillsMixin):
            def __init__(self) -> None:
                self.course_dir = Path("/tmp/repo") if has_dir else None
                self._ai_config = SimpleNamespace(is_complete=ai_complete)
                self._git_library = SimpleNamespace(
                    diff_working_vs_head=lambda d: diff
                )
                self.experience_metrics = ExperienceMetrics()
                self.job_tray = JobRegistry()
                self.conflict_guard = ConflictGuard()
                self.experience = SimpleNamespace(context=None)
                self._settings_obj = None
                self._status: list[str] = []
                self._events: list = []
                self._refresh_called = False
                self._shown: list = []
                self._git_results: list[str] = []

            def statusBar(self):  # noqa: N802
                return _Status(self)

            def _record_experience_event(self, *a, **k):
                self._events.append((a, k))

            def _refresh_experience(self, immediate=False, focus_only=False):
                self._refresh_called = True

            def _show_git_skill_result(self, title, text):
                self._git_results.append(text)

            def _resolve_experience_policy(self, action_id=None):
                from src.backend.experience.policy import resolve_policy
                return resolve_policy(None, action_id=action_id)

        return Host()

    def test_dispatch_commit_message_full_path(self) -> None:
        import src.backend.ai_generator as ai_gen

        orig_chat = ai_gen.request_chat
        ai_gen.request_chat = lambda *a, **k: {
            "choices": [{"message": {"content": "feat: 补全空课内容"}}]
        }
        try:
            host = self._make_host(diff="diff --git a/x b/x")
            captured: dict = {}
            host._goal_fill_worker_factory = _fake_worker_factory(captured)
            host._on_experience_suggestion({"action_id": "git.commit_message", "scope": {}})
            self.assertEqual(host._git_results, ["feat: 补全空课内容"])
            # Timeline recorded with action_id but no diff body.
            self.assertTrue(host._events)
            args, kwargs = host._events[0]
            self.assertEqual(kwargs.get("action_id"), "git.commit_message")
            # Ensure no diff body leaked into recorded summary.
            joined = str(args) + str(kwargs)
            self.assertNotIn("diff --git", joined)
        finally:
            ai_gen.request_chat = orig_chat

    def test_dispatch_no_config_status_only(self) -> None:
        host = self._make_host(diff="diff", ai_complete=False)
        host._on_experience_suggestion({"action_id": "git.commit_message", "scope": {}})
        self.assertEqual(host._git_results, [])
        self.assertTrue(any("配置不完整" in m for m in host._status))

    def test_dispatch_no_dir_status(self) -> None:
        host = self._make_host(diff="diff", has_dir=False)
        host._on_experience_suggestion({"action_id": "git.explain_diff", "scope": {}})
        self.assertEqual(host._git_results, [])
        self.assertTrue(any("Git 仓库" in m or "课程" in m for m in host._status))

    def test_dispatch_empty_diff_status(self) -> None:
        host = self._make_host(diff="   ")
        host._on_experience_suggestion({"action_id": "git.commit_message", "scope": {}})
        self.assertEqual(host._git_results, [])
        self.assertTrue(any("无改动" in m for m in host._status))

    def test_dispatch_ai_error_status_no_modal(self) -> None:
        import src.backend.ai_generator as ai_gen

        orig_chat = ai_gen.request_chat

        def boom(*a, **k):
            raise RuntimeError("network down")

        ai_gen.request_chat = boom
        try:
            host = self._make_host(diff="diff --git")
            host._goal_fill_worker_factory = _fake_worker_factory({})
            host._on_experience_suggestion({"action_id": "git.commit_message", "scope": {}})
            self.assertEqual(host._git_results, [])
            self.assertTrue(any("失败" in m for m in host._status))
        finally:
            ai_gen.request_chat = orig_chat


if __name__ == "__main__":
    unittest.main()