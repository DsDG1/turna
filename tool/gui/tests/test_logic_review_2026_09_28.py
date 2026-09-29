"""Batch-B regression tests for the 2026-09-28 logic-review fix plan.

One test per data-safety fix, each locking the *real* integration shape:

B1  adapter.load failure must roll the course_dir binding back — otherwise
    the next Ctrl+S writes the OLD in-memory course over the NEW directory;
B2  git pull / branch switch on the clone that IS the open course must ask
    the host to reload it (otherwise the next save overwrites fetched work);
B3  the publish direct-save must mark the undo stack clean so the window
    title / save indicator stop claiming "● 未保存";
B4  bulk append_as_new must deep-rewrite nested unit/lesson ids like the
    single-import path does (shallow rename => duplicate ids on save).
"""
from __future__ import annotations

import shutil
import sys
import contextlib
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from PySide6.QtCore import QObject
from PySide6.QtWidgets import QApplication, QWidget

from src.backend.course_adapter import CourseAdapter
from tests._course_fixture import real_adapter_with_course
from tests._qtapp import _App


def _qt_app() -> QApplication:
    return _App.get()


class B1OpenFailureRollbackTest(unittest.TestCase):
    """打开失败后保存：course_dir 不得指向失败的新目录。"""

    def setUp(self):
        self.adapter, self.tmp = real_adapter_with_course()

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_load_failure_keeps_previous_binding(self):
        prev_dir = self.adapter.course_dir
        bad_dir = self.tmp / "not-a-course"
        bad_dir.mkdir()
        (bad_dir / "index.json").write_text("{ not json", encoding="utf-8")
        with self.assertRaises(ValueError):
            self.adapter.load(bad_dir)
        self.assertEqual(self.adapter.course_dir, prev_dir)
        # And the follow-up save must still land in the OLD directory.
        result = self.adapter.save()
        self.assertTrue(result.ok)


class B1SessionOpenFailureTest(unittest.TestCase):
    """session.open_course 失败：session 状态保持指向旧课程。"""

    def setUp(self):
        _qt_app()
        from src.application.course_session import CourseSession

        adapter, self.tmp = real_adapter_with_course()
        self.session = CourseSession()
        self.session.open_course(adapter.course_dir)

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_open_failure_keeps_session_state(self):
        old_dir = self.session.course_dir
        opened: list[Path] = []
        self.session.repo_opened.connect(lambda p: opened.append(p))
        bad_dir = self.tmp / "broken"
        bad_dir.mkdir()
        (bad_dir / "index.json").write_text("{ bad", encoding="utf-8")
        with self.assertRaises(ValueError):
            self.session.open_course(bad_dir)
        self.assertEqual(self.session.course_dir, old_dir)
        self.assertEqual(opened, [])
        self.assertTrue(self.session.is_open)


class B1WorkerLoaderIsPureTest(unittest.TestCase):
    """复审回归：worker 侧加载器必须只做 adapter.load。

    在 open worker 里调 session.open_course 会提前改写 session.course_dir
    （host.course_dir 代理它），使 bind_loaded_course 读到的"旧目录"已是新
    路径，从而跳过 prepare_course_switch；还会跨线程 clear QUndoStack。
    """

    def setUp(self):
        _qt_app()

    def test_load_via_session_never_touches_session(self):
        import src.application.repo_session_host as rsh
        from src.application.course_session import CourseSession

        loaded: list[Path] = []

        class _Adapter:
            course_dir = None

            def load(self, p):
                loaded.append(Path(p))

        session = CourseSession()
        session.adapter = _Adapter()
        session.course_dir = Path("old") / "course"
        opened: list[Path] = []
        session.repo_opened.connect(lambda p: opened.append(p))

        target = Path("new") / "course"
        rsh.load_via_session(session, target)

        self.assertEqual(loaded, [target])  # the load happened…
        # …and NOTHING else: session state untouched for bind_loaded_course.
        self.assertEqual(session.course_dir, Path("old") / "course")
        self.assertEqual(opened, [])


