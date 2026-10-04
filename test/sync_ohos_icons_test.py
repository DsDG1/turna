#!/usr/bin/env python3
"""Tests for tool/sync_ohos_icons.py.

The bug this guards: `flutter_launcher_icons` has no OHOS target, so the two
HarmonyOS media slots kept the DevEco Studio scaffold placeholder and the
Turna peacock never shipped on OHOS. Nothing in the build failed -- the app
just wore someone else's logo. These tests are the ratchet that keeps a
re-scaffold, or a brand-art change that nobody regenerated from, out.
"""

from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path

from PIL import Image

# tool/ is not a package; import the module by path.
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tool"))

import sync_ohos_icons  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parent.parent


def _teal(color: tuple[int, int, int] = (31, 114, 126)) -> tuple[int, int, int, int]:
    return (*color, 255)


class CommittedIconTests(unittest.TestCase):
    """The committed media must be exactly what the generator produces."""

    generated: Image.Image

    @classmethod
    def setUpClass(cls) -> None:
        if not sync_ohos_icons.SOURCE.exists():
            raise unittest.SkipTest("brand source render is missing")
        if not sync_ohos_icons.TARGETS[0].exists():
            raise unittest.SkipTest("ohos/ is absent; ADR 0041 retired it")
        cls.generated = sync_ohos_icons.build_icon()

    def test_targets_exist(self) -> None:
        for target in sync_ohos_icons.TARGETS:
            with self.subTest(target=target.name):
                self.assertTrue(target.exists(), f"missing {target}")

    def test_targets_match_generator_output(self) -> None:
        """Pixel-for-pixel, so an un-regenerated brand change fails here."""
        for target in sync_ohos_icons.TARGETS:
            with self.subTest(target=target.name):
                with Image.open(target) as committed:
                    pixels = committed.convert("RGB").tobytes()
                self.assertEqual(
                    pixels,
                    self.generated.tobytes(),
                    f"{target} is stale; run `python tool/sync_ohos_icons.py`",
                )

    def test_targets_are_in_sync(self) -> None:
        """A partial regeneration must not leave the two slots disagreeing."""
        first, *rest = sync_ohos_icons.TARGETS
        for target in rest:
            with self.subTest(target=target.name):
                self.assertEqual(
                    first.read_bytes(),
                    target.read_bytes(),
                    f"{target} drifted from {first.name}",
                )

    def test_icon_meets_harmonyos_spec(self) -> None:
        self.assertEqual(self.generated.size, (216, 216))
        with Image.open(sync_ohos_icons.TARGETS[0]) as committed:
            # HarmonyOS rejects an alpha channel in a media icon.
            self.assertNotIn("A", committed.getbands())

    def test_corners_are_full_bleed(self) -> None:
        """The system masks this PNG, so a pale corner would ship as one."""
        pixels = self.generated.load()
        width, height = self.generated.size
        probe = max(2, min(width, height) // 24)
        for x in range(probe + 1):
            for y in range(probe + 1):
                for point in (
                    (x, y),
                    (width - 1 - x, y),
                    (x, height - 1 - y),
                    (width - 1 - x, height - 1 - y),
                ):
                    with self.subTest(point=point):
                        self.assertFalse(
                            sync_ohos_icons._is_margin((*pixels[point], 255)),
                            f"corner {point} is still near-white",
                        )


class MarginDetectionTests(unittest.TestCase):
    """The flood fill must find the outer mask without eating the artwork."""

    SIZE = 128
    MARGIN = 8

    def _sample(self) -> Image.Image:
        """Teal field inside a white margin, with a white face in the middle.

        Sized so the teal band clears BLEND_GUARD, which is what lets the
        inpaint reach a solid seed.
        """
        size, margin = self.SIZE, self.MARGIN
        image = Image.new("RGBA", (size, size), _teal())
        pixels = image.load()
        for y in range(size):
            for x in range(size):
                in_margin = x < margin or y < margin or x >= size - margin or y >= size - margin
                in_face = (x - size // 2) ** 2 + (y - size // 2) ** 2 <= 144
                if in_margin or in_face:
                    pixels[x, y] = (255, 255, 255, 255)
        return image

    def test_border_margin_is_detected(self) -> None:
        margin = sync_ohos_icons.find_margin(self._sample())
        self.assertIn((0, 0), margin)
        self.assertIn((self.SIZE - 1, self.SIZE - 1), margin)
        self.assertIn((0, self.SIZE // 2), margin)
        self.assertIn((self.SIZE // 2, 0), margin)
        self.assertNotIn((self.SIZE // 2, self.SIZE // 2), margin)

    def test_interior_white_survives_the_inpaint(self) -> None:
        """The peacock's white face is near-white too; it must stay put."""
        image = self._sample()
        margin = sync_ohos_icons.find_margin(image)
        filled = sync_ohos_icons.inpaint(image, margin).convert("RGB")
        self.assertEqual(filled.getpixel((self.SIZE // 2, self.SIZE // 2)), (255, 255, 255))
        # The corner now carries the teal that surrounded the mask.
        self.assertEqual(filled.getpixel((0, 0)), (31, 114, 126))

    def test_absent_margin_is_reported_as_empty(self) -> None:
        """A full-bleed source means the script no longer matches its input."""
        flat = Image.new("RGBA", (32, 32), _teal())
        self.assertEqual(sync_ohos_icons.find_margin(flat), set())


class FullBleedGuardTests(unittest.TestCase):
    def test_pale_corner_is_rejected(self) -> None:
        """The self-check is what catches a washed-out fill, so it must fire."""
        pale = Image.new("RGB", (216, 216), (255, 255, 255))
        pale.putpixel((108, 108), (31, 114, 126))
        with self.assertRaises(SystemExit):
            sync_ohos_icons.assert_full_bleed(pale)

    def test_teal_corner_is_accepted(self) -> None:
        icon = Image.new("RGB", (216, 216), (31, 114, 126))
        sync_ohos_icons.assert_full_bleed(icon)


if __name__ == "__main__":
    unittest.main()
