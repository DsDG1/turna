"""Experience shell glue on MainWindow (ambient / policy / skill wrappers).

Skill *implementations* live in ``experience_handlers.*`` (M7). This mixin keeps:

- policy / mute / ambient banner wiring
- ``_on_experience_suggestion`` → ``dispatch_experience_action``
- thin ``_experience_*`` wrappers for direct calls and tests

No Qt subclassing required — mix into ``MainWindow`` before ``QMainWindow``.
"""
from __future__ import annotations

from typing import Any

from PySide6.QtWidgets import QMessageBox

from src.application.ui_guard import safe_warning
from src.backend.experience.proactive import make_mute
import logging
logger = logging.getLogger(__name__)


def _validate_course_problems(course_dir) -> list[dict]:
    """Validate a course dir and normalize problems to plain dicts.

    Shared by on-open async diagnose and interactive validate-and-fix.
    Raises on validation failure — callers decide how to surface errors.
    """
    from src.backend import api

    result = api.validate_course_dir(course_dir)
    problems: list[dict] = []
    raw = getattr(result, "problems", None)
    if raw is None:
        raw = getattr(result, "errors", None) or []
    for p in raw:
        if isinstance(p, dict):
            problems.append(p)
        else:
            problems.append(
                {
                    "level": getattr(p, "level", "error"),
                    "message": str(getattr(p, "message", p)),
                    "path": str(getattr(p, "path", "") or ""),
                }
            )
    return problems


def _find_stage_and_item(
    lesson: dict, item_id: str
) -> tuple[dict | None, dict | None]:
    """Locate the stage (or listeningPhase) holding ``item_id`` in lesson.

    Module-level helper (v4.39 K-13) so it is callable from both the mixin
    (``MainWindow`` subclass) and tests with a plain ``QWidget`` host. Returns
    ``(stage, item)`` where ``stage`` is the live dict whose ``items`` list
    contains the item (so ``ApplyItemPatchCommand`` mutates the adapter in
    place). Searches stages → subLesson stages → listeningPhases. Pure-ish
    (no IO); returns ``(None, None)`` if not found.
    """
    iid = str(item_id or "")
    if not iid or not isinstance(lesson, dict):
        return None, None
    content = lesson.get("content") or {}
    if not isinstance(content, dict):
        return None, None
    containers: list[dict] = []
    for stage in content.get("stages") or []:
        if isinstance(stage, dict):
            containers.append(stage)
    for sub in content.get("subLessons") or []:
        if isinstance(sub, dict):
            for stage in sub.get("stages") or []:
                if isinstance(stage, dict):
                    containers.append(stage)
    for phase in content.get("listeningPhases") or []:
        if isinstance(phase, dict):
            containers.append(phase)
    for stage in containers:
        items = stage.get("items")
        if not isinstance(items, list):
            continue
        for it in items:
            if isinstance(it, dict) and str(it.get("id") or "") == iid:
                return stage, it
    return None, None


