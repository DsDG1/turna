"""Palette open / dispatch orchestration (E5-D / S-10) + K-25 help.fix + M-04 voice.

Single source of truth for ⌘K lifecycle: seed history, wire metrics, S-04
low-confidence scope gate, app.* builtins, and skill dispatch via the same
``_on_experience_suggestion`` funnel as the Dock.

Pure helpers (history rows, scope fill, confirm predicate) are Qt-free and
unit-tested without MainWindow. Host-facing functions duck-type MainWindow.

C-06 prep: CommandPalette may expose an async candidate hook; this module
does **not** call any LLM (default off, separate slice).

M-04: ``transcribe_to_palette`` is an input channel only — fills the box,
never auto-dispatches, never writes the course tree.
"""
from __future__ import annotations

from typing import Any, Mapping, MutableMapping, Sequence

# Confidence below this (and non-app write actions) requires S-04 confirm.
LOW_CONFIDENCE_THRESHOLD = 0.8

# M-04 job tray ids (local kind — no LLM).
VOICE_JOB_ID = "voice-palette"
VOICE_JOB_LABEL = "语音输入"
VOICE_ACTION_ID = "app.voice_input"


def history_rows_from_timeline(timeline: Any, n: int = 3) -> list[dict[str, Any]]:
    """Build palette history rows from ``ExperienceTimeline.replayable``."""
    if timeline is None or not hasattr(timeline, "replayable"):
        return []
    try:
        events = timeline.replayable(int(n))
    except Exception:
        return []
    rows: list[dict[str, Any]] = []
    for e in events:
        aid = str(getattr(e, "action_id", "") or "")
        if not aid:
            continue
        rows.append(
            {
                "action_id": aid,
                "label": f"最近 · {getattr(e, 'summary', '') or aid}",
                "scope": dict(getattr(e, "scope", None) or {}),
                # F2 v4.47: history replay must not skip S-04 (was conf 1.0).
                "confidence": 0.6,
            }
        )
    return rows


def should_confirm_scope(
    action_id: str,
    confidence: float,
    *,
    needs_confirm: bool,
) -> bool:
    """True when S-04 independent scope dialog should run before dispatch."""
    if float(confidence) >= LOW_CONFIDENCE_THRESHOLD:
        return False
    if str(action_id or "").startswith("app."):
        return False
    return bool(needs_confirm)


def enrich_fill_empty_scope(
    scope: MutableMapping[str, Any] | Mapping[str, Any] | None,
    empty_lessons: Sequence[str] | None,
) -> dict[str, Any]:
    """Ensure ``lesson.fill_empty`` has ``first_lesson_id`` when empty lessons exist."""
    out = dict(scope or {})
    if "first_lesson_id" in out:
        return out
    if not empty_lessons:
        return out
    first = empty_lessons[0]
    if first:
        out["first_lesson_id"] = first
    return out


def empty_lessons_from_host(host: Any) -> list[str]:
    """Best-effort empty lesson ids from Experience context."""
    try:
        exp = getattr(host, "experience", None)
        ctx = getattr(exp, "context", None) if exp is not None else None
        empty = getattr(ctx, "empty_lessons", None) if ctx is not None else None
        if not empty:
            return []
        return [str(x) for x in empty if x]
    except Exception:
        return []


def open_command_palette(host: Any) -> Any:
    """Create, wire, and show the ⌘K palette on ``host``.

    Returns the dialog instance (for tests). Does not call LLM.
    """
    from src.widgets.command_palette import CommandPalette

    parent = host if _is_qwidget(host) else None
    dlg = CommandPalette(parent)
    dlg.set_history(history_rows_from_timeline(getattr(host, "experience_timeline", None)))
    dlg.command_triggered.connect(
        lambda payload: dispatch_palette_payload(host, dict(payload or {}))
    )
    metrics = getattr(host, "experience_metrics", None)
    if metrics is not None:
        if hasattr(metrics, "inc_intent_resolved"):
            dlg.intent_resolved.connect(
                lambda _text, _action: metrics.inc_intent_resolved()
            )
        if hasattr(metrics, "inc_intent_fell_through"):
            dlg.intent_fellthrough.connect(
                lambda _text: metrics.inc_intent_fell_through()
            )
    # C-06 prep: host may install an async provider later; default is no-op.
    hook = getattr(host, "_palette_async_candidate_hook", None)
    if callable(hook) and hasattr(dlg, "set_async_candidate_hook"):
        try:
            dlg.set_async_candidate_hook(hook)
        except Exception:
            pass
    # M-04: mic visible only when experience/voice_palette is on.
    try:
        from src.backend.experience.voice_skill import is_voice_palette_enabled

        settings = getattr(host, "_settings_obj", None)
        dlg.set_voice_enabled(is_voice_palette_enabled(settings))
    except Exception:
        dlg.set_voice_enabled(False)
    dlg.voice_requested.connect(lambda: transcribe_to_palette(host, dlg))
    # Keep a weak ref so async voice callbacks can fill the open dialog.
    try:
        host._active_command_palette = dlg  # type: ignore[attr-defined]
    except Exception:
        pass
    dlg.show_and_focus()
    return dlg