class B2GitChangeReloadTest(unittest.TestCase):
    """pull/切分支后：克隆目录=当前课程时必须触发重载。"""

    def setUp(self):
        _qt_app()

    def _make_dlg(self, course_dir):
        emitted: list[str] = []
        host = QWidget()
        host.course_dir = course_dir

        class Dlg:
            def __init__(self):
                self._clone_dir = course_dir
                self.open_requested = MagicMock()
                self.open_requested.emit = lambda p: emitted.append(p)

            def parent(self):
                return host

        return Dlg(), emitted

    def test_reload_emitted_when_clone_is_open_course(self):
        from src.dialogs.git_library.sync import reload_open_course_after_git_change

        dlg, emitted = self._make_dlg(Path("some") / "course")
        reload_open_course_after_git_change(dlg)
        # str(Path) keeps the assertion portable across platforms.
        self.assertEqual(emitted, [str(dlg._clone_dir)])

    def test_no_reload_when_clone_is_other_repo(self):
        from src.dialogs.git_library.sync import reload_open_course_after_git_change

        dlg, emitted = self._make_dlg(Path("some") / "course")
        dlg._clone_dir = Path("elsewhere") / "clone"
        reload_open_course_after_git_change(dlg)
        self.assertEqual(emitted, [])

    def test_no_reload_without_parent(self):
        from src.dialogs.git_library.sync import reload_open_course_after_git_change

        dlg, emitted = self._make_dlg(Path("some") / "course")
        dlg.parent = lambda: None
        reload_open_course_after_git_change(dlg)
        self.assertEqual(emitted, [])


class B3PublishMarksCleanTest(unittest.TestCase):
    """发布成功后标题栏：undo 栈必须 setClean + _mark_saved。"""

    def setUp(self):
        _qt_app()
        self._dlg = None

    def tearDown(self):
        if self._dlg is not None:
            # accept() inside _on_publish_result may have torn the C++
            # object down already.
            with contextlib.suppress(RuntimeError):
                self._dlg.deleteLater()

    def test_publish_success_marks_clean(self):
        from src.backend.course_io import SaveResult
        from src.widgets.publish_dialog import PublishDialog

        host = QWidget()
        host.undo_stack = MagicMock()
        marked = []
        host._mark_saved = lambda: marked.append(True)

        adapter = MagicMock()
        adapter.release_report.return_value = {
            "changes": {},
            "version_bump": {},
            "audio_manifest": [],
            "diff": {},
            "validation": {"ok": True, "errors": [], "warnings": []},
        }
        dlg = PublishDialog(adapter, host, teacher_friendly=True, load_async=False)
        self._dlg = dlg
        with patch("src.widgets.publish_dialog.QMessageBox.information"):
            dlg._on_publish_result(SaveResult(ok=True, message="saved"))
        host.undo_stack.setClean.assert_called_once()
        self.assertEqual(marked, [True])


class B4BulkAppendNewRewritesNestedIdsTest(unittest.TestCase):
    """批量 append_as_new 后保存通过校验：嵌套 id 必须深重写。"""

    def setUp(self):
        _qt_app()
        from PySide6.QtGui import QUndoStack

        from src.application.section_import_service import SectionImportService
        from tests._course_samples import sample_section_from_chapter

        self.adapter = CourseAdapter()
        self.undo_stack = QUndoStack()
        self.service = SectionImportService(self.adapter, self.undo_stack)
        # Existing section whose nested ids collide with the incoming copy.
        self.existing = sample_section_from_chapter("sec-a")
        self.adapter.sections.append(self.existing)
        self.adapter.index = {"sections": [{"id": "sec-a"}]}

    def _nested_ids(self, section: dict) -> set[str]:
        ids: set[str] = set()
        for unit in section.get("units") or []:
            ids.add(str(unit.get("id") or ""))
            for lesson in unit.get("lessons") or []:
                ids.add(str(lesson.get("id") or ""))
        return {i for i in ids if i}

    def test_bulk_append_rewrites_nested_ids(self):
        from tests._course_samples import sample_section_from_chapter

        incoming = sample_section_from_chapter("sec-a")
        _results, counts = self.service.import_bulk(
            [incoming], strategy="append_as_new"
        )
        self.assertEqual(counts["imported"], 1)
        new_section = self.adapter.sections[-1]
        self.assertNotEqual(new_section["id"], "sec-a")
        # Nested unit/lesson ids must no longer collide with the existing
        # section — the shallow rename used to keep them identical.
        self.assertFalse(
            self._nested_ids(new_section) & self._nested_ids(self.existing),
            "nested ids still collide after bulk append_as_new",
        )
        # And the imported section must validate cleanly as a *new* section:
        # pop it (validator counts ids against the adapter's existing set,
        # both sections and index), validate, then restore.
        self.adapter.sections.pop()
        self.adapter.index["sections"] = [
            e
            for e in self.adapter.index.get("sections", [])
            if e.get("id") != new_section["id"]
        ]
        if hasattr(self.adapter, "invalidate_node_index"):
            self.adapter.invalidate_node_index()
        problems = self.adapter.validate_section_json(
            new_section, check_existing_ids=True
        )
        self.adapter.sections.append(new_section)
        self.adapter.index.setdefault("sections", []).append({"id": new_section["id"]})
        if hasattr(self.adapter, "invalidate_node_index"):
            self.adapter.invalidate_node_index()
        errors = [p for p in problems if p.get("level") == "error"]
        self.assertEqual(errors, [])


if __name__ == "__main__":
    unittest.main()
