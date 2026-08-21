"""E1.5 / S-09: non-modal PreviewHost."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from tests._qtapp import qt_app  # noqa: E402


class PreviewHostTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        qt_app()

    def test_offer_apply_runs_callback_and_clears(self) -> None:
        from src.widgets.preview_host import PreviewHost

        host = PreviewHost()
        applied: list[str] = []

        def _apply() -> None:
            applied.append("ok")

        host.offer(
            title="预览",
            summary="before → after",
            apply_fn=_apply,
            payload={"x": 1},
        )
        self.assertTrue(host.isVisible())
        self.assertTrue(host.has_pending())
        host._on_apply()
        self.assertEqual(applied, ["ok"])
        self.assertFalse(host.isVisible())
        self.assertFalse(host.has_pending())

    def test_discard_runs_callback(self) -> None:
        from src.widgets.preview_host import PreviewHost

        host = PreviewHost()
        discarded = []

        host.offer(
            title="t",
            summary="s",
            apply_fn=lambda: None,
            discard_fn=lambda: discarded.append(1),
        )
        host._on_discard()
        self.assertEqual(discarded, [1])
        self.assertFalse(host.isVisible())

    def test_busy_disables_apply(self) -> None:
        from src.widgets.preview_host import PreviewHost

        host = PreviewHost()
        host.set_busy("生成中")
        self.assertTrue(host.is_busy())
        self.assertTrue(host.isVisible())
        self.assertFalse(host._apply_btn.isEnabled())
        # Apply while busy is a no-op
        host._on_apply()
        self.assertTrue(host.isVisible())
        host.clear()
        self.assertFalse(host.isVisible())


class PreviewHostDetailsTest(unittest.TestCase):
    """A2: optional per-field diff (details) in PreviewHost."""

    @classmethod
    def setUpClass(cls) -> None:
        qt_app()

    def test_offer_with_details_populates_and_toggle(self) -> None:
        from src.widgets.preview_host import PreviewHost

        host = PreviewHost()
        host.offer(
            title="AI 改题预览",
            summary="题目 i1: old → new",
            apply_fn=lambda: None,
            details=["prompt: old → new"],
        )
        self.assertTrue(host._details_btn.isVisible())
        # ≤4 lines auto-expand
        self.assertTrue(host._details.isVisible())
        self.assertIn("prompt: old → new", host._details.text())
        # Toggle collapses then re-expands
        host._toggle_details()
        self.assertFalse(host._details.isVisible())
        host._toggle_details()
        self.assertTrue(host._details.isVisible())

    def test_offer_without_details_hides_toggle_backward_compat(self) -> None:
        from src.widgets.preview_host import PreviewHost

        host = PreviewHost()
        host.offer(title="t", summary="s", apply_fn=lambda: None)
        self.assertFalse(host._details_btn.isVisible())
        self.assertFalse(host._details.isVisible())
        self.assertEqual(host._details.text(), "")

    def test_apply_clears_details(self) -> None:
        from src.widgets.preview_host import PreviewHost

        host = PreviewHost()
        applied = []
        host.offer(
            title="t",
            summary="s",
            apply_fn=lambda: applied.append(1),
            details=["a: 1 → 2"],
        )
        host._on_apply()
        self.assertEqual(applied, [1])
        self.assertFalse(host._details_btn.isVisible())
        self.assertEqual(host._details.text(), "")

    def test_discard_clears_details(self) -> None:
        from src.widgets.preview_host import PreviewHost

        host = PreviewHost()
        discarded = []
        host.offer(
            title="t",
            summary="s",
            apply_fn=lambda: None,
            discard_fn=lambda: discarded.append(1),
            details=["a: 1 → 2", "b: 3 → 4", "c: 5 → 6", "d: 7 → 8", "e: 9 → 10"],
        )
        # >4 lines -> collapsed by default
        self.assertFalse(host._details.isVisible())
        self.assertTrue(host._details_btn.isVisible())
        host._on_discard()
        self.assertEqual(discarded, [1])
        self.assertFalse(host._details_btn.isVisible())
        self.assertEqual(host._details.text(), "")

    def test_busy_then_offer_details_no_leak(self) -> None:
        from src.widgets.preview_host import PreviewHost

        host = PreviewHost()
        host.set_busy("生成中")
        self.assertFalse(host._details_btn.isVisible())  # busy resets details
        host.offer(title="t", summary="s", apply_fn=lambda: None, details=["x: 1 → 2"])
        self.assertFalse(host.is_busy())
        self.assertTrue(host._details_btn.isVisible())
        self.assertIn("x: 1 → 2", host._details.text())

    def test_unapplied_details_do_not_mutate_model(self) -> None:
        """O-11-style: offering a diff never mutates the underlying model dict."""
        from src.widgets.preview_host import PreviewHost

        item = {"id": "i1", "prompt": "old"}
        host = PreviewHost()

        def _apply() -> None:
            item["prompt"] = "new"

        host.offer(
            title="t",
            summary="s",
            apply_fn=_apply,
            details=["prompt: old → new"],
        )
        # Offered but not applied: model untouched.
        self.assertEqual(item["prompt"], "old")
        host._on_discard()
        self.assertEqual(item["prompt"], "old")


class ItemChipHelperTest(unittest.TestCase):
    def test_find_main_attr_walks_parents(self) -> None:
        from PySide6.QtWidgets import QWidget
        from src.teacher.item_ai_chip import find_main_attr

        qt_app()
        root = QWidget()
        root.preview_host = object()  # type: ignore[attr-defined]
        child = QWidget(root)
        grand = QWidget(child)
        self.assertIs(find_main_attr(grand, "preview_host"), root.preview_host)
        self.assertIsNone(find_main_attr(grand, "no_such"))


if __name__ == "__main__":
    unittest.main()
