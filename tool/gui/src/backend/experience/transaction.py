"""Transaction snapshot and pre/post-flight verification service (E2.0).

Pure Python, no Qt, no disk writes, never raises.
Protects Set C dangerous actions (regenerate, batch regenerate, batch set template)
from partial writes, concurrent node deletion, and ghost overwriting.
"""
from __future__ import annotations

import copy
from dataclasses import dataclass
import hashlib
import logging
import time
from typing import Any

logger = logging.getLogger(__name__)


def _compute_fingerprint(data: Any) -> str:
    """Compute a lightweight deterministic fingerprint for a node or section dict."""
    try:
        if not isinstance(data, dict):
            return ""
        nid = str(data.get("id") or "")
        name = str(data.get("name") or "")
        content_len = len(str(data.get("content") or ""))
        items_count = 0
        stages = (data.get("content") or {}).get("stages") or []
        if isinstance(stages, list):
            for st in stages:
                if isinstance(st, dict):
                    items_count += len(st.get("items") or [])
        units_count = len(data.get("units") or [])
        lessons_count = len(data.get("lessons") or [])
        raw = f"{nid}|{name}|{content_len}|{items_count}|{units_count}|{lessons_count}"
        return hashlib.sha256(raw.encode("utf-8", errors="replace")).hexdigest()[:16]
    except Exception:
        return ""


@dataclass(frozen=True)
class TransactionSnapshot:
    """An in-memory snapshot of course sections before a dangerous AI operation."""

    transaction_id: str
    action_id: str
    created_at: float
    affected_sections: dict[str, dict[str, Any]]
    node_fingerprints: dict[str, str]
    node_keys: tuple[str, ...]

    def summary(self) -> str:
        return (
            f"Transaction[{self.transaction_id[:8]}] {self.action_id} "
            f"sections={list(self.affected_sections.keys())} "
            f"nodes={len(self.node_keys)}"
        )


def create_transaction_snapshot(
    adapter: Any,
    action_id: str,
    node_keys: list[str] | tuple[str, ...] | None = None,
) -> TransactionSnapshot:
    """Create a non-destructive snapshot of the affected sections and nodes.

    Never raises. Returns an empty snapshot if adapter is invalid.
    """
    node_keys = tuple(str(k or "").strip() for k in (node_keys or []) if str(k or "").strip())
    tx_id = f"tx_{int(time.time() * 1000)}_{len(node_keys)}"
    empty = TransactionSnapshot(
        transaction_id=tx_id,
        action_id=action_id,
        created_at=time.time(),
        affected_sections={},
        node_fingerprints={},
        node_keys=node_keys,
    )
    if adapter is None:
        return empty

    affected_sections: dict[str, dict[str, Any]] = {}
    fingerprints: dict[str, str] = {}

    try:
        raw_sections = getattr(adapter, "sections", None)
        sections = [s for s in raw_sections if isinstance(s, dict)] if isinstance(raw_sections, list) else []
        for key in node_keys:
            parts = key.split(":", 1)
            kind = parts[0]
            nid = parts[1] if len(parts) > 1 else ""
            if not nid:
                continue

            sec_dict: dict[str, Any] | None = None
            node_dict: dict[str, Any] | None = None

            if kind == "section":
                for s in sections:
                    if str(s.get("id") or "") == nid:
                        sec_dict = s
                        node_dict = s
                        break
            elif kind == "unit":
                try:
                    sec_dict, node_dict = adapter.find_unit(nid)
                except Exception as exc:
                    logger.debug("transaction.py find_unit best-effort step failed: %s", exc)
            elif kind == "lesson":
                try:
                    sec_dict, _u, node_dict = adapter.find_lesson(nid)
                except Exception as exc:
                    logger.debug("transaction.py find_lesson best-effort step failed: %s", exc)

            if sec_dict is not None and isinstance(sec_dict, dict):
                sid = str(sec_dict.get("id") or "")
                if sid and sid not in affected_sections:
                    affected_sections[sid] = copy.deepcopy(sec_dict)
            if node_dict is not None and isinstance(node_dict, dict):
                fingerprints[key] = _compute_fingerprint(node_dict)

        # If no specific nodes resolved but we have sections, snapshot all as fallback
        if not affected_sections and sections:
            for s in sections:
                sid = str(s.get("id") or "")
                if sid:
                    affected_sections[sid] = copy.deepcopy(s)

        return TransactionSnapshot(
            transaction_id=tx_id,
            action_id=action_id,
            created_at=time.time(),
            affected_sections=affected_sections,
            node_fingerprints=fingerprints,
            node_keys=node_keys,
        )
    except Exception as exc:
        logger.debug("create_transaction_snapshot best-effort step failed: %s", exc, exc_info=True)
        return empty


