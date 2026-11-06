from __future__ import annotations

import argparse
import json
import sys
from collections.abc import Sequence
from pathlib import Path
from typing import Any

from .render import course_url, preview_url
from .server import run_server
from .store import PreviewStore


def _json_input(path: str | None) -> Any:
    if path:
        with Path(path).open(encoding="utf-8") as handle:
            return json.load(handle)
    return json.load(sys.stdin)


def _write_json(value: Any) -> None:
    json.dump(value, sys.stdout, ensure_ascii=False, indent=2)
    sys.stdout.write("\n")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Turna course preview server-side commands")
    parser.add_argument("--root", default="/var/lib/turna-course-preview")
    parser.add_argument("--public-base", default="https://turnalangua.xyz/course-preview")
    commands = parser.add_subparsers(dest="command", required=True)

    publish = commands.add_parser("publish")
    publish.add_argument("path", nargs="?")
    publish.add_argument("--preview-id", default="")

    publish_course = commands.add_parser("publish-course")
    publish_course.add_argument("path", nargs="?")

    feedback = commands.add_parser("feedback")
    feedback.add_argument("--preview-id", required=True)

    serve = commands.add_parser("serve")
    serve.add_argument("--host", default="127.0.0.1")
    serve.add_argument("--port", type=int, default=8765)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        store = PreviewStore(args.root)
        if args.command == "publish":
            section = _json_input(args.path)
            result = store.publish(section, preview_id=args.preview_id or None)
            result["url"] = preview_url(args.public_base, result["preview_id"])
            _write_json(result)
            return 0
        if args.command == "publish-course":
            result = store.publish_course(_json_input(args.path))
            result["url"] = course_url(args.public_base, result["course_id"])
            for entry in result["publications"]:
                if entry.get("preview_id"):
                    entry["url"] = preview_url(args.public_base, entry["preview_id"])
            _write_json(result)
            return 0
        if args.command == "feedback":
            entries = store.feedback(args.preview_id)
            _write_json({"preview_id": args.preview_id, "feedback": entries})
            return 0
        if args.command == "serve":
            run_server(args.host, args.port, store, public_base=args.public_base)
            return 0
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as exc:
        print(str(exc), file=sys.stderr)
        return 2
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
