#!/usr/bin/env python3
"""Drive Official Review Show Answer + rating on Device A. Does not bury."""

from __future__ import annotations

import argparse
import re
import subprocess
import time


def sh(serial: str, *args: str, check: bool = True) -> str:
    proc = subprocess.run(
        ["adb", "-s", serial, *args],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    if check and proc.returncode != 0:
        raise RuntimeError(f"adb {' '.join(args)} -> {proc.returncode}")
    return proc.stdout or ""


def dump(serial: str) -> str:
    last_error: Exception | None = None
    for attempt in range(5):
        try:
            sh(serial, "shell", "uiautomator", "dump", "/sdcard/uidump.xml")
            sh(serial, "pull", "/sdcard/uidump.xml", "/tmp/uidump-loop.xml")
            return open("/tmp/uidump-loop.xml", encoding="utf-8", errors="ignore").read()
        except Exception as error:
            last_error = error
            time.sleep(0.4 * (attempt + 1))
    raise RuntimeError(f"uiautomator dump failed: {last_error}")


def find(xml: str, *needles: str) -> list[tuple[str, int, int]]:
    hits: list[tuple[str, int, int]] = []
    for match in re.finditer(r"<node[^>]*>", xml):
        node = match.group(0)
        text_m = re.search(r'text="([^"]*)"', node)
        desc_m = re.search(r'content-desc="([^"]*)"', node)
        bounds = re.search(
            r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',
            node,
        )
        if bounds is None:
            continue
        label = (text_m.group(1) if text_m else "") or (
            desc_m.group(1) if desc_m else ""
        )
        if any(needle in label for needle in needles):
            x1, y1, x2, y2 = map(int, bounds.groups())
            hits.append((label, (x1 + x2) // 2, (y1 + y2) // 2))
    return hits


def wait_any(
    serial: str, needles: list[str], timeout: float
) -> tuple[list[tuple[str, int, int]], str]:
    deadline = time.time() + timeout
    last = ""
    while time.time() < deadline:
        last = dump(serial)
        hits = find(last, *needles)
        if hits:
            return hits, last
        time.sleep(0.3)
    return [], last


def tap(serial: str, x: int, y: int) -> None:
    sh(serial, "shell", "input", "tap", str(x), str(y))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--serial", default="3B15AG00FPB00000")
    parser.add_argument("--count", type=int, default=20)
    parser.add_argument(
        "--ratings",
        default="good",
        help="comma list cycling again,hard,good,easy",
    )
    args = parser.parse_args()
    cycle = [item.strip().lower() for item in args.ratings.split(",") if item.strip()]
    if not cycle:
        cycle = ["good"]
    needles = {
        "again": ["Again"],
        "hard": ["Hard"],
        "good": ["Good"],
        "easy": ["Easy"],
    }
    counts = {name: 0 for name in ("again", "hard", "good", "easy")}
    timeouts = 0
    superseded = 0
    unrenderable = 0
    rated = 0
    queue_exhausted = False

    for index in range(1, args.count + 1):
        xml = dump(args.serial)
        if find(xml, "Congrats"):
            print(f"stop: congrats at {index}")
            queue_exhausted = True
            break
        if "RENDER_TIMEOUT" in xml:
            timeouts += 1
            retries = find(xml, "重试")
            print(f"card {index}: RENDER_TIMEOUT")
            if retries:
                tap(args.serial, retries[0][1], retries[0][2])
                time.sleep(0.8)
                continue
        if "RENDER_SUPERSEDED" in xml:
            superseded += 1
            retries = find(xml, "重试")
            print(f"card {index}: RENDER_SUPERSEDED")
            if retries:
                tap(args.serial, retries[0][1], retries[0][2])
                time.sleep(0.8)
                continue
        if "UNRENDERABLE" in xml:
            unrenderable += 1
            print(f"card {index}: UNRENDERABLE (no auto-bury)")
            break

        shows = find(xml, "Show Answer")
        if not shows:
            shows, xml = wait_any(args.serial, ["Show Answer"], 14)
        ratings_up = find(xml, "Good", "Again", "Hard", "Easy")
        if not shows and not ratings_up:
            print(f"stop: no Show Answer / ratings at {index}")
            break
        if shows and not find(xml, "Good"):
            tap(args.serial, shows[0][1], shows[0][2])
            goods, xml = wait_any(args.serial, ["Good"], 14)
            if not goods:
                if "RENDER_TIMEOUT" in xml:
                    timeouts += 1
                    print(f"card {index}: timeout after flip")
                    continue
                print(f"stop: no Good after flip at {index}")
                break

        rating = cycle[(rated) % len(cycle)]
        buttons = find(xml, *needles[rating])
        if not buttons:
            buttons, xml = wait_any(args.serial, needles[rating], 8)
        if not buttons:
            print(f"stop: no {rating} button at {index}")
            break
        tap(args.serial, buttons[0][1], buttons[0][2])
        rated += 1
        counts[rating] += 1
        print(f"rated {rated}/{args.count} {rating}")
        time.sleep(0.55)

    print(
        "DONE "
        f"rated={rated} again={counts['again']} hard={counts['hard']} "
        f"good={counts['good']} easy={counts['easy']} "
        f"timeout={timeouts} superseded={superseded} unrenderable={unrenderable}"
        f"{' queue_exhausted=1' if queue_exhausted else ''}"
    )
    if rated == args.count:
        return 0
    if queue_exhausted and timeouts == 0:
        return 0
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
