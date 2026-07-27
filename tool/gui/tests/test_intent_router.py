"""E1 C-05: intent router golden set + command palette light UI test."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.experience.intent_router import (  # noqa: E402
    SLASH_COMMANDS,
    match_commands,
    route_intent,
)
from tests._qtapp import _App as _TestApp  # noqa: E402


class RouteIntentGoldenTest(unittest.TestCase):
    """Q-02：规则路由黄金集（斜杠 + 关键词 + 边界 + JSON 文件）。"""

    def test_slash_commands_exact(self) -> None:
        expected = {
            "/validate": "validate.open_and_fix",
            "/fill": "lesson.fill_empty",
            "/stubs": "resource.fill_stubs",
            "/listening": "listening.fill_gaps",
            "/soft": "soft.preview_hygiene",
            "/resources": "resource.open_hygiene",
            "/why": "app.why",
            "/pin": "app.pin",
            "/save": "app.save",
            "/undo": "app.undo",
            "/help": "app.help",
        }
        for cmd, action_id in expected.items():
            intent = route_intent(cmd)
            self.assertIsNotNone(intent, cmd)
            self.assertEqual(intent.action_id, action_id, cmd)
            self.assertEqual(intent.confidence, 1.0, cmd)

    def test_keywords(self) -> None:
        cases = [
            ("帮我修错", "validate.open_and_fix"),
            ("校验一下", "validate.open_and_fix"),
            ("修全部错误", "validate.open_and_fix"),
            ("填充空课", "lesson.fill_empty"),
            ("这节课是空课", "lesson.fill_empty"),
            ("清理待补词条", "resource.fill_stubs"),
            ("补全听力缺口", "listening.fill_gaps"),
            ("这节听力课没题目", "listening.fill_gaps"),
            ("规则规范化", "soft.preview_hygiene"),
            ("打开资源", "resource.open_hygiene"),
            ("为什么错了", "app.why"),
            ("钉住这个节点", "app.pin"),
            ("保存", "app.save"),
            ("撤销上一步", "app.undo"),
        ]
        for text, action_id in cases:
            intent = route_intent(text)
            self.assertIsNotNone(intent, text)
            self.assertEqual(intent.action_id, action_id, text)

    def test_no_match_returns_none(self) -> None:
        for text in ("", "   ", "今天天气不错", "xyz"):
            self.assertIsNone(route_intent(text), text)

    def test_json_golden_file_at_least_30(self) -> None:
        import json

        path = Path(__file__).resolve().parent / "ai_goldens" / "intent_routes.json"
        rows = json.loads(path.read_text(encoding="utf-8"))
        self.assertGreaterEqual(len(rows), 30)
        for row in rows:
            text = row.get("text", "")
            expected = row.get("action_id")
            intent = route_intent(text)
            if expected is None:
                self.assertIsNone(intent, text)
            else:
                self.assertIsNotNone(intent, text)
                self.assertEqual(intent.action_id, expected, text)
                if "confidence" in row:
                    self.assertEqual(intent.confidence, row["confidence"], text)


class MatchCommandsTest(unittest.TestCase):
    def test_empty_lists_all_slash_commands(self) -> None:
        intents = match_commands("")
        self.assertEqual(len(intents), len(SLASH_COMMANDS))

    def test_slash_prefix_filters(self) -> None:
        intents = match_commands("/va")
        self.assertEqual(len(intents), 1)
        self.assertEqual(intents[0].action_id, "validate.open_and_fix")

    def test_label_substring(self) -> None:
        intents = match_commands("保存")
        self.assertTrue(any(i.action_id == "app.save" for i in intents))
        # F1 v4.47: non-slash label match is 0.6 so S-04 stays armed.
        save = next(i for i in intents if i.action_id == "app.save")
        self.assertEqual(save.confidence, 0.6)

    def test_label_match_conf_is_keyword_not_slash(self) -> None:
        """Write skills via free text must not get conf 0.8 (S-04 bypass)."""
        for q in ("填充", "听力", "重生成"):
            intents = match_commands(q)
            self.assertTrue(intents, q)
            self.assertLess(intents[0].confidence, 0.8, q)
            self.assertEqual(intents[0].confidence, 0.6, q)

    def test_single_char_skips_label_flood(self) -> None:
        # F4: bare 「课」 must not list every lesson.* command.
        intents = match_commands("课")
        self.assertEqual(intents, [])

    def test_fallback_to_keyword_route(self) -> None:
        intents = match_commands("帮我把空课填上")
        self.assertTrue(intents)
        self.assertEqual(intents[0].action_id, "lesson.fill_empty")

    def test_new_keywords_help_ocr_attachments(self) -> None:
        self.assertEqual(route_intent("帮助").action_id, "app.help")
        self.assertEqual(route_intent("OCR").action_id, "textbook.ocr_suggest")
        self.assertEqual(route_intent("查看附件").action_id, "attachment.open_in_workshop")

    def test_gibberish_empty(self) -> None:
        self.assertEqual(match_commands("zzzqqq"), [])


class CommandPaletteUiTest(unittest.TestCase):
    def setUp(self) -> None:
        _TestApp.get()

    def test_filter_and_trigger(self) -> None:
        from src.widgets.command_palette import CommandPalette

        dlg = CommandPalette()
        received: list[dict] = []
        dlg.command_triggered.connect(received.append)
        dlg.input.setText("/va")
        self.assertEqual(dlg.list.count(), 1)
        dlg._trigger_current()
        self.assertEqual(len(received), 1)
        self.assertEqual(received[0]["action_id"], "validate.open_and_fix")

    def test_no_match_shows_hint_and_no_trigger(self) -> None:
        from src.widgets.command_palette import CommandPalette

        dlg = CommandPalette()
        received: list[dict] = []
        dlg.command_triggered.connect(received.append)
        dlg.input.setText("zzzqqq")
        dlg._trigger_current()
        self.assertEqual(received, [])

    def test_single_click_selects_without_dispatch(self) -> None:
        from src.widgets.command_palette import CommandPalette

        dlg = CommandPalette()
        received: list[dict] = []
        dlg.command_triggered.connect(received.append)
        dlg.input.setText("/validate")
        self.assertGreaterEqual(dlg.list.count(), 1)
        item = dlg.list.item(0)
        dlg.list.itemClicked.emit(item)
        self.assertEqual(received, [], "F3: single click must not dispatch")
        dlg.list.itemDoubleClicked.emit(item)
        self.assertEqual(len(received), 1)
        self.assertEqual(received[0]["action_id"], "validate.open_and_fix")

    def test_async_loading_enter_does_not_fellthrough(self) -> None:
        from src.widgets.command_palette import CommandPalette

        dlg = CommandPalette()
        fell: list[str] = []
        cmds: list = []
        dlg.intent_fellthrough.connect(fell.append)
        dlg.command_triggered.connect(cmds.append)
        dlg.set_async_candidate_hook(lambda t: None)
        dlg.input.setText("zzzzz不存在的查询词")
        self.assertTrue(dlg._loading_async)
        dlg._trigger_current()
        self.assertEqual(fell, [], "F10: loading must not silent-fellthrough")
        self.assertEqual(cmds, [])


if __name__ == "__main__":
    unittest.main()
