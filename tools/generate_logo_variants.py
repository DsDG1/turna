"""Generate white-bg and black-bg variants of the app logo for all platforms.

Source: assets/images/app_logo.png (1024x1024 RGBA, transparent).
- Light variant: solid white (#FFFFFF) background, logo centered.
- Dark  variant: solid black (#000000) background, logo centered.
"""

from PIL import Image
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, 'assets', 'images', 'app_logo.png')

WHITE = (255, 255, 255, 255)
BLACK = (0, 0, 0, 255)


def make_icon(bg_rgba: tuple[int, int, int, int], size: int) -> Image.Image:
    """Render the source logo onto a solid-color square of `size` x `size`."""
    src = Image.open(SOURCE).convert('RGBA')
    # Scale the logo to fit within 80% of the icon canvas so it has a
    # consistent margin on every platform density.
    target = int(size * 0.78)
    src.thumbnail((target, target), Image.LANCZOS)
    canvas = Image.new('RGBA', (size, size), bg_rgba)
    x = (size - src.width) // 2
    y = (size - src.height) // 2
    canvas.alpha_composite(src, (x, y))
    return canvas


def write(path: str, bg: tuple[int, int, int, int], size: int) -> None:
    full = os.path.join(ROOT, path.replace('/', os.sep))
    os.makedirs(os.path.dirname(full), exist_ok=True)
    img = make_icon(bg, size)
    img.save(full, 'PNG')
    print(f'wrote {path}  {img.size}')


# ---- OpenHarmony (ohos) ----
# entry/src/main/resources/base/media/*  and  AppScope/resources/base/media/*
# Ohos uses 114x114 for entry media, 173x173 for AppScope (current 173x173 — keep).
write('ohos/entry/src/main/resources/base/media/launcher_icon.png', WHITE, 114)
write('ohos/entry/src/main/resources/base/media/icon.png',         WHITE, 114)
write('ohos/AppScope/resources/base/media/app_icon.png',            WHITE, 173)

# Dark variant: Ohos resource qualifier `dark` (matches system dark mode).
# The system picks the dark variant automatically when the device is in dark mode.
for path in [
    'ohos/entry/src/main/resources/dark/media/launcher_icon.png',
    'ohos/entry/src/main/resources/dark/media/icon.png',
]:
    write(path, BLACK, 114)
write('ohos/AppScope/resources/dark/media/app_icon.png', BLACK, 173)

# ---- Android (light = mipmap-*/launcher_icon.png, dark = *_night.png) ----
DENSITIES = {
    'mipmap-ldpi':    36,
    'mipmap-mdpi':    48,
    'mipmap-hdpi':    72,
    'mipmap-xhdpi':   96,
    'mipmap-xxhdpi':  144,
    'mipmap-xxxhdpi': 192,
}
for folder, size in DENSITIES.items():
    write(f'android/app/src/main/res/{folder}/launcher_icon.png',      WHITE, size)
    write(f'android/app/src/main/res/{folder}/launcher_icon_night.png', BLACK, size)

print('done')
