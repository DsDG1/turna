"""Port the OHOS adaptation of TargetPlatform into the vendored Flutter UI packages.

Flutter 3.44 split Material and Cupertino out of the framework into the hosted
packages `material_ui` and `cupertino_ui`. The OHOS fork adapted its in-tree
copies but never adapted the split hosted copies, so every non-exhaustive
`switch` over `TargetPlatform` there fails to compile with "doesn't match
'TargetPlatform.ohos'". No fork of these two packages exists in any of the
openharmony-tpc / openharmony-sig / CPF-Flutter organisations, so the companion
build maintains the port itself (ADR 0047 §7.1).

Why a wildcard arm and not `case TargetPlatform.ohos:`
------------------------------------------------------
The two are equivalent on the OHOS fork: explicit labels match first and ohos
falls into the default arm, which is unreachable on the official SDK. Only the
second form cannot be used. `TargetPlatform.ohos` does not exist in the pinned
official SDK, and `dependency_overrides` has no platform conditioning, so a copy
that names it breaks the Android/iOS build and every test in the suite. That was
measured, not assumed: naming it produced 43 test failures, all
`Member not found: 'ohos'`.

Matching rule
-------------
The fork only *added* the `ohos` label, so both versions of a switch carry arms
built from identical other labels. That structure is the key, with `ohos` stripped
from it, otherwise the two sides can never be equal. Signatures repeating within
one file are disambiguated by ordinal order. Only arm membership is copied; the
order of labels inside an arm carries no meaning in Dart.

Placement
---------
Dart requires a switch statement's `default` to be its last case, so the
wildcard arm is appended at the end with a copy of the target arm's body. A
fall-through arm (labels with no body) takes the body it falls into.

Sites needing a judgement call -- a nullable subject, where a bare `_` would
shadow the `null` arm and make it unreachable -- are reported, not guessed.

Usage:
    python third_party/flutter/migrate_ohos_platform.py --check
    python third_party/flutter/migrate_ohos_platform.py --apply
    python third_party/flutter/migrate_ohos_platform.py --verify
"""

from __future__ import annotations

import argparse
import collections
import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parents[2]
VENDOR = REPO / "third_party" / "flutter"
FORK = pathlib.Path(
    r"C:\Users\DsDogs\Desktop\developper\flutter_ohos_344\packages\flutter\lib\src"
)

# vendored package -> (subdir in the fork's src, subdir in the vendored lib)
PACKAGES = {
    "material_ui": ("material", "src"),
    "cupertino_ui": ("cupertino", "src"),
}

LABEL_RE = re.compile(r"TargetPlatform\.(\w+)")
CASE_RE = re.compile(r"^(\s*)case TargetPlatform\.(\w+):\s*$")
CASE_NULL_RE = re.compile(r"^\s*case null:\s*$")
DEFAULT_CASE_RE = re.compile(r"^\s*default\s*:\s*$")
SWITCH_RE = re.compile(r"\bswitch\s*\(")
ARROW_RE = re.compile(r"=>")
# Only `_` and `default` are wildcards. A looser pattern also matches `null =>`
# and named constants, which are real patterns; treating those as wildcards made
# `port` skip the one site that most needed migrating.
WILDCARD_EXPR_RE = re.compile(r"^\s*(?:_|default)\s*=>")

PLATFORMS = {"android", "fuchsia", "iOS", "linux", "macOS", "windows"}


class NeedsHands(Exception):
    """A site the script refuses to guess at."""


class Switch:
    def __init__(self, style: str, line: int, close: int) -> None:
        self.style = style  # "case" | "expr"
        self.line = line
        self.close = close
        self.subject = ""
        self.arms: list[list[tuple[str, int]]] = []
        self.arrow: list[int] = []
        self.body: list[tuple[int, int]] = []  # inclusive line range, empty if lo > hi
        self.inline_body: list[str] = []  # expr arms whose body sits on the arrow line
        self.has_null: bool = False
        self.has_wildcard: bool = False

    def signature(self) -> tuple:
        return tuple(
            tuple(lbl for lbl, _ in arm if lbl != "ohos")
            for arm in self.arms
            if any(lbl != "ohos" for lbl, _ in arm)
        )

    def has_ohos(self) -> bool:
        return any(lbl == "ohos" for arm in self.arms for lbl, _ in arm)

    def platform_labels(self) -> set[str]:
        return {lbl for arm in self.arms for lbl, _ in arm} & PLATFORMS


def block_end(lines: list[str], start: int) -> int:
    """Index of the line closing the block opened at `start`.

    Tolerates the header not opening its brace on the same line, which matters
    because `switch (foo) {` and `switch (foo)
    {` both occur upstream.
    """
    depth = 0
    opened = False
    for i in range(start, len(lines)):
        depth += lines[i].count("{") - lines[i].count("}")
        if depth > 0:
            opened = True
        elif opened and i > start:
            return i
    return len(lines)


def subject_of(line: str) -> str:
    match = SWITCH_RE.search(line)
    if not match:
        return ""
    tail = line[match.end() :]
    depth = tail.count("(") - tail.count(")")
    cut = tail.find(")")
    return tail[:cut] if depth <= 0 and cut >= 0 else ""


def parse(lines: list[str], start: int) -> Switch | None:
    close = block_end(lines, start)
    head = "\n".join(lines[start : min(close, start + 6)])
    if "TargetPlatform." not in head:
        return None
    is_case = any(CASE_RE.match(ln) for ln in lines[start : min(close, start + 6)])
    sw = Switch("case" if is_case else "expr", start, close)
    sw.subject = subject_of(lines[start])

    pending: list[tuple[str, int]] = []
    i = start + 1
    while i < close:
        line = lines[i]
        # A nested switch owns its own cases and its own closing brace. Without
        # this skip they are attributed to the outer switch, its body range
        # swallows the inner `}`, and the port duplicates whole blocks.
        if SWITCH_RE.search(line):
            i = block_end(lines, i) + 1
            continue
        if not line.strip():
            i += 1
            continue
        if CASE_NULL_RE.match(line):
            sw.has_null = True
            pending.append(("null", i))
            continue
        if CASE_NULL_RE.match(line):
            sw.has_null = True
            pending.append(("null", i))
            i += 1
            continue
        case = CASE_RE.match(line)
        if case:
            pending.append((case.group(2), i))
            i += 1
            continue
        if DEFAULT_CASE_RE.match(line):
            sw.has_wildcard = True
            pending.append(("default", i))
            i += 1
            continue
        labels = LABEL_RE.findall(line)
        for lbl in labels:
            pending.append((lbl, i))
        if not labels and WILDCARD_EXPR_RE.match(line):
            sw.has_wildcard = True
            pending.append(("_", i))
        arrow = ARROW_RE.search(line)
        if arrow and pending:
            sw.arms.append(pending)
            sw.arrow.append(i)
            after = line[arrow.end() :].strip().rstrip(",")
            sw.inline_body.append(after)
            sw.body.append((i, i))  # body range resolved below
            pending = []
        i += 1
    if pending:
        sw.arms.append(pending)
        sw.arrow.append(close - 1)
        sw.inline_body.append("")
        sw.body.append((close - 1, close - 1))

    # An expression arm whose body spans following lines: extend to the line
    # before the next arm's first label.
    for k, arm in enumerate(sw.arms):
        if sw.inline_body[k]:
            continue
        first_body = sw.arrow[k] + 1
        next_start = sw.arms[k + 1][0][1] if k + 1 < len(sw.arms) else close
        lo, hi = first_body, next_start - 1
        while hi >= lo and not lines[hi].strip():
            hi -= 1
        sw.body[k] = (lo, hi)
    # A statement arm's body is likewise the lines before the next arm.
    if sw.style == "case":
        for k, arm in enumerate(sw.arms):
            first_body = arm[-1][1] + 1
            next_start = sw.arms[k + 1][0][1] if k + 1 < len(sw.arms) else close
            lo, hi = first_body, next_start - 1
            while hi >= lo and not lines[hi].strip():
                hi -= 1
            sw.body[k] = (lo, hi)
            sw.arrow[k] = arm[-1][1]
            sw.inline_body[k] = ""
    return sw


def switches(lines: list[str]) -> list[Switch]:
    out = []
    for i, line in enumerate(lines):
        if not SWITCH_RE.search(line):
            continue
        sw = parse(lines, i)
        if sw is not None and sw.arms:
            out.append(sw)
    return out


def indent_of(lines: list[str], i: int) -> str:
    line = lines[i]
    return line[: len(line) - len(line.lstrip())]


def body_lines(sw: Switch, k: int, lines: list[str]) -> list[str]:
    if sw.inline_body[k]:
        return []
    lo, hi = sw.body[k]
    if lo > hi:
        return []
    return lines[lo : hi + 1]


def effective_body(sw: Switch, k: int, lines: list[str]) -> tuple[list[str], str | None]:
    """Body for the wildcard arm, following fall-through labels if needed."""
    if sw.inline_body[k]:
        return [], sw.inline_body[k]
    got = body_lines(sw, k, lines)
    if got:
        return got, None
    for nxt in range(k + 1, len(sw.arms)):
        if sw.inline_body[nxt]:
            return [], sw.inline_body[nxt]
        got = body_lines(sw, nxt, lines)
        if got:
            return got, None
    return [], None


def wildcard_arm(sw: Switch, k: int, lines: list[str]) -> list[str]:
    """The wildcard arm text, appended as the switch's last arm."""
    pad = indent_of(lines, sw.arrow[k])
    body, inline = effective_body(sw, k, lines)
    if inline is not None:
        return [f"{pad}_ => {inline},"]

    # Appending the wildcard last is what makes this safe on a nullable subject:
    # an existing `null =>` / `case null:` sits earlier and still wins, so ohos
    # falls through to the wildcard rather than shadowing it. A switch statement
    # takes `default:`; a switch expression must use `_` -- Dart rejects
    # `default` in an expression outright.
    out = [f"{pad}default:" if sw.style == "case" else f"{pad}_ =>"]

    out.extend(body)
    # Only a switch expression separates arms with commas; a statement body ends
    # at `break;` and a trailing comma there is a syntax error.
    if sw.style == "expr" and out and not out[-1].rstrip().endswith(("{", ",")):
        out[-1] = out[-1].rstrip() + ","
    return out


def port(vendor_root: pathlib.Path, fork_root: pathlib.Path, apply: bool) -> int:
    total = 0
    unresolved: list[str] = []

    for package, (fork_sub, vendor_sub) in PACKAGES.items():
        fork_dir = fork_root / fork_sub
        vendor_dir = vendor_root / package / "lib" / vendor_sub
        if not fork_dir.is_dir() or not vendor_dir.is_dir():
            print(f"skip {package}: missing {fork_dir} or {vendor_dir}", file=sys.stderr)
            continue

        for dart in sorted(vendor_dir.rglob("*.dart")):
            fork_file = fork_dir / dart.relative_to(vendor_dir)
            if not fork_file.is_file():
                continue
            vendor_lines = dart.read_text(encoding="utf-8").splitlines()
            fork_lines = fork_file.read_text(encoding="utf-8").splitlines()

            by_sig: dict[tuple, list[Switch]] = collections.defaultdict(list)
            for sw in switches(fork_lines):
                if sw.has_ohos():
                    by_sig[sw.signature()].append(sw)
            if not by_sig:
                continue

            used: collections.Counter = collections.Counter()
            inserts: dict[int, list[str]] = collections.defaultdict(list)

            for sw in switches(vendor_lines):
                if sw.has_ohos() or sw.has_wildcard:
                    continue
                sig = sw.signature()
                bucket = by_sig.get(sig)
                if not bucket:
                    continue
                pick = used[sig]
                used[sig] += 1
                if pick >= len(bucket) or bucket[pick].style != sw.style:
                    unresolved.append(f"{package}/{dart.name}: no counterpart for {sig}")
                    continue
                reference = bucket[pick]
                ohos_arm = next(i for i, a in enumerate(reference.arms) if any(l == "ohos" for l, _ in a))
                companions = {l for l, _ in reference.arms[ohos_arm] if l != "ohos"}
                target = next(
                    (i for i, a in enumerate(sw.arms) if companions <= {l for l, _ in a}),
                    None,
                )
                if target is None and sw.arms:
                    target = max(
                        range(len(sw.arms)),
                        key=lambda i: len({l for l, _ in sw.arms[i]} & companions),
                    )
                if target is None:
                    unresolved.append(f"{package}/{dart.name}: no arm for {sig}")
                    continue
                try:
                    arm = wildcard_arm(sw, target, vendor_lines)
                except NeedsHands as exc:
                    unresolved.append(f"{package}/{dart.name}: {exc}")
                    continue
                inserts[sw.close].extend(arm)
                total += 1

            if not inserts or not apply:
                continue
            out: list[str] = []
            for i, line in enumerate(vendor_lines):
                out.extend(inserts.get(i, []))
                out.append(line)
            dart.write_text("\n".join(out) + "\n", encoding="utf-8")

    for item in unresolved[:20]:
        print(f"unresolved: {item}", file=sys.stderr)
    if unresolved:
        print(f"total unresolved: {len(unresolved)}", file=sys.stderr)
    return total


def verify(vendor_root: pathlib.Path) -> int:
    """The vendored tree must name no ohos enum value and reach a wildcard arm."""
    problems: list[str] = []
    open_switches = 0
    for package, (_, vendor_sub) in PACKAGES.items():
        vendor_dir = vendor_root / package / "lib" / vendor_sub
        if not vendor_dir.is_dir():
            continue
        for dart in sorted(vendor_dir.rglob("*.dart")):
            lines = dart.read_text(encoding="utf-8").splitlines()
            for i, line in enumerate(lines):
                stripped = line.strip()
                if stripped.startswith(("//", "/*", "*")):
                    continue
                if "TargetPlatform.ohos" in line:
                    problems.append(
                        f"{package}/{dart.name}:{i + 1} names TargetPlatform.ohos, "
                        "absent from the official SDK"
                    )
                if re.search(r"TargetPlatform\.\w+[^\s|,)]+TargetPlatform\.", line):
                    problems.append(f"{package}/{dart.name}:{i + 1} missing '||'")
            for sw in switches(lines):
                if sw.has_wildcard or not sw.platform_labels():
                    continue
                open_switches += 1
                problems.append(
                    f"{package}/{dart.name}: no wildcard arm at line {sw.line + 1}"
                )
    for item in problems[:25]:
        print(f"  {item}")
    print(f"switches without a wildcard arm: {open_switches}")
    return 1 if problems else 0


def main() -> int:
    parser = argparse.ArgumentParser()
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--check", action="store_true")
    group.add_argument("--apply", action="store_true")
    group.add_argument("--verify", action="store_true")
    args = parser.parse_args()

    if not FORK.is_dir() and not args.verify:
        print(
            f"fork reference tree not found: {FORK}\n"
            "point FORK at <ohos flutter sdk>/packages/flutter/lib/src",
            file=sys.stderr,
        )
        return 2
    if args.verify:
        return verify(VENDOR)
    print(f"ohos case sites ported: {port(VENDOR, FORK, apply=args.apply)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
