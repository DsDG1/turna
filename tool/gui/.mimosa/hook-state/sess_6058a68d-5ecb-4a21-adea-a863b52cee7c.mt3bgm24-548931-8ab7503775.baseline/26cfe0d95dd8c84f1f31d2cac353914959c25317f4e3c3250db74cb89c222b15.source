"""C-06 intent_llm pure tests (no network)."""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.application.settings import Settings  # noqa: E402
from src.backend.experience.intent_llm import (  # noqa: E402
    LLM_INTENT_MIN_CONFIDENCE,
    allowed_action_ids,
    build_classify_messages,
    classify_intent_sync,
    is_llm_intent_enabled,
    parse_classify_response,
)
from src.backend.experience.policy import resolve_policy  # noqa: E402


class AllowedIdsTest(unittest.TestCase):
    def test_includes_core_actions(self) -> None:
        ids = allowed_action_ids()
        self.assertIn("validate.open_and_fix", ids)
        self.assertIn("app.save", ids)
        self.assertIn("course.compare_sections", ids)


class ParseClassifyTest(unittest.TestCase):
    def setUp(self) -> None:
        self.allowed = frozenset(
            {
                "validate.open_and_fix",
                "lesson.fill_empty",
                "app.why",
            }
        )

    def test_valid_json(self) -> None:
        raw = json.dumps(
            {
                "action_id": "validate.open_and_fix",
                "confidence": 0.9,
                "label": "修错",
            }
        )
        intent = parse_classify_response(raw, self.allowed)
        self.assertIsNotNone(intent)
        assert intent is not None
        self.assertEqual(intent.action_id, "validate.open_and_fix")
        self.assertGreaterEqual(intent.confidence, 0.9)
        self.assertIn("AI", intent.label)

    def test_code_fence(self) -> None:
        raw = '```json\n{"action_id":"app.why","confidence":0.8}\n```'
        intent = parse_classify_response(raw, self.allowed)
        self.assertIsNotNone(intent)
        assert intent is not None
        self.assertEqual(intent.action_id, "app.why")

    def test_unknown_action_none(self) -> None:
        raw = '{"action_id":"hack.delete_all","confidence":0.99}'
        self.assertIsNone(parse_classify_response(raw, self.allowed))

    def test_low_confidence_none(self) -> None:
        conf = LLM_INTENT_MIN_CONFIDENCE - 0.1
        raw = json.dumps(
            {"action_id": "lesson.fill_empty", "confidence": conf}
        )
        self.assertIsNone(parse_classify_response(raw, self.allowed))

    def test_null_action_none(self) -> None:
        self.assertIsNone(
            parse_classify_response(
                '{"action_id":null,"confidence":0}', self.allowed
            )
        )

    def test_garbage_none(self) -> None:
        self.assertIsNone(parse_classify_response("not json at all", self.allowed))
        self.assertIsNone(parse_classify_response("", self.allowed))
        self.assertIsNone(parse_classify_response(None, self.allowed))

    def test_confidence_clamped(self) -> None:
        raw = '{"action_id":"app.why","confidence":1.5}'
        intent = parse_classify_response(raw, self.allowed)
        self.assertIsNotNone(intent)
        assert intent is not None
        self.assertEqual(intent.confidence, 1.0)


class GateTest(unittest.TestCase):
    def test_default_off(self) -> None:
        self.assertFalse(is_llm_intent_enabled(Settings()))
        self.assertFalse(resolve_policy(Settings()).allow_llm_intent)

    def test_flag_on_copilot(self) -> None:
        s = Settings(experience_llm_intent=True)
        self.assertTrue(is_llm_intent_enabled(s))
        self.assertTrue(resolve_policy(s).allow_llm_intent)

    def test_observer_blocks(self) -> None:
        s = Settings(experience_llm_intent=True, experience_mode="observer")
        self.assertFalse(is_llm_intent_enabled(s))
        self.assertFalse(resolve_policy(s).allow_llm_intent)

    def test_budget_blocks(self) -> None:
        s = Settings(experience_llm_intent=True, experience_daily_ai_budget=1)
        pol = resolve_policy(s, usage_today={"requests": 1})
        self.assertTrue(pol.budget_exceeded)
        self.assertFalse(pol.allow_llm_intent)
        self.assertFalse(
            is_llm_intent_enabled(s, usage_today={"requests": 1})
        )


