"""K-22 / v4.58: textbook_skill + handlers + routes."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.experience.actions import get_action  # noqa: E402
from src.backend.experience.intent_router import route_intent  # noqa: E402
from src.backend.experience.textbook_skill import (  # noqa: E402
    build_grounded_instruction,
    build_import_suggestion,
    draft_import_ready,
)
from src.application.experience_handlers import textbook as th  # noqa: E402


class DraftReadyTest(unittest.TestCase):
    def test_ready_when_has_draft_not_imported(self) -> None:
        ctx = SimpleNamespace(
            workshop_draft={
                "has_draft": True,
                "has_imported": False,
                "draft_section_count": 2,
                "project_id": "p1",
                "ui_stage": 3,
            }
        )
        self.assertTrue(draft_import_ready(ctx))
        sug = build_import_suggestion(ctx)
        self.assertIsNotNone(sug)
        assert sug is not None
        self.assertEqual(sug["action_id"], "textbook.import_draft")
        self.assertEqual(sug["scope"]["count"], 2)
        self.assertNotIn("secret", str(sug))

    def test_not_ready_when_imported(self) -> None:
        ctx = SimpleNamespace(
            workshop_draft={"has_draft": True, "has_imported": True}
        )
        self.assertFalse(draft_import_ready(ctx))
        self.assertIsNone(build_import_suggestion(ctx))


class GroundedInstructionTest(unittest.TestCase):
    def test_no_body_leak(self) -> None:
        atts = [
            {
                "ref_id": "att-abc",
                "kind": "pdf",
                "name": "x.pdf",
                "content": "SECRET_BODY",
            }
        ]
        instr = build_grounded_instruction(atts, language="Turkish")
        self.assertIn("pdf", instr)
        self.assertIn("att-abc", instr)
        self.assertNotIn("SECRET_BODY", instr)


class HandlerTest(unittest.TestCase):
    def test_open_workshop_delegates(self) -> None:
        host = SimpleNamespace(experience_metrics=MagicMock())
        with patch(
            "src.application.workshop_controller.open_workshop"
        ) as open_w:
            th.handle_open_workshop(host, {})
            open_w.assert_called_once_with(host)

    def test_import_no_draft_status(self) -> None:
        status = MagicMock()
        host = SimpleNamespace(
            course_dir=Path("/tmp/c"),
            _workshop_window=None,
            statusBar=MagicMock(return_value=status),
            experience_metrics=MagicMock(),
            _record_experience_event=MagicMock(),
        )
        with patch(
            "src.application.experience_handlers.textbook.handle_open_workshop"
        ):
            th.handle_import_draft(host, {})
        status.showMessage.assert_called()


class ContractTest(unittest.TestCase):
    def test_actions(self) -> None:
        for aid, confirm in (
            ("textbook.open_workshop", False),
            ("textbook.import_draft", True),
            ("textbook.grounded_fill", True),
        ):
            spec = get_action(aid)
            self.assertIsNotNone(spec, aid)
            assert spec is not None
            self.assertEqual(spec.needs_confirm, confirm, aid)

    def test_routes(self) -> None:
        self.assertEqual(
            route_intent("/workshop").action_id, "textbook.open_workshop"
        )
        self.assertEqual(
            route_intent("/import-draft").action_id, "textbook.import_draft"
        )
        self.assertEqual(
            route_intent("打开工坊").action_id, "textbook.open_workshop"
        )


if __name__ == "__main__":
    unittest.main()