def verify_transaction_integrity(
    adapter: Any,
    snapshot: TransactionSnapshot,
) -> tuple[bool, str]:
    """Verify that nodes targeted by the transaction have not been deleted or mutated.

    Returns (True, "") if intact, or (False, reason) if integrity check fails.
    Never raises.
    """
    if adapter is None or not snapshot.affected_sections:
        return True, ""

    try:
        raw_sections = getattr(adapter, "sections", None)
        sections = [s for s in raw_sections if isinstance(s, dict)] if isinstance(raw_sections, list) else []
        section_ids = {str(s.get("id") or "") for s in sections}

        if sections:
            for sid in snapshot.affected_sections:
                if sid not in section_ids:
                    return False, f"所属章节 [{sid}] 已被删除或移除"

        for key in snapshot.node_keys:
            parts = key.split(":", 1)
            kind = parts[0]
            nid = parts[1] if len(parts) > 1 else ""
            if not nid:
                continue

            node_dict: dict[str, Any] | None = None
            if kind == "section":
                for s in sections:
                    if str(s.get("id") or "") == nid:
                        node_dict = s
                        break
            elif kind == "unit":
                try:
                    _s, node_dict = adapter.find_unit(nid)
                except Exception as exc:
                    logger.debug("verify_transaction_integrity find_unit error: %s", exc)
                    node_dict = None
            elif kind == "lesson":
                try:
                    _s, _u, node_dict = adapter.find_lesson(nid)
                except Exception as exc:
                    logger.debug("verify_transaction_integrity find_lesson error: %s", exc)
                    node_dict = None

            if node_dict is None or not isinstance(node_dict, dict):
                return False, f"目标节点 [{key}] 在生成期间已被删除或移动"

            expected_fp = snapshot.node_fingerprints.get(key)
            if expected_fp:
                cur_fp = _compute_fingerprint(node_dict)
                if cur_fp != expected_fp:
                    return False, f"目标节点 [{key}] 在生成期间已被外部修改（指纹不一致）"

        return True, ""
    except Exception as exc:
        logger.debug("verify_transaction_integrity best-effort check failed: %s", exc, exc_info=True)
        return True, ""


def rollback_transaction(adapter: Any, snapshot: TransactionSnapshot) -> bool:
    """Atomically restore affected sections from the snapshot.

    Never raises. Returns True if restored successfully, False otherwise.
    """
    if adapter is None or not snapshot.affected_sections:
        return False

    try:
        sections = getattr(adapter, "sections", None)
        if not isinstance(sections, list):
            return False

        restored_any = False
        for i, current_sec in enumerate(list(sections)):
            if not isinstance(current_sec, dict):
                continue
            sid = str(current_sec.get("id") or "")
            if sid in snapshot.affected_sections:
                sections[i] = copy.deepcopy(snapshot.affected_sections[sid])
                restored_any = True

        if restored_any:
            if hasattr(adapter, "invalidate_node_index"):
                adapter.invalidate_node_index()
            if hasattr(adapter, "notify_resources_changed"):
                adapter.notify_resources_changed()
            return True
        return False
    except Exception as exc:
        logger.debug("rollback_transaction best-effort step failed: %s", exc, exc_info=True)
        return False