def transcribe_to_palette(host: Any, palette: Any | None = None) -> None:
    """M-04: local mic transcription → fill palette input (no auto-dispatch).

    ``host`` duck-types MainWindow: ``_settings_obj``, ``job_tray``,
    ``experience_metrics``, ``statusBar``, ``_make_ai_worker`` (optional),
    ``_record_experience_event``, ``_experience_worker``.
    """
    from src.backend.experience.voice_skill import (
        build_voice_metrics,
        is_voice_palette_enabled,
        status_message,
        transcribe_once,
        voice_available,
    )

    dlg = palette if palette is not None else getattr(host, "_active_command_palette", None)

    def _status(msg: str, ms: int = 6000) -> None:
        try:
            host.statusBar().showMessage(msg, ms)
        except Exception:
            pass

    if not is_voice_palette_enabled(getattr(host, "_settings_obj", None)):
        _status(status_message("disabled"))
        return

    # Offscreen / no live GUI: never open a real microphone in CI.
    try:
        from PySide6.QtWidgets import QApplication

        app = QApplication.instance()
        if app is None or app.platformName() == "offscreen":
            _status("语音输入需在可视化窗口运行", 5000)
            return
    except Exception:
        _status("语音输入：GUI 不可用", 5000)
        return

    avail, reason = voice_available()
    if not avail:
        _status(status_message(reason))
        return

    tray = getattr(host, "job_tray", None)
    metrics = getattr(host, "experience_metrics", None)
    if tray is not None:
        try:
            tray.start(VOICE_JOB_ID, f"{VOICE_JOB_LABEL}…", kind="local")
        except Exception:
            pass
    if metrics is not None:
        try:
            metrics.inc_job("local", "started")
        except Exception:
            pass
    if dlg is not None and hasattr(dlg, "set_voice_busy"):
        try:
            dlg.set_voice_busy(True)
        except Exception:
            pass

    # Lang hint from course if present; Sphinx is English-centric by default.
    lang = "en-US"
    try:
        exp = getattr(host, "experience", None)
        ctx = getattr(exp, "context", None) if exp is not None else None
        course_lang = str(getattr(ctx, "language", "") or "").strip().lower()
        if course_lang in {"en", "eng", "en-us", "en_us"}:
            lang = "en-US"
        elif course_lang:
            # Keep en-US for Sphinx; user can edit free-form after fill.
            lang = "en-US"
    except Exception:
        pass

    def _finish(text: str, status: str) -> None:
        if tray is not None:
            try:
                tray.finish(VOICE_JOB_ID)
            except Exception:
                pass
        if metrics is not None:
            try:
                if status in ("ok", "too_long"):
                    metrics.inc_job("local", "finished")
                else:
                    metrics.inc_job("local", "failed")
            except Exception:
                pass
        if dlg is not None and hasattr(dlg, "set_voice_busy"):
            try:
                dlg.set_voice_busy(False)
            except Exception:
                pass
        # §14.5.3: closed-set only — never transcript text.
        scope = build_voice_metrics(status, ok=status in ("ok", "too_long"))
        record = getattr(host, "_record_experience_event", None)
        if callable(record):
            try:
                record(
                    VOICE_ACTION_ID,
                    VOICE_JOB_LABEL,
                    action_id=VOICE_ACTION_ID,
                    scope=scope,
                )
            except Exception:
                pass
        if status in ("ok", "too_long") and text:
            target = dlg if dlg is not None else getattr(host, "_active_command_palette", None)
            if target is not None and hasattr(target, "set_input_text"):
                try:
                    target.set_input_text(text)
                except Exception:
                    pass
            _status(status_message(status))
        else:
            _status(status_message(status))

    make_worker = getattr(host, "_make_ai_worker", None)
    if callable(make_worker):
        worker = make_worker(transcribe_once, lang=lang)

        def _on_ok(result: object) -> None:
            text, status = "", "failed"
            if isinstance(result, (tuple, list)) and len(result) >= 2:
                text, status = str(result[0] or ""), str(result[1] or "failed")
            _finish(text, status)

        def _on_err(msg: str) -> None:
            _finish("", "failed")

        worker.result_ready.connect(_on_ok)
        worker.error_occurred.connect(_on_err)
        worker.start()
        try:
            host._experience_worker = worker
        except Exception:
            pass
        return

    # Sync fallback (tests without worker factory).
    text, status = transcribe_once(lang=lang)
    _finish(text, status)


