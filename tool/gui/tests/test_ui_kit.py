"""UI-kit component tests (GUI 焕新 W1).

Covers ActivityBar state switching, TurnaButton variants, Badge/Pill,
ViewHeader, TurnaDialog, EmptyState, SearchField debounce, ToastHost.
"""
from __future__ import annotations

import unittest

from tests._qtapp import qt_app


def _app():
    return qt_app()


class ActivityBarTest(unittest.TestCase):
    def setUp(self) -> None:
        _app()
        from PySide6.QtWidgets import QWidget

        from src.widgets.ui import ActivityBar

        self.parent = QWidget()
        self.bar = ActivityBar(self.parent)
        self.bar.add_menu_button("菜单")
        self.bar.add_separator()
        for key, ic in (
            ("edit", "folder-open"),
            ("workshop", "sparkles"),
            ("overview", "map"),
            ("resources", "library"),
        ):
            self.bar.add_item(key, ic, key, view=True)
        self.bar.add_separator()
        self.bar.add_item("copilot", "bot", "copilot")
        self.bar.add_stretch()
        self.bar.add_item("settings", "settings", "settings", checkable=False)

    def test_view_items_exclusive(self) -> None:
        self.bar.set_current("edit")
        self.bar.set_current("overview")
        self.assertEqual(self.bar.current_view_key(), "overview")
        self.assertFalse(self.bar.item("edit").isChecked())

    def test_view_activated_signal(self) -> None:
        fired: list[str] = []
        self.bar.view_activated.connect(fired.append)
        self.bar.item("workshop").setChecked(True)
        self.assertEqual(fired, ["workshop"])

    def test_toggle_item_not_in_view_group(self) -> None:
        self.bar.set_current("edit")
        copilot = self.bar.item("copilot")
        copilot.setChecked(True)
        # Checking the copilot toggle must not clear the active view.
        self.assertEqual(self.bar.current_view_key(), "edit")

    def test_badge_set_and_clear(self) -> None:
        item = self.bar.item("overview")
        self.bar.set_badge("overview", 4, danger=True)
        self.assertEqual(item.badge_count(), 4)
        self.assertFalse(item._badge.isHidden())
        self.bar.set_badge("overview", 0)
        self.assertTrue(item._badge.isHidden())

    def test_non_checkable_item(self) -> None:
        self.assertFalse(self.bar.item("settings").isCheckable())

    def test_item_clicked_signal(self) -> None:
        fired: list[str] = []
        self.bar.item_clicked.connect(fired.append)
        self.bar.item("resources").click()
        self.assertEqual(fired, ["resources"])

    def test_width_fixed(self) -> None:
        self.assertEqual(self.bar.width(), self.bar.WIDTH)


class TurnaButtonTest(unittest.TestCase):
    def setUp(self) -> None:
        _app()
        from src.widgets.ui import TurnaButton

        self.TurnaButton = TurnaButton

    def test_variant_property(self) -> None:
        for variant in ("primary", "secondary", "ghost", "danger"):
            b = self.TurnaButton("x", variant=variant)
            self.assertEqual(b.property("variant"), variant)
            self.assertEqual(b.variant(), variant)

    def test_invalid_variant_falls_back(self) -> None:
        b = self.TurnaButton("x", variant="weird")
        self.assertEqual(b.variant(), "secondary")

    def test_size_property(self) -> None:
        self.assertEqual(self.TurnaButton("a", size="sm").property("btnSize"), "sm")
        self.assertEqual(self.TurnaButton("a", size="md").property("btnSize"), "md")
        self.assertEqual(self.TurnaButton("a", size="huge").property("btnSize"), "md")

    def test_icon_set(self) -> None:
        b = self.TurnaButton("save", icon_name="save")
        self.assertFalse(b.icon().isNull())

    def test_object_name(self) -> None:
        self.assertEqual(self.TurnaButton("x").objectName(), "TurnaButton")


class BadgePillTest(unittest.TestCase):
    def setUp(self) -> None:
        _app()

    def test_badge_count_and_overflow(self) -> None:
        from src.widgets.ui import Badge

        b = Badge(5)
        self.assertEqual(b.text(), "5")
        b.set_count(150)
        self.assertEqual(b.text(), "99+")
        b.set_count(0)
        self.assertTrue(b.isHidden())

    def test_badge_variants(self) -> None:
        from src.widgets.ui import Badge

        for variant in ("accent", "danger", "muted"):
            b = Badge(1, variant=variant)
            self.assertEqual(b.property("variant"), variant)
        self.assertEqual(Badge(1, variant="nope").property("variant"), "accent")

    def test_pill_variants_and_custom(self) -> None:
        from src.widgets.ui import Pill

        for variant in ("accent", "success", "warning", "danger", "muted"):
            p = Pill("t", variant=variant)
            self.assertEqual(p.property("variant"), variant)
        p = Pill("t", color="#B85C3F")
        self.assertEqual(p.property("variant"), "custom")
        self.assertIn("#B85C3F", p.styleSheet())


