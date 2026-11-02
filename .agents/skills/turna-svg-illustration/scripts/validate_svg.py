#!/usr/bin/env python3
"""Static SVG validator for Turna illustrations (flutter_svg safe profile).

Adapted from syi0808/svg-skills (MIT License) and tailored for Flutter's
flutter_svg renderer constraints (no <style>, <filter>, <image>, or <script>).
Zero external dependencies (Python 3.10+ stdlib only).
"""

from __future__ import annotations

import argparse
import graphlib
import json
import math
import re
import sys
import xml.etree.ElementTree as ET
from collections import Counter
from pathlib import Path

SVG_NS = "http://www.w3.org/2000/svg"
XLINK_NS = "http://www.w3.org/1999/xlink"
XML_NS = "http://www.w3.org/XML/1998/namespace"
MAX_BYTES = 2 * 1024 * 1024
NUMBER = r"[+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?"
NUMBER_RE = re.compile(NUMBER)

DRAWING_TAGS = {"path", "rect", "circle", "ellipse", "line", "polyline", "polygon", "use"}
RESOURCE_TAGS = {"defs", "clipPath", "mask", "pattern", "symbol", "linearGradient", "radialGradient", "stop"}
ALLOWED_TAGS = DRAWING_TAGS | RESOURCE_TAGS | {"svg", "g", "title", "desc"}
FORBIDDEN_HINTS = {
    "style": "flutter_svg: inline presentation attributes required instead of <style>",
    "filter": "flutter_svg: <filter> / blur / dropShadow unsupported; use gradients or opacity shapes",
    "image": "Do not embed raster <image> inside vector illustrations",
    "text": "Avoid <text> in course illustrations to prevent missing-font tofu; convert small symbols to <path>",
    "foreignObject": "HTML <foreignObject> is unsupported in flutter_svg",
}

ALLOWED_ATTRS = set("""
    id width height viewBox preserveAspectRatio transform
    x y x1 y1 x2 y2 cx cy r rx ry d points
    fill fill-rule fill-opacity stroke stroke-width stroke-linecap stroke-linejoin
    stroke-miterlimit stroke-dasharray stroke-dashoffset stroke-opacity opacity
    display visibility clip-path clip-rule mask
    gradientUnits gradientTransform spreadMethod fx fy fr
    stop-color stop-opacity offset clipPathUnits maskUnits maskContentUnits
    patternUnits patternContentUnits patternTransform href
    role aria-label aria-labelledby aria-describedby aria-hidden
""".split())

PATH_ARITY = {"M": 2, "L": 2, "H": 1, "V": 1, "C": 6, "S": 4, "Q": 4, "T": 2, "A": 7}


class SVGError(ValueError):
    pass


class SafeTreeBuilder(ET.TreeBuilder):
    def doctype(self, name, public_id, system_id):
        raise SVGError("DTDs and entity declarations are not supported")

    def pi(self, target, text):
        raise SVGError("XML processing instructions are not supported")


def local_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def parse_numbers(value: str) -> list[float]:
    if re.sub(NUMBER, "", value).strip(" \t\r\n,"):
        raise SVGError(f"Invalid number list: {value[:60]!r}")
    nums = [float(m.group()) for m in NUMBER_RE.finditer(value)]
    if not all(math.isfinite(n) for n in nums):
        raise SVGError("Numbers must be finite")
    return nums


def count_path_segments(data: str) -> int:
    pos = 0
    cmd = None
    segments = 0
    while pos < len(data):
        while pos < len(data) and data[pos] in " \t\r\n,":
            pos += 1
        if pos == len(data):
            break
        if data[pos].isalpha():
            cmd = data[pos]
            pos += 1
            if segments == 0 and cmd.upper() != "M":
                raise SVGError("Path must start with M/m moveto")
            if cmd.upper() == "Z":
                segments += 1
                cmd = None
                continue
            if cmd.upper() not in PATH_ARITY:
                raise SVGError(f"Unsupported path command: {cmd}")
        if cmd is None:
            raise SVGError("Path numbers require a preceding command")
        for idx in range(PATH_ARITY[cmd.upper()]):
            while pos < len(data) and data[pos] in " \t\r\n,":
                pos += 1
            if cmd.upper() == "A" and idx in {3, 4}:
                if pos == len(data) or data[pos] not in "01":
                    raise SVGError("Arc flags must be 0 or 1")
                pos += 1
                continue
            match = NUMBER_RE.match(data, pos)
            if match is None:
                raise SVGError(f"Path command {cmd} has invalid arguments")
            pos = match.end()
        segments += 1
        cmd = "L" if cmd == "M" else ("l" if cmd == "m" else cmd)
    if segments == 0:
        raise SVGError("Path 'd' attribute must not be empty")
    return segments


