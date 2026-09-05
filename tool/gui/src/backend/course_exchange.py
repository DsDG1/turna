"""Course external resource exchange, CSV import/export, and Git synchronization.

Decoupled from CourseAdapter.
"""
from __future__ import annotations

import json
import os
import time
from pathlib import Path
from typing import Any

from src.backend import api
from src.infrastructure.telemetry import telemetry


class CourseExchangeService:
    """Service handling resource exchange, CSV, packs, and Git sync."""

    @staticmethod
    def import_csv(
        adapter: Any, row_type: str, csv_path: Path
    ) -> list[dict[str, str]]:
        """Read CSV, merge into memory, return problems. Does not write files."""
        start = time.perf_counter()
        rows = api.read_csv_file(csv_path)
        existing = adapter._resource_list(row_type)
        expression_ids = {e["id"] for e in adapter.expressions}
        merged, problems = api.import_csv_rows(
            row_type, existing, rows, expression_ids
        )
        errors = [p for p in problems if p.level == "error"]
        if not errors:
            adapter._set_resource_list(row_type, merged)
        telemetry.record_duration(
            "repo.import_csv",
            (time.perf_counter() - start) * 1000,
            payload={
                "row_type": row_type,
                "csv_path": str(csv_path),
                "error_count": len(errors),
                "warning_count": len([p for p in problems if p.level == "warning"]),
            },
        )
        return [p.to_dict() for p in problems]

    @staticmethod
    def export_csv(adapter: Any, row_type: str, output_path: Path) -> None:
        """Write current in-memory resources to CSV."""
        headers, rows = api.export_csv_rows(
            row_type, adapter._resource_list(row_type)
        )
        api.write_csv_file(output_path, headers, rows)

    @staticmethod
    def sync_resources_with_git(adapter: Any, git_dir: Path, lang: str) -> str:
        """Bidirectionally merge local resources with a git clone's resource JSON."""
        git_dir = Path(git_dir)
        mapping: dict[str, tuple[list[dict[str, Any]], str, str, dict[str, Any]]] = {
            "vocab": (adapter.vocab, "vocab.json", "words",
                      {"version": 1, "language": lang, "words": []}),
            "expressions": (adapter.expressions, "expressions.json", "expressions",
                            {"version": getattr(adapter, "expressions_version", 1), "language": lang, "expressions": []}),
            "grammar_points": (adapter.grammar_points, "grammar_points.json", "grammarPoints",
                               {"grammarPoints": []}),
        }
        parts: list[str] = []
        for row_type, (local_list, filename, list_key, default_wrapper) in mapping.items():
            git_file = git_dir / filename
            git_wrapper: dict[str, Any] = dict(default_wrapper)
            if git_file.is_file():
                try:
                    raw = json.loads(git_file.read_text(encoding="utf-8"))
                except Exception:
                    raw = None
                if isinstance(raw, dict):
                    git_wrapper.update(raw)
                    existing_list = raw.get(list_key)
                    if not isinstance(existing_list, list):
                        existing_list = []
                elif isinstance(raw, list):
                    existing_list = raw
                else:
                    existing_list = []
            else:
                existing_list = []
            git_list: list[dict[str, Any]] = existing_list

            local_ids = {e.get("id") for e in local_list}
            added_to_local = 0
            for entry in git_list:
                if not isinstance(entry, dict):
                    continue
                eid = entry.get("id")
                if eid and eid not in local_ids:
                    local_list.append(entry)
                    local_ids.add(eid)
                    added_to_local += 1

            git_ids = {e.get("id") for e in git_list}
            added_to_git = 0
            for entry in local_list:
                if not isinstance(entry, dict):
                    continue
                eid = entry.get("id")
                if eid and eid not in git_ids:
                    git_list.append(entry)
                    git_ids.add(eid)
                    added_to_git += 1

            git_wrapper[list_key] = git_list
            if "language" in git_wrapper:
                git_wrapper["language"] = lang
            if row_type == "expressions":
                git_wrapper["version"] = getattr(adapter, "expressions_version", 1)

            tmp_file = git_file.with_suffix(git_file.suffix + ".tmp")
            tmp_file.write_text(
                json.dumps(git_wrapper, ensure_ascii=False, indent=2),
                encoding="utf-8",
            )
            os.replace(tmp_file, git_file)
            parts.append(f"{row_type}: 本地新增 {added_to_local}，Git 新增 {added_to_git}")
        if hasattr(adapter, "notify_resources_changed"):
            adapter.notify_resources_changed()
        return "\n".join(parts)

    @staticmethod
    def detect_duplicates(adapter: Any) -> list[dict[str, str]]:
        """Detect duplicate terms across vocab and expressions."""
        seen: dict[str, str] = {}
        dupes: list[dict[str, str]] = []
        for entry in adapter.vocab:
            term = str(entry.get("term") or entry.get("source") or "").strip().lower()
            if not term:
                continue
            if term in seen:
                dupes.append({
                    "type": "vocab",
                    "id": str(entry.get("id", "")),
                    "term": term,
                    "duplicate_in": seen[term],
                })
            else:
                seen[term] = f"vocab:{entry.get('id', '')}"
        for entry in adapter.expressions:
            term = str(entry.get("source") or entry.get("term") or "").strip().lower()
            if not term:
                continue
            if term in seen:
                dupes.append({
                    "type": "expressions",
                    "id": str(entry.get("id", "")),
                    "term": term,
                    "duplicate_in": seen[term],
                })
            else:
                seen[term] = f"expressions:{entry.get('id', '')}"
        return dupes

    @staticmethod
    def export_resource_pack(adapter: Any, output_path: Path) -> Path:
        """Export all resource lists as a single JSON file (resource pack)."""
        output_path = Path(output_path)
        data = {
            "vocab": adapter.vocab,
            "expressions": adapter.expressions,
            "grammar_points": adapter.grammar_points,
        }
        output_path.write_text(
            json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        return output_path

    @staticmethod
    def import_resource_pack(
        adapter: Any, pack_path: Path, *, replace: bool = False
    ) -> dict[str, int]:
        """Import a resource pack JSON file, merging by id."""
        pack_path = Path(pack_path)
        data = json.loads(pack_path.read_text(encoding="utf-8"))
        counts = {"vocab": 0, "expressions": 0, "grammar_points": 0}
        mapping = {
            "vocab": adapter.vocab,
            "expressions": adapter.expressions,
            "grammar_points": adapter.grammar_points,
        }
        for key, target in mapping.items():
            incoming = data.get(key, [])
            if replace:
                target.clear()
                target.extend(incoming)
                counts[key] = len(incoming)
            else:
                existing_ids = {e.get("id") for e in target}
                added = 0
                for entry in incoming:
                    eid = entry.get("id")
                    if eid and eid not in existing_ids:
                        target.append(entry)
                        existing_ids.add(eid)
                        added += 1
                counts[key] = added
        if hasattr(adapter, "notify_resources_changed"):
            adapter.notify_resources_changed()
        return counts
