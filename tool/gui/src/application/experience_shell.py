"""Experience shell coordinator (E0): rebuild Context + push to UI.

Owns the live :class:`ExperienceContext` for the main window. Pure rebuild
logic stays in ``backend/experience``; this module only schedules refreshes
and emits Qt signals so Dock / StatusStrip can bind without knowing adapter
internals.
"""
from __future__ import annotations

from typing import Any, Mapping, Sequence

from PySide6.QtCore import QObject, QTimer, Signal

from src.backend.experience import (
    ExperienceContext,
    NodeRef,
    build_experience_context,
    local_suggestions,
    normalize_node,
)


def format_health_status_line(ctx: ExperienceContext | None) -> str:
    """One-line health summary for the status bar."""
    if ctx is None:
        return "未加载课程"
    if ctx.healthy:
        return f"健康 · {ctx.lesson_count} 课 · {ctx.section_count} 节"
    parts: list[str] = []
    if ctx.empty_lesson_count:
        parts.append(f"空课 {ctx.empty_lesson_count}")
    if ctx.validate_error_count:
        parts.append(f"错 {ctx.validate_error_count}")
    if ctx.validate_warning_count:
        parts.append(f"警 {ctx.validate_warning_count}")
    ph = int(ctx.hygiene.get("placeholder_count") or 0)
    nr = int(ctx.hygiene.get("needs_review_count") or 0)
    if ph:
        parts.append(f"待补 {ph}")
    if nr:
        parts.append(f"审 {nr}")
    if not parts:
        parts.append(f"{ctx.lesson_count} 课")
    return " · ".join(parts)


