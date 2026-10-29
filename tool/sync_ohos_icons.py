#!/usr/bin/env python3
"""Regenerate the HarmonyOS app icon from the canonical Turna brand source.

Why this exists: `flutter_launcher_icons` covers android / ios / web / windows /
macos from `pubspec.yaml`, but it has no OHOS target. The two HarmonyOS media
slots therefore kept the DevEco Studio scaffold placeholder (a 114x114 grey
placeholder) and the Turna peacock never shipped on OHOS.

Two constraints shape the output:

* HarmonyOS masks the icon resource itself (circle / squircle), so the PNG must
  be **full bleed**. `assets/images/app_logo.png` is a 1024x1024 store render
  with its own rounded-corner mask baked in over a white margin -- pasted as-is
  the white corners survive the system mask as white corners. The margin is
  inpainted here by propagating the interior teal outward, which continues the
  existing diagonal gradient instead of inventing a flat fill. The margin is
  located by flood fill from the border rather than by probing a corner radius:
  the source render's arc is anti-aliased, so a radius probe lands inside the
  arc and leaves a white halo.
* HarmonyOS expects 216x216 for `AppScope` / ability media. Anything else is
  either rejected or scaled into a soft blur by the launcher.

Run: `python tool/sync_ohos_icons.py`
"""

from __future__ import annotations

import sys
from collections import deque
from pathlib import Path

from PIL import Image

REPO_ROOT = Path(__file__).resolve().parent.parent

# Single source of truth: the same file `pubspec.yaml` feeds to
# flutter_launcher_icons for every other platform.
SOURCE = REPO_ROOT / "assets" / "images" / "app_logo.png"

# `app.json5` -> `$media:app_icon`, and `module.json5` -> ability `icon` plus
# `startWindowIcon`. Both must carry the brand mark or the launcher and the
# splash fall back to the DevEco placeholder.
TARGETS = (
    REPO_ROOT / "ohos" / "AppScope" / "resources" / "base" / "media" / "app_icon.png",
    REPO_ROOT / "ohos" / "entry" / "src" / "main" / "resources" / "base" / "media" / "icon.png",
)

# HarmonyOS app icon spec.
ICON_SIZE = 216

# This tolerance is the value that walks the source render's anti-aliased
# corner edge. Too tight and the fill stops one pixel short of the arc,
# leaving a white halo.
MARGIN_TOLERANCE = 20

# Width of the white-to-teal ramp the browser/PIL resizer left along the arc.
# It sits just inside the margin, so a margin pixel's immediate non-margin
# neighbour is a blend, not the background: seeding the fill from it floods the
# corner with light cyan. Seeding is therefore delayed until this far in, where
# the background is solid.
BLEND_GUARD = 20

_STEPS = ((1, 0), (-1, 0), (0, 1), (0, -1))

Point = tuple[int, int]


def _is_margin(pixel: tuple[int, int, int, int]) -> bool:
    red, green, blue, alpha = pixel
    if alpha < 128:
        return True
    floor = 255 - MARGIN_TOLERANCE
    return red >= floor and green >= floor and blue >= floor


def find_margin(image: Image.Image) -> set[Point]:
    """Border-connected near-white region, i.e. the render's own outer mask.

    Flood fill rather than a bounding box so the peacock's white face -- also
    near-white, but interior -- is never touched.
    """
    width, height = image.size
    pixels = image.load()
    margin: set[Point] = set()
    queue: deque[Point] = deque()

    for x in range(width):
        for y in (0, height - 1):
            if (x, y) not in margin and _is_margin(pixels[x, y]):
                margin.add((x, y))
                queue.append((x, y))
    for y in range(height):
        for x in (0, width - 1):
            if (x, y) not in margin and _is_margin(pixels[x, y]):
                margin.add((x, y))
                queue.append((x, y))

    while queue:
        x, y = queue.popleft()
        for step_x, step_y in _STEPS:
            neighbor = (x + step_x, y + step_y)
            if not (0 <= neighbor[0] < width and 0 <= neighbor[1] < height):
                continue
            if neighbor in margin:
                continue
            if not _is_margin(pixels[neighbor[0], neighbor[1]]):
                continue
            margin.add(neighbor)
            queue.append(neighbor)

    return margin


def _dilate(seeds: set[Point], width: int, height: int, radius: int) -> set[Point]:
    """Grow `seeds` outward by `radius` in Chebyshev distance, clipped."""
    grown = set(seeds)
    for _ in range(radius):
        ring: set[Point] = set()
        for x, y in grown:
            for step_x in (-1, 0, 1):
                for step_y in (-1, 0, 1):
                    neighbor = (x + step_x, y + step_y)
                    if (
                        0 <= neighbor[0] < width
                        and 0 <= neighbor[1] < height
                        and neighbor not in grown
                    ):
                        ring.add(neighbor)
        grown |= ring
    return grown


