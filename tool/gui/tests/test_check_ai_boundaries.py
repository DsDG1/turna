"""Negative matrix for every rule in tool/check_ai_boundaries.py.

Each test builds a miniature ``src/`` tree containing exactly one violation
and asserts the corresponding scan/count function reports it — and only it.
This file exists because the matrix was missing: during the 2026-09-27
remediation ``scan_backend_qt_imports()`` was accidentally rewritten to search
with the backend→UI regex, so ``--fail-backend-qt`` (passed by every gate
entry point) reported 0 on any input while the ad-hoc probes only exercised
the backend→UI rule. A per-rule matrix is the regression guard for the guard.

The script is loaded via importlib (it is a tool script, not a package
module) and its module-level ``_GUI_ROOT`` / ``_SRC`` globals are repointed
at a temp tree per test; every scan function reads them at call time, so no
files ever need to be created inside the real source tree.
"""
from __future__ import annotations

import importlib.util
import tempfile
import textwrap
import unittest
from pathlib import Path

_SCRIPT = Path(__file__).resolve().parents[1] / "tool" / "check_ai_boundaries.py"
_SPEC = importlib.util.spec_from_file_location("_check_ai_boundaries_under_test", _SCRIPT)
check = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(check)


class BoundaryRuleMatrixTest(unittest.TestCase):
    """One probe per gate rule: the violation must be found, clean trees must not."""

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self._gui_root = Path(self._tmp.name) / "gui"
        self._src = self._gui_root / "src"
        self._src.mkdir(parents=True)
        self._saved = (check._GUI_ROOT, check._SRC)
        check._GUI_ROOT = self._gui_root
        check._SRC = self._src

    def tearDown(self) -> None:
        check._GUI_ROOT, check._SRC = self._saved
        self._tmp.cleanup()

    def _write(self, rel: str, text: str) -> None:
        p = self._src / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(textwrap.dedent(text), encoding="utf-8")

    # --- layering rules ----------------------------------------------------

    def test_rule_private_ai_import(self) -> None:
        self._write("backend/ai/__init__.py", "")
        self._write("backend/ai/client.py", "def _impl(): pass\n")
        self._write("widgets/w.py", "from src.backend.ai import _impl\n")
        hits = check.scan_private_imports()
        self.assertEqual(len(hits), 1)
        self.assertTrue(hits[0][0].endswith("widgets/w.py"))

    def test_rule_dialogs_app(self) -> None:
        self._write("dialogs/d.py", "from src.app import MainWindow\n")
        self.assertEqual(len(check.scan_dialogs_app_imports()), 1)

    def test_rule_backend_app(self) -> None:
        self._write("backend/b.py", "import src.app\n")
        self._write("application/a.py", "import src.app\n")
        self.assertEqual(len(check.scan_lower_layer_app_imports()), 2)

    def test_rule_backend_ui(self) -> None:
        self._write("backend/b.py", "from src.widgets.w import W\n")
        self.assertEqual(len(check.scan_backend_ui_imports()), 1)

    def test_rule_backend_qt_from_import(self) -> None:
        # Regression guard: this scanner once searched with the backend→UI
        # regex, making --fail-backend-qt a dead check on any input.
        self._write("backend/b.py", "from PySide6.QtWidgets import QWidget\n")
        self.assertEqual(len(check.scan_backend_qt_imports()), 1)

    def test_rule_backend_qt_bare_import(self) -> None:
        self._write("backend/b.py", "import PySide6.QtCore\n")
        self.assertEqual(len(check.scan_backend_qt_imports()), 1)

    def test_rule_backend_qt_ignores_ui_rule_hits(self) -> None:
        # backend→UI and backend→PySide6 are different rules: a UI-layer import
        # in backend/ must not satisfy (nor trigger) the Qt-free rule.
        self._write("backend/b.py", "from src.widgets.w import W\n")
        self.assertEqual(len(check.scan_backend_qt_imports()), 0)
        self.assertEqual(len(check.scan_backend_ui_imports()), 1)

    def test_rule_app_dialogs(self) -> None:
        self._write("app.py", "from src.dialogs.d import D\n")
        self._write("application/a.py", "from src.dialogs.d import D\n")
        self.assertEqual(len(check.scan_app_dialogs_imports()), 2)

    def test_rule_dialogs_pipeline(self) -> None:
        self._write("dialogs/d.py", "from src.backend.ai_pipeline import x\n")
        self.assertEqual(len(check.scan_dialogs_pipeline_imports()), 1)

    def test_rule_ui_backend_includes_lazy(self) -> None:
        self._write("dialogs/d.py", "from src.backend.course_query import q\n")
        self._write("widgets/w.py", "def f():\n    from src.backend.api import g\n")
        self._write("teacher/t.py", "import src.backend\n")
        self.assertEqual(len(check.scan_ui_backend_imports()), 3)

    def test_rule_course_cli_gateway_exempt(self) -> None:
        self._write("backend/api.py", "import course_cli\n")  # the gateway itself
        self._write("widgets/w.py", "from src.backend.api import course_cli\n")
        hits = check.scan_course_cli_bindings()
        self.assertEqual(len(hits), 1)
        self.assertTrue(hits[0][0].endswith("widgets/w.py"))

    def test_rule_host_drift(self) -> None:
        self._write(
            "application/experience_host.py",
            '''\
            from typing import Any, Protocol


            class ExperienceHost(Protocol):
                _known: Any
            ''',
        )
        self._write(
            "application/handler.py",
            '''\
            from src.application.experience_host import ExperienceHost


            def go(host: ExperienceHost) -> None:
                host._known()
                host._unknown_drift()
            ''',
        )
        hits = check.scan_undeclared_host_access()
        self.assertEqual(len(hits), 1)
        self.assertIn("_unknown_drift", hits[0][2])

    def test_rule_import_cycle(self) -> None:
        self._write("a.py", "import src.b\n")
        self._write("b.py", "import src.a\n")
        cycles = check.count_module_import_cycles()
        self.assertEqual(len(cycles), 1)
        self.assertEqual(cycles[0], ["a", "b"])

    # --- ratchets ----------------------------------------------------------

    def test_ratchet_except_pass_broad_only(self) -> None:
        self._write(
            "backend/b.py",
            '''\
            try:
                x = 1
            except Exception:
                pass
            try:
                x = 2
            except RuntimeError:
                pass  # narrow probe: deliberately not a swallowed failure
            ''',
        )
        self.assertEqual(check.count_silent_except_pass(), 1)

    def test_ratchet_except_continue(self) -> None:
        self._write(
            "backend/b.py",
            '''\
            for i in range(3):
                try:
                    x = i
                except Exception:
                    continue
            ''',
        )
        self.assertEqual(check.count_silent_except_continue(), 1)

    def test_ratchet_broad_except(self) -> None:
        self._write(
            "backend/b.py",
            '''\
            try:
                x = 1
            except Exception:
                x = 2
            ''',
        )
        self.assertEqual(check.count_broad_except(), 1)

    def test_ratchet_style_hex_palette_fallback_exempt(self) -> None:
        self._write("widgets/w.py", 'w.setStyleSheet("color: #ff0000;")\n')
        self._write("widgets/p.py", 'w.setStyleSheet(pal.get("token", "#ff0000"))\n')
        self.assertEqual(check.count_hardcoded_style_hex(), 1)

    # --- clean tree --------------------------------------------------------

    def test_clean_tree_all_zero(self) -> None:
        self._write(
            "backend/b.py",
            '''\
            import logging

            logger = logging.getLogger(__name__)

            try:
                x = 1
            except RuntimeError:
                # narrow probe: safe by construction
                logger.debug("probe failed", exc_info=True)
            ''',
        )
        self._write("widgets/w.py", "w.setStyleSheet(pal['token'])\n")
        self._write("dialogs/d.py", "from src.application.shell import run\n")
        self.assertEqual(check.scan_private_imports(), [])
        self.assertEqual(check.scan_dialogs_app_imports(), [])
        self.assertEqual(check.scan_lower_layer_app_imports(), [])
        self.assertEqual(check.scan_backend_ui_imports(), [])
        self.assertEqual(check.scan_backend_qt_imports(), [])
        self.assertEqual(check.scan_app_dialogs_imports(), [])
        self.assertEqual(check.scan_dialogs_pipeline_imports(), [])
        self.assertEqual(check.scan_ui_backend_imports(), [])
        self.assertEqual(check.scan_course_cli_bindings(), [])
        self.assertEqual(check.scan_undeclared_host_access(), [])
        self.assertEqual(check.count_module_import_cycles(), [])
        self.assertEqual(check.count_silent_except_pass(), 0)
        self.assertEqual(check.count_silent_except_continue(), 0)
        self.assertEqual(check.count_hardcoded_style_hex(), 0)


if __name__ == "__main__":
    unittest.main()
