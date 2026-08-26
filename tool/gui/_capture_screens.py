#!/usr/bin/env python3
"""Capture real GUI screenshots in offscreen mode for documentation.

Run with:
    cd Varnamalaplus && QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \\
        /usr/bin/python3 tool/gui/_capture_screens.py
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")

ROOT = Path(__file__).resolve().parents[2]
GUI_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(GUI_DIR))
sys.path.insert(0, str(ROOT / "tool"))

OUT_DIR = Path(
    "/home/whwen/documents/reso/Varnamalaplus/TurnaWeb/docs/public/images/authoring/_real"
)
OUT_DIR.mkdir(parents=True, exist_ok=True)

from PySide6 import QtCore, QtGui, QtWidgets  # noqa: E402

from src.app import MainWindow  # noqa: E402
from src.application.settings import Settings  # noqa: E402
from src.backend.course_adapter import CourseAdapter  # noqa: E402
from src.theme import apply_theme  # noqa: E402

COURSE_DIR = ROOT / "assets" / "courses" / "turkish"


def grab(widget, name: str) -> None:
    pixmap: QtGui.QPixmap = widget.grab()
    target = OUT_DIR / f"{name}.png"
    pixmap.save(str(target), "PNG")
    print(f"  saved {target.name}  ({pixmap.width()}x{pixmap.height()})")


def expand_tree_items(tree) -> None:
    for i in range(min(tree.topLevelItemCount(), 4)):
        it = tree.topLevelItem(i)
        it.setExpanded(True)
        for j in range(min(it.childCount(), 3)):
            it.child(j).setExpanded(True)
            for k in range(min(it.child(j).childCount(), 3)):
                it.child(j).child(k).setExpanded(True)
    if tree.topLevelItemCount() > 0:
        first = tree.topLevelItem(0)
        if first.childCount() > 0:
            unit = first.child(0)
            if unit.childCount() > 0:
                tree.setCurrentItem(unit.child(0))
            else:
                tree.setCurrentItem(unit)


def _pump(app: QtWidgets.QApplication, n: int = 4) -> None:
    for _ in range(n):
        app.processEvents()


def capture_existing(app, win, adapter) -> None:
    expand_tree_items(win.tree)
    _pump(app, 5)
    grab(win, "01-main-window")

    if win.tree.topLevelItemCount() > 0:
        first_section = win.tree.topLevelItem(0)
        if first_section.childCount() > 0 and first_section.child(0).childCount() > 0:
            lesson_item = first_section.child(0).child(0)
            win.tree.setCurrentItem(lesson_item)
            _pump(app, 4)
            grab(win, "02-lesson-selected")

    try:
        win._on_overview()
        _pump(app, 5)
        if win._overview_window is not None:
            win._overview_window.resize(1280, 820)
            win._overview_window.show()
            _pump(app, 5)
            grab(win._overview_window, "03-overview")
            win._overview_window.close()
    except Exception as exc:
        print(f"  overview skipped: {exc}")

    try:
        from src.widgets.resource_editor import ResourceEditorDialog

        dlg = ResourceEditorDialog(adapter, parent=win)
        dlg.resize(1180, 760)
        dlg.show()
        _pump(app, 5)
        grab(dlg, "04-resource-editor")
        dlg.close()
    except Exception as exc:
        print(f"  resource editor skipped: {exc}")

    try:
        from src.dialogs.workshop_window import WorkshopWindow

        ws = WorkshopWindow(adapter, parent=win)
        ws.resize(1480, 920)
        ws.show()
        _pump(app, 4)
        entered = ws.restore_last_session()
        if not entered and ws._store is not None:
            try:
                projects = ws._store.list_projects()
                if projects:
                    pid = projects[0].get("id") or projects[0].get("project_id")
                    if pid:
                        proj = ws._store.load_project(str(pid))
                        if proj is not None:
                            ws._on_project_selected(proj)
                            entered = True
            except Exception as exc:
                print(f"  workshop restore fallback failed: {exc}")
        if not entered:
            try:
                from src.backend.textbook_project import TextbookProject

                blank = TextbookProject.create(
                    project_id="capture-blank-001",
                    name="土耳其语 A1 样例",
                    source_path=None,
                )
                ws._on_project_selected(blank)
                entered = True
            except Exception as exc:
                print(f"  workshop blank fallback failed: {exc}")
        _pump(app, 5)
        grab(ws, "05-workshop")
        ws.close()
    except Exception as exc:
        print(f"  workshop skipped: {exc}")

    try:
        from src.teacher.preview_window import LessonPreviewDialog

        sections = adapter.sections
        if sections and sections[0]["units"] and sections[0]["units"][0]["lessons"]:
            lesson = sections[0]["units"][0]["lessons"][0]
            tw = LessonPreviewDialog(adapter, lesson, parent=win)
            tw.resize(1280, 800)
            tw.show()
            _pump(app, 5)
            grab(tw, "06-teacher-mode")
            tw.close()
    except Exception as exc:
        print(f"  teacher mode skipped: {exc}")


def capture_extensions(app, win, adapter) -> None:
    # 07 Publish dialog — expert mode
    try:
        from src.widgets.publish_dialog import PublishDialog

        dlg = PublishDialog(adapter, parent=win, teacher_friendly=False)
        dlg.resize(820, 720)
        dlg.show()
        _pump(app, 5)
        grab(dlg, "07-publish-expert")
        dlg.close()
    except Exception as exc:
        print(f"  publish expert skipped: {exc}")

    # 08 Publish dialog — teacher_friendly mode
    try:
        from src.widgets.publish_dialog import PublishDialog

        dlg = PublishDialog(adapter, parent=win, teacher_friendly=True)
        dlg.resize(620, 640)
        dlg.show()
        _pump(app, 5)
        grab(dlg, "08-publish-teacher")
        dlg.close()
    except Exception as exc:
        print(f"  publish teacher skipped: {exc}")

    # 09 Functional Lesson Wizard
    try:
        from src.dialogs.functional_lesson_wizard import FunctionalLessonWizard

        # Pick the first unit of the first section as the wizard target
        unit_id = "u-tmp"
        if adapter.sections and adapter.sections[0].get("units"):
            unit_id = adapter.sections[0]["units"][0].get("id", "u-tmp")
        dlg = FunctionalLessonWizard(adapter, unit_id, parent=win)
        dlg.resize(720, 560)
        dlg.show()
        _pump(app, 5)
        grab(dlg, "09-functional-wizard")
        dlg.close()
    except Exception as exc:
        import traceback
        print(f"  functional wizard skipped: {exc}")
        traceback.print_exc()

    # 10 Generate Audio dialog (preview state)
    try:
        from src.dialogs.generate_audio_dialog import GenerateAudioDialog

        settings = Settings.load_from_qsettings(win._settings)
        preview = {
            "total": 12,
            "existing": 3,
            "sounds_dir": str(ROOT / "assets" / "sounds" / "turkish"),
        }
        dlg = GenerateAudioDialog(settings, preview, parent=win)
        dlg.resize(560, 480)
        dlg.show()
        _pump(app, 5)
        grab(dlg, "10-generate-audio")
        dlg.close()
    except Exception as exc:
        print(f"  generate audio skipped: {exc}")

    # 11 Settings dialog — AI 配置 tab
    try:
        from src.dialogs.settings_dialog import SettingsDialog

        settings = Settings.load_from_qsettings(win._settings)
        dlg = SettingsDialog(settings, parent=win)
        dlg.resize(720, 600)
        dlg.show()
        _pump(app, 5)
        # Switch to the AI configuration tab (index 1 in the tab order)
        if hasattr(dlg, "tabs"):
            dlg.tabs.setCurrentIndex(1)
            _pump(app, 4)
        grab(dlg, "11-settings-ai")
        dlg.close()
    except Exception as exc:
        print(f"  settings skipped: {exc}")

    # 12 Init course dialog
    try:
        from src.dialogs.init_course_dialog import InitCourseDialog

        dlg = InitCourseDialog(adapter, parent=win)
        dlg.resize(560, 360)
        dlg.show()
        _pump(app, 5)
        grab(dlg, "12-init-course")
        dlg.close()
    except Exception as exc:
        print(f"  init course skipped: {exc}")

    # 13 Textbook library dialog
    try:
        from src.dialogs.textbook_library_dialog import TextbookLibraryDialog

        dlg = TextbookLibraryDialog(parent=win)
        dlg.resize(820, 480)
        dlg.show()
        _pump(app, 5)
        grab(dlg, "13-textbook-library")
        dlg.close()
    except Exception as exc:
        print(f"  textbook library skipped: {exc}")

    # 14 Quality campaign dialog
    try:
        from src.dialogs.quality_campaign_dialog import (
            QualityCampaignDialog,
            build_campaign_items,
        )

        # Pull a couple of weak / empty sections for a meaningful list
        items = build_campaign_items(
            quality_by_section={"s-basics": 0.42, "s-everyday": 0.55, "s-grammar": 0.38},
            empty_lessons=["l-u1-greetings-intro", "l-u2-numbers-listening"],
            sections=adapter.sections,
            worst_n=4,
            quality_threshold=0.7,
        )
        dlg = QualityCampaignDialog(items, parent=win)
        dlg.resize(540, 420)
        dlg.show()
        _pump(app, 5)
        grab(dlg, "14-quality-campaign")
        dlg.close()
    except Exception as exc:
        print(f"  quality campaign skipped: {exc}")

    # 15 Validation report widget (populated with sample problems)
    try:
        from src.widgets.validation_report import ValidationReportWidget

        rep = ValidationReportWidget(adapter, parent=win)
        rep.resize(900, 540)
        # Inject sample problems for screenshot
        sample = [
            {
                "id": "unresolved-reference",
                "level": "error",
                "code": "E_REFERENCE",
                "path": "sections/section2.json#/units/0/lessons/1/content/subLessons/0/stages/0/items/0/wordId",
                "message": "Lesson l-u2-numbers-fill 引用了不存在的 vocab id: w-yuz",
                "suggestion": "检查 vocab.json；该 id 是否拼写错误或已被删除",
            },
            {
                "id": "duplicate-id",
                "level": "error",
                "code": "E_DUPLICATE_ID",
                "path": "sections/section1.json#/units/0/lessons/0/id",
                "message": "ID l-u1-greetings-intro 在全课程内重复出现",
                "suggestion": "改用 short_id 重新生成",
            },
            {
                "id": "missing-audio",
                "level": "warning",
                "code": "W_AUDIO",
                "path": "sections/section3.json#/units/0/lessons/0/content/listeningPhases/1/audioAsset",
                "message": "听力课引用了不存在的音频：lessons/l-u1/main.mp3",
                "suggestion": "补录或删除该引用",
            },
        ]
        if hasattr(rep, "set_problems"):
            rep.set_problems(sample)
        elif hasattr(rep, "load_problems"):
            rep.load_problems(sample)
        rep.show()
        _pump(app, 5)
        grab(rep, "15-validation-report")
        rep.close()
    except Exception as exc:
        print(f"  validation report skipped: {exc}")

    # 16 Course tree right-click context menu
    try:
        if win.tree.topLevelItemCount() > 0:
            first_section = win.tree.topLevelItem(0)
            if first_section.childCount() > 0:
                # Build a unit-kind context menu mirroring course_tree._on_context_menu
                target = first_section.child(0)
                win.tree.setCurrentItem(target)
                _pump(app, 3)
                # Replicate the unit-kind branch in offscreen mode (no exec)
                ref = target.data(0, 0x0100)
                if ref is not None:
                    kind, node_id = ref
                    menu = QtWidgets.QMenu(win.tree)
                    if kind == "unit":
                        menu.addAction("新建 Lesson")
                        menu.addAction("功能课向导…")
                        menu.addAction("删除 Unit")
                        menu.addSeparator()
                        menu.addAction("AI 编辑此 Unit")
                        menu.addAction("AI 修正此 Unit")
                    elif kind == "section":
                        menu.addAction("新建 Unit")
                        menu.addAction("删除 Section")
                        menu.addSeparator()
                        menu.addAction("AI 编辑此 Section")
                        menu.addAction("AI 修正此 Section")
                    elif kind == "lesson":
                        menu.addAction("复制 Lesson   Ctrl+D")
                        menu.addAction("删除 Lesson")
                        menu.addSeparator()
                        menu.addAction("AI 编辑此 Lesson")
                        menu.addAction("AI 修正此 Lesson")
                    if not menu.isEmpty():
                        menu.popup(QtCore.QPoint(60, 60))
                        _pump(app, 4)
                        grab(menu, "16-context-menu")
                        menu.close()
    except Exception as exc:
        import traceback
        print(f"  context menu skipped: {exc}")
        traceback.print_exc()


def main() -> int:
    print("Qt platform: offscreen")
    print(f"loading course: {COURSE_DIR}")
    if not COURSE_DIR.exists():
        print(f"course dir missing: {COURSE_DIR}")
        return 1

    app = QtWidgets.QApplication.instance() or QtWidgets.QApplication(sys.argv)
    app.setApplicationName("Turna Capture")
    apply_theme(app)

    win = MainWindow()
    win.resize(1480, 920)
    win.show()
    _pump(app, 3)

    adapter = CourseAdapter()
    adapter.load(COURSE_DIR)
    win.adapter = adapter
    win.course_dir = COURSE_DIR
    win.tree.display(adapter)
    win.undo_stack.clear()
    win._enable_editor_actions()
    win.statusBar().showMessage(f"已加载: {COURSE_DIR}", 4000)

    capture_existing(app, win, adapter)
    capture_extensions(app, win, adapter)

    win.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
