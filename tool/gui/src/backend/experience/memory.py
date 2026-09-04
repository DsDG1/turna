"""C-13 Experience Memory — session / project / author (pure Python).

Default: **in-memory only**. Optional disk for project (v4.58) and author
(v4.60) is host-gated via settings and **defaults off**.

Red lines (experienceai §6 / §14.5):
- Never store api_key / Authorization / full prompts
- Session clears with course lifecycle; session never disks
- Not a second undo stack (Timeline remains the UI event ring)
- No Qt
"""
from __future__ import annotations

import time
from collections import deque
from dataclasses import dataclass, field
from typing import Any, Mapping, Sequence
import logging
logger = logging.getLogger(__name__)


# Closed keys allowed on a recorded intent / skill entry.
_INTENT_KEYS = frozenset({"action_id", "label", "ts", "scope_keys", "source"})

# Substrings that must never appear as stored values (defense-in-depth).
_FORBIDDEN_SUBSTR = (
    "api_key",
    "apikey",
    "authorization",
    "bearer ",
    "sk-",
)


def _safe_str(value: Any, *, limit: int = 120) -> str:
    s = str(value or "").strip()
    if len(s) > limit:
        s = s[: limit - 1] + "…"
    low = s.lower()
    for bad in _FORBIDDEN_SUBSTR:
        if bad in low:
            return "[redacted]"
    return s


def _scope_keys(scope: Mapping[str, Any] | None) -> list[str]:
    """Keep only key names (ids only if short), never large payloads."""
    if not scope:
        return []
    out: list[str] = []
    try:
        for k, v in dict(scope).items():
            key = _safe_str(k, limit=40)
            if not key or key == "[redacted]":
                continue
            # Prefer ids as short anchors without dumping content.
            if key.endswith("_id") or key in (
                "section_id",
                "lesson_id",
                "item_id",
                "error_count",
            ):
                vs = _safe_str(v, limit=48)
                if vs and vs != "[redacted]":
                    out.append(f"{key}={vs}")
                else:
                    out.append(key)
            else:
                out.append(key)
            if len(out) >= 6:
                break
    except Exception:
        return []
    return out


@dataclass(frozen=True)
class IntentRecord:
    """One recent intent / skill dispatch (session layer)."""

    action_id: str
    label: str = ""
    ts: float = 0.0
    scope_keys: tuple[str, ...] = ()
    source: str = ""  # palette | dock | chip | soft | other

    def to_dict(self) -> dict[str, Any]:
        return {
            "action_id": self.action_id,
            "label": self.label,
            "ts": self.ts,
            "scope_keys": list(self.scope_keys),
            "source": self.source,
        }


