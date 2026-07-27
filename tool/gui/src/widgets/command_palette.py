"""⌘K command palette (E1, S-03; E5-D C-06; M-04 voice; v4.47 UX fixes).

Non-modal-style frameless dialog: type to filter, Enter executes,
Esc dismisses. Routing lives in ``backend.experience.intent_router``;
this widget only renders candidates and emits the chosen action as a
dict compatible with ``ExperienceDock.suggestion_clicked``.

v4.47:
* Single-click selects; **double-click or Enter** dispatches (F3).
* Async LLM loading: Enter does not silent-fellthrough (F10).
* History rows use confidence from history dict (default 0.6).
* Header hint for Ctrl/⌘+K.
"""
from __future__ import annotations

from collections.abc import Callable, Sequence

from PySide6.QtCore import Qt, Signal
from PySide6.QtWidgets import (
    QDialog,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QListWidget,
    QListWidgetItem,
    QToolButton,
    QVBoxLayout,
)

from src.backend.experience.intent_router import Intent, match_commands

# Hook: (query_text) -> None  (host schedules async work; may call apply_async_candidates)
AsyncCandidateHook = Callable[[str], None]

# History / keyword confidence when not provided (S-04 armed).
_DEFAULT_HISTORY_CONF = 0.6


class CommandPalette(QDialog):
    """Ctrl/⌘+K palette: NL / slash command entry → action dispatch."""

    command_triggered = Signal(dict)
    intent_resolved = Signal(str, str)
    intent_fellthrough = Signal(str)
    voice_requested = Signal()

    def __init__(self, parent=None) -> None:
        super().__init__(parent)
        self.setWindowFlags(
            Qt.WindowType.FramelessWindowHint | Qt.WindowType.Dialog
        )
        self.setModal(True)
        self.resize(480, 340)

        layout = QVBoxLayout(self)
        layout.setContentsMargins(8, 8, 8, 8)
        layout.setSpacing(6)

        # F14: visible chrome without system title bar.
        self._title = QLabel("命令面板 · Ctrl/⌘+K · 双击或 Enter 执行 · Esc 关闭")
        self._title.setStyleSheet("color: #64748b; font-size: 11px;")
        layout.addWidget(self._title)

        row = QHBoxLayout()
        row.setSpacing(4)
        self.input = QLineEdit()
        self.input.setPlaceholderText(
            "输入命令或描述（/validate /fill /why …；双击或 Enter 执行）"
        )
        row.addWidget(self.input, stretch=1)

        self.voice_btn = QToolButton()
        self.voice_btn.setText("🎤")
        self.voice_btn.setToolTip("语音输入（本地转录，填回后需确认 Enter）")
        self.voice_btn.setAutoRaise(True)
        self.voice_btn.setVisible(False)
        self.voice_btn.clicked.connect(self.voice_requested.emit)
        row.addWidget(self.voice_btn)
        layout.addLayout(row)

        self.list = QListWidget()
        layout.addWidget(self.list, stretch=1)

        self._intents: list[Intent] = []
        self._history: list[dict] = []
        self._async_candidate_hook: AsyncCandidateHook | None = None
        self._async_pending_query: str | None = None
        self._loading_async = False
        self.input.textChanged.connect(self._refresh)
        self.input.returnPressed.connect(self._trigger_current)
        # F3: click = select only; double-click = dispatch.
        self.list.itemClicked.connect(self._on_item_clicked)
        self.list.itemDoubleClicked.connect(self._trigger_item)
        self.list.itemActivated.connect(self._trigger_item)
        self._refresh("")

    def set_async_candidate_hook(self, hook: AsyncCandidateHook | None) -> None:
        self._async_candidate_hook = hook

    def set_voice_enabled(self, enabled: bool) -> None:
        on = bool(enabled)
        self.voice_btn.setVisible(on)
        if on:
            self.voice_btn.setEnabled(True)
            self.voice_btn.setText("🎤")

    def set_voice_busy(self, busy: bool) -> None:
        if not self.voice_btn.isVisible():
            return
        self.voice_btn.setEnabled(not busy)
        self.voice_btn.setText("…" if busy else "🎤")

    def set_input_text(self, text: str) -> None:
        self.input.setText(str(text or ""))
        self.input.setFocus()

    def apply_async_candidates(
        self, query: str, intents: Sequence[Intent] | None
    ) -> None:
        current = self.input.text() or ""
        if current != (query or ""):
            return
        self._loading_async = False
        self._async_pending_query = None
        extra = [i for i in (intents or []) if getattr(i, "action_id", None)]
        if not extra:
            if not self._intents:
                self._paint_intents([])
            return
        seen = {i.action_id for i in self._intents}
        merged = list(self._intents)
        for intent in extra:
            if intent.action_id not in seen:
                merged.append(intent)
                seen.add(intent.action_id)
        self._paint_intents(merged)
        # F10: after LLM returns, select first row for Enter.
        if self._intents:
            self.list.setCurrentRow(0)

    def set_history(self, history: list[dict] | None) -> None:
        self._history = list(history or [])

    def show_and_focus(self) -> None:
        self._refresh("")
        self.input.clear()
        self.input.setFocus()
        self.show()
        self.raise_()

    def _refresh(self, text: str) -> None:
        text = text or ""
        self._loading_async = False
        self._async_pending_query = None
        intents = match_commands(text)
        if not text.strip() and self._history:
            hist_intents = [
                Intent(
                    action_id=str(h.get("action_id") or ""),
                    label=str(h.get("label") or h.get("action_id") or "最近"),
                    confidence=float(
                        h.get("confidence", _DEFAULT_HISTORY_CONF) or _DEFAULT_HISTORY_CONF
                    ),
                    scope=dict(h.get("scope") or {}),
                )
                for h in self._history
                if h.get("action_id")
            ]
            seen = {i.action_id for i in hist_intents}
            rest = [i for i in intents if i.action_id not in seen]
            intents = hist_intents + rest
        self._paint_intents(intents)
        if (
            not intents
            and text.strip()
            and self._async_candidate_hook is not None
        ):
            self._loading_async = True
            self._async_pending_query = text
            self.list.clear()
            item = QListWidgetItem("正在理解…（请稍候，或继续输入 / Esc）")
            item.setFlags(Qt.ItemFlag.NoItemFlags)
            self.list.addItem(item)
            try:
                self._async_candidate_hook(text)
            except Exception:
                self._loading_async = False
                self._paint_intents([])

    def _paint_intents(self, intents: list[Intent]) -> None:
        self._intents = list(intents or [])
        self.list.clear()
        if not self._intents:
            item = QListWidgetItem("无匹配命令（Enter 不执行）")
            item.setFlags(Qt.ItemFlag.NoItemFlags)
            self.list.addItem(item)
            return
        for intent in self._intents:
            QListWidgetItem(intent.label, self.list)
        self.list.setCurrentRow(0)

    def _on_item_clicked(self, item: QListWidgetItem) -> None:
        """F3: single click only moves selection — does not dispatch."""
        row = self.list.row(item)
        if 0 <= row < len(self._intents):
            self.list.setCurrentRow(row)

    def _trigger_current(self) -> None:
        # F10: while LLM is classifying, do not fellthrough silently.
        if self._loading_async and not self._intents:
            # Keep loading row; user can Esc or wait.
            return
        if self._intents:
            row = self.list.currentRow()
            if not (0 <= row < len(self._intents)):
                row = 0
            self._emit(self._intents[row])
            return
        self.intent_fellthrough.emit(self.input.text() or "")

    def _trigger_item(self, item: QListWidgetItem) -> None:
        row = self.list.row(item)
        if 0 <= row < len(self._intents):
            self._emit(self._intents[row])

    def _emit(self, intent: Intent) -> None:
        self.intent_resolved.emit(self.input.text() or "", intent.action_id)
        self.command_triggered.emit(
            {
                "action_id": intent.action_id,
                "label": intent.label,
                "scope": dict(intent.scope),
                "confidence": float(intent.confidence),
            }
        )
        self.accept()

    def keyPressEvent(self, event) -> None:  # noqa: N802
        if event.key() == Qt.Key.Key_Escape:
            self.reject()
            return
        if event.key() in (Qt.Key.Key_Down, Qt.Key.Key_Up):
            count = self.list.count()
            if count and self._intents:
                delta = 1 if event.key() == Qt.Key.Key_Down else -1
                row = max(0, min(len(self._intents) - 1, self.list.currentRow() + delta))
                self.list.setCurrentRow(row)
            return
        super().keyPressEvent(event)