class MessagesAndSyncTest(unittest.TestCase):
    def test_build_messages_contains_text_and_ids(self) -> None:
        msgs = build_classify_messages(
            "帮我清一下空课",
            ["lesson.fill_empty", "app.save"],
        )
        self.assertEqual(len(msgs), 2)
        blob = msgs[0]["content"] + msgs[1]["content"]
        self.assertIn("lesson.fill_empty", blob)
        self.assertIn("帮我清一下空课", blob)

    def test_classify_sync_incomplete_config(self) -> None:
        cfg = SimpleNamespace(is_complete=False)
        self.assertIsNone(classify_intent_sync(cfg, "修错"))

    def test_classify_sync_mock_request(self) -> None:
        cfg = SimpleNamespace(is_complete=True, model="m", select_model=lambda k: "chat-m")
        body = {
            "choices": [
                {
                    "message": {
                        "content": json.dumps(
                            {
                                "action_id": "validate.open_and_fix",
                                "confidence": 0.88,
                            }
                        )
                    }
                }
            ]
        }
        with patch(
            "src.backend.ai_generator.request_chat", return_value=body
        ) as mock_chat:
            intent = classify_intent_sync(
                cfg,
                "修一下校验错误",
                allowed_ids={"validate.open_and_fix"},
            )
            mock_chat.assert_called_once()
        self.assertIsNotNone(intent)
        assert intent is not None
        self.assertEqual(intent.action_id, "validate.open_and_fix")


class GoldenParseFileTest(unittest.TestCase):
    def test_ai_goldens_intent_llm_parse(self) -> None:
        path = Path(__file__).resolve().parent / "ai_goldens" / "intent_llm_parse.json"
        rows = json.loads(path.read_text(encoding="utf-8"))
        for row in rows:
            with self.subTest(raw=row.get("raw", "")[:40]):
                intent = parse_classify_response(
                    row["raw"], frozenset(row.get("allowed") or [])
                )
                expected = row.get("expect_action")
                if expected is None:
                    self.assertIsNone(intent)
                else:
                    self.assertIsNotNone(intent)
                    assert intent is not None
                    self.assertEqual(intent.action_id, expected)


class SettingsRoundTripTest(unittest.TestCase):
    def test_llm_intent_persists(self) -> None:
        from unittest.mock import MagicMock

        store: dict = {"recent_repos": "[]"}
        qs = MagicMock()
        qs.value = lambda k, d=None: store.get(k, d)
        qs.setValue = lambda k, v: store.__setitem__(k, v)
        qs.contains = lambda k: k in store
        qs.remove = lambda k: store.pop(k, None)

        s = Settings(experience_llm_intent=True)
        s.save_to_qsettings(qs)
        self.assertTrue(store.get("experience/llm_intent"))
        loaded = Settings.load_from_qsettings(qs)
        self.assertTrue(loaded.experience_llm_intent)

    def test_default_false_on_load(self) -> None:
        from unittest.mock import MagicMock

        store: dict = {"recent_repos": "[]"}
        qs = MagicMock()
        qs.value = lambda k, d=None: store.get(k, d)
        qs.setValue = lambda k, v: store.__setitem__(k, v)
        qs.contains = lambda k: k in store
        qs.remove = lambda k: store.pop(k, None)
        loaded = Settings.load_from_qsettings(qs)
        self.assertFalse(loaded.experience_llm_intent)


if __name__ == "__main__":
    unittest.main()