class SessionMemory:
    """Process-local ring of recent intents; cleared on course close/switch."""

    def __init__(self, *, maxlen: int = 20) -> None:
        self._maxlen = max(1, int(maxlen))
        self._intents: deque[IntentRecord] = deque(maxlen=self._maxlen)
        self._last_surface: str = ""
        self._last_action_id: str = ""
        # R-07: per-lesson Surgeon style hints (session-only KV, no disk).
        self._lesson_styles: dict[str, list[str]] = {}

    def __len__(self) -> int:
        return len(self._intents)

    def clear(self) -> None:
        self._intents.clear()
        self._last_surface = ""
        self._last_action_id = ""
        self._lesson_styles.clear()

    def record_lesson_style(
        self, lesson_id: str, hint: str, *, limit: int = 4
    ) -> None:
        """R-07: remember one applied chip-rewrite instruction per lesson.

        Dedup keeps the newest position; ring capped at ``limit`` per lesson.
        Session-only (cleared on course close); values are ``_safe_str``
        sanitized/truncated — never secrets, never long bodies. Never raises.
        """
        try:
            lid = _safe_str(lesson_id, limit=80)
            if not lid or lid == "[redacted]":
                return
            h = _safe_str(hint, limit=80)
            if not h or h == "[redacted]":
                return
            hints = [x for x in self._lesson_styles.get(lid, []) if x != h]
            hints.append(h)
            self._lesson_styles[lid] = hints[-max(1, int(limit)) :]
        except Exception:
            logger.debug("backend/experience/memory.py:record_lesson_style best-effort step failed", exc_info=True)

    def lesson_style_hints(self, lesson_id: str) -> list[str]:
        """R-07: style hints recorded for one lesson (oldest first)."""
        try:
            lid = _safe_str(lesson_id, limit=80)
            return list(self._lesson_styles.get(lid, []))
        except Exception:
            return []

    def record_intent(
        self,
        action_id: str,
        *,
        label: str = "",
        scope: Mapping[str, Any] | None = None,
        source: str = "",
        ts: float | None = None,
    ) -> IntentRecord | None:
        """Append one intent. Returns None when action_id empty. Never raises."""
        try:
            aid = _safe_str(action_id, limit=80)
            if not aid or aid == "[redacted]":
                return None
            rec = IntentRecord(
                action_id=aid,
                label=_safe_str(label or aid, limit=80),
                ts=float(time.time() if ts is None else ts),
                scope_keys=tuple(_scope_keys(scope)),
                source=_safe_str(source, limit=24),
            )
            self._intents.append(rec)
            self._last_action_id = aid
            return rec
        except Exception:
            return None

    def set_last_surface(self, surface: str) -> None:
        try:
            self._last_surface = _safe_str(surface, limit=32)
        except Exception:
            self._last_surface = ""

    @property
    def last_surface(self) -> str:
        return self._last_surface

    @property
    def last_action_id(self) -> str:
        return self._last_action_id

    def recent_intents(self, n: int | None = None) -> list[IntentRecord]:
        """Newest last (same order as Timeline)."""
        items = list(self._intents)
        if n is None:
            return items
        n = max(0, int(n))
        return items[-n:] if n else []

    def recent_intent_dicts(self, n: int | None = None) -> list[dict[str, Any]]:
        return [r.to_dict() for r in self.recent_intents(n)]

    def snapshot(self) -> dict[str, Any]:
        """JSON-safe session snapshot for Context / debug."""
        return {
            "recent_intents": self.recent_intent_dicts(),
            "last_surface": self._last_surface,
            "last_action_id": self._last_action_id,
            "count": len(self._intents),
        }


def default_project_memory_dir() -> "Any":
    """tool/var/experience_memory under repo (never raises → None)."""
    try:
        from pathlib import Path

        return Path(__file__).resolve().parents[3] / "var" / "experience_memory"
    except Exception:
        return None


def project_memory_file(base_dir: Any, course_key: str) -> "Any":
    """Stable filename for one course_key (hash basename)."""
    try:
        from pathlib import Path
        import hashlib

        key = _safe_str(course_key, limit=64)
        if not key or key == "[redacted]":
            return None
        h = hashlib.sha256(key.encode("utf-8")).hexdigest()[:24]
        return Path(base_dir) / f"project_{h}.json"
    except Exception:
        return None


def save_project_snapshot(path: Any, snapshot: Mapping[str, Any] | None) -> bool:
    """Write closed project snapshot; never raises. Returns ok."""
    try:
        import json
        from pathlib import Path

        if not path or not snapshot:
            return False
        p = Path(path)
        p.parent.mkdir(parents=True, exist_ok=True)
        # Closed keys only
        payload = {
            "course_key": _safe_str(snapshot.get("course_key"), limit=64),
            "recent_skills": [
                _safe_str(x, limit=80)
                for x in list(snapshot.get("recent_skills") or [])[:24]
                if _safe_str(x, limit=80) not in ("", "[redacted]")
            ],
            "preferred_templates": [
                _safe_str(x, limit=40)
                for x in list(snapshot.get("preferred_templates") or [])[:12]
                if _safe_str(x, limit=40) not in ("", "[redacted]")
            ],
        }
        blob = json.dumps(payload, ensure_ascii=False, indent=0)
        low = blob.lower()
        for bad in _FORBIDDEN_SUBSTR:
            if bad in low:
                return False
        p.write_text(blob + "\n", encoding="utf-8")
        return True
    except Exception:
        return False


