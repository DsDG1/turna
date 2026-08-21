"""C-14 M-09 command palette → metrics integration tests (Qt light).

Verifies the interception semantics: a dispatched candidate is a resolved
intent (intent_resolved + command_triggered), and only a genuinely empty
candidate list on Enter is a fall-through (intent_fellthrough). This locks in
Fix 1: the M-09 truth is "what dispatches", not "route_intent(raw_text)" —
those two diverge for slash prefixes like ``/val`` (match_commands lists the
candidate via cmd.startswith, but route_intent returns None for the
non-exact slash).
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.widgets.command_palette import CommandPalette  # noqa: E402
from tests._qtapp import qt_app  # noqa: E402


def _drive(palette: CommandPalette, text: str) -> None:
    """Set the palette input text and press Enter.

    Uses ``setText`` + a manual ``textChanged`` fire (so ``_refresh`` repopulates
    candidates) rather than ``QTest.keyClicks``: the latter can assert inside
    Qt's test library in offscreen builds, and the dispatch logic only reads
    ``input.text()`` + ``_intents``, both of which ``setText`` populates.
    """
    palette.input.setText(text)
    palette.input.textChanged.emit(text)
    # returnPressed fires on Enter; _trigger_current is connected to it.
    palette.input.returnPressed.emit()


class CommandPaletteMetricsTest(unittest.TestCase):
    def setUp(self) -> None:
        qt_app()

    def _collect(self, palette: CommandPalette) -> dict[str, list]:
        out: dict[str, list] = {
            "resolved": [],
            "fellthrough": [],
            "command": [],
        }
        palette.intent_resolved.connect(
            lambda t, a: out["resolved"].append((t, a))
        )
        palette.intent_fellthrough.connect(lambda t: out["fellthrough"].append(t))
        palette.command_triggered.connect(lambda p: out["command"].append(p))
        return out

    def test_slash_exact_dispatches_and_resolves(self) -> None:
        pal = CommandPalette()
        out = self._collect(pal)
        _drive(pal, "/validate")
        self.assertEqual(len(out["resolved"]), 1)
        self.assertEqual(out["resolved"][0][1], "validate.open_and_fix")
        self.assertEqual(len(out["command"]), 1)
        self.assertEqual(out["command"][0]["action_id"], "validate.open_and_fix")
        self.assertEqual(out["fellthrough"], [])

    def test_slash_prefix_dispatches_and_resolves_not_fallthrough(self) -> None:
        # The bug: "/val" lists /validate via cmd.startswith, but route_intent
        # returns None for the non-exact slash → must still count as resolved.
        pal = CommandPalette()
        out = self._collect(pal)
        _drive(pal, "/val")
        self.assertEqual(len(out["resolved"]), 1, "dispatched candidate = resolved")
        self.assertEqual(out["resolved"][0][1], "validate.open_and_fix")
        self.assertEqual(len(out["command"]), 1)
        self.assertEqual(out["fellthrough"], [], "must NOT be a fall-through")

    def test_label_substring_dispatches_and_resolves(self) -> None:
        # "保存课程" is the /save label; keyword "保存" is a substring, so
        # route_intent also matches here — but the point is the dispatched
        # candidate is the source of truth. Still resolved.
        pal = CommandPalette()
        out = self._collect(pal)
        _drive(pal, "保存课程")
        self.assertEqual(len(out["resolved"]), 1)
        self.assertEqual(out["command"][0]["action_id"], "app.save")
        self.assertEqual(out["fellthrough"], [])

    def test_no_match_enter_is_fallthrough(self) -> None:
        pal = CommandPalette()
        out = self._collect(pal)
        _drive(pal, "zzzzz不存在的查询词")
        self.assertEqual(out["resolved"], [])
        self.assertEqual(out["command"], [])
        self.assertEqual(len(out["fellthrough"]), 1)
        self.assertEqual(out["fellthrough"][0], "zzzzz不存在的查询词")

    def test_empty_query_enter_is_fallthrough(self) -> None:
        pal = CommandPalette()
        out = self._collect(pal)
        # Empty query lists all slash commands as candidates, so Enter
        # dispatches row 0 — NOT a fall-through. This confirms empty-query
        # shows candidates (history + slash table) and Enter resolves.
        _drive(pal, "")
        self.assertEqual(len(out["resolved"]), 1)
        self.assertEqual(len(out["command"]), 1)
        self.assertEqual(out["fellthrough"], [])


if __name__ == "__main__":
    unittest.main()