#!/usr/bin/env python3
"""Join Cargo.lock package names with anki/cargo/licenses.json."""

from __future__ import annotations

import json
import re
import collections
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOCK = ROOT / "Cargo.lock"
TABLE = ROOT / "anki/cargo/licenses.json"


def main() -> None:
    names = set(re.findall(r'^name = "([^"]+)"', LOCK.read_text(), re.M))
    rows = {row["name"]: row for row in json.loads(TABLE.read_text())}
    matched = [rows[name] for name in sorted(names) if name in rows]
    missing = sorted(name for name in names if name not in rows)
    buckets = collections.Counter(
        (row.get("license") or "(none)") for row in matched
    )
    print(f"lock_packages={len(names)}")
    print(f"matched={len(matched)}")
    print(f"missing={len(missing)}")
    if missing:
        print("missing_names=" + ",".join(missing))
    print("buckets:")
    for license_id, count in buckets.most_common():
        print(f"  {count}\t{license_id}")


if __name__ == "__main__":
    main()
