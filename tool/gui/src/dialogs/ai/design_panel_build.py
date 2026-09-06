"""UI construction for :class:`DesignPanel` (extracted, api-preserving)."""
from __future__ import annotations

from PySide6.QtWidgets import (
    QCheckBox,
    QComboBox,
    QGroupBox,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QPushButton,
    QSpinBox,
    QTextBrowser,
    QVBoxLayout,
    QWidget,
)

from src.application.ai_prompt_library import prompt_library
from src.backend.ai.facade import CHECKLIST_STEPS
from src.dialogs.ai.attachment_bar import AttachmentBar
from src.dialogs.ai.chat_view import ChatView
from src.dialogs.ai.prompt_template_bar import PromptTemplateBar
from src.widgets.json_editor import JsonEditor

_TEMPLATES = ("mixed", "intro", "practice", "review", "listening", "reading", "mastery")
_LEVELS = ("A1", "A2", "B1", "B2", "C1")


def build_ui(panel) -> None:
    layout = QVBoxLayout(panel)
    layout.setContentsMargins(8, 8, 8, 8)
    layout.setSpacing(6)

    panel._pool_label = QLabel("")
    panel._pool_label.setStyleSheet("font-weight: 600;")
    layout.addWidget(panel._pool_label)

    panel._param_hint = QLabel(
        "主参数（主题 / 等级 / 规模 / 生成模式）在中间「AI 轨道」设置。"
    )
    panel._param_hint.setWordWrap(True)
    panel._param_hint.setStyleSheet("font-size: 11px; opacity: 0.85;")
    layout.addWidget(panel._param_hint)

    # Hidden mirrors kept for tests / set_project restore; not shown.
    # Primary editing surface is Orbit when embedded in the workshop.
    panel._topic_edit = QLineEdit()
    panel._topic_edit.setVisible(False)
    panel._level_combo = QComboBox()
    panel._level_combo.addItems(_LEVELS)
    panel._level_combo.setVisible(False)
    panel._units_spin = QSpinBox()
    panel._units_spin.setRange(1, 5)
    panel._units_spin.setVisible(False)
    panel._lessons_spin = QSpinBox()
    panel._lessons_spin.setRange(1, 5)
    panel._lessons_spin.setValue(3)
    panel._lessons_spin.setVisible(False)
    panel._template_combo = QComboBox()
    panel._template_combo.addItems(_TEMPLATES)
    panel._template_combo.setVisible(False)
    panel._gen_mode_combo = QComboBox()
    panel._gen_mode_combo.addItem("快速（整节）", "fast")
    panel._gen_mode_combo.addItem("精修（流水线）", "phased")
    panel._gen_mode_combo.setVisible(False)
    panel._gen_mode_combo.currentIndexChanged.connect(panel._on_gen_mode_changed)
    panel._level_combo.currentTextChanged.connect(panel._on_level_text_changed)
    for w in (
        panel._topic_edit,
        panel._level_combo,
        panel._units_spin,
        panel._lessons_spin,
        panel._template_combo,
        panel._gen_mode_combo,
    ):
        layout.addWidget(w)

    # --- Chat (primary content of this panel) ---
    panel._chat_view = ChatView()
    layout.addWidget(panel._chat_view, 1)

    panel._ocr_enabled = False
    panel._attachment_bar = AttachmentBar(panel)
    panel._attachment_bar.ocr_requested.connect(panel.ocr_requested.emit)
    layout.addWidget(panel._attachment_bar)

    chat_row = QHBoxLayout()
    panel._attach_btn = QPushButton("附件")
    panel._attach_btn.setToolTip("添加图片 / PDF / Word / 文本文件作为参考")
    panel._attach_btn.clicked.connect(panel._on_attach_files)
    chat_row.addWidget(panel._attach_btn)
    panel._chat_input = QLineEdit()
    panel._chat_input.setPlaceholderText("与 AI 讨论课程设计…（回车发送）")
    panel._chat_input.returnPressed.connect(panel._on_send_chat)
    chat_row.addWidget(panel._chat_input, 1)
    panel._send_btn = QPushButton("发送")
    panel._send_btn.clicked.connect(panel._on_send_chat)
    chat_row.addWidget(panel._send_btn)
    layout.addLayout(chat_row)

    gen_row = QHBoxLayout()
    panel._generate_btn = QPushButton("按对话再生成")
    panel._generate_btn.setToolTip(
        "用当前聊天记录 + 中栏轨道参数生成/改写课程（无对话时等同中栏生成）"
    )
    panel._generate_btn.clicked.connect(panel._on_generate)
    gen_row.addWidget(panel._generate_btn)
    panel._stage_label = QLabel("")
    gen_row.addWidget(panel._stage_label)
    gen_row.addStretch(1)
    panel._usage_label = QLabel("")
    gen_row.addWidget(panel._usage_label)
    layout.addLayout(gen_row)

    panel._checklist_widget = QWidget()
    checklist_row = QHBoxLayout(panel._checklist_widget)
    checklist_row.setContentsMargins(0, 0, 0, 0)
    checklist_row.setSpacing(8)
    panel._checklist_labels: dict[str, QLabel] = {}
    for step in CHECKLIST_STEPS:
        label = QLabel()
        label.setStyleSheet("color: gray;")
        panel._checklist_labels[step] = label
        checklist_row.addWidget(label)
    checklist_row.addStretch(1)
    panel._render_pipeline_checklist({})
    panel._checklist_widget.setVisible(False)
    layout.addWidget(panel._checklist_widget)

    panel._fast_progress_label = QLabel("")
    panel._fast_progress_label.setStyleSheet("color: gray; font-size: 11px;")
    panel._fast_progress_label.setVisible(False)
    layout.addWidget(panel._fast_progress_label)

    # --- Advanced (collapsed): intent, extras, templates, pipeline skips ---
    panel._advanced_group = QGroupBox("高级：模板 · 意图 · 精修选项")
    panel._advanced_group.setCheckable(True)
    panel._advanced_group.setChecked(False)
    panel._advanced_group.setFlat(False)
    adv_lay = QVBoxLayout(panel._advanced_group)
    adv_lay.setSpacing(6)

    panel._pedagogy_badge = QLabel("")
    panel._pedagogy_badge.setStyleSheet(
        "color: #0f766e; font-size: 11px; font-weight: 600;"
    )
    adv_lay.addWidget(panel._pedagogy_badge)
    panel._refresh_pedagogy_badge()

    skip_row = QHBoxLayout()
    panel._skip_fix_check = QCheckBox("跳过修复")
    panel._skip_fix_check.setToolTip("精修流水线跳过 Fix 步")
    panel._skip_explain_check = QCheckBox("跳过解释")
    panel._skip_explain_check.setToolTip("精修流水线跳过 Explain 步")
    skip_row.addWidget(panel._skip_fix_check)
    skip_row.addWidget(panel._skip_explain_check)
    skip_row.addStretch(1)
    adv_lay.addLayout(skip_row)

    brief_row = QHBoxLayout()
    brief_row.addWidget(QLabel("编排意图:"))
    panel._brief_edit = QLineEdit()
    panel._brief_edit.setPlaceholderText("可选，如：前两章 intro，语法单独 review")
    brief_row.addWidget(panel._brief_edit, 1)
    adv_lay.addLayout(brief_row)

    extra_row = QHBoxLayout()
    extra_row.addWidget(QLabel("额外指令:"))
    panel._extra_edit = QLineEdit()
    panel._extra_edit.setPlaceholderText("可选；开启 [genre] 后可插入 [intro] 等")
    extra_row.addWidget(panel._extra_edit, 1)
    adv_lay.addLayout(extra_row)

    panel._template_bar = PromptTemplateBar(panel)
    panel._template_bar.set_library(prompt_library())
    panel._template_bar.template_applied.connect(panel._on_template_applied)
    panel._template_bar.history_applied.connect(panel._on_history_applied)
    panel._template_bar.template_changed.connect(panel._on_bar_template_changed)
    panel._template_bar.genre_toggled.connect(panel._on_genre_toggled)
    panel._template_combo.currentTextChanged.connect(panel._on_combo_template_changed)
    adv_lay.addWidget(panel._template_bar)

    layout.addWidget(panel._advanced_group)

    # --- JSON (collapsed by default) ---
    panel._json_group = QGroupBox("高级：草稿 JSON")
    panel._json_group.setCheckable(True)
    panel._json_group.setChecked(False)
    json_outer = QVBoxLayout(panel._json_group)
    panel._json_editor = JsonEditor()
    panel._json_editor.setMinimumHeight(120)
    json_outer.addWidget(panel._json_editor, 1)
    action_row = QHBoxLayout()
    panel._validate_btn = QPushButton("校验")
    panel._validate_btn.clicked.connect(panel._on_validate)
    action_row.addWidget(panel._validate_btn)
    panel._try_btn = QPushButton("试做")
    panel._try_btn.clicked.connect(panel._on_try_lesson)
    action_row.addWidget(panel._try_btn)
    panel._restore_raw_btn = QPushButton("恢复原始输出")
    panel._restore_raw_btn.setToolTip("放弃手动修改，回到 AI 刚生成的内容")
    panel._restore_raw_btn.clicked.connect(panel._on_restore_raw)
    action_row.addWidget(panel._restore_raw_btn)
    action_row.addStretch(1)
    panel._import_btn = QPushButton("导入到课程 ↗")
    panel._import_btn.clicked.connect(panel._on_import)
    action_row.addWidget(panel._import_btn)
    json_outer.addLayout(action_row)
    panel._validate_label = QLabel("")
    json_outer.addWidget(panel._validate_label)
    layout.addWidget(panel._json_group)

    panel._explain_group = QGroupBox("AI 通俗解释")
    panel._explain_group.setCheckable(True)
    panel._explain_group.setChecked(False)
    panel._explain_group.setVisible(False)
    explain_lay = QVBoxLayout(panel._explain_group)
    panel._explain_browser = QTextBrowser()
    panel._explain_browser.setMaximumHeight(120)
    explain_lay.addWidget(panel._explain_browser)
    layout.addWidget(panel._explain_group)

    for btn in (panel._validate_btn, panel._try_btn, panel._import_btn):
        btn.setEnabled(False)
    panel._restore_raw_btn.setEnabled(False)
    panel._on_gen_mode_changed(panel._gen_mode_combo.currentIndex())
