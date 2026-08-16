#!/usr/bin/env python3
"""Convert generated Turna mascot JPG concepts to transparent PNGs."""

import os
from collections import deque
from pathlib import Path
from PIL import Image, ImageFilter

def make_transparent_from_border(img: Image.Image, tolerance: int = 20) -> Image.Image:
    """Flood fill outer white background to transparent while keeping inner whites intact."""
    img = img.convert("RGBA")
    width, height = img.size
    pixels = img.load()

    # Visited grid
    visited = [[False] * height for _ in range(width)]
    queue = deque()

    def is_white_enough(r, g, b):
        return r >= (255 - tolerance) and g >= (255 - tolerance) and b >= (255 - tolerance)

    # Seed with all boundary pixels
    for x in range(width):
        for y in (0, height - 1):
            r, g, b, a = pixels[x, y]
            if is_white_enough(r, g, b):
                queue.append((x, y))
                visited[x][y] = True

    for y in range(height):
        for x in (0, width - 1):
            if not visited[x][y]:
                r, g, b, a = pixels[x, y]
                if is_white_enough(r, g, b):
                    queue.append((x, y))
                    visited[x][y] = True

    # 4-direction BFS flood fill
    while queue:
        cx, cy = queue.popleft()
        pixels[cx, cy] = (255, 255, 255, 0)  # Transparent

        for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            nx, ny = cx + dx, cy + dy
            if 0 <= nx < width and 0 <= ny < height and not visited[nx][ny]:
                visited[nx][ny] = True
                r, g, b, a = pixels[nx, ny]
                if is_white_enough(r, g, b):
                    queue.append((nx, ny))

    # Anti-alias mask edge slightly to remove harsh white fringe
    alpha = img.split()[-1]
    # Simple threshold smoothing
    alpha = alpha.filter(ImageFilter.BoxBlur(0.5))
    img.putalpha(alpha)
    return img

def main():
    root = Path(__file__).resolve().parent.parent
    src_dir = root / "assets" / "images"
    turna_dir = src_dir / "turna"
    turna_dir.mkdir(exist_ok=True)

    mappings = [
        ("turna_waving.jpg", "turna_waving.png"),
        ("turna_reading.jpg", "turna_reading.png"),
        ("turna_listening.jpg", "turna_listening.png"),
        ("turna_thinking.jpg", "turna_thinking.png"),
        ("turna_celebrate.jpg", "turna_celebrate.png"),
        ("turna_encourage.jpg", "turna_encourage.png"),
        ("turna_mascot_flat.jpg", "turna_standing.png"),
    ]

    for src_name, dst_name in mappings:
        src_path = src_dir / src_name
        dst_path = turna_dir / dst_name
        if src_path.exists():
            print(f"Processing {src_name} -> turna/{dst_name}...")
            img = Image.open(src_path)
            transparent_img = make_transparent_from_border(img, tolerance=25)
            transparent_img.save(dst_path, "PNG")
            print(f"Saved {dst_path}")

    # Process app logo (keep full square / rounded square)
    logo_src = src_dir / "turna_app_logo.jpg"
    if logo_src.exists():
        print(f"Processing App Logo...")
        img = Image.open(logo_src).convert("RGBA")
        img.save(src_dir / "app_logo.png", "PNG")
        img.resize((1024, 1024), Image.Resampling.LANCZOS).save(src_dir / "app_logo_store_1024.png", "PNG")
        img.resize((216, 216), Image.Resampling.LANCZOS).save(src_dir / "app_logo_store_216.png", "PNG")
        img.save(turna_dir / "app_logo.png", "PNG")
        print("Updated app_logo.png, app_logo_store_1024.png, app_logo_store_216.png")

if __name__ == "__main__":
    main()