def load_project_snapshot(path: Any) -> dict[str, Any] | None:
    """Load closed project snapshot; never raises."""
    try:
        import json
        from pathlib import Path

        p = Path(path)
        if not p.is_file():
            return None
        data = json.loads(p.read_text(encoding="utf-8"))
        if not isinstance(data, dict):
            return None
        skills = [
            _safe_str(x, limit=80)
            for x in list(data.get("recent_skills") or [])[:24]
            if _safe_str(x, limit=80) not in ("", "[redacted]")
        ]
        templates = [
            _safe_str(x, limit=40)
            for x in list(data.get("preferred_templates") or [])[:12]
            if _safe_str(x, limit=40) not in ("", "[redacted]")
        ]
        return {
            "course_key": _safe_str(data.get("course_key"), limit=64),
            "recent_skills": skills,
            "preferred_templates": templates,
        }
    except Exception:
        return None


class ProjectMemory:
    """Per-course_key preferences (memory default; optional disk via host)."""

    def __init__(self) -> None:
        self._buckets: dict[str, dict[str, Any]] = {}
        self._active_key: str = ""
        self.persist_enabled: bool = False
        self.persist_dir: Any = None

    def clear_all(self) -> None:
        self._buckets.clear()
        self._active_key = ""

    def bind(self, course_key: str | None) -> None:
        """Switch active project bucket (empty key = unbound)."""
        key = _safe_str(course_key or "", limit=64)
        if key == "[redacted]":
            key = ""
        self._active_key = key
        if key and key not in self._buckets:
            self._buckets[key] = {
                "recent_skills": [],
                "preferred_templates": [],
            }
            self._maybe_load_disk(key)

    @property
    def active_key(self) -> str:
        return self._active_key

    def record_skill(self, action_id: str, *, limit: int = 12) -> None:
        if not self._active_key:
            return
        try:
            aid = _safe_str(action_id, limit=80)
            if not aid or aid == "[redacted]":
                return
            bucket = self._buckets.setdefault(
                self._active_key,
                {"recent_skills": [], "preferred_templates": []},
            )
            skills: list[str] = list(bucket.get("recent_skills") or [])
            skills = [s for s in skills if s != aid]
            skills.append(aid)
            bucket["recent_skills"] = skills[-max(1, int(limit)) :]
            self._maybe_save_disk()
        except Exception:
            logger.debug("backend/experience/memory.py:record_skill best-effort step failed", exc_info=True)

    def snapshot(self) -> dict[str, Any] | None:
        if not self._active_key:
            return None
        bucket = self._buckets.get(self._active_key) or {}
        return {
            "course_key": self._active_key,
            "recent_skills": list(bucket.get("recent_skills") or []),
            "preferred_templates": list(bucket.get("preferred_templates") or []),
        }

    def configure_persist(
        self, *, enabled: bool = False, base_dir: Any = None
    ) -> None:
        """Enable/disable optional project disk (host wires settings)."""
        self.persist_enabled = bool(enabled)
        self.persist_dir = base_dir if base_dir is not None else default_project_memory_dir()

    def _maybe_load_disk(self, key: str) -> None:
        if not self.persist_enabled or not key:
            return
        try:
            path = project_memory_file(self.persist_dir, key)
            data = load_project_snapshot(path)
            if not data:
                return
            self._buckets[key] = {
                "recent_skills": list(data.get("recent_skills") or []),
                "preferred_templates": list(data.get("preferred_templates") or []),
            }
        except Exception:
            logger.debug("backend/experience/memory.py:_maybe_load_disk best-effort step failed", exc_info=True)

    def _maybe_save_disk(self) -> None:
        if not self.persist_enabled or not self._active_key:
            return
        try:
            path = project_memory_file(self.persist_dir, self._active_key)
            save_project_snapshot(path, self.snapshot())
        except Exception:
            logger.debug("backend/experience/memory.py:_maybe_save_disk best-effort step failed", exc_info=True)


