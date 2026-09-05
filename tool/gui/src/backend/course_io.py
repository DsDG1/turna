"""Course file IO, snapshot, atomic saving, and backup services.

Decoupled from CourseAdapter.
"""
from __future__ import annotations

import logging
import os
import shutil
import tempfile
import time
from copy import deepcopy
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Any

from src.backend import api
from src.infrastructure.telemetry import telemetry

logger = logging.getLogger(__name__)


@dataclass
class SaveResult:
    ok: bool
    errors: list[dict[str, str]] = field(default_factory=list)
    warnings: list[dict[str, str]] = field(default_factory=list)
    message: str = ""


class CourseIoService:
    """Service handling course snapshots, atomic writes, backups, and save flows."""

    @staticmethod
    def deep_snapshot(adapter: Any) -> dict[str, Any]:
        return {
            "index": deepcopy(adapter.index),
            "sections": deepcopy(adapter.sections),
            "vocab": deepcopy(adapter.vocab),
            "expressions": deepcopy(adapter.expressions),
            "grammar_points": deepcopy(adapter.grammar_points),
        }

    @staticmethod
    def restore_from(adapter: Any, snapshot: dict[str, Any]) -> None:
        adapter.index = deepcopy(snapshot["index"])
        adapter.sections = deepcopy(snapshot["sections"])
        adapter.vocab = deepcopy(snapshot.get("vocab", adapter.vocab))
        adapter.expressions = deepcopy(snapshot.get("expressions", adapter.expressions))
        adapter.grammar_points = deepcopy(snapshot.get("grammar_points", adapter.grammar_points))
        if hasattr(adapter, "invalidate_node_index"):
            adapter.invalidate_node_index()

    @staticmethod
    def write_files_to_dir(adapter: Any, target_dir: Path) -> None:
        """Write all course files to ``target_dir`` mirroring the course layout."""
        assert adapter.course_dir is not None
        target_dir = Path(target_dir)
        target_dir.mkdir(parents=True, exist_ok=True)
        (target_dir / "sections").mkdir(exist_ok=True)

        api.save_json(target_dir / "index.json", adapter.index)
        for section in adapter.sections:
            path = adapter.section_file(section["id"])
            rel = path.relative_to(adapter.course_dir)
            api.save_json(target_dir / rel, section)
        language = adapter.index.get("language", "")
        api.save_json(
            target_dir / "vocab.json",
            {"version": 1, "language": language, "words": adapter.vocab},
        )
        api.save_json(
            target_dir / "expressions.json",
            {
                "version": getattr(adapter, "expressions_version", 1),
                "language": language,
                "expressions": adapter.expressions,
            },
        )
        api.save_json(
            target_dir / "grammar_points.json",
            {"grammarPoints": adapter.grammar_points},
        )

    @staticmethod
    def backup_json_files(src: Path, dst: Path) -> None:
        """Copy every JSON file under ``src`` to ``dst`` preserving structure."""
        for path in src.rglob("*.json"):
            rel = path.relative_to(src)
            if any(part.startswith(".varnamala-backup") for part in rel.parts):
                continue
            target = dst / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, target)
        CourseIoService.prune_old_backups(dst.parent, keep=20)

    @staticmethod
    def prune_old_backups(backup_root: Path, keep: int = 20) -> None:
        """Remove the oldest backup dirs under ``backup_root`` beyond ``keep``."""
        if not backup_root.is_dir() or keep < 1:
            return
        try:
            children = [
                p for p in backup_root.iterdir()
                if p.is_dir() and not p.name.startswith(".")
            ]
        except OSError:
            return
        if len(children) <= keep:
            return
        children.sort(key=lambda p: p.name)
        for old in children[:-keep]:
            try:
                shutil.rmtree(old, ignore_errors=True)
            except Exception:
                logger.debug("backend/course_io.py:prune_old_backups best-effort step failed", exc_info=True)

    @staticmethod
    def replace_course_files_with(tmp_dir: Path, course_dir: Path) -> None:
        """Atomically replace course files with those in ``tmp_dir``."""
        new_rel_paths: set[Path] = set()
        for tmp_file in tmp_dir.rglob("*.json"):
            rel = tmp_file.relative_to(tmp_dir)
            new_rel_paths.add(rel)
            target = course_dir / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            os.replace(tmp_file, target)

        sections_dir = course_dir / "sections"
        if sections_dir.is_dir():
            for old_file in sections_dir.glob("*.json"):
                rel = old_file.relative_to(course_dir)
                if rel not in new_rel_paths:
                    old_file.unlink()

    @staticmethod
    def save(adapter: Any) -> SaveResult:
        """Persist the in-memory course to disk atomically with backup."""
        if adapter.course_dir is None:
            return SaveResult(ok=False, message="未加载课程目录")

        rollback = getattr(adapter, "_snapshot", None)
        if rollback is None:
            rollback = CourseIoService.deep_snapshot(adapter)

        start = time.perf_counter()
        tmp_dir: Path | None = None
        result: SaveResult | None = None
        try:
            tmp_dir = Path(tempfile.mkdtemp(prefix=".turna-save-"))
            if hasattr(adapter, "_write_files_to_dir"):
                adapter._write_files_to_dir(tmp_dir)
            else:
                CourseIoService.write_files_to_dir(adapter, tmp_dir)

            validate = api.validate_course_dir(tmp_dir)
            if not validate.ok:
                if hasattr(adapter, "_restore_from"):
                    adapter._restore_from(rollback)
                else:
                    CourseIoService.restore_from(adapter, rollback)
                errors = [p.to_dict() for p in validate.problems if p.level == "error"]
                result = SaveResult(
                    ok=False,
                    errors=errors,
                    message=f"校验失败，已回滚（{len(errors)} 个错误）",
                )
                telemetry.record_event(
                    "repo.save.failed",
                    payload={"reason": "validation", "error_count": len(errors)},
                )
                return result

            backup_dir = (
                adapter.course_dir
                / ".varnamala-backup"
                / datetime.now().strftime("%Y%m%d-%H%M%S-%f")
            )
            if hasattr(adapter, "_backup_json_files"):
                adapter._backup_json_files(adapter.course_dir, backup_dir)
            else:
                CourseIoService.backup_json_files(adapter.course_dir, backup_dir)

            if hasattr(adapter, "_replace_course_files_with"):
                adapter._replace_course_files_with(tmp_dir, adapter.course_dir)
            else:
                CourseIoService.replace_course_files_with(tmp_dir, adapter.course_dir)

            adapter._snapshot = CourseIoService.deep_snapshot(adapter)
            if hasattr(adapter, "_refresh_hash_cache"):
                adapter._refresh_hash_cache()
            if hasattr(adapter, "invalidate_node_index"):
                adapter.invalidate_node_index()
        except Exception as exc:
            if hasattr(adapter, "_restore_from"):
                adapter._restore_from(rollback)
            else:
                CourseIoService.restore_from(adapter, rollback)
            if hasattr(adapter, "_write_files_to_dir"):
                adapter._write_files_to_dir(adapter.course_dir)
            else:
                CourseIoService.write_files_to_dir(adapter, adapter.course_dir)
            telemetry.record_error(
                exc,
                context={"action": "repo.save", "course_dir": str(adapter.course_dir)},
            )
            result = SaveResult(ok=False, message=f"保存失败: {exc}")
            return result
        finally:
            if tmp_dir is not None:
                shutil.rmtree(tmp_dir, ignore_errors=True)

        try:
            lint = api.lint_course_dir(adapter.course_dir)
            warnings = [p.to_dict() for p in lint if p.level == "warning"]
        except Exception as exc:
            telemetry.record_error(
                exc,
                context={"action": "repo.save.lint", "course_dir": str(adapter.course_dir)},
            )
            warnings = []
        result = SaveResult(
            ok=True,
            warnings=warnings,
            message=f"保存成功，{len(warnings)} 条 lint 警告",
        )
        telemetry.record_duration(
            "repo.save",
            (time.perf_counter() - start) * 1000,
            payload={
                "course_dir": str(adapter.course_dir),
                "warning_count": len(warnings),
            },
        )
        return result
