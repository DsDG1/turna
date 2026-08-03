"""v4.49: T-08 blueprint「AI 生成 N 阶段/题目」+ T-09 表单/蓝图 AI 芯片入口。

T-08 routes empty-stage AI generation through the existing
``_run_fill_lesson_patch_flow`` (preview + confirm + undo stay inside it);
T-09 wires QuestionCard chips in the blueprint view and adds the
「AI 填干扰项」 button to choice-type InteractionForms, both reusing
``run_item_chip`` (K-12 chain). Tests mock at those two seams only.
"""
from __future__ import annotations

import os
import shutil
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from PySide6.QtWidgets import QPushButton, QSpinBox, QVBoxLayout, QWidget  # noqa: E402

from src.backend.ai_presets_ui import ITEM_CHIP_INSTRUCTIONS  # noqa: E402
from src.backend.course_adapter import CourseAdapter  # noqa: E402
from src.backend.lesson_presets import build_preset_lesson  # noqa: E402
from src.teacher.question_cards import QuestionCard  # noqa: E402
from src.widgets.interaction_forms import InteractionForm  # noqa: E402
from src.widgets.lesson_blueprint import LessonBlueprint  # noqa: E402
from tests._course_fixture import real_adapter_with_course  # noqa: E402
from tests._qtapp import qt_app  # noqa: E402


class _FlowHost(QWidget):
    """Parent widget exposing the MainWindow fill-flow entry (T-03 chain)."""

    def __init__(self) -> None:
        super().__init__()
        self.calls: list[dict] = []
        QVBoxLayout(self)

    def _run_fill_lesson_patch_flow(self, **kwargs) -> None:
        self.calls.append(kwargs)


def _ai_buttons(bp: LessonBlueprint) -> list[QPushButton]:
    return bp.findChildren(QPushButton, "aiGenerateBtn")


class BlueprintAiGenerateTest(unittest.TestCase):
    """T-08: empty-stage AI generation entries in the blueprint view."""

    def setUp(self) -> None:
        qt_app()
        self.adapter, self.tmp = real_adapter_with_course(prefix="turna_t08_")
        self.addCleanup(lambda: shutil.rmtree(self.tmp, ignore_errors=True))
        _s, _u, self.lesson = self.adapter.find_lesson(self._first_lesson_id())

    def _first_lesson_id(self) -> str:
        for section in self.adapter.sections:
            for unit in section.get("units", []):
                for lesson in unit.get("lessons", []):
                    return lesson["id"]
        raise AssertionError("fixture course has no lessons")

    def _make_empty_listening(self, host: QWidget | None = None) -> LessonBlueprint:
        self.lesson["template"] = "listening"
        self.lesson["content"] = {"listeningPhases": []}
        bp = LessonBlueprint(self.adapter, self.lesson, read_only=False)
        if host is not None:
            host.layout().addWidget(bp)
        return bp

    def test_empty_listening_shows_ai_generate_row(self) -> None:
        bp = self._make_empty_listening()
        buttons = _ai_buttons(bp)
        self.assertEqual(len(buttons), 1)
        self.assertEqual(buttons[0].text(), "生成听力阶段")
        spins = bp.findChildren(QSpinBox, "aiGenerateSpin")
        self.assertEqual(len(spins), 1)
        self.assertEqual(spins[0].value(), 3)
        self.assertEqual(spins[0].minimum(), 1)
        self.assertEqual(spins[0].maximum(), 8)

    def test_non_empty_listening_hides_ai_generate_row(self) -> None:
        lesson = build_preset_lesson("listening-3phase")
        bp = LessonBlueprint(self.adapter, lesson, read_only=False)
        self.assertEqual(_ai_buttons(bp), [])

    def test_read_only_hides_ai_entries(self) -> None:
        self.lesson["template"] = "listening"
        self.lesson["content"] = {"listeningPhases": []}
        bp = LessonBlueprint(self.adapter, self.lesson, read_only=True)
        self.assertEqual(_ai_buttons(bp), [])

    def test_click_passes_n_and_instruction_to_fill_flow(self) -> None:
        host = _FlowHost()
        bp = self._make_empty_listening(host)
        spin = bp.findChildren(QSpinBox, "aiGenerateSpin")[0]
        spin.setValue(5)
        _ai_buttons(bp)[0].click()
        self.assertEqual(len(host.calls), 1)
        call = host.calls[0]
        self.assertEqual(call["lesson_id"], self.lesson["id"])
        self.assertIn("units", call["section"])
        self.assertIn("5 个听力阶段", call["instruction"])
        self.assertIn("保持 lesson id 不变", call["instruction"])

    def test_empty_stage_items_show_ai_generate_items_row(self) -> None:
        host = _FlowHost()
        stage = {"id": "st1", "name": "Check", "items": []}
        self.lesson["template"] = "mastery"
        self.lesson["content"] = {"stages": [stage]}
        bp = LessonBlueprint(self.adapter, self.lesson, read_only=False)
        host.layout().addWidget(bp)
        buttons = [b for b in _ai_buttons(bp) if b.text() == "生成题目"]
        self.assertEqual(len(buttons), 1)
        bp.findChildren(QSpinBox, "aiGenerateSpin")[0].setValue(4)
        buttons[0].click()
        self.assertEqual(len(host.calls), 1)
        self.assertIn("4 道题", host.calls[0]["instruction"])
        self.assertIn("阶段结构不变", host.calls[0]["instruction"])

    def test_missing_host_flow_degrades_silently(self) -> None:
        # No _run_fill_lesson_patch_flow anywhere in the parent chain: the
        # click must not raise (statusBar fallback or fully silent).
        bp = self._make_empty_listening()
        _ai_buttons(bp)[0].click()  # no raise
        # Lesson not locatable in the adapter either: still silent.
        orphan = CourseAdapter()
        bp2 = LessonBlueprint(
            orphan,
            {"id": "missing", "template": "listening", "content": {"listeningPhases": []}},
            read_only=False,
        )
        _ai_buttons(bp2)[0].click()  # no raise


