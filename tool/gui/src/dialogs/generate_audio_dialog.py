"""Dialog to configure and trigger listening-audio (TTS) generation.

Collects the MiniMax TTS options (voice-id, model, speed, force-overwrite) and
the API key, plus a read-only preview of how many assets will be generated /
skipped. The preview counts are computed by the caller *before* opening the
dialog, so this widget never touches the network.

The API key is forwarded to the ``generate_audio`` subprocess via the
environment, never persisted and never placed on the command line.
"""
from __future__ import annotations

from typing import Any

from PySide6.QtWidgets import (
    QCheckBox,
    QComboBox,
    QDialog,
    QDoubleSpinBox,
    QFormLayout,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QPushButton,
    QVBoxLayout,
    QWidget,
)

from src.application.settings import Settings
from src.theme import current_palette


class GenerateAudioDialog(QDialog):
    """Modal TTS-generation configuration dialog."""

    def __init__(
        self,
        settings: Settings,
        preview: dict[str, int] | None = None,
        parent: QWidget | None = None,
    ) -> None:
        super().__init__(parent)
        self.setWindowTitle("生成听力音频")
        self.setMinimumWidth(460)
        self._settings = settings
        self._preview = preview or {}

        layout = QVBoxLayout(self)
        layout.setSpacing(10)

        form = QFormLayout()
        form.setSpacing(10)

        # Editable voice-id combo: common MiniMax voices plus the persisted one.
        self._voice_combo = QComboBox()
        self._voice_combo.setEditable(True)
        _known_voices = [
            "female-tianmei",
            "male-qn-jingying",
            "female-yujie",
            "male-qn-daxiong",
            "female-shaonv",
            "male-chengshu",
        ]
        current_voice = settings.tts_voice_id or "female-tianmei"
        if current_voice not in _known_voices:
            _known_voices.insert(0, current_voice)
        for v in _known_voices:
            self._voice_combo.addItem(v)
        self._voice_combo.setCurrentText(current_voice)
        form.addRow("音色 Voice ID：", self._voice_combo)

        self._model_edit = QLineEdit(settings.tts_model or "speech-2.8-hd")
        self._model_edit.setPlaceholderText("speech-2.8-hd")
        form.addRow("模型 Model：", self._model_edit)

        self._speed_spin = QDoubleSpinBox()
        self._speed_spin.setRange(0.5, 2.0)
        self._speed_spin.setSingleStep(0.05)
        self._speed_spin.setDecimals(2)
        self._speed_spin.setValue(settings.tts_speed)
        form.addRow("语速 Speed：", self._speed_spin)

        self._force_check = QCheckBox("强制重新生成（覆盖已存在文件）")
        self._force_check.setChecked(settings.tts_force)
        form.addRow("", self._force_check)

        self._key_edit = QLineEdit()
        self._key_edit.setEchoMode(QLineEdit.EchoMode.Password)
        self._key_edit.setPlaceholderText("MiniMax API Key (sk-…)")
        self._key_edit.setText(settings.tts_api_key)
        form.addRow("API Key：", self._key_edit)
        layout.addLayout(form)

        hint = QLabel("API Key 仅在内存中用于本次生成，不会写入设置。")
        hint.setStyleSheet(f"color: {current_palette()['text_secondary']};")
        layout.addWidget(hint)

        total = int(self._preview.get("total", 0))
        existing = int(self._preview.get("existing", 0))
        if total == 0:
            preview_text = "当前课程没有可生成的可朗读听力阶段（缺少 audioAsset 与 transcript）。"
        else:
            preview_text = f"将生成 {total} 条；其中 {existing} 条已存在将被跳过。"
        self._preview_label = QLabel(preview_text)
        self._preview_label.setWordWrap(True)
        self._preview_label.setStyleSheet(
            f"color: {current_palette()['text_secondary']}; padding: 4px;"
        )
        layout.addWidget(self._preview_label)

        btn_row = QHBoxLayout()
        btn_row.addStretch()
        cancel_btn = QPushButton("取消")
        cancel_btn.clicked.connect(self.reject)
        generate_btn = QPushButton("开始生成")
        generate_btn.setDefault(True)
        generate_btn.clicked.connect(self._on_accept)
        btn_row.addWidget(cancel_btn)
        btn_row.addWidget(generate_btn)
        layout.addLayout(btn_row)

    def _on_accept(self) -> None:
        self._sync_to_settings()
        self.accept()

    def _sync_to_settings(self) -> None:
        """Write the chosen non-secret options back to the in-memory Settings."""
        self._settings.tts_voice_id = self.voice_id()
        self._settings.tts_model = self.model()
        self._settings.tts_speed = self.speed()
        self._settings.tts_force = self.force()
        # API key is memory-only on Settings; it is never persisted by save().
        self._settings.tts_api_key = self.api_key()

    # --- result getters (read after exec() == Accepted) -------------------

    def voice_id(self) -> str:
        return self._voice_combo.currentText().strip() or "female-tianmei"

    def model(self) -> str:
        return self._model_edit.text().strip() or "speech-2.8-hd"

    def speed(self) -> float:
        return self._speed_spin.value()

    def force(self) -> bool:
        return self._force_check.isChecked()

    def api_key(self) -> str:
        return self._key_edit.text().strip()