def dispatch_palette_payload(host: Any, payload: Mapping[str, Any] | None) -> None:
    """Route one palette (or help.fix) payload through gates then skills."""
    payload = dict(payload or {})
    action = str(payload.get("action_id") or "")
    if not action:
        return

    try:
        from src.infrastructure.telemetry import telemetry

        telemetry.record_event("experience.palette", payload={"action_id": action})
    except Exception:
        pass

    confidence = float(payload.get("confidence") or 1.0)
    scope = dict(payload.get("scope") or {})

    if action == "lesson.fill_empty":
        scope = enrich_fill_empty_scope(scope, empty_lessons_from_host(host))

    # S-04: low-confidence NL writes → independent scope confirm.
    if should_confirm_scope(action, confidence, needs_confirm=_needs_confirm(action)):
        label = str(payload.get("label") or action)
        confirm = getattr(host, "_confirm_scope_for_low_confidence", None)
        if callable(confirm):
            if not confirm(label, action, scope, confidence):
                return

    if action == "app.save":
        save = getattr(host, "_on_save", None)
        if callable(save):
            save(reason="palette")
        return

    if action == "app.undo":
        stack = getattr(host, "undo_stack", None)
        if stack is not None and hasattr(stack, "undo"):
            stack.undo()
        return

    if action in ("app.help", "help.fix"):
        show_help_tour(host)
        return

    if action == "app.pin":
        pin = getattr(host, "_on_experience_pin_toggled", None)
        if callable(pin):
            pin()
        return

    if action == "app.why":
        why = getattr(host, "_experience_why_current", None)
        if callable(why):
            why()
        return

    record = getattr(host, "_record_experience_event", None)
    if callable(record):
        try:
            record(
                "palette.run",
                str(payload.get("label") or action),
                action_id=action,
                scope=scope,
            )
        except Exception:
            pass

    suggest = getattr(host, "_on_experience_suggestion", None)
    if callable(suggest):
        suggest({"action_id": action, "scope": scope})


def show_help_tour(host: Any) -> None:
    """K-25: clickable slash tour — each row dispatches like ⌘K exact slash.

    Skips ``app.help`` to avoid recursion. Parent is ``host`` when it is a
    QWidget; otherwise the dialog is parentless (tests).
    """
    from PySide6.QtCore import Qt
    from PySide6.QtWidgets import (
        QDialog,
        QLabel,
        QListWidget,
        QListWidgetItem,
        QVBoxLayout,
    )

    from src.backend.experience.intent_router import SLASH_COMMANDS

    parent = host if _is_qwidget(host) else None
    dlg = QDialog(parent)
    dlg.setWindowTitle("命令清单 · 点击执行")
    dlg.resize(440, 420)
    layout = QVBoxLayout(dlg)
    layout.addWidget(
        QLabel("点击一行即执行（等同在 ⌘K 输入该斜杠命令，置信 100%）")
    )
    list_w = QListWidget()
    layout.addWidget(list_w, stretch=1)

    for cmd, action_id, label in SLASH_COMMANDS:
        if action_id == "app.help":
            continue
        item = QListWidgetItem(f"{cmd}　{label}")
        item.setData(
            Qt.ItemDataRole.UserRole,
            {
                "action_id": action_id,
                "label": label,
                "confidence": 1.0,
                "scope": {},
            },
        )
        list_w.addItem(item)

    fired = {"done": False}

    def _run(item: QListWidgetItem) -> None:
        if fired["done"]:
            return
        data = item.data(Qt.ItemDataRole.UserRole)
        if not isinstance(data, dict) or not data.get("action_id"):
            return
        fired["done"] = True
        dlg.accept()
        dispatch_palette_payload(host, data)

    # Single click runs (K-25 可点执行); guard avoids double-fire with activate.
    list_w.itemClicked.connect(_run)
    # Prefer non-blocking in offscreen tests when host marks headless.
    if getattr(host, "_palette_help_non_modal", False):
        dlg.show()
        host._last_help_dialog = dlg  # type: ignore[attr-defined]
        return
    dlg.exec()