def author_memory_file(base_dir: Any) -> "Any":
    """Stable path for cross-course author profile (single file)."""
    try:
        from pathlib import Path

        if base_dir is None:
            return None
        return Path(base_dir) / "author.json"
    except Exception:
        return None


def save_author_snapshot(path: Any, snapshot: Mapping[str, Any] | None) -> bool:
    """Write closed author snapshot; never raises. Returns ok."""
    try:
        import json
        from pathlib import Path

        if not path:
            return False
        # Empty profile → remove file when possible (privacy-friendly).
        if not snapshot:
            try:
                p = Path(path)
                if p.is_file():
                    p.unlink()
            except Exception:
                logger.debug("backend/experience/memory.py:save_author_snapshot best-effort step failed", exc_info=True)
            return True
        p = Path(path)
        p.parent.mkdir(parents=True, exist_ok=True)
        hints = [
            _safe_str(x, limit=80)
            for x in list(snapshot.get("style_hints") or [])[:8]
            if _safe_str(x, limit=80) not in ("", "[redacted]")
        ]
        prefs_raw = snapshot.get("language_prefs") or {}
        prefs: dict[str, str] = {}
        if isinstance(prefs_raw, Mapping):
            for k, v in list(prefs_raw.items())[:16]:
                sk = _safe_str(k, limit=32)
                sv = _safe_str(v, limit=32)
                if sk and sk != "[redacted]" and sv and sv != "[redacted]":
                    prefs[sk] = sv
        payload = {
            "style_hints": hints,
            "language_prefs": prefs,
        }
        if not hints and not prefs:
            try:
                if p.is_file():
                    p.unlink()
            except Exception:
                logger.debug("backend/experience/memory.py:save_author_snapshot best-effort step failed", exc_info=True)
            return True
        blob = json.dumps(payload, ensure_ascii=False, indent=0)
        low = blob.lower()
        for bad in _FORBIDDEN_SUBSTR:
            if bad in low:
                return False
        p.write_text(blob + "\n", encoding="utf-8")
        return True
    except Exception:
        return False


def load_author_snapshot(path: Any) -> dict[str, Any] | None:
    """Load closed author snapshot; never raises."""
    try:
        import json
        from pathlib import Path

        p = Path(path)
        if not p.is_file():
            return None
        data = json.loads(p.read_text(encoding="utf-8"))
        if not isinstance(data, dict):
            return None
        hints = [
            _safe_str(x, limit=80)
            for x in list(data.get("style_hints") or [])[:8]
            if _safe_str(x, limit=80) not in ("", "[redacted]")
        ]
        prefs: dict[str, str] = {}
        raw = data.get("language_prefs") or {}
        if isinstance(raw, Mapping):
            for k, v in list(raw.items())[:16]:
                sk = _safe_str(k, limit=32)
                sv = _safe_str(v, limit=32)
                if sk and sk != "[redacted]" and sv and sv != "[redacted]":
                    prefs[sk] = sv
        if not hints and not prefs:
            return None
        return {"style_hints": hints, "language_prefs": prefs}
    except Exception:
        return None


