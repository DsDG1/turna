"""T-04 AI / v4.57–v4.59: lesson.batch_regenerate + unit.batch_regenerate."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.application.experience_handlers.regenerate import (  # noqa: E402
    BATCH_REGEN_CAP,
    UNIT_BATCH_REGEN_CAP,
    _batch_regen_lesson_ids,
    _batch_regen_unit_ids,
    _lesson_ids_in_unit,
    apply_regen_result,
    handle_batch_regenerate,
    handle_batch_regenerate_units,
)
from src.backend.experience.actions import get_action  # noqa: E402
from src.backend.experience.intent_router import route_intent  # noqa: E402
from src.backend.experience.patch import (  # noqa: E402
    apply_lesson_patch,
    lesson_patches_from_section_diff,
)


class ResolveIdsTest(unittest.TestCase):
    def test_from_scope(self) -> None:
        host = SimpleNamespace(experience=SimpleNamespace(context=None, _multi=None))
        ids = _batch_regen_lesson_ids(
            host, {"lesson_ids": ["l1", "l2", "l1", "l3"]}
        )
        self.assertEqual(ids, ["l1", "l2", "l3"])

    def test_cap(self) -> None:
        host = SimpleNamespace(experience=SimpleNamespace(context=None, _multi=None))
        many = [f"l{i}" for i in range(20)]
        ids = _batch_regen_lesson_ids(host, {"lesson_ids": many})
        self.assertEqual(len(ids), BATCH_REGEN_CAP)

    def test_from_multi_selection(self) -> None:
        ctx = SimpleNamespace(
            multi_selection=[
                SimpleNamespace(kind="lesson", id="a"),
                SimpleNamespace(kind="section", id="s"),
                ("lesson", "b"),
            ]
        )
        host = SimpleNamespace(
            experience=SimpleNamespace(context=ctx, _multi=None),
            _current_node_ref=None,
        )
        self.assertEqual(_batch_regen_lesson_ids(host, {}), ["a", "b"])


class ApplyRegenResultTest(unittest.TestCase):
    def test_lesson_patch_path_pushes_undo(self) -> None:
        old = {
            "id": "s1",
            "units": [
                {
                    "id": "u1",
                    "lessons": [{"id": "l1", "name": "A", "content": {}}],
                }
            ],
        }
        new = {
            "id": "s1",
            "units": [
                {
                    "id": "u1",
                    "lessons": [
                        {"id": "l1", "name": "B", "content": {"stages": []}}
                    ],
                }
            ],
        }
        unit = old["units"][0]
        adapter = MagicMock()
        adapter.find_lesson.return_value = (old, unit, unit["lessons"][0])
        adapter.plan_section_merge = MagicMock()
        undo = MagicMock()
        host = SimpleNamespace(
            adapter=adapter,
            undo_stack=undo,
            experience_metrics=MagicMock(),
            _record_experience_event=MagicMock(),
            _refresh_validate_after_ai=MagicMock(),
            _on_ai_edit_applied=MagicMock(),
        )
        ok = apply_regen_result(
            host,
            old,
            new,
            section_id="s1",
            focus_lesson_ids={"l1"},
            action_id="lesson.regenerate",
            job_label="重生成课",
        )
        self.assertTrue(ok)
        undo.push.assert_called_once()
        # Prefer LessonPatch command, not merge plan.
        adapter.plan_section_merge.assert_not_called()
        host.experience_metrics.inc_suggestion.assert_any_call(
            "lesson.regenerate", "applied"
        )


class BatchHandlerTest(unittest.TestCase):
    def test_no_selection_status(self) -> None:
        status = MagicMock()
        host = SimpleNamespace(
            course_dir=Path("/tmp/c"),
            experience=SimpleNamespace(context=None, _multi=[]),
            _current_node_ref=None,
            statusBar=MagicMock(return_value=status),
            job_tray=MagicMock(is_busy_ai=MagicMock(return_value=False)),
        )
        handle_batch_regenerate(host, {})
        status.showMessage.assert_called()

    def test_sync_worker_factory_applies_batch(self) -> None:
        old_sec = {
            "id": "s1",
            "units": [
                {
                    "id": "u1",
                    "lessons": [
                        {"id": "l1", "name": "A", "content": {}},
                        {"id": "l2", "name": "B", "content": {}},
                    ],
                }
            ],
        }

        def find_lesson(lid):
            for les in old_sec["units"][0]["lessons"]:
                if les["id"] == lid:
                    return old_sec, old_sec["units"][0], les
            raise KeyError(lid)

        adapter = MagicMock()
        adapter.find_lesson.side_effect = find_lesson
        undo = MagicMock()
        metrics = MagicMock()
        tray = MagicMock()
        tray.is_busy_ai.return_value = False
        host = SimpleNamespace(
            course_dir=Path("/tmp/c"),
            adapter=adapter,
            undo_stack=undo,
            experience_metrics=metrics,
            job_tray=tray,
            conflict_guard=MagicMock(),
            experience=SimpleNamespace(context=None, _multi=None),
            _current_node_ref=None,
            _ai_config=SimpleNamespace(is_complete=True),
            _deny_ai_write_if_blocked=MagicMock(return_value=False),
            _record_experience_event=MagicMock(),
            _refresh_validate_after_ai=MagicMock(),
            _on_ai_edit_applied=MagicMock(),
            statusBar=MagicMock(return_value=MagicMock()),
            _batch_regen_inline=True,
        )

        def fake_regen(config, spec, draft, lid, instruction=None):
            import copy

            out = copy.deepcopy(draft)
            for u in out["units"]:
                for les in u["lessons"]:
                    if les["id"] == lid:
                        les["name"] = f"{lid}-new"
                        les["content"] = {"ok": True}
            return out

        with (
            patch(
                "src.application.experience_handlers.regenerate.safe_question",
                return_value=True,
            ),
            patch(
                "src.backend.ai.regenerate_lesson_in_section",
                side_effect=fake_regen,
            ),
            patch(
                "src.backend.ai.AiCourseSpec", return_value=object()
            ),
        ):
            handle_batch_regenerate(
                host, {"lesson_ids": ["l1", "l2"]}
            )
        undo.push.assert_called()
        metrics.inc_suggestion.assert_any_call(
            "lesson.batch_regenerate", "applied"
        )


class ContractTest(unittest.TestCase):
    def test_action_registered(self) -> None:
        spec = get_action("lesson.batch_regenerate")
        self.assertIsNotNone(spec)
        assert spec is not None
        self.assertTrue(spec.needs_confirm)
        # v4.69: structural batch regenerate is dangerous (set C member).
        self.assertTrue(spec.dangerous)

    def test_route_slash_and_keyword(self) -> None:
        r = route_intent("/batch-regen")
        self.assertIsNotNone(r)
        assert r is not None
        self.assertEqual(r.action_id, "lesson.batch_regenerate")
        r2 = route_intent("批量重生成这些课")
        self.assertIsNotNone(r2)
        assert r2 is not None
        self.assertEqual(r2.action_id, "lesson.batch_regenerate")


class ResolveUnitIdsTest(unittest.TestCase):
    def test_from_scope(self) -> None:
        host = SimpleNamespace(experience=SimpleNamespace(context=None, _multi=None))
        ids = _batch_regen_unit_ids(
            host, {"unit_ids": ["u1", "u2", "u1", "u3"]}
        )
        self.assertEqual(ids, ["u1", "u2", "u3"])

    def test_cap(self) -> None:
        host = SimpleNamespace(experience=SimpleNamespace(context=None, _multi=None))
        many = [f"u{i}" for i in range(20)]
        ids = _batch_regen_unit_ids(host, {"unit_ids": many})
        self.assertEqual(len(ids), UNIT_BATCH_REGEN_CAP)

    def test_from_multi_selection_ignores_lesson(self) -> None:
        ctx = SimpleNamespace(
            multi_selection=[
                SimpleNamespace(kind="unit", id="a"),
                SimpleNamespace(kind="lesson", id="l1"),
                ("unit", "b"),
            ]
        )
        host = SimpleNamespace(
            experience=SimpleNamespace(context=ctx, _multi=None),
            _current_node_ref=None,
        )
        self.assertEqual(_batch_regen_unit_ids(host, {}), ["a", "b"])

    def test_current_unit_ref(self) -> None:
        host = SimpleNamespace(
            experience=SimpleNamespace(context=None, _multi=[]),
            _current_node_ref=("unit", "u-only"),
        )
        self.assertEqual(_batch_regen_unit_ids(host, {}), ["u-only"])

    def test_lesson_ids_in_unit(self) -> None:
        sec = {
            "id": "s1",
            "units": [
                {
                    "id": "u1",
                    "lessons": [{"id": "l1"}, {"id": "l2"}],
                },
                {"id": "u2", "lessons": [{"id": "l3"}]},
            ],
        }
        self.assertEqual(_lesson_ids_in_unit(sec, "u1"), {"l1", "l2"})
        self.assertEqual(_lesson_ids_in_unit(sec, "missing"), set())


class UnitBatchHandlerTest(unittest.TestCase):
    def test_no_selection_status(self) -> None:
        status = MagicMock()
        host = SimpleNamespace(
            course_dir=Path("/tmp/c"),
            experience=SimpleNamespace(context=None, _multi=[]),
            _current_node_ref=None,
            statusBar=MagicMock(return_value=status),
            job_tray=MagicMock(is_busy_ai=MagicMock(return_value=False)),
        )
        handle_batch_regenerate_units(host, {})
        status.showMessage.assert_called()

    def test_sync_worker_factory_applies_batch(self) -> None:
        old_sec = {
            "id": "s1",
            "units": [
                {
                    "id": "u1",
                    "name": "U1",
                    "lessons": [
                        {"id": "l1", "name": "A", "content": {}},
                        {"id": "l2", "name": "B", "content": {}},
                    ],
                },
                {
                    "id": "u2",
                    "name": "U2",
                    "lessons": [
                        {"id": "l3", "name": "C", "content": {}},
                    ],
                },
            ],
        }

        def find_unit(uid):
            for u in old_sec["units"]:
                if u["id"] == uid:
                    return old_sec, u
            raise KeyError(uid)

        def find_lesson(lid):
            for u in old_sec["units"]:
                for les in u["lessons"]:
                    if les["id"] == lid:
                        return old_sec, u, les
            raise KeyError(lid)

        adapter = MagicMock()
        adapter.find_unit.side_effect = find_unit
        adapter.find_lesson.side_effect = find_lesson
        undo = MagicMock()
        metrics = MagicMock()
        tray = MagicMock()
        tray.is_busy_ai.return_value = False
        host = SimpleNamespace(
            course_dir=Path("/tmp/c"),
            adapter=adapter,
            undo_stack=undo,
            experience_metrics=metrics,
            job_tray=tray,
            conflict_guard=MagicMock(),
            experience=SimpleNamespace(context=None, _multi=None),
            _current_node_ref=None,
            _ai_config=SimpleNamespace(is_complete=True),
            _deny_ai_write_if_blocked=MagicMock(return_value=False),
            _record_experience_event=MagicMock(),
            _refresh_validate_after_ai=MagicMock(),
            _on_ai_edit_applied=MagicMock(),
            statusBar=MagicMock(return_value=MagicMock()),
            _batch_regen_inline=True,
        )

        def fake_regen(config, spec, draft, uid, instruction=None):
            import copy

            out = copy.deepcopy(draft)
            for u in out["units"]:
                if u["id"] == uid:
                    for les in u["lessons"]:
                        les["name"] = f"{les['id']}-new"
                        les["content"] = {"ok": True}
            return out

        with (
            patch(
                "src.application.experience_handlers.regenerate.safe_question",
                return_value=True,
            ),
            patch(
                "src.backend.ai.regenerate_unit_in_section",
                side_effect=fake_regen,
            ),
            patch(
                "src.backend.ai.AiCourseSpec", return_value=object()
            ),
        ):
            handle_batch_regenerate_units(
                host, {"unit_ids": ["u1", "u2"]}
            )
        undo.push.assert_called()
        metrics.inc_suggestion.assert_any_call(
            "unit.batch_regenerate", "applied"
        )
        host._record_experience_event.assert_called()
        scope = host._record_experience_event.call_args.kwargs.get("scope") or {}
        self.assertIn("count", scope)
        self.assertNotIn("secret", str(scope).lower())

    def test_reject_first_confirm(self) -> None:
        old_sec = {
            "id": "s1",
            "units": [
                {
                    "id": "u1",
                    "name": "U1",
                    "lessons": [{"id": "l1", "name": "A", "content": {}}],
                }
            ],
        }
        adapter = MagicMock()
        adapter.find_unit.return_value = (old_sec, old_sec["units"][0])
        metrics = MagicMock()
        host = SimpleNamespace(
            course_dir=Path("/tmp/c"),
            adapter=adapter,
            experience_metrics=metrics,
            job_tray=MagicMock(is_busy_ai=MagicMock(return_value=False)),
            experience=SimpleNamespace(context=None, _multi=None),
            _current_node_ref=None,
            _deny_ai_write_if_blocked=MagicMock(return_value=False),
            statusBar=MagicMock(return_value=MagicMock()),
        )
        with patch(
            "src.application.experience_handlers.regenerate.safe_question",
            return_value=False,
        ):
            handle_batch_regenerate_units(host, {"unit_ids": ["u1"]})
        metrics.inc_suggestion.assert_any_call(
            "unit.batch_regenerate", "rejected"
        )


class UnitContractTest(unittest.TestCase):
    def test_action_registered(self) -> None:
        spec = get_action("unit.batch_regenerate")
        self.assertIsNotNone(spec)
        assert spec is not None
        self.assertTrue(spec.needs_confirm)
        # v4.69: structural batch regenerate is dangerous (set C member).
        self.assertTrue(spec.dangerous)

    def test_route_slash_and_keyword_order(self) -> None:
        r = route_intent("/unit-batch-regen")
        self.assertIsNotNone(r)
        assert r is not None
        self.assertEqual(r.action_id, "unit.batch_regenerate")
        r_unit = route_intent("批量重生成单元")
        self.assertIsNotNone(r_unit)
        assert r_unit is not None
        self.assertEqual(r_unit.action_id, "unit.batch_regenerate")
        r_lesson = route_intent("批量重生成这些课")
        self.assertIsNotNone(r_lesson)
        assert r_lesson is not None
        self.assertEqual(r_lesson.action_id, "lesson.batch_regenerate")


if __name__ == "__main__":
    unittest.main()