def inspect_svg(path: Path) -> dict:
    raw = path.read_bytes()
    if len(raw) > MAX_BYTES:
        raise SVGError("SVG exceeds 2 MiB limit")
    text = raw.decode("utf-8-sig")
    try:
        root = ET.fromstring(text, parser=ET.XMLParser(target=SafeTreeBuilder()))
    except ET.ParseError as exc:
        raise SVGError(f"Invalid XML: {exc}") from exc

    errors: list[str] = []
    warnings: list[str] = []

    if root.tag != f"{{{SVG_NS}}}svg":
        errors.append("Root element must be <svg xmlns='http://www.w3.org/2000/svg'>")

    view_box = None
    try:
        vb = parse_numbers(root.get("viewBox", ""))
        if len(vb) != 4 or vb[2] <= 0 or vb[3] <= 0:
            raise SVGError("viewBox requires 4 numbers with positive width and height")
        view_box = vb
    except SVGError as exc:
        errors.append(str(exc))

    stack = [(root, ())]
    nodes = []
    while stack:
        el, ancestors = stack.pop()
        if not isinstance(el.tag, str):
            continue
        nodes.append((el, ancestors))
        stack.extend((child, ancestors + (el,)) for child in reversed(el))

    counts = Counter(local_name(el.tag) for el, _ in nodes)
    ids: dict[str, ET.Element] = {}
    refs: list[tuple[str, str, list[str]]] = []
    total_segments = 0

    for el, ancestors in nodes:
        tag = local_name(el.tag)
        el_id = el.get("id")
        label = f"{tag}#{el_id}" if el_id else tag

        if el.tag != f"{{{SVG_NS}}}{tag}" or tag not in ALLOWED_TAGS:
            hint = FORBIDDEN_HINTS.get(tag, "unsupported element in Turna flutter_svg profile")
            errors.append(f"{label}: {hint}")

        if el_id is not None:
            if not el_id or re.search(r"\s", el_id):
                errors.append(f"{label}: id must be non-empty without whitespace")
            elif el_id in ids:
                errors.append(f"{label}: duplicate id '{el_id}'")
            ids[el_id] = el

        for attr, val in el.attrib.items():
            name = local_name(attr)
            if attr in {f"{{{XML_NS}}}space", f"{{{XML_NS}}}lang"}:
                continue
            if name not in ALLOWED_ATTRS and not name.startswith("data-"):
                errors.append(f"{label}: unsupported attribute '{name}' (avoid style/class)")
                continue
            if name == "href" or attr == f"{{{XLINK_NS}}}href":
                if not val.startswith("#") or len(val) < 2:
                    errors.append(f"{label}: only local #id href references allowed")
                else:
                    owners = [a.get("id") for a in ancestors + (el,) if a.get("id")]
                    refs.append((label, val[1:], owners))
            if name in {"fill", "stroke", "clip-path", "mask"} and "url(" in val:
                for m in re.finditer(r"url\s*\(([^)]*)\)", val):
                    target = m.group(1).strip().strip("\"'")
                    if not target.startswith("#") or len(target) < 2:
                        errors.append(f"{label}: only local url(#id) references allowed")
                    else:
                        owners = [a.get("id") for a in ancestors + (el,) if a.get("id")]
                        refs.append((label, target[1:], owners))

        if tag == "path":
            try:
                total_segments += count_path_segments(el.get("d", ""))
            except SVGError as exc:
                errors.append(f"{label}: {exc}")

    graph = {k: set() for k in ids}
    for label, target, owners in refs:
        if target not in ids:
            errors.append(f"{label}: unresolved reference #{target}")
        else:
            for owner in owners:
                graph[owner].add(target)
    try:
        graphlib.TopologicalSorter(graph).prepare()
    except graphlib.CycleError as exc:
        errors.append(f"Cyclic reference detected: {exc}")

    if counts["g"] == 0 and sum(counts[t] for t in DRAWING_TAGS) > 4:
        warnings.append("Recommend grouping semantic parts with <g id='...'> for easier local editing")
    if len(nodes) > 120:
        warnings.append(f"High element count ({len(nodes)}); keep flat illustrations concise (<80 preferred)")

    return {
        "valid": not errors,
        "file": str(path),
        "viewBox": view_box,
        "errors": errors,
        "warnings": warnings,
        "stats": {
            "bytes": len(raw),
            "elements": len(nodes),
            "groups": counts["g"],
            "drawing_elements": sum(counts[t] for t in DRAWING_TAGS),
            "path_segments": total_segments,
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate SVG against Turna flutter_svg profile.")
    parser.add_argument("files", nargs="+", help="One or more SVG files to validate")
    args = parser.parse_args()

    all_valid = True
    for file_arg in args.files:
        p = Path(file_arg)
        try:
            report = inspect_svg(p)
        except (OSError, UnicodeDecodeError, SVGError) as exc:
            report = {"valid": False, "file": str(p), "error": str(exc)}
        print(json.dumps(report, ensure_ascii=False, indent=2))
        if not report.get("valid"):
            all_valid = False
    return 0 if all_valid else 1


if __name__ == "__main__":
    sys.exit(main())