class AuthorMemory:
    """Cross-course author profile (clearable; optional disk v4.60, default off)."""

    def __init__(self) -> None:
        self._style_hints: list[str] = []
        self._language_prefs: dict[str, str] = {}
        self.persist_enabled: bool = False
        self.persist_dir: Any = None

    def clear(self) -> None:
        self._style_hints.clear()
        self._language_prefs.clear()
        self._maybe_delete_disk()

    def set_language_pref(self, key: str, value: str) -> None:
        k = _safe_str(key, limit=32)
        if not k or k == "[redacted]":
            return
        self._language_prefs[k] = _safe_str(value, limit=32)
        self._maybe_save_disk()

    def add_style_hint(self, hint: str, *, limit: int = 8) -> None:
        h = _safe_str(hint, limit=80)
        if not h or h == "[redacted]":
            return
        hints = [x for x in self._style_hints if x != h]
        hints.append(h)
        self._style_hints = hints[-max(1, int(limit)) :]
        self._maybe_save_disk()

    def snapshot(self) -> dict[str, Any] | None:
        if not self._style_hints and not self._language_prefs:
            return None
        return {
            "style_hints": list(self._style_hints),
            "language_prefs": dict(self._language_prefs),
        }

    def configure_persist(
        self, *, enabled: bool = False, base_dir: Any = None
    ) -> None:
        """Enable/disable optional author disk (host wires settings)."""
        was = self.persist_enabled
        self.persist_enabled = bool(enabled)
        self.persist_dir = (
            base_dir if base_dir is not None else default_project_memory_dir()
        )
        # Turning on: load disk into empty memory; do not clobber live data
        # if already populated this session.
        if self.persist_enabled and not was:
            self._maybe_load_disk(prefer_existing=True)
        # Turning off: leave memory as-is; do not delete file (user may re-enable).

    def _maybe_load_disk(self, *, prefer_existing: bool = True) -> None:
        if not self.persist_enabled:
            return
        if prefer_existing and (self._style_hints or self._language_prefs):
            return
        try:
            path = author_memory_file(self.persist_dir)
            data = load_author_snapshot(path)
            if not data:
                return
            self._style_hints = list(data.get("style_hints") or [])
            prefs = data.get("language_prefs") or {}
            self._language_prefs = dict(prefs) if isinstance(prefs, Mapping) else {}
        except Exception:
            logger.debug("backend/experience/memory.py:_maybe_load_disk best-effort step failed", exc_info=True)

    def _maybe_save_disk(self) -> None:
        if not self.persist_enabled:
            return
        try:
            path = author_memory_file(self.persist_dir)
            save_author_snapshot(path, self.snapshot())
        except Exception:
            logger.debug("backend/experience/memory.py:_maybe_save_disk best-effort step failed", exc_info=True)

    def _maybe_delete_disk(self) -> None:
        """Unlink author.json when clearing (only if persist path known)."""
        try:
            path = author_memory_file(
                self.persist_dir
                if self.persist_dir is not None
                else default_project_memory_dir()
            )
            if path is None:
                return
            from pathlib import Path

            p = Path(path)
            if p.is_file():
                p.unlink()
        except Exception:
            logger.debug("backend/experience/memory.py:_maybe_delete_disk best-effort step failed", exc_info=True)