class ExperienceShell(QObject):
    """Debounced Context rebuild hub for MainWindow.

    Signals
    -------
    context_changed:
        Emits the new :class:`ExperienceContext` after each rebuild.
    status_line_changed:
        Emits :func:`format_health_status_line` text for the status strip.
    """

    context_changed = Signal(object)
    status_line_changed = Signal(str)

    def __init__(self, parent: QObject | None = None, *, debounce_ms: int = 120) -> None:
        super().__init__(parent)
        self._adapter: Any = None
        self._selection: NodeRef | tuple[str, str] | None = None
        self._multi: list[NodeRef | tuple[str, str]] = []
        self._pinned: list[NodeRef | tuple[str, str]] = []
        self._surface: str = "tree"
        self._validate_problems: list[dict[str, Any]] | None = None
        # G2: quality is on by default (section-level cache in context_bus
        # keeps it cheap); set_include_quality(False) is the escape hatch.
        self._include_quality: bool = True
        self._include_hygiene: bool = True
        # S-07: snapshots from JobTray (list[dict]); empty when idle.
        self._active_jobs: list[Any] = []
        # C-14: optional callable returning a metrics snapshot dict (or None),
        # injected into ExperienceContext.metrics alongside active_jobs.
        self._metrics_provider: Any = None
        # C-15: AI usage today (ints) from telemetry.usage_summary alignment.
        self._usage_today: dict[str, int] = {}
        # E5 / M3: workshop draft snapshot (JSON-safe dict or None).
        self._workshop_draft: dict[str, Any] | None = None
        # C-13: recent intents + author profile from ExperienceMemory.
        self._recent_intents: list[Any] = []
        self._author_profile: dict[str, Any] | None = None
        # E4 / M-01: closed-shape attachment summaries (raw content never enters).
        self._attachments: list[dict[str, Any]] = []
        # M-03 v4.42: OCR switch hint for Dock P2 suggestion (default off).
        self._ocr_enabled: bool = False
        self._ctx: ExperienceContext | None = None
        self._suggestions: list[dict[str, Any]] = []
        # A3 ③: content-stale flag - set by mark_stale() on edit commits so the
        # heartbeat knows a full rebuild is pending (vs a focus-only refresh).
        self._content_stale: bool = False

        self._timer = QTimer(self)
        self._timer.setSingleShot(True)
        self._timer.setInterval(max(0, int(debounce_ms)))
        self._timer.timeout.connect(self._rebuild_now)

    # --- public state -----------------------------------------------------

    @property
    def context(self) -> ExperienceContext | None:
        return self._ctx

    @property
    def suggestions(self) -> list[dict[str, Any]]:
        return list(self._suggestions)

    def set_adapter(self, adapter: Any | None) -> None:
        self._adapter = adapter
        if adapter is None:
            self._ctx = None
            self._suggestions = []
            self._pinned = []
            self._selection = None
            self._multi = []
            self._active_jobs = []
            self._workshop_draft = None
            self._recent_intents = []
            self._author_profile = None
            self._attachments = []
            self.context_changed.emit(None)
            self.status_line_changed.emit(format_health_status_line(None))

    def set_selection(
        self,
        selection: NodeRef | tuple[str, str] | None,
        *,
        multi: Sequence[NodeRef | tuple[str, str]] | None = None,
    ) -> None:
        self._selection = selection
        if multi is not None:
            self._multi = list(multi)

    @property
    def pinned_refs(self) -> list[NodeRef | tuple[str, str]]:
        return list(self._pinned)

    def set_pinned(
        self, refs: Sequence[NodeRef | tuple[str, str]] | None
    ) -> None:
        """Replace pinned refs (S-14). Survives selection changes until clear."""
        self._pinned = list(refs or [])

    def clear_pinned(self) -> None:
        self._pinned = []

    def toggle_pin_selection(self) -> bool:
        """Pin current selection if not pinned; else unpin it.

        Returns True when the selection is pinned after the call.
        """
        if self._selection is None:
            return False
        key = self._ref_key(self._selection)
        existing = [self._ref_key(r) for r in self._pinned]
        if key in existing:
            self._pinned = [
                r for r in self._pinned if self._ref_key(r) != key
            ]
            return False
        # Cap at 3 pins (experienceai scope limit).
        self._pinned = (self._pinned + [self._selection])[-3:]
        return True

    @staticmethod
    def _ref_key(ref: NodeRef | tuple[str, str]) -> tuple[str, str]:
        if isinstance(ref, NodeRef):
            return (ref.kind, ref.id)
        if isinstance(ref, (tuple, list)) and len(ref) >= 2:
            return (str(ref[0]), str(ref[1]))
        return ("", str(ref))

    def set_surface(self, surface: str) -> None:
        self._surface = surface or "tree"

    def set_validate_problems(
        self, problems: Sequence[Mapping[str, Any]] | None
    ) -> None:
        if problems is None:
            self._validate_problems = None
        else:
            self._validate_problems = [dict(p) for p in problems]

    def set_include_quality(self, enabled: bool) -> None:
        self._include_quality = bool(enabled)

    def set_active_jobs(self, jobs: Sequence[Any] | None) -> None:
        """S-07: feed JobTray snapshots into the next Context rebuild."""
        self._active_jobs = list(jobs or [])

    def set_metrics_provider(self, provider: Any) -> None:
        """C-14: set a no-arg callable returning a metrics snapshot dict/None.

        Called on every rebuild to fill ``ExperienceContext.metrics``. Pass
        ``None`` to disable. The provider must be total (never raise); a
        raising provider is treated as no metrics.
        """
        self._metrics_provider = provider

    def set_usage_today(self, usage: Mapping[str, int] | None) -> None:
        """C-15: inject telemetry/ai_usage today bucket into next Context rebuild."""
        try:
            self._usage_today = {
                str(k): int(v or 0) for k, v in dict(usage or {}).items()
            }
        except Exception:
            self._usage_today = {}

    def set_workshop_draft(self, draft: Mapping[str, Any] | None) -> None:
        """E5/M3: inject workshop draft snapshot into the next Context rebuild.

        Pass ``None`` to clear (idle workshop / course close). Values are
        normalized to the closed key set; invalid input becomes None.
        """
        if draft is None:
            self._workshop_draft = None
            return
        try:
            from src.backend.experience.workshop_draft import normalize_workshop_draft

            self._workshop_draft = normalize_workshop_draft(dict(draft))
        except Exception:
            self._workshop_draft = None

    def set_recent_intents(self, intents: Sequence[Any] | None) -> None:
        """C-13: inject SessionMemory recent intents into next rebuild."""
        try:
            self._recent_intents = list(intents or [])
        except Exception:
            self._recent_intents = []

    def set_attachments(self, items: Sequence[Any] | None) -> None:
        """E4/M-01: inject attachment summary snapshots into the next rebuild.

        Values are normalized to the closed key set (raw content never
        enters); invalid input becomes an empty list. Pass ``None`` to clear.
        """
        if items is None:
            self._attachments = []
            return
        try:
            from src.backend.experience.attachments import normalize_attachments

            self._attachments = normalize_attachments(list(items))
        except Exception:
            self._attachments = []

    def set_ocr_enabled(self, enabled: bool) -> None:
        """M-03 v4.42: gate the Dock OCR P2 suggestion (switch hint only).

        Does not trigger a rebuild; the caller (app) follows up with
        ``_refresh_experience`` when the toggle changes at runtime. Default off.
        """
        self._ocr_enabled = bool(enabled)

    def set_author_profile(self, profile: Mapping[str, Any] | None) -> None:
        """C-13: inject AuthorMemory snapshot (or None when empty)."""
        if profile is None:
            self._author_profile = None
            return
        try:
            self._author_profile = dict(profile)
        except Exception:
            self._author_profile = None

    # --- rebuild ----------------------------------------------------------

    def invalidate(self, *, immediate: bool = False) -> None:
        """Schedule (or immediately run) a context rebuild."""
        if immediate or self._timer.interval() == 0:
            self._timer.stop()
            self._rebuild_now()
            return
        self._timer.start()

    def mark_stale(self) -> None:
        """A3 ③: flag content as stale and schedule a full rebuild.

        Used by edit-commit triggers (resource row / lesson metadata / item
        undo) so the heartbeat can distinguish a pending full rebuild from a
        focus-only refresh. Equivalent to ``invalidate`` but sets the stale
        flag so the next heartbeat tick prioritises a full rebuild.
        """
        self._content_stale = True
        if self._timer.interval() == 0:
            self._timer.stop()
            self._rebuild_now()
            return
        self._timer.start()

    def rebuild_now(self) -> ExperienceContext | None:
        """Force a synchronous rebuild and return the context."""
        self._timer.stop()
        self._rebuild_now()
        return self._ctx

    def invalidate_focus(self) -> None:
        """C-03: focus-only fast path — mutate the retained ``_ctx`` in place.

        Used when only focus state changed (selection / multi-selection / pin
        / surface / active_jobs / metrics). Skips the full
        ``build_experience_context`` pipeline (no ``_scan_structure`` /
        ``_course_hygiene`` / ``_quality_by_section`` / ``_resolve_validate``),
        so structure-derived fields (empty_lessons, counts, hygiene,
        quality_by_section, validate_*, listening_gaps, node_badges) are
        preserved from the last full rebuild.

        Falls back to a full rebuild when there is no retained context (e.g.
        right after open). Never raises — a normalization failure degrades to
        a full rebuild.
        """
        if self._ctx is None or self._adapter is None:
            self._rebuild_now()
            return
        try:
            ctx = self._ctx
            ctx.selection = normalize_node(self._selection, self._adapter)
            ctx.multi_selection = [
                n for n in (normalize_node(m, self._adapter) for m in self._multi)
                if n is not None
            ]
            ctx.pinned_refs = [
                n for n in (normalize_node(p, self._adapter) for p in self._pinned)
                if n is not None
            ]
            ctx.surface = self._surface or "tree"
            ctx.active_jobs = list(self._active_jobs or [])
            ctx.workshop_draft = (
                dict(self._workshop_draft) if self._workshop_draft else None
            )
            ctx.recent_intents = list(self._recent_intents or [])
            ctx.author_profile = (
                dict(self._author_profile) if self._author_profile else None
            )
            ctx.attachments = list(self._attachments or [])
            ctx.metrics = self._snapshot_metrics()
            ctx.usage_today = dict(self._usage_today or {})
            self._suggestions = local_suggestions(
                ctx, limit=3, soft_fix_count=self._soft_fix_count()
            )
        except Exception:
            # Defensive: any normalization hiccup falls back to a full rebuild
            # rather than emitting a half-mutated context.
            self._rebuild_now()
            return
        self.context_changed.emit(ctx)
        self.status_line_changed.emit(format_health_status_line(ctx))

    def _soft_fix_count(self) -> int | None:
        """v4.12: pure local Soft evaluate count for Dock suggestions.

        Never raises. Returns None when no adapter or evaluate fails so
        suggestions omit the soft skill rather than crash rebuild.
        """
        if self._adapter is None:
            return None
        try:
            from src.backend.experience.soft_autopilot import evaluate_soft_fixes

            batch = evaluate_soft_fixes(self._adapter)
            n = len(batch)
            return n if n > 0 else 0
        except Exception:
            return None

    def _rebuild_now(self) -> None:
        if self._adapter is None:
            self._ctx = None
            self._suggestions = []
            self._content_stale = False
            self.context_changed.emit(None)
            self.status_line_changed.emit(format_health_status_line(None))
            return

        ctx = build_experience_context(
            self._adapter,
            selection=self._selection,
            multi_selection=self._multi or None,
            pinned_refs=self._pinned or None,
            surface=self._surface,
            validate_problems=self._validate_problems,
            include_quality=self._include_quality,
            include_hygiene=self._include_hygiene,
            refresh_validate=False,
            workshop_draft=(
                dict(self._workshop_draft) if self._workshop_draft else None
            ),
            active_jobs=self._active_jobs or None,
            metrics=self._snapshot_metrics(),
            usage_today=self._usage_today or None,
            recent_intents=self._recent_intents or None,
            author_profile=self._author_profile,
            attachments=self._attachments or None,
        )
        self._ctx = ctx
        self._suggestions = local_suggestions(
            ctx, limit=3, soft_fix_count=self._soft_fix_count(),
            ocr_enabled=self._ocr_enabled,
        )
        self._content_stale = False
        self.context_changed.emit(ctx)
        self.status_line_changed.emit(format_health_status_line(ctx))

    def _snapshot_metrics(self) -> Any:
        """C-14: call the metrics provider defensively; None on any failure."""
        provider = self._metrics_provider
        if provider is None:
            return None
        try:
            return provider()
        except Exception:
            return None
