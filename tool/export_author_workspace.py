#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import shutil
import tempfile
from pathlib import Path

from course_cli import _validate_course
from course_quality_report import build_quality_report

REPO = Path(__file__).resolve().parent.parent


def _source_for_media(course_dir: Path, asset: str, kind: str) -> Path | None:
    if "://" in asset:
        return None
    normalized = asset.replace("\\", "/").strip()
    if normalized.startswith("media/"):
        return course_dir / normalized
    if normalized.startswith("assets/"):
        return REPO / normalized
    if kind == "audio":
        return REPO / "assets" / "sounds" / "listening" / f"{normalized}.mp3"
    return REPO / normalized


def export_author_workspace(course_dir: Path, output_dir: Path) -> dict:
    course_dir = course_dir.resolve()
    output_dir = output_dir.resolve()
    if output_dir.is_relative_to(course_dir) or course_dir.is_relative_to(output_dir):
        raise ValueError("Output and course directories must not contain each other")
    if output_dir.exists():
        raise FileExistsError(f"Output already exists: {output_dir}")
    output_dir.parent.mkdir(parents=True, exist_ok=True)
    report = build_quality_report(course_dir)
    staging = Path(
        tempfile.mkdtemp(prefix=f".{output_dir.name}-", dir=output_dir.parent)
    )
    try:
        target_course = staging / "course"
        shutil.copytree(course_dir, target_course)
        media_rows = []
        for row in report["media"]:
            source = _source_for_media(course_dir, row["asset"], row["kind"])
            if source is None:
                media_rows.append({"asset": row["asset"], "status": "external"})
                continue
            exists = source.is_file()
            if exists:
                if row["asset"].startswith("media/"):
                    destination = target_course / row["asset"]
                else:
                    destination = staging / row["asset"]
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source, destination)
            media_rows.append(
                {
                    "asset": row["asset"],
                    "kind": row["kind"],
                    "status": "ok" if exists else "missing",
                }
            )
        problems = _validate_course(target_course)
        if problems:
            raise ValueError(f"Course validation failed: {[p.message for p in problems]}")
        manifest = {
            "format": "turna-author-workspace/1",
            "courseDir": "course",
            "requiresAppReleaseForMedia": True,
            "media": media_rows,
        }
        (staging / "workspace.json").write_text(
            json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        os.replace(staging, output_dir)
    except Exception:
        shutil.rmtree(staging, ignore_errors=True)
        raise
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser(description="Export a self-contained course author workspace")
    parser.add_argument("--course-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    manifest = export_author_workspace(args.course_dir, args.output)
    missing = sum(row["status"] == "missing" for row in manifest["media"])
    print(f"Author workspace: {args.output.resolve()}")
    print(f"Media missing: {missing}")


if __name__ == "__main__":
    main()
