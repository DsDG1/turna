"""Resource editor experience hooks (V-01 multi-select, V-05 CSV diagnose).

Also covers T-05 new-lesson dialog AI-generate checkbox wiring into the tree.
Formerly part of the version-tagged test_experience_v415 module.
"""
from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from tests._qtapp import qt_app  # noqa: E402


class _ResourceAdapter:
    def __init__(self) -> None:
        self.vocab = [
            {"id": "w1", "term": "merhaba", "translation": "你好"},
            {"id": "w2", "term": "günaydın", "translation": "早上好"},
        ]
        self.expressions: list = []
        self.grammar_points: list = []
        self.notified = 0

    def _resource_list(self, row_type: str) -> list:
        return {
            "vocab": self.vocab,
            "expressions": self.expressions,
            "grammar_points": self.grammar_points,
        }[row_type]

    def import_csv(self, row_type: str, path) -> list:
        self.vocab.append({"id": "w3", "term": "teşekkürler", "translation": "谢谢"})
        return []

    def notify_resources_changed(self) -> None:
        self.notified += 1


class ResourceExperienceTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        qt_app()

    def test_v01_selected_refs_single_and_multi(self) -> None:
        from PySide6.QtWidgets import QTableWidgetSelectionRange
        from src.widgets.resource_editor import ResourceEditorDialog

        dlg = ResourceEditorDialog(_ResourceAdapter())
        self.addCleanup(dlg.deleteLater)
        tab = dlg.tabs[0]
        self.assertEqual(dlg.selected_refs(), [])
        tab.table.selectRow(0)
        self.assertEqual(dlg.selected_refs(), [("vocab", "w1")])
        tab.table.setRangeSelected(
            QTableWidgetSelectionRange(0, 0, 1, tab.table.columnCount() - 1), True
        )
        self.assertEqual(
            dlg.selected_refs(), [("vocab", "w1"), ("vocab", "w2")]
        )

    def test_v05_csv_import_triggers_diagnose(self) -> None:
        from PySide6.QtWidgets import QWidget
        from src.widgets.resource_editor import ResourceTableWidget

        calls: list[str] = []
        host = QWidget()
        self.addCleanup(host.deleteLater)
        host._start_experience_diagnose = lambda: calls.append("diagnose")
        tab = ResourceTableWidget(_ResourceAdapter(), "vocab")
        tab.setParent(host)
        with patch(
            "src.widgets.resource_editor.QFileDialog.getOpenFileName",
            return_value=("/tmp/words.csv", ""),
        ), patch("src.widgets.resource_editor.QMessageBox"):
            tab._on_import()
        self.assertEqual(calls, ["diagnose"])
        self.assertEqual(tab.adapter.notified, 1)


class V04DeleteRefGraphTest(unittest.TestCase):
    """V-04 (v4.52): delete confirmation carries ref graph; replacement mapping."""

    @classmethod
    def setUpClass(cls) -> None:
        qt_app()

    def _adapter(self):
        class _A:
            def __init__(self) -> None:
                self.vocab = [
                    {"id": "w1", "term": "merhaba", "translation": "你好"},
                    {"id": "w2", "term": "Merhaba", "translation": "您好"},
                    {"id": "w3", "term": "su", "translation": "水"},
                ]
                self.expressions: list = []
                self.grammar_points: list = []
                self.sections = [
                    {
                        "id": "s1",
                        "units": [
                            {
                                "id": "u1",
                                "lessons": [
                                    {
                                        "id": "l1",
                                        "content": {
                                            "stages": [
                                                {
                                                    "id": "st1",
                                                    "items": [
                                                        {"id": "i1", "wordId": "w1"},
                                                        {"id": "i2", "wordIds": ["w1"]},
                                                    ],
                                                }
                                            ]
                                        },
                                    }
                                ],
                            }
                        ],
                    }
                ]
                self.notified = 0

            def _resource_list(self, row_type: str) -> list:
                return {
                    "vocab": self.vocab,
                    "expressions": self.expressions,
                    "grammar_points": self.grammar_points,
                }[row_type]

            def delete_resource_entry(self, row_type: str, entry_id: str) -> None:
                entries = self._resource_list(row_type)
                for i, e in enumerate(entries):
                    if e.get("id") == entry_id:
                        del entries[i]
                        return
                raise KeyError(entry_id)

            def notify_resources_changed(self) -> None:
                self.notified += 1

        return _A()

    def test_delete_confirm_text_includes_ref_count_and_locations(self) -> None:
        from src.backend.experience.resource_refs import find_resource_refs
        from src.widgets.resource_editor import ResourceTableWidget

        adapter = self._adapter()
        tab = ResourceTableWidget(adapter, "vocab")
        self.addCleanup(tab.deleteLater)
        report = find_resource_refs(adapter, "vocab", "w1")
        text = tab._delete_confirm_text("vocab [w1]", report)
        self.assertIn("2 处引用", text)
        self.assertIn("l1", text)
        self.assertIn("i1", text)
        # 零引用词条：明示「未发现引用」
        empty = find_resource_refs(adapter, "vocab", "w3")
        self.assertEqual(empty["count"], 0)
        self.assertIn("未发现引用", tab._delete_confirm_text("vocab [w3]", empty))

    def test_batch_del_decline_with_refs_offers_replacement(self) -> None:
        from src.widgets.resource_editor import ResourceTableWidget

        adapter = self._adapter()
        tab = ResourceTableWidget(adapter, "vocab")
        self.addCleanup(tab.deleteLater)
        tab.table.selectRow(0)  # w1（被引用）
        with patch(
            "src.widgets.resource_editor.QMessageBox"
        ) as qbox, patch.object(
            tab, "_maybe_propose_batch_replacement"
        ) as propose:
            qbox.question.return_value = qbox.StandardButton.No
            tab._on_batch_del()
        propose.assert_called_once()
        # 取消后词条仍在
        self.assertIn("w1", [e["id"] for e in adapter.vocab])

    def test_propose_replacement_applies_without_host(self) -> None:
        from src.widgets.resource_editor import ResourceTableWidget

        adapter = self._adapter()
        tab = ResourceTableWidget(adapter, "vocab")
        self.addCleanup(tab.deleteLater)
        with patch.object(
            tab, "_choose_replacement", return_value="w2"
        ), patch("src.widgets.resource_editor.QMessageBox") as qbox:
            qbox.question.return_value = qbox.StandardButton.Yes
            ok = tab._propose_replacement("w1")
        self.assertTrue(ok)
        item = adapter.sections[0]["units"][0]["lessons"][0]["content"]["stages"][0]["items"][0]
        self.assertEqual(item["wordId"], "w2")
        self.assertEqual(item["id"], "i1")  # 保 item id


class NewLessonAiGenerateTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        qt_app()

    def test_checkbox_defaults_off(self) -> None:
        from src.dialogs.new_lesson_dialog import NewLessonDialog

        dlg = NewLessonDialog()
        self.addCleanup(dlg.deleteLater)
        self.assertFalse(dlg.generate_with_ai())
        dlg.ai_generate_check.setChecked(True)
        self.assertTrue(dlg.generate_with_ai())

    def test_tree_wires_fill_empty_when_checked(self) -> None:
        from PySide6.QtWidgets import QWidget
        from src.widgets.course_tree import CourseTreeWidget

        class _Adapter:
            sections: list = []

            def new_lesson(self, unit_id: str, template: str) -> str:
                return "l-new"

            def find_lesson(self, lesson_id: str):
                return ({}, {}, {"id": lesson_id})

            def delete_lesson(self, lesson_id: str) -> None:
                pass

        calls: list[dict] = []
        win = QWidget()
        self.addCleanup(win.deleteLater)
        win._experience_fill_empty = lambda scope: calls.append(scope)
        tree = CourseTreeWidget()
        tree.setParent(win)
        tree.adapter = _Adapter()

        class _Dlg:
            use_wizard = False

            def exec(self) -> int:
                return 1

            def template(self) -> str:
                return "intro"

            def lesson_name(self) -> str:
                return ""

            def generate_with_ai(self) -> bool:
                return True

        with patch(
            "src.dialogs.new_lesson_dialog.NewLessonDialog", return_value=_Dlg()
        ):
            tree._new_lesson("u1")
        self.assertEqual(calls, [{"first_lesson_id": "l-new"}])

    def test_tree_skips_fill_when_unchecked(self) -> None:
        from PySide6.QtWidgets import QWidget
        from src.widgets.course_tree import CourseTreeWidget

        class _Adapter:
            sections: list = []

            def new_lesson(self, unit_id: str, template: str) -> str:
                return "l-new"

            def find_lesson(self, lesson_id: str):
                return ({}, {}, {"id": lesson_id})

            def delete_lesson(self, lesson_id: str) -> None:
                pass

        calls: list[dict] = []
        win = QWidget()
        self.addCleanup(win.deleteLater)
        win._experience_fill_empty = lambda scope: calls.append(scope)
        tree = CourseTreeWidget()
        tree.setParent(win)
        tree.adapter = _Adapter()

        class _Dlg:
            use_wizard = False

            def exec(self) -> int:
                return 1

            def template(self) -> str:
                return "intro"

            def lesson_name(self) -> str:
                return ""

            def generate_with_ai(self) -> bool:
                return False

        with patch(
            "src.dialogs.new_lesson_dialog.NewLessonDialog", return_value=_Dlg()
        ):
            tree._new_lesson("u1")
        self.assertEqual(calls, [])


if __name__ == "__main__":
    unittest.main()
