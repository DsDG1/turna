"""v4.63 M-02: course.outline_shells — bullet outline → unit/lesson shells."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import MagicMock

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.experience.actions import get_action  # noqa: E402
from src.backend.experience.intent_router import route_intent  # noqa: E402
from src.backend.experience.outline_skill import (  # noqa: E402
    all_course_ids,
    is_outline_shell_enabled,
    outline_to_shell_section,
    parse_bullet_outline,
    shell_stats,
)


class ParseOutlineTest(unittest.TestCase):
    def test_units_and_lessons(self) -> None:
        o = parse_bullet_outline(
            "问候\n  - 打招呼\n  - 自我介绍 [listening]\n数字\n  - 数字 1-10\n"
        )
        self.assertEqual(len(o["units"]), 2)
        u0 = o["units"][0]
        self.assertEqual(u0["name"], "问候")
        self.assertEqual(len(u0["lessons"]), 2)
        self.assertEqual(u0["lessons"][1]["template"], "listening")
        self.assertEqual(o["units"][1]["lessons"][0]["template"], "intro")

    def test_numbered_and_bullet_markers(self) -> None:
        o = parse_bullet_outline("1. 单元A\n  1.1 课一\n- 课二\n")
        self.assertEqual(len(o["units"]), 1)
        self.assertEqual(len(o["units"][0]["lessons"]), 2)

    def test_comment_and_blank_skipped(self) -> None:
        o = parse_bullet_outline("# 注释\n\n单元\n  - 课\n")
        self.assertEqual(len(o["units"]), 1)
        self.assertEqual(o["units"][0]["name"], "单元")

    def test_existing_ids_avoided(self) -> None:
        o = parse_bullet_outline("问候\n", existing_ids=["u-wen-hou", "u-u"])
        # generated id must not collide with any existing id
        new_ids = {u["id"] for u in o["units"]}
        self.assertFalse(new_ids & {"u-wen-hou", "u-u"})

    def test_never_raises_on_garbage(self) -> None:
        for bad in (None, "", "   ", "\n\n# only comment\n"):
            o = parse_bullet_outline(bad)  # type: ignore[arg-type]
            self.assertEqual(o["units"], [])

    def test_ids_unique_within_outline(self) -> None:
        o = parse_bullet_outline("重复\n  - 课\n  - 课\n重复\n")
        ids = [u["id"] for u in o["units"]] + [
            l["id"] for u in o["units"] for l in u["lessons"]
        ]
        self.assertEqual(len(ids), len(set(ids)))


class ShellSectionTest(unittest.TestCase):
    def test_shell_has_empty_content_and_forced_section_id(self) -> None:
        o = parse_bullet_outline("问候\n  - 打招呼\n  - 听 [listening]\n")
        shell = outline_to_shell_section(o, section_id="section9")
        self.assertEqual(shell["id"], "section9")
        les = shell["units"][0]["lessons"]
        # intro -> subLessons shell; listening -> listeningPhases shell
        self.assertIn("subLessons", les[0]["content"])
        self.assertIn("listeningPhases", les[1]["content"])

    def test_shell_never_raises_on_empty(self) -> None:
        shell = outline_to_shell_section({}, section_id="s")
        self.assertEqual(shell["id"], "s")
        self.assertEqual(shell["units"], [])

    def test_shell_stats_closed_set(self) -> None:
        o = parse_bullet_outline("A\n  - a1\n  - a2\nB\n  - b1\n")
        stats = shell_stats(outline_to_shell_section(o))
        self.assertEqual(stats["unit_count"], 2)
        self.assertEqual(stats["lesson_count"], 3)
        self.assertLessEqual(len(stats["unit_ids"]), 20)
        # no title text leaks into scope (§14.5.3)
        self.assertNotIn("name", stats)


class AllCourseIdsTest(unittest.TestCase):
    def test_collects_unit_lesson_section_ids(self) -> None:
        adapter = SimpleNamespace(
            sections=[
                {
                    "id": "s1",
                    "units": [
                        {"id": "u1", "lessons": [{"id": "l1"}, {"id": "l2"}]}
                    ],
                }
            ]
        )
        ids = set(all_course_ids(adapter))
        self.assertEqual(ids, {"s1", "u1", "l1", "l2"})

    def test_never_raises_on_malformed(self) -> None:
        self.assertEqual(all_course_ids(SimpleNamespace(sections=None)), [])
        self.assertEqual(
            all_course_ids(SimpleNamespace(sections=[None, {"units": "x"}])), []
        )


class EnabledGateTest(unittest.TestCase):
    def test_default_off(self) -> None:
        self.assertFalse(is_outline_shell_enabled(None))
        self.assertFalse(is_outline_shell_enabled(SimpleNamespace()))

    def test_on(self) -> None:
        self.assertTrue(
            is_outline_shell_enabled(
                SimpleNamespace(experience_outline_shell=True)
            )
        )


class ContractTest(unittest.TestCase):
    def test_action_registered_write(self) -> None:
        spec = get_action("course.outline_shells")
        self.assertIsNotNone(spec)
        assert spec is not None
        self.assertTrue(spec.needs_confirm)
        # v4.69: structural shell creation is dangerous but deliberately NOT in
        # set C (largest blast radius) — always confirms, even under immersive.
        self.assertTrue(spec.dangerous)

    def test_route_slash(self) -> None:
        r = route_intent("/outline")
        self.assertIsNotNone(r)
        assert r is not None
        self.assertEqual(r.action_id, "course.outline_shells")
        self.assertEqual(r.confidence, 1.0)

    def test_route_keyword(self) -> None:
        r = route_intent("课程大纲")
        self.assertIsNotNone(r)
        assert r is not None
        self.assertEqual(r.action_id, "course.outline_shells")
        self.assertEqual(r.confidence, 0.6)


class HandlerGateTest(unittest.TestCase):
    def _host(self, **over):
        base = dict(
            _settings_obj=SimpleNamespace(experience_outline_shell=False),
            course_dir=None,
            statusBar=MagicMock(return_value=MagicMock()),
            experience_metrics=MagicMock(),
            _current_node_ref=None,
        )
        base.update(over)
        return SimpleNamespace(**base)

    def test_off_flag_statusbar_no_dispatch(self) -> None:
        from src.application.experience_handlers.outline import (
            handle_outline_shells,
        )

        host = self._host()
        handle_outline_shells(host, {})
        host.statusBar().showMessage.assert_called()
        host.experience_metrics.inc_suggestion.assert_not_called()

    def test_no_course_warns(self) -> None:
        from src.application.experience_handlers import outline as mod

        host = self._host(
            _settings_obj=SimpleNamespace(experience_outline_shell=True),
            course_dir=None,
        )
        with _patch_safe_warning(mod) as warn:
            mod.handle_outline_shells(host, {})
        warn.assert_called()


class _patch_safe_warning:
    def __init__(self, mod):
        self._mod = mod

    def __enter__(self):
        from unittest.mock import patch

        self._p = patch.object(self._mod, "safe_warning")
        return self._p.__enter__()

    def __exit__(self, *a):
        return self._p.__exit__(*a)


if __name__ == "__main__":
    unittest.main()