@dataclass
class ExperienceMemory:
    """Facade over session / project / author layers."""

    session: SessionMemory = field(default_factory=lambda: SessionMemory(maxlen=20))
    project: ProjectMemory = field(default_factory=ProjectMemory)
    author: AuthorMemory = field(default_factory=AuthorMemory)

    def clear_session(self) -> None:
        """Course close / switch — session only."""
        self.session.clear()

    def clear_author(self) -> bool:
        """M-07: clear cross-course author profile only.

        Returns True when there was data to clear. Does not touch session
        intents or project buckets. Never raises.
        """
        try:
            had = self.author.snapshot() is not None
            self.author.clear()
            return bool(had)
        except Exception:
            try:
                self.author.clear()
            except Exception:
                logger.debug("backend/experience/memory.py:clear_author best-effort step failed", exc_info=True)
            return False

    def clear_all(self) -> None:
        self.session.clear()
        self.project.clear_all()
        self.author.clear()

    def record_intent(
        self,
        action_id: str,
        *,
        label: str = "",
        scope: Mapping[str, Any] | None = None,
        source: str = "",
    ) -> IntentRecord | None:
        rec = self.session.record_intent(
            action_id, label=label, scope=scope, source=source
        )
        if rec is not None:
            try:
                self.project.record_skill(rec.action_id)
            except Exception:
                logger.debug("backend/experience/memory.py:record_intent best-effort step failed", exc_info=True)
        return rec

    def record_lesson_style(
        self, lesson_id: str, hint: str, *, limit: int = 4
    ) -> None:
        """R-07: session-layer per-lesson Surgeon style memory."""
        try:
            self.session.record_lesson_style(lesson_id, hint, limit=limit)
        except Exception:
            logger.debug("backend/experience/memory.py:record_lesson_style best-effort step failed", exc_info=True)

    def lesson_style_hints(self, lesson_id: str) -> list[str]:
        """R-07: style hints for one lesson; empty on any failure."""
        try:
            return self.session.lesson_style_hints(lesson_id)
        except Exception:
            return []

    def configure_project_persist(
        self, *, enabled: bool = False, base_dir: Any = None
    ) -> None:
        """C-13 v4.58: optional ProjectMemory disk (host wires settings)."""
        try:
            self.project.configure_persist(enabled=enabled, base_dir=base_dir)
        except Exception:
            logger.debug("backend/experience/memory.py:configure_project_persist best-effort step failed", exc_info=True)

    def configure_author_persist(
        self, *, enabled: bool = False, base_dir: Any = None
    ) -> None:
        """C-13 v4.60: optional AuthorMemory disk (host wires settings)."""
        try:
            self.author.configure_persist(enabled=enabled, base_dir=base_dir)
        except Exception:
            logger.debug("backend/experience/memory.py:configure_author_persist best-effort step failed", exc_info=True)

    def bind_course(self, course_dir: Any | None) -> None:
        """Bind project bucket using C-15 course_key when possible."""
        try:
            if course_dir is None:
                self.project.bind(None)
                return
            from src.backend.experience.metrics import course_attribution

            attr = course_attribution(course_dir)
            key = ""
            if isinstance(attr, Mapping):
                key = str(attr.get("course_key") or attr.get("course_name") or "")
            if not key:
                key = _safe_str(course_dir, limit=64)
            self.project.bind(key or None)
        except Exception:
            try:
                self.project.bind(_safe_str(course_dir, limit=64) or None)
            except Exception:
                self.project.bind(None)

    def context_fields(self) -> dict[str, Any]:
        """Fields to inject into ExperienceContext."""
        return {
            "recent_intents": self.session.recent_intent_dicts(),
            "author_profile": self.author.snapshot(),
        }

    def snapshot(self) -> dict[str, Any]:
        return {
            "session": self.session.snapshot(),
            "project": self.project.snapshot(),
            "author": self.author.snapshot(),
        }


def format_author_profile_line(profile: Mapping[str, Any] | None) -> str:
    """Dock one-liner for author profile — counts only, never hint text.

    Empty profile → ``\"\"``. Never raises. §14.5.3: style_hints body must
    not appear in the returned string (only counts / labels).
    """
    try:
        if not profile or not isinstance(profile, Mapping):
            return ""
        hints = profile.get("style_hints") or []
        prefs = profile.get("language_prefs") or {}
        n_hints = len(hints) if isinstance(hints, (list, tuple)) else 0
        n_prefs = len(prefs) if isinstance(prefs, Mapping) else 0
        if n_hints <= 0 and n_prefs <= 0:
            return ""
        parts: list[str] = []
        if n_hints > 0:
            parts.append(f"{n_hints} 条风格提示")
        if n_prefs > 0:
            parts.append(f"{n_prefs} 项语言偏好")
        return "画像 · " + " · ".join(parts)
    except Exception:
        return ""


def assert_no_secrets(payload: Mapping[str, Any] | Sequence[Any] | None) -> bool:
    """Return True when no forbidden substrings appear in a JSON-ish tree."""
    try:
        if payload is None:
            return True
        if isinstance(payload, Mapping):
            for k, v in payload.items():
                if not assert_no_secrets(str(k)):
                    return False
                if not assert_no_secrets(v):  # type: ignore[arg-type]
                    return False
            return True
        if isinstance(payload, (list, tuple)):
            return all(assert_no_secrets(x) for x in payload)  # type: ignore[arg-type]
        low = str(payload).lower()
        return not any(bad in low for bad in _FORBIDDEN_SUBSTR)
    except Exception:
        return False