def inpaint(image: Image.Image, margin: set[Point]) -> Image.Image:
    """Replace the render's own outer mask with the background it clipped.

    `margin` is the white surround; the white-to-teal ramp hugging the arc
    goes with it, so the fill region is the margin dilated by [BLEND_GUARD].
    Every pixel in that region takes the colour of its nearest already-filled
    pixel, so the fill follows the brand gradient instead of flattening it: the
    gradient spans the full 1024px, which keeps a pixel and its interior
    neighbour under one 8-bit level apart. Seeding only from pixels past the
    ramp is what stops the corners turning pale.
    """
    filled = image.convert("RGBA")
    width, height = filled.size
    pixels = filled.load()

    def in_bounds(point: Point) -> bool:
        return 0 <= point[0] < width and 0 <= point[1] < height

    region = _dilate(margin, width, height, BLEND_GUARD)

    done: set[Point] = set()
    frontier: deque[Point] = deque()

    # Sorted so the committed binary asset is reproducible byte for byte.
    for point in sorted(region, key=lambda p: p[0] + p[1]):
        for step_x, step_y in _STEPS:
            neighbor = (point[0] + step_x, point[1] + step_y)
            if not in_bounds(neighbor) or neighbor in region:
                continue
            red, green, blue, _ = pixels[neighbor[0], neighbor[1]]
            pixels[point[0], point[1]] = (red, green, blue, 255)
            done.add(point)
            frontier.append(point)
            break

    while frontier:
        point = frontier.popleft()
        red, green, blue, _ = pixels[point[0], point[1]]
        for step_x, step_y in _STEPS:
            neighbor = (point[0] + step_x, point[1] + step_y)
            if neighbor in done or neighbor not in region:
                continue
            pixels[neighbor[0], neighbor[1]] = (red, green, blue, 255)
            done.add(neighbor)
            frontier.append(neighbor)

    if len(done) != len(region):
        raise SystemExit(
            f"margin inpaint left {len(region) - len(done)} px unfilled; the "
            "mask is not border-connected, or BLEND_GUARD is too large for "
            "this source render"
        )

    return filled


def assert_full_bleed(icon: Image.Image) -> None:
    """Fail loudly if the corners are still pale.

    The whole point of the inpaint is that HarmonyOS masks this PNG itself, so
    a white corner survives as a white corner. A future brand render that
    widens the blend ramp past [BLEND_GUARD] would quietly reintroduce it --
    better to stop here than to commit a half-white icon.
    """
    width, height = icon.size
    pixels = icon.load()
    probe = max(2, min(width, height) // 24)
    pale: list[str] = []
    for x in range(probe + 1):
        for y in range(probe + 1):
            corners = (
                (x, y),
                (width - 1 - x, y),
                (x, height - 1 - y),
                (width - 1 - x, height - 1 - y),
            )
            for point in corners:
                if _is_margin((*pixels[point], 255)):
                    pale.append(f"{point[0]},{point[1]}")
    if pale:
        raise SystemExit(
            f"{len(pale)} corner px are still near-white (first: {pale[0]}); "
            f"BLEND_GUARD={BLEND_GUARD} no longer clears the source's arc ramp"
        )


def build_icon() -> Image.Image:
    with Image.open(SOURCE) as source:
        if source.width != source.height:
            raise SystemExit(
                f"{SOURCE.name} is {source.size}, expected a square brand render; "
                "the corner geometry below assumes one"
            )
        rgba = source.convert("RGBA")
        margin = find_margin(rgba)
        if not margin:
            raise SystemExit(
                f"{SOURCE.name} has no border-connected margin; the source is "
                "already full bleed and this script no longer matches it"
            )
        print(f"{SOURCE.name}: {len(margin)} margin px to inpaint")
        filled = inpaint(rgba, margin)

    # HarmonyOS rejects transparency in a media icon. The margin inpaint is
    # already opaque, but the source carries an alpha channel, so flatten it.
    icon = filled.convert("RGB").resize(
        (ICON_SIZE, ICON_SIZE), Image.Resampling.LANCZOS
    )
    assert_full_bleed(icon)
    return icon


def main() -> int:
    icon = build_icon()
    for target in TARGETS:
        if not target.parent.is_dir():
            raise SystemExit(f"missing resource directory: {target.parent}")
        icon.save(target, format="PNG", optimize=True)
        print(f"wrote {target.relative_to(REPO_ROOT)} ({ICON_SIZE}x{ICON_SIZE})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