class ExperienceSkillsMixin:
    """Skill dispatch glue (M7). Implementations live in experience_handlers.*."""

    def _usage_today_for_policy(self) -> dict | None:
        """Best-effort usage_today for M-08; never raises.

        Prefer Shell's live ``_usage_today`` (updated by set_usage_today /
        _sync_usage_today) over a possibly stale Context snapshot.
        """
        try:
            shell = getattr(self, "experience", None)
            raw = getattr(shell, "_usage_today", None) if shell is not None else None
            if isinstance(raw, dict) and raw:
                return dict(raw)
        except Exception:
            logger.debug("application/experience_skills_mixin.py:_usage_today_for_policy best-effort step failed", exc_info=True)
        try:
            self._sync_usage_today()
            shell = getattr(self, "experience", None)
            raw = getattr(shell, "_usage_today", None) if shell is not None else None
            if isinstance(raw, dict) and raw:
                return dict(raw)
        except Exception:
            logger.debug("application/experience_skills_mixin.py:_usage_today_for_policy best-effort step failed", exc_info=True)
        try:
            ctx = getattr(self.experience, "context", None)
            if ctx is not None and getattr(ctx, "usage_today", None):
                return dict(ctx.usage_today)
        except Exception:
            logger.debug("application/experience_skills_mixin.py:_usage_today_for_policy best-effort step failed", exc_info=True)
        return None
    def _resolve_experience_policy(self, *, action_id: str | None = None):
        """C-07 + M-08: resolve policy with live settings + usage_today."""
        from src.backend.experience import resolve_policy

        return resolve_policy(
            getattr(self, "_settings_obj", None),
            action_id=action_id,
            usage_today=self._usage_today_for_policy(),
        )
    def _deny_ai_write_if_blocked(self, *, label: str = "AI") -> bool:
        """Return True if AI write must not proceed (budget / observer).

        Uses a synthetic needs_confirm write action against current policy.
        Non-modal statusBar only (no QMessageBox hang in tests).
        """
        from src.backend.experience import can_dispatch
        from src.backend.experience.actions import ActionSpec

        policy = self._resolve_experience_policy(action_id="lesson.fill_empty")
        ok, reason = can_dispatch(
            ActionSpec("lesson.fill_empty", label, needs_confirm=True),
            policy,
        )
        if ok:
            return False
        try:
            self.statusBar().showMessage(f"{reason}：{label}", 6000)
        except Exception:
            logger.debug("application/experience_skills_mixin.py:_deny_ai_write_if_blocked best-effort step failed", exc_info=True)
        return True
    def _load_experience_mute_dict(self) -> dict:
        import json

        raw = getattr(self._settings_obj, "experience_mute_json", "") or ""
        if not raw.strip():
            return {}
        try:
            data = json.loads(raw)
            return data if isinstance(data, dict) else {}
        except json.JSONDecodeError:
            return {}
    def _save_experience_mute(self) -> None:
        import json

        self._settings_obj.experience_mute_json = json.dumps(
            self._ambient_mute.to_dict(), ensure_ascii=False
        )
        self._settings_obj.save_to_qsettings(self._settings)
    def _load_defer_store(self):
        """A3 ②: load DeferStore from ``experience_defer_json`` (never raises)."""
        import json

        from src.backend.experience.defer_store import DeferStore

        raw = getattr(self._settings_obj, "experience_defer_json", "") or ""
        if not raw.strip():
            return DeferStore()
        try:
            data = json.loads(raw)
            return DeferStore.from_dict(data if isinstance(data, dict) else {})
        except (json.JSONDecodeError, ValueError):
            return DeferStore()
    def _save_defer_store(self) -> None:
        import json

        store = getattr(self, "_defer_store", None)
        if store is None:
            return
        try:
            self._settings_obj.experience_defer_json = json.dumps(
                store.to_dict(), ensure_ascii=False
            )
            self._settings_obj.save_to_qsettings(self._settings)
        except Exception:
            logger.debug("application/experience_skills_mixin.py:_save_defer_store best-effort step failed", exc_info=True)
    def _refresh_ambient(self) -> None:
        """E2.0 + A3 ①: evaluate up to 3 Ambient proposals (local, no LLM)."""
        from src.backend.experience.proactive import evaluate_ambient_batch

        if not hasattr(self, "ambient_banner"):
            return
        from src.backend.experience import resolve_policy

        policy = resolve_policy(getattr(self, "_settings_obj", None))
        if policy.is_observer:
            self.ambient_banner.clear()
            return
        ctx = self.experience.context
        # A3 ② + P2: defer via policy effective flag (active bundle ORs setting).
        defer_on = bool(getattr(policy, "allow_defer_resurface", False))
        defer_store = self._defer_store if defer_on else None
        props = evaluate_ambient_batch(
            ctx,
            mute=self._ambient_mute,
            archived_ids=self._ambient_archived,
            suggestions=self.experience.suggestions,
            limit=3,
            defer_store=defer_store,
        )
        # A3 ②: drop defers whose issue has resolved (best-effort, never raises).
        if defer_store is not None:
            try:
                from src.backend.experience.proactive import proposal_id_for

                current_ids = {
                    proposal_id_for(str(s.get("action_id") or ""), dict(s.get("scope") or {}))
                    for s in (self.experience.suggestions or [])
                    if isinstance(s, dict) and s.get("action_id")
                }
                defer_store.purge_resolved(current_ids)
            except Exception:
                logger.debug("application/experience_skills_mixin.py:_refresh_ambient best-effort step failed", exc_info=True)
        if not props:
            self.ambient_banner.clear()
        elif getattr(policy, "runtime_opaque", False):
            # P4/F4: opaque — hide explanatory ambient text but still count
            # evaluation (silent presence). Heartbeat must keep refreshing.
            self.ambient_banner.clear()
            self.experience_metrics.inc_ambient("shown")
            try:
                sb = getattr(self, "statusBar", None)
                if callable(sb) and props:
                    bar = sb()
                    if bar is not None and hasattr(bar, "showMessage"):
                        bar.showMessage("…", 800)
            except Exception:
                logger.debug("application/experience_skills_mixin.py:_refresh_ambient best-effort step failed", exc_info=True)
        else:
            self.ambient_banner.show_proposals(props)
            self.experience_metrics.inc_ambient("shown")
            # A3 ②: count resurfaced proposals separately (no-op when defer_store
            # is None - no deferred_resurface source is produced).
            for _p in props:
                if getattr(_p, "source", "") == "deferred_resurface":
                    self.experience_metrics.inc_ambient("resurfaced")
        # F3: immersive full-auto silent drive of allowlisted ambient props.
        try:
            from src.application.presence_drive import maybe_silent_drive_proposals

            if getattr(policy, "allow_full_auto_apply", False):
                maybe_silent_drive_proposals(self, props, policy)
        except Exception:
            logger.debug("application/experience_skills_mixin.py:_refresh_ambient best-effort step failed", exc_info=True)
        # P2: once-per-course campaign auto surface (writes still confirm).
        try:
            from src.application.presence_mode import maybe_auto_enqueue_campaign

            maybe_auto_enqueue_campaign(self)
        except Exception:
            logger.debug("application/experience_skills_mixin.py:_refresh_ambient best-effort step failed", exc_info=True)
        # P5: local precognition refresh (soft/empty/weak fingerprints).
        try:
            from src.backend.experience.precognition import (
                get_or_create_precog,
                refresh_local_precog,
            )

            if getattr(policy, "allow_full_auto_apply", False) or getattr(
                policy, "is_active_bundle", False
            ):
                cache = get_or_create_precog(self)
                ctx = self.experience.context
                budget_ok = bool(getattr(policy, "allow_ai_skill", True))
                refresh_local_precog(
                    cache,
                    adapter=getattr(self, "adapter", None),
                    empty_lessons=list(getattr(ctx, "empty_lessons", None) or [])
                    if ctx
                    else [],
                    quality_by_section=dict(
                        getattr(ctx, "quality_by_section", None) or {}
                    )
                    if ctx
                    else {},
                    budget_ok=budget_ok,
                )
                # F3: after precog miss/hit, try soft/fill silent drive once.
                if getattr(policy, "allow_full_auto_apply", False):
                    try:
                        from src.application.presence_drive import (
                            maybe_silent_drive_precog,
                        )

                        maybe_silent_drive_precog(self, policy)
                    except Exception:
                        logger.debug("application/experience_skills_mixin.py:_refresh_ambient best-effort step failed", exc_info=True)
        except Exception:
            logger.debug("application/experience_skills_mixin.py:_refresh_ambient best-effort step failed", exc_info=True)
    def _on_ambient_heartbeat(self) -> None:
        """A3 ③ + F4 + P2: re-evaluate only when AI is idle.

        Interval is full ``HEARTBEAT_IDLE_INTERVAL_MS`` after each successful
        tick **or** after AI jobs finish (timer restarts from idle moment).
        While AI is busy the timer is stopped so the interval does not count.
        """
        if not hasattr(self, "ambient_banner") or self.course_dir is None:
            return
        from src.backend.experience import resolve_policy
        from src.application.presence_drive import is_experience_ai_busy

        policy = resolve_policy(getattr(self, "_settings_obj", None))
        if policy.is_observer:
            return
        live = bool(getattr(policy, "allow_ambient_live", False))
        defer = bool(getattr(policy, "allow_defer_resurface", False))
        if not (live or defer):
            return
        try:
            if hasattr(self, "isActiveWindow") and not self.isActiveWindow():
                return
        except Exception:
            logger.debug("application/experience_skills_mixin.py:_on_ambient_heartbeat best-effort step failed", exc_info=True)
        # P2: do not refresh/drive while AI is still answering.
        if is_experience_ai_busy(self):
            self._pause_ambient_heartbeat_until_idle()
            return
        if live and getattr(self.experience, "_content_stale", False):
            self.experience.invalidate(immediate=False)
        else:
            self._refresh_ambient()

    def _pause_ambient_heartbeat_until_idle(self) -> None:
        """Stop interval clock; resume full interval when AI goes idle."""
        try:
            self._heartbeat_wait_idle = True
            hb = getattr(self, "_ambient_heartbeat", None)
            if hb is not None and hb.isActive():
                hb.stop()
        except Exception:
            logger.debug("application/experience_skills_mixin.py:_pause_ambient_heartbeat_until_idle best-effort step failed", exc_info=True)

    def _on_job_tray_ai_busy_changed(self, busy: bool) -> None:
        """P2: AI job started → pause heartbeat; all done → start full interval."""
        try:
            self._presence_ai_busy = bool(busy)
        except Exception:
            logger.debug("application/experience_skills_mixin.py:_on_job_tray_ai_busy_changed best-effort step failed", exc_info=True)
        if busy:
            self._pause_ambient_heartbeat_until_idle()
            return
        # Became idle: start counting the full interval only now.
        try:
            hb = getattr(self, "_ambient_heartbeat", None)
            if hb is None:
                return
            from src.backend.experience import resolve_policy
            from src.application.presence_drive import HEARTBEAT_IDLE_INTERVAL_MS

            policy = resolve_policy(getattr(self, "_settings_obj", None))
            live = bool(getattr(policy, "allow_ambient_live", False))
            defer = bool(getattr(policy, "allow_defer_resurface", False))
            if policy.is_observer or not (live or defer):
                return
            if self.course_dir is None:
                return
            hb.setInterval(int(HEARTBEAT_IDLE_INTERVAL_MS))
            if not hb.isActive():
                hb.start()
            self._heartbeat_wait_idle = False
        except Exception:
            logger.debug("application/experience_skills_mixin.py:_on_job_tray_ai_busy_changed best-effort step failed", exc_info=True)
    def _on_ambient_accepted(self, proposal) -> None:
        from src.backend.experience.proactive import AmbientProposal

        if isinstance(proposal, AmbientProposal):
            payload = {
                "action_id": proposal.action_id,
                "scope": dict(proposal.scope),
                "title": proposal.title,
            }
            pid = proposal.id
        else:
            payload = {
                "action_id": str(proposal.get("action_id") or ""),
                "scope": dict(proposal.get("scope") or {}),
                "title": str(proposal.get("title") or ""),
            }
            pid = str(proposal.get("id") or "")
        if pid:
            self._ambient_archived.add(pid)
        # A3 ①: promote the next proposal instead of hiding the banner.
        self._refresh_ambient()
        self.experience_metrics.inc_ambient("accepted")
        self._record_experience_event(
            "ambient.accept",
            payload.get("title") or payload["action_id"],
            action_id=payload["action_id"],
            scope=payload.get("scope"),
        )
        self._on_experience_suggestion(payload)
    def _on_ambient_archived(self, proposal_id: str) -> None:
        pid = str(proposal_id or "")
        if not pid:
            return
        from src.backend.experience import resolve_policy

        defer_on = bool(
            getattr(
                resolve_policy(getattr(self, "_settings_obj", None)),
                "allow_defer_resurface",
                False,
            )
        )
        # Look up the proposal in the current queue to capture action_id.
        prop = None
        for p in self.ambient_banner.proposals():
            if getattr(p, "id", "") == pid:
                prop = p
                break
        if defer_on and prop is not None:
            # A3 ②: defer with escalating cooldown (15->30->60min->permanent).
            record = self._defer_store.add(
                pid, getattr(prop, "action_id", "") or ""
            )
            if not record.re_surface_after_iso:
                # Escalated to permanent -> session-level archive, no resurface.
                self._ambient_archived.add(pid)
                self.experience_metrics.inc_ambient("dismissed")
            else:
                self._save_defer_store()
                self.experience_metrics.inc_ambient("deferred")
        else:
            # Legacy: session-only archive (no resurface).
            self._ambient_archived.add(pid)
            self.experience_metrics.inc_ambient("dismissed")
        self.statusBar().showMessage("已归档本条主动建议", 3000)
        self._refresh_ambient()
    def _on_ambient_mute_changed(self, level: str) -> None:
        self._ambient_mute = make_mute(level)
        self._save_experience_mute()
        self.ambient_banner.clear()
        self.experience_metrics.inc_ambient("muted")
        labels = {
            "hours4": "4 小时",
            "today": "今日",
            "permanent": "永久",
        }
        self.statusBar().showMessage(
            f"主动建议已静音（{labels.get(level, level)}）", 5000
        )
        self._record_experience_event(
            "ambient.mute", f"静音 {level}", action_id="app.mute"
        )
    def _on_experience_suggestion(self, suggestion: dict) -> None:
        """Dispatch Experience suggestions via the M4/M7 handler registry.

        Policy, telemetry, and metrics live in
        :func:`src.application.experience_dispatch.dispatch_experience_action`.
        Skill bodies live in ``experience_handlers``; this method only funnels.
        """
        from src.application.experience_dispatch import dispatch_experience_action

        dispatch_experience_action(self, suggestion)
    def _run_local_validate(self) -> list[dict] | None:
        """Validate the course dir and normalize problems to dicts.

        Returns ``None`` on failure (a warning has already been shown).
        """
        if not self.course_dir:
            safe_warning(self, "未加载课程目录", "请先打开课程目录。")
            return None
        try:
            problems = _validate_course_problems(self.course_dir)
        except Exception as exc:
            QMessageBox.warning(self, "校验失败", str(exc))
            return None
        self.experience.set_validate_problems(problems)
        self._refresh_experience(immediate=True)
        return problems
    def _make_ai_worker(self, target, *args, **kwargs):
        """Construct an ``AiRequestWorker`` for *target*.

        Tests inject ``_goal_fill_worker_factory`` to run the target inline
        (no real QThread); production uses the real worker. Falls back to
        ``AiRequestWorker`` when no factory is set.
        """
        factory = getattr(self, "_goal_fill_worker_factory", None)
        if callable(factory):
            return factory(target, *args, **kwargs)
        from src.dialogs.ai.worker import AiRequestWorker

        return AiRequestWorker(target, *args, **kwargs)
    def _current_section_for_experience(self) -> dict | None:
        """Section under the current selection, else the first section."""
        ref = self._current_node_ref
        try:
            if ref:
                kind, node_id = ref
                if kind == "section":
                    return self.adapter.find_section(node_id)
                if kind == "unit":
                    section, _unit = self.adapter.find_unit(node_id)
                    return section
                if kind == "lesson":
                    section, _unit, _lesson = self.adapter.find_lesson(node_id)
                    return section
        except KeyError:
            logger.debug("application/experience_skills_mixin.py:_current_section_for_experience best-effort step failed", exc_info=True)
        sections = getattr(self.adapter, "sections", None) or []
        return sections[0] if sections else None
    def _experience_open_validation(self) -> None:
        """Run local validate and open the report (no auto-fix)."""
        problems = self._run_local_validate()
        if problems is None:
            return
        if problems:
            self._show_validation_report(problems, title="校验结果（体验副驾驶）")
        else:
            self.statusBar().showMessage("校验通过：无 error", 4000)
    def _experience_align_pos(self, scope: dict) -> None:
        from src.application.experience_handlers.resources import handle_align_pos
        return handle_align_pos(self, scope)

    def _experience_resolve_term_conflicts(self, scope: dict) -> None:
        from src.application.experience_handlers.resources import (
            handle_resolve_term_conflicts,
        )
        return handle_resolve_term_conflicts(self, scope)

    def _experience_batch_polish(self, scope: dict) -> None:
        from src.application.experience_handlers.resources import handle_batch_polish
        return handle_batch_polish(self, scope)

    def _experience_balance_lesson(self, scope: dict) -> None:
        from src.application.experience_handlers.regenerate import handle_balance_lesson
        return handle_balance_lesson(self, scope)

    def _experience_batch_set_template(self, scope: dict) -> None:
        from src.application.experience_handlers.resources import handle_batch_set_template
        return handle_batch_set_template(self, scope)

    def _experience_clear_author(self, scope: dict | None = None) -> None:
        from src.application.experience_handlers.memory_nav import handle_clear_author
        return handle_clear_author(self, scope)

    def _experience_compare_sections(self, scope: dict) -> None:
        from src.application.experience_handlers.resources import handle_compare_sections
        return handle_compare_sections(self, scope)

    def _experience_dedupe_suggest(self, scope: dict) -> None:
        from src.application.experience_handlers.resources import handle_dedupe_suggest
        return handle_dedupe_suggest(self, scope)

    def _experience_fill_empty(self, scope: dict) -> None:
        from src.application.experience_handlers.fill import handle_fill_empty
        return handle_fill_empty(self, scope)

    def _experience_fill_listening_gaps(
        self, scope: dict, *, action_id: str = "listening.fill_gaps"
    ) -> None:
        from src.application.experience_handlers.fill import handle_fill_listening_gaps
        return handle_fill_listening_gaps(self, scope, action_id=action_id)

    def _experience_fill_stubs(self) -> None:
        from src.application.experience_handlers.fill import handle_fill_stubs
        return handle_fill_stubs(self)

    def _experience_git_skill(self, action: str) -> None:
        from src.application.experience_handlers.multimodal import handle_git_skill
        return handle_git_skill(self, action)

    def _experience_ocr(
        self,
        scope: dict | None = None,
        *,
        records=None,
        unlink_after: bool = False,
    ) -> None:
        from src.application.experience_handlers.multimodal import handle_ocr
        return handle_ocr(
            self, scope, records=records, unlink_after=unlink_after
        )

    def _experience_quality_campaign(self, scope: dict) -> None:
        from src.application.experience_handlers.quality import handle_quality_campaign
        return handle_quality_campaign(self, scope)

    def _experience_reading_gen(self, scope: dict) -> None:
        from src.application.experience_handlers.regenerate import handle_reading_gen
        return handle_reading_gen(self, scope)

    def _experience_regenerate(self, scope: dict) -> None:
        from src.application.experience_handlers.regenerate import handle_regenerate
        return handle_regenerate(self, scope)

    def _experience_soft_preview_hygiene(self, scope: dict | None = None) -> None:
        from src.application.experience_handlers.quality import handle_soft_preview_hygiene
        return handle_soft_preview_hygiene(self, scope)

    def _experience_spiral_vocab(self, scope: dict) -> None:
        from src.application.experience_handlers.regenerate import handle_spiral_vocab
        return handle_spiral_vocab(self, scope)

    def _experience_to_listening(self, scope: dict) -> None:
        from src.application.experience_handlers.memory_nav import handle_to_listening
        return handle_to_listening(self, scope)

    def _experience_validate_and_fix(self) -> None:
        from src.application.experience_handlers.fill import handle_validate_and_fix
        return handle_validate_and_fix(self)

    def _experience_why_current(self) -> None:
        from src.application.experience_handlers.memory_nav import handle_why_current
        return handle_why_current(self)

    def _on_diagnose_failed(self, course_dir, message: str) -> None:
        from src.application.experience_handlers.memory_nav import handle_on_diagnose_failed
        return handle_on_diagnose_failed(self, course_dir, message)

    def _on_diagnose_problems(self, course_dir, problems: object) -> None:
        from src.application.experience_handlers.memory_nav import handle_on_diagnose_problems
        return handle_on_diagnose_problems(self, course_dir, problems)

    def _refresh_validate_after_ai(self, success_message: str) -> None:
        from src.application.experience_handlers.regenerate import handle_refresh_validate_after_ai
        return handle_refresh_validate_after_ai(self, success_message)

    def _run_fill_lesson_patch_flow(
        self,
        *,
        section=None,
        lesson_id=None,
        follow_up_ids=None,
        instruction: str = "",
    ):
        from src.application.experience_handlers.fill import (
            handle_run_fill_lesson_patch_flow,
        )
        return handle_run_fill_lesson_patch_flow(
            self,
            section=section,
            lesson_id=lesson_id,
            follow_up_ids=follow_up_ids,
            instruction=instruction,
        )

    def _run_regen_flow(
        self,
        *,
        action_id=None,
        kind=None,
        node_id=None,
        section=None,
        job_id=None,
        job_label=None,
        instruction=None,
        engine_kind=None,
    ):
        from src.application.experience_handlers.regenerate import handle_run_regen_flow
        return handle_run_regen_flow(
            self,
            action_id=action_id,
            kind=kind,
            node_id=node_id,
            section=section,
            job_id=job_id,
            job_label=job_label,
            instruction=instruction,
            engine_kind=engine_kind,
        )

    def _show_git_skill_result(self, title: str, text: str) -> None:
        from src.application.experience_handlers.multimodal import handle_show_git_skill_result
        return handle_show_git_skill_result(self, title, text)

    def _start_experience_diagnose(self) -> None:
        from src.application.experience_handlers.memory_nav import handle_start_experience_diagnose
        return handle_start_experience_diagnose(self)



