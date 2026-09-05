"""Course release planning, version bumping, and diff services.

Decoupled from CourseAdapter.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any

from src.backend import api


class CourseReleaseService:
    """Service handling course version bumping, diffs, and release reports."""

    @staticmethod
    def state_hash(data: dict[str, Any]) -> str:
        """Return a stable, salt-independent hash for a state dict.

        Uses sha256 over the canonical JSON so the value is reproducible
        across interpreter runs (Python's builtin hash is per-process
        salted, which produced false-positive "changed" results whenever
        the cache was rebuilt in a different session). (P5/B14)
        """
        payload = json.dumps(data, ensure_ascii=False, sort_keys=True).encode("utf-8")
        return hashlib.sha256(payload).hexdigest()

    @classmethod
    def detect_changes(cls, adapter: Any) -> dict[str, bool]:
        """Compare current in-memory state vs last-saved snapshot using cached hashes."""
        current = {
            "index": adapter.index,
            "sections": adapter.sections,
            "vocab": adapter.vocab,
            "expressions": adapter.expressions,
            "grammar_points": adapter.grammar_points,
        }
        if not adapter._hash_cache:
            adapter._refresh_hash_cache()
        return {
            key: cls.state_hash({key: current[key]}) != adapter._hash_cache.get(key, "")
            for key in current
        }

    @classmethod
    def version_bump_plan(
        cls, adapter: Any, changes: dict[str, bool] | None = None
    ) -> dict[str, tuple[int, int]]:
        """Return {file: (current_version, next_version)} for files to bump.

        ``changes`` may be passed to reuse an already-computed
        ``detect_changes()`` result (avoids re-hashing the whole course).

        vocab.json carries no version of its own; the app re-seeds trigger is
        the composite ``indexVersion + expressionsVersion``
        (course_database_seeder.dart). Vocab is resource-layer kin to
        expressions, so a vocab-only change rides the expressions bump to
        reach installed clients (G9) — both changed together bump once.
        """
        if changes is None:
            changes = cls.detect_changes(adapter)
        plan: dict[str, tuple[int, int]] = {}
        if changes["index"] or changes["sections"]:
            cur = int(adapter.index.get("version", 1))
            plan["index"] = (cur, cur + 1)
        if changes["expressions"] or changes["vocab"]:
            expr_ver = getattr(adapter, "expressions_version", 1)
            plan["expressions"] = (expr_ver, expr_ver + 1)
        return plan

    @staticmethod
    def apply_version_bump(adapter: Any, plan: dict[str, tuple[int, int]]) -> None:
        """Apply version bumps to in-memory state (caller then save())."""
        if "index" in plan:
            adapter.index["version"] = plan["index"][1]
        if "expressions" in plan:
            adapter.expressions_version = plan["expressions"][1]

    @staticmethod
    def audio_manifest_rows(adapter: Any) -> list[dict[str, str]]:
        """Return audio manifest rows (delegates to backend API)."""
        if adapter.course_dir is None:
            return []
        return api.build_audio_manifest_rows(adapter.course_dir)

    @staticmethod
    def release_diff(adapter: Any) -> dict[str, dict[str, Any]]:
        """Compare last-saved snapshot (before) vs current (after) by id sets."""
        snap = adapter._snapshot or adapter._deep_snapshot()
        result: dict[str, dict[str, Any]] = {}
        for key, snap_list, cur_list in [
            ("vocab", snap["vocab"], adapter.vocab),
            ("expressions", snap["expressions"], adapter.expressions),
            ("grammar_points", snap["grammar_points"], adapter.grammar_points),
            ("sections", snap["index"].get("sections", []), adapter.index.get("sections", [])),
        ]:
            before = {e.get("id", "") for e in snap_list if e.get("id")}
            after = {e.get("id", "") for e in cur_list if e.get("id")}
            result[key] = {
                "added": sorted(after - before),
                "removed": sorted(before - after),
                "unchanged_count": len(before & after),
            }
        return result

    @classmethod
    def release_report(cls, adapter: Any) -> dict[str, Any]:
        """Aggregate release checklist data for the publish dialog."""
        changes = cls.detect_changes(adapter)
        version_bump = cls.version_bump_plan(adapter, changes)
        audio_manifest = cls.audio_manifest_rows(adapter)
        diff = cls.release_diff(adapter)
        validate = api.validate_course_dir(adapter.course_dir) if adapter.course_dir else api.ValidationResult(ok=True, error_count=0, problems=[])
        lint = api.lint_course_dir(adapter.course_dir) if adapter.course_dir else []
        return {
            "changes": changes,
            "version_bump": version_bump,
            "audio_manifest": audio_manifest,
            "diff": diff,
            "validation": {
                "ok": validate.ok,
                "errors": [p.to_dict() for p in validate.problems if p.level == "error"],
                "warnings": [p.to_dict() for p in lint if p.level == "warning"],
            },
        }
