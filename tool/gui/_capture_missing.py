#!/usr/bin/env python3
"""Capture only the two missing dialogs: 09 wizard and 16 context menu."""
from __future__ import annotations

import os
import sys
from pathlib import Path

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")

ROOT = Path("/home/whwen/documents/reso/Varnamalaplus/Varnamalaplus")
GUI_DIR = ROOT / "tool" / "gui"
sys.path.insert(0, str(GUI_DIR))
sys.path.insert(0, str(ROOT / "tool"))

OUT_DIR = Path(
    "/home/whwen/documents/reso/Varnamalaplus/TurnaWeb/docs/public/images/authoring/_real"
)
OUT_DIR.mkdir(parents=True, exist_ok=True)

from PySide6 import QtCore, QtGui, QtWidgets  # noqa: E402

from src.app import MainWindow  # noqa: E402
from src.backend.course_adapter import CourseAdapter  # noqa: E402
from src.theme import apply_theme  # noqa: E402

COURSE_DIR = ROOT / "assets" / "courses" / "turkish"


def grab(widget, name: str) -> None:
    pixmap = widget.grab()
    target = OUT_DIR / f"{name}.png"
    pixmap.save(str(target), "PNG")
    print(f"saved {target.name}  ({pixmap.width()}x{pixmap.height()})")


def pump(app, n: int = 4) -> None:
    for _ in range(n):
        app.processEvents()


def main() -> int:
    app = QtWidgets.QApplication.instance() or QtWidgets.QApplication(sys.argv)
    apply_theme(app)
    win = MainWindow()
    win.resize(1480, 920)
    win.show()
    pump(app, 3)

    adapter = CourseAdapter()
    adapter.load(COURSE_DIR)
    win.adapter = adapter
    win.course_dir = COURSE_DIR
    win.tree.display(adapter)
    win.undo_stack.clear()
    win._enable_editor_actions()
    pump(app, 4)

    # 09 Functional Lesson Wizard
    try:
        from src.dialogs.functional_lesson_wizard import FunctionalLessonWizard

        unit_id = "u-tmp"
        if adapter.sections and adapter.sections[0].get("units"):
            unit_id = adapter.sections[0]["units"][0].get("id", "u-tmp")
        dlg = FunctionalLessonWizard(adapter, unit_id, parent=win)
        dlg.resize(720, 560)
        dlg.show()
        pump(app, 5)
        grab(dlg, "09-functional-wizard")
        dlg.close()
    except Exception as exc:
        import traceback
        print(f"09 skipped: {exc}")
        traceback.print_exc()

    # 16 Context menu — unit kind
    try:
        if win.tree.topLevelItemCount() > 0:
            first_section = win.tree.topLevelItem(0)
            if first_section.childCount() > 0:
                target = first_section.child(0)
                win.tree.setCurrentItem(target)
                pump(app, 3)
                ref = target.data(0, 0x0100)
                if ref is not None:
                    kind, _ = ref
                    menu = QtWidgets.QMenu(win.tree)
                    if kind == "unit":
                        for label in [
                            "新建 Lesson",
                            "功能课向导…",
                            "删除 Unit",
                            None,
                            "AI 编辑此 Unit",
                            "AI 修正此 Unit",
                        ]:
                            if label is None:
                                menu.addSeparator()
                            else:
                                menu.addAction(label)
                    elif kind == "lesson":
                        for label in [
                            "复制 Lesson   Ctrl+D",
                            "删除 Lesson",
                            None,
                            "AI 编辑此 Lesson",
                            "AI 修正此 Lesson",
                        ]:
                            if label is None:
                                menu.addSeparator()
                            else:
                                menu.addAction(label)
                    else:
                        for label in [
                            "新建 Unit",
                            "删除 Section",
                            None,
                            "AI 编辑此 Section",
                            "AI 修正此 Section",
                        ]:
                            if label is None:
                                menu.addSeparator()
                            else:
                                menu.addAction(label)
                    menu.popup(QtCore.QPoint(40, 40))
                    pump(app, 5)
                    grab(menu, "16-context-menu")
                    menu.close()
    except Exception as exc:
        import traceback
        print(f"16 skipped: {exc}")
        traceback.print_exc()

    win.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
