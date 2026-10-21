"""Persistence for course plans (P0-2).

Plans are small, human-editable JSON files under ``tool/var/course_plans``
(already git-ignored). They are deliberately separate from ``project.json``:
a plan can outlive one workshop project and should never bump
``TextbookProject.PROJECT_VERSION``.

Writes are atomic (temp file + ``os.replace``) so a crash cannot leave a
truncated plan behind. Reads tolerate missing/corrupt files and return ``None``.
"""
from __future__ import annotations

import json
import os
import re
import shutil
import uuid
from datetime import datetime
from pathlib import Path
from typing import Any

from src.backend.ai.course_plan import CoursePlan

_PLAN_FILE = "plan.json"
_SAFE_RE = re.compile(r"[^\w\-]+")


def _now() -> str:
    return datetime.now().isoformat(timespec="seconds")


def _safe_name(text: str) -> str:
    safe = _SAFE_RE.sub("_", str(text or "")).strip("_")[:40]
    return safe or "course"


class CoursePlanStore:
    """CRUD for course plans on the local filesystem."""

    def __init__(self, base_dir: Path | None = None) -> None:
        if base_dir is None:
            # tool/gui/src/backend -> tool/var/course_plans (see .gitignore:
            # ``tool/var/`` is ignored; this matches TextbookProjectStore).
            base_dir = Path(__file__).resolve().parents[3] / "var" / "course_plans"
        self.base_dir = Path(base_dir)
        self.base_dir.mkdir(parents=True, exist_ok=True)

    def plan_dir(self, plan_id: str) -> Path:
        return self.base_dir / str(plan_id)

    def plan_file(self, plan_id: str) -> Path:
        return self.plan_dir(plan_id) / _PLAN_FILE

    def draft_dir(self, plan_id: str) -> Path:
        return self.plan_dir(plan_id) / "drafts"

    def draft_file(self, plan_id: str, section_id: str) -> Path:
        return self.draft_dir(plan_id) / f"{_safe_name(section_id)}.json"

    def save_plan(self, plan: CoursePlan) -> str:
        """Persist *plan* and return its id (generated on first save)."""
        if not plan.plan_id:
            plan.plan_id = f"{_safe_name(plan.title)}_{uuid.uuid4().hex[:8]}"
        if not plan.created_at:
            plan.created_at = _now()
        plan.updated_at = _now()

        target_dir = self.plan_dir(plan.plan_id)
        target_dir.mkdir(parents=True, exist_ok=True)
        path = target_dir / _PLAN_FILE
        tmp = target_dir / (_PLAN_FILE + ".tmp")
        payload = json.dumps(plan.to_dict(), ensure_ascii=False, indent=2)
        tmp.write_text(payload, encoding="utf-8")
        os.replace(tmp, path)
        return plan.plan_id

    def load_plan(self, plan_id: str) -> CoursePlan | None:
        """Load one plan; returns ``None`` for missing or corrupt files."""
        path = self.plan_file(plan_id)
        if not path.is_file():
            return None
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return None
        if not isinstance(data, dict):
            return None
        plan = CoursePlan.from_dict(data)
        if not plan.plan_id:
            plan.plan_id = str(plan_id)
        return plan

    def save_draft(
        self, plan_id: str, section_id: str, draft: dict[str, Any]
    ) -> Path:
        """Persist one generated section draft; never touches the course."""
        directory = self.draft_dir(plan_id)
        directory.mkdir(parents=True, exist_ok=True)
        path = self.draft_file(plan_id, section_id)
        tmp = path.with_suffix(path.suffix + ".tmp")
        tmp.write_text(
            json.dumps(draft, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        os.replace(tmp, path)
        return path

    def load_draft(self, plan_id: str, section_id: str) -> dict[str, Any] | None:
        path = self.draft_file(plan_id, section_id)
        if not path.is_file():
            return None
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return None
        return data if isinstance(data, dict) else None

    def delete_draft(self, plan_id: str, section_id: str) -> bool:
        path = self.draft_file(plan_id, section_id)
        try:
            path.unlink()
        except FileNotFoundError:
            return False
        except OSError:
            return False
        return True

    def has_draft(self, plan_id: str, section_id: str) -> bool:
        return self.draft_file(plan_id, section_id).is_file()

    def list_summaries(self) -> list[dict[str, Any]]:
        """Lightweight rows for a plan picker, newest first."""
        rows: list[dict[str, Any]] = []
        if not self.base_dir.is_dir():
            return rows
        for child in self.base_dir.iterdir():
            if not child.is_dir():
                continue
            plan = self.load_plan(child.name)
            if plan is None:
                continue
            rows.append(
                {
                    "plan_id": plan.plan_id,
                    "title": plan.title,
                    "course_dir": plan.course_dir,
                    "section_count": len(plan.sections),
                    "word_count": len(plan.lexicon),
                    "level_from": plan.spec.level_from,
                    "level_to": plan.spec.level_to,
                    "updated_at": plan.updated_at,
                }
            )
        rows.sort(key=lambda row: str(row.get("updated_at") or ""), reverse=True)
        return rows

    def delete_plan(self, plan_id: str) -> bool:
        """Delete one plan directory. Only ever removes beneath ``base_dir``."""
        target = self.plan_dir(plan_id).resolve()
        root = self.base_dir.resolve()
        if target == root or root not in target.parents:
            return False
        if not target.is_dir():
            return False
        try:
            shutil.rmtree(target)
        except OSError:
            return False
        return True