class BlueprintItemChipTest(unittest.TestCase):
    """T-09 (gap 1): blueprint QuestionCard chips reach run_item_chip."""

    def setUp(self) -> None:
        qt_app()
        self.adapter = CourseAdapter()

    def test_chip_routes_run_item_chip_with_distractor_instruction(self) -> None:
        lesson = build_preset_lesson("mastery-mix")
        bp = LessonBlueprint(self.adapter, lesson, read_only=False)
        cards = bp.findChildren(QuestionCard)
        self.assertGreaterEqual(len(cards), 1)
        card = cards[0]
        with patch("src.teacher.item_ai_chip.run_item_chip") as mock_run:
            card.ai_chip_requested.emit(ITEM_CHIP_INSTRUCTIONS[2])
        mock_run.assert_called_once()
        args, kwargs = mock_run.call_args
        self.assertIs(args[0], bp)
        self.assertIs(kwargs["item"], card.item)
        self.assertEqual(kwargs["instruction"], ITEM_CHIP_INSTRUCTIONS[2])
        self.assertIn("保持答案与 id 不变", kwargs["instruction"])
        self.assertTrue(callable(kwargs["on_applied"]))


class InteractionFormAiDistractorTest(unittest.TestCase):
    """T-09 (gap 2): 「AI 填干扰项」 button on choice-type forms."""

    def setUp(self) -> None:
        qt_app()
        self.adapter = CourseAdapter()

    @staticmethod
    def _mcq() -> tuple[dict, dict]:
        item = {
            "id": "q1",
            "runtimeType": "multipleChoice",
            "prompt": "Hangisi doğru?",
            "options": ["a", "b"],
            "correctIndex": 0,
        }
        stage = {"id": "s1", "name": "Stage", "items": [item]}
        return item, stage

    def test_choice_type_shows_button(self) -> None:
        item, stage = self._mcq()
        form = InteractionForm(self.adapter, item, stage=stage)
        self.assertIsNotNone(form.ai_distractor_btn)
        self.assertEqual(form.ai_distractor_btn.text(), "AI 填干扰项")

    def test_non_choice_type_hides_button(self) -> None:
        item = {
            "id": "q2",
            "runtimeType": "fillBlank",
            "sentence": "Ben ___ öğrenci.",
            "expectedAnswer": "bir",
        }
        stage = {"id": "s1", "items": [item]}
        form = InteractionForm(self.adapter, item, stage=stage)
        self.assertIsNone(form.ai_distractor_btn)

    def test_missing_stage_hides_button(self) -> None:
        # Fallback-safe: without the owning stage the chip chain cannot
        # apply a patch, so no button is offered (never raises).
        item, _stage = self._mcq()
        form = InteractionForm(self.adapter, item)
        self.assertIsNone(form.ai_distractor_btn)

    def test_button_invokes_chip_with_distractor_instruction(self) -> None:
        item, stage = self._mcq()
        form = InteractionForm(self.adapter, item, stage=stage)
        with patch("src.teacher.item_ai_chip.run_item_chip") as mock_run:
            form.ai_distractor_btn.click()
        mock_run.assert_called_once()
        args, kwargs = mock_run.call_args
        self.assertIs(args[0], form)
        self.assertIs(kwargs["stage"], stage)
        self.assertIs(kwargs["item"], item)
        self.assertEqual(kwargs["instruction"], ITEM_CHIP_INSTRUCTIONS[2])
        self.assertTrue(callable(kwargs["on_applied"]))

    def test_on_applied_resyncs_options_editor(self) -> None:
        item, stage = self._mcq()
        form = InteractionForm(self.adapter, item, stage=stage)
        item["options"] = ["x", "y", "z"]
        form._on_ai_applied()
        editor = form._widgets["options"]
        texts = [
            editor.list_widget.item(i).text()
            for i in range(editor.list_widget.count())
        ]
        self.assertEqual(texts, ["x", "y", "z"])


if __name__ == "__main__":
    unittest.main()