def _needs_confirm(action_id: str) -> bool:
    try:
        from src.backend.experience import get_action

        spec = get_action(action_id)
        if spec is None:
            return True
        return bool(spec.needs_confirm)
    except Exception:
        return True


def _is_qwidget(obj: Any) -> bool:
    try:
        from PySide6.QtWidgets import QWidget

        return isinstance(obj, QWidget)
    except Exception:
        return False


def run_palette_llm_classify(host: Any) -> None:
    """C-06: fire AiRequestWorker for pending palette query (S-10 / v4.46)."""
    from src.backend.experience.intent_llm import (
        classify_intent_sync,
        is_llm_intent_enabled,
    )
    from src.dialogs.ai.worker import AiRequestWorker

    query = str(getattr(host, "_palette_llm_pending_query", "") or "").strip()
    if not query:
        return
    settings = getattr(host, "_settings_obj", None)
    usage = None
    usage_fn = getattr(host, "_usage_today_for_policy", None)
    if callable(usage_fn):
        try:
            usage = usage_fn()
        except Exception:
            usage = None
    if not is_llm_intent_enabled(settings, usage_today=usage):
        return
    cfg = getattr(host, "_ai_config", None)
    if cfg is None or not getattr(cfg, "is_complete", False):
        return

    prev = getattr(host, "_palette_llm_worker", None)
    if prev is not None and prev.isRunning():
        try:
            prev.cancel()
        except Exception:
            pass

    def _target(cancel_check=None):
        return classify_intent_sync(
            cfg,
            query,
            cancel_check=cancel_check,
        )

    worker = AiRequestWorker(_target, parent=host if _is_qwidget(host) else None)
    host._palette_llm_worker = worker
    worker._palette_query = query  # type: ignore[attr-defined]

    def _on_ok(result) -> None:
        apply_palette_llm_result(host, query, result)

    def _on_err(_msg: str) -> None:
        apply_palette_llm_result(host, query, None)

    worker.result_ready.connect(_on_ok)
    worker.error_occurred.connect(_on_err)
    try:
        from src.infrastructure.telemetry import telemetry

        telemetry.record_event(
            "experience.llm_intent",
            payload={"phase": "start", "q_len": len(query)},
        )
    except Exception:
        pass
    worker.start()


def apply_palette_llm_result(host: Any, query: str, intent: Any) -> None:
    """C-06: push LLM Intent into the open palette if still matching."""
    pal = getattr(host, "_active_command_palette", None)
    if pal is None:
        return
    try:
        if not pal.isVisible():
            return
    except Exception:
        return
    current = ""
    try:
        current = (pal.input.text() or "").strip()
    except Exception:
        return
    if current != (query or "").strip():
        return
    intents = [intent] if intent is not None else []
    try:
        pal.apply_async_candidates(query, intents)
    except Exception:
        try:
            pal.apply_async_candidates(query, [])
        except Exception:
            pass
    try:
        from src.infrastructure.telemetry import telemetry

        telemetry.record_event(
            "experience.llm_intent",
            payload={
                "phase": "done",
                "hit": intent is not None,
                "action_id": getattr(intent, "action_id", "") or "",
                "confidence": float(getattr(intent, "confidence", 0) or 0),
            },
        )
    except Exception:
        pass
