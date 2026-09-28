"""Tests for path redaction before an error report leaves the machine."""
from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.dialogs.ai_error_analyzer import _redact_paths


class RedactPathsTest(unittest.TestCase):
    def test_windows_user_profile_is_stripped(self) -> None:
        out = _redact_paths(r"failed to open C:\Users\alice\courses\turkish\a1\lessons.json")
        self.assertNotIn("alice", out)
        self.assertNotIn("Users", out)
        self.assertIn("lessons.json", out)

    def test_posix_home_is_stripped(self) -> None:
        out = _redact_paths("cannot read /home/bob/projects/turna/course.yaml")
        self.assertNotIn("bob", out)
        self.assertIn("course.yaml", out)

    def test_non_home_absolute_path_collapses_to_tail(self) -> None:
        out = _redact_paths(r"missing D:\projects\secret-folder\data.bin")
        self.assertNotIn("secret-folder", out)
        self.assertIn("data.bin", out)

    def test_traceback_keeps_useful_frame_names(self) -> None:
        tb = (
            'Traceback (most recent call last):\n'
            '  File "D:\\program\\Turna\\Turna\\tool\\gui\\src\\widgets\\course_tree.py", line 453, in paint\n'
            '    painter.drawRect(rect)\n'
            'AttributeError: boom'
        )
        out = _redact_paths(tb)
        self.assertIn("course_tree.py", out)
        self.assertIn("AttributeError: boom", out)
        self.assertNotIn("D:\\program\\Turna", out)

    def test_bare_url_is_not_mangled(self) -> None:
        url = "POST https://api.example.com/v1/chat/completions failed"
        self.assertEqual(_redact_paths(url), url)

    def test_text_without_paths_is_unchanged(self) -> None:
        s = "Application failure: türkiye  dersi  生成失败"
        self.assertEqual(_redact_paths(s), s)

    def test_empty_is_safe(self) -> None:
        self.assertEqual(_redact_paths(""), "")


class PromptIsRedactedTest(unittest.TestCase):
    """The redaction must sit where the prompt is BUILT, not only exist.

    A helper nothing calls is the state this repo was in: the test existed,
    the function existed only in a working tree, and the prompt shipped raw
    absolute paths to the endpoint.
    """

    @classmethod
    def setUpClass(cls) -> None:
        from tests._qtapp import _App

        _App.get()

    def _prompt(self, traceback_text: str, context: dict | None = None) -> str:
        from unittest.mock import MagicMock, patch

        from src.dialogs.ai_error_analyzer import AiErrorAnalyzerDialog

        dlg = AiErrorAnalyzerDialog(
            traceback_text, context=context or {}, parent=None
        )
        dlg.deleteLater()
        with patch(
            "src.dialogs.ai_error_analyzer.telemetry.recent_lines",
            return_value=[
                '{"event": "repo.open.failed", "path": "/home/bob/courses/x"}'
            ],
        ):
            return dlg._build_prompt()

    def test_traceback_paths_are_redacted_in_the_prompt(self) -> None:
        prompt = self._prompt(
            'Traceback (most recent call last):\n'
            '  File "C:/Users/alice/Turna/tool/gui/src/widgets/course_tree.py",'
            " line 453, in paint\nAttributeError: boom\n",
            {"course": "C:/Users/alice/courses/turkish"},
        )
        self.assertNotIn("alice", prompt)
        self.assertNotIn("Users", prompt)
        # The parts the model actually needs survive.
        self.assertIn("course_tree.py", prompt)
        self.assertIn("AttributeError: boom", prompt)

    def test_telemetry_lines_in_the_prompt_are_redacted(self) -> None:
        prompt = self._prompt("boom", {"course": "/home/bob/x"})
        self.assertNotIn("bob", prompt)
        self.assertIn("repo.open.failed", prompt)


class ErrorAnalysisMessageTest(unittest.TestCase):
    """#12/N1: error-analysis entry points must hand the model the real error.

    Both call sites run *outside* any except block, so the old
    ``traceback.format_exc()`` produced the useless "NoneType: None".
    """

    def _patched_analyzer(self):
        ctx = patch(
            "src.dialogs.ai_error_analyzer.AiErrorAnalyzerDialog.analyze_exception",
            return_value=MagicMock(),
        )
        offer = patch(
            "src.dialogs.ai_error_analyzer.offer_ai_analysis",
            return_value=True,
        )
        return ctx, offer

    def test_show_load_error_passes_message_not_empty_traceback(self) -> None:
        from src.application import repo_session_host

        host = MagicMock()
        analyzer_ctx, offer_ctx = self._patched_analyzer()
        with offer_ctx, analyzer_ctx as analyze:
            repo_session_host.show_load_error(host, "course.yaml 缺失")
            analyze.assert_called_once()
            # analyze_exception(parent, exc, ...) — the "exception" argument
            # must be the load error, never "NoneType: None".
            self.assertEqual(analyze.call_args.args[1], "course.yaml 缺失")

    def test_worker_hub_error_analysis_passes_message(self) -> None:
        from src.dialogs.ai.generator_worker_hub import GeneratorWorkerHub

        analyzer_ctx, offer_ctx = self._patched_analyzer()
        with offer_ctx, analyzer_ctx as analyze:
            GeneratorWorkerHub.offer_error_analysis(
                MagicMock(), "HTTP 429 too many requests", context={"action": "ai.generate"}
            )
            analyze.assert_called_once()
            sent = analyze.call_args.args[1]
            self.assertEqual(sent, "HTTP 429 too many requests")


if __name__ == "__main__":
    unittest.main()