class ViewHeaderTest(unittest.TestCase):
    def setUp(self) -> None:
        _app()
        from src.widgets.ui import TurnaButton, ViewHeader

        self.header = ViewHeader("编辑")
        self.TurnaButton = TurnaButton

    def test_title_and_breadcrumb(self) -> None:
        self.header.set_title("工坊")
        self.assertEqual(self.header.title(), "工坊")
        self.header.set_breadcrumb(["Section", "Unit", "Lesson"])
        self.assertIn("Section", self.header._context.text())
        self.assertIn("›", self.header._context.text())
        self.header.set_breadcrumb(None)
        self.assertFalse(self.header._context.isVisible())

    def test_actions_slot(self) -> None:
        self.assertEqual(self.header.action_count(), 0)
        self.header.add_action(self.TurnaButton("保存", variant="primary"))
        self.header.add_action(self.TurnaButton("⋮", variant="ghost"))
        self.assertEqual(self.header.action_count(), 2)


class TurnaDialogTest(unittest.TestCase):
    def setUp(self) -> None:
        _app()
        from src.widgets.ui import TurnaDialog

        self.TurnaDialog = TurnaDialog

    def test_header_body_footer(self) -> None:
        dlg = self.TurnaDialog(title="标题", description="说明")
        self.assertEqual(dlg.windowTitle(), "标题")
        self.assertEqual(dlg._title.text(), "标题")
        self.assertFalse(dlg._description.isHidden())
        # Footer hidden until a button is added.
        self.assertTrue(dlg._footer_host.isHidden())
        dlg.add_button("取消", slot=dlg.reject)
        dlg.add_button("确定", variant="primary", slot=dlg.accept)
        self.assertFalse(dlg._footer_host.isHidden())
        self.assertEqual(dlg._footer.count(), 3)  # stretch + 2 buttons

    def test_standard_buttons(self) -> None:
        dlg = self.TurnaDialog(title="t")
        _cancel, ok = dlg.add_standard_buttons()
        self.assertEqual(ok.property("variant"), "primary")
        self.assertTrue(ok.isDefault())


class EmptyStateTest(unittest.TestCase):
    def setUp(self) -> None:
        _app()
        from src.widgets.ui import EmptyState

        self.EmptyState = EmptyState

    def test_structure_and_cta(self) -> None:
        fired: list[bool] = []
        e = self.EmptyState(
            icon_name="map",
            title="空标题",
            description="说明",
            cta_text="新建",
            on_cta=lambda: fired.append(True),
        )
        self.assertEqual(e._title.text(), "空标题")
        self.assertIsNotNone(e._cta)
        e._cta.click()
        self.assertEqual(fired, [True])

    def test_no_cta_by_default(self) -> None:
        e = self.EmptyState(title="t")
        self.assertIsNone(e._cta)


class SearchFieldTest(unittest.TestCase):
    def setUp(self) -> None:
        _app()
        from src.widgets.ui import SearchField

        self.field = SearchField("过滤…", debounce_ms=10)

    def test_leading_icon_and_clear(self) -> None:
        self.assertTrue(self.field.isClearButtonEnabled())
        self.assertTrue(self.field.actions())

    def test_debounce_emits_once(self) -> None:
        from PySide6.QtCore import QCoreApplication
        from PySide6.QtTest import QTest

        fired: list[str] = []
        self.field.text_changed_debounced.connect(fired.append)
        self.field.setText("a")
        self.field.setText("ab")
        self.field.setText("abc")
        QTest.qWait(50)
        QCoreApplication.processEvents()
        self.assertEqual(fired, ["abc"])


class ToastHostTest(unittest.TestCase):
    def setUp(self) -> None:
        _app()
        from PySide6.QtWidgets import QWidget

        from src.widgets.ui import ToastHost

        self.parent = QWidget()
        self.parent.resize(600, 400)
        self.parent.show()
        self.host = ToastHost(self.parent)

    def test_show_and_stack(self) -> None:
        t1 = self.host.show_toast("one", severity="info", duration_ms=0)
        t2 = self.host.show_toast("two", severity="success", duration_ms=0)
        self.assertEqual(len(self.host._toasts), 2)
        # Newest toast sits bottom-most (larger y); older ones stack upward.
        self.assertGreater(t2.y(), t1.y())

    def test_max_stack(self) -> None:
        for i in range(8):
            self.host.show_toast(f"t{i}", duration_ms=0)
        self.assertLessEqual(len(self.host._toasts), self.host._MAX_STACK)

    def test_dismiss(self) -> None:
        t = self.host.show_toast("bye", duration_ms=0)
        t.dismiss()
        self.assertNotIn(t, self.host._toasts)

    def test_severity_property(self) -> None:
        t = self.host.show_toast("w", severity="warning", duration_ms=0)
        self.assertEqual(t.property("severity"), "warning")
        t2 = self.host.show_toast("x", severity="bogus", duration_ms=0)
        self.assertEqual(t2.property("severity"), "info")


if __name__ == "__main__":
    unittest.main()
