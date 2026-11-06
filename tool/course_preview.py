#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
from collections.abc import Sequence
from pathlib import Path

_GUI = Path(__file__).resolve().parent / "gui"
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.course_preview.client import PreviewSyncError, SshPreviewClient
from src.backend.course_preview.course import load_course_bundle
from src.backend.course_preview.server import run_server
from src.backend.course_preview.store import PreviewStore


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="发布 Turna 课程或 section 草稿到网页预览")
    commands = parser.add_subparsers(dest="command", required=True)

    publish = commands.add_parser("publish", help="通过 SSH 发布或更新单节预览")
    publish.add_argument("path", help="section JSON 文件")
    publish.add_argument("--preview-id", default="", help="已有预览 id；省略则创建新链接")
    publish.add_argument("--ssh-target", default="turna")
    publish.add_argument("--public-base", default="https://turnalangua.xyz/course-preview")

    publish_course = commands.add_parser("publish-course", help="通过 SSH 发布或更新整门课程")
    publish_course.add_argument("path", help="包含 index.json 的课程目录")
    publish_course.add_argument("--course-id", default="", help="稳定课程 id；默认使用目录名")
    publish_course.add_argument("--title", default="", help="可选的网站课程标题")
    publish_course.add_argument("--ssh-target", default="turna")
    publish_course.add_argument("--public-base", default="https://turnalangua.xyz/course-preview")

    feedback = commands.add_parser("feedback", help="通过 SSH 拉取预览反馈")
    feedback.add_argument("--preview-id", required=True)
    feedback.add_argument("--ssh-target", default="turna")
    feedback.add_argument("--output", default="", help="可选的 JSON 输出文件")

    serve = commands.add_parser("serve", help="直接在本机运行预览服务（调试用）")
    serve.add_argument("--root", default=str(Path("tool/var/course_preview")))
    serve.add_argument("--host", default="127.0.0.1")
    serve.add_argument("--port", type=int, default=8765)
    serve.add_argument("--public-base", default="")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        if args.command == "serve":
            run_server(args.host, args.port, PreviewStore(args.root), public_base=args.public_base)
            return 0
        client = SshPreviewClient(
            args.ssh_target,
            public_base=getattr(args, "public_base", "https://turnalangua.xyz/course-preview"),
        )
        if args.command == "publish":
            with Path(args.path).open(encoding="utf-8") as handle:
                section = json.load(handle)
            result = client.publish(section, preview_id=args.preview_id)
        elif args.command == "publish-course":
            bundle = load_course_bundle(
                args.path,
                course_id=args.course_id,
                title=args.title,
            )
            result = client.publish_course(bundle)
        else:
            result = {"preview_id": args.preview_id, "feedback": client.feedback(args.preview_id)}
        output = json.dumps(result, ensure_ascii=False, indent=2) + "\n"
        if getattr(args, "output", ""):
            Path(args.output).write_text(output, encoding="utf-8")
        else:
            sys.stdout.write(output)
        return 0
    except (OSError, ValueError, KeyError, json.JSONDecodeError, PreviewSyncError) as exc:
        print(str(exc), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
