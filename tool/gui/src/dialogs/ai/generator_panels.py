"""Panel builders for :class:`SectionAiDialog` (extracted, api-preserving).

Every builder takes the dialog (``dlg``) as its context and assigns widget
attributes back onto it, so the dialog keeps all original attribute and
method names (tests + signal wiring unchanged).
"""
from __future__ import annotations

from PySide6.QtCore import Qt
from PySide6.QtWidgets import (
    QCheckBox,
    QComboBox,
    QDialogButtonBox,
    QFormLayout,
    QFrame,
    QGroupBox,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QProgressBar,
    QPushButton,
    QSpinBox,
    QSplitter,
    QTabWidget,
    QTextBrowser,
    QTextEdit,
    QVBoxLayout,
    QWidget,
)

from src.dialogs.ai.attachment_bar import AttachmentBar
from src.dialogs.ai.chat_view import ChatView
from src.dialogs.ai.generator_wizard_panel import GeneratorWizardPanel
from src.dialogs.ai.prompt_template_bar import PromptTemplateBar
from src.theme_tokens import BRAND_REED, BRAND_TEAL, BRAND_TEAL_DARK
from src.widgets.json_editor import JsonEditor
from src.widgets.result_preview import ResultPreviewWidget


def build_ui(dlg) -> None:
    root = QVBoxLayout(dlg)
    root.setSpacing(14)
    root.setContentsMargins(16, 16, 16, 16)

    dlg._beta_banner = dlg._build_beta_banner()
    dlg._header_bar = dlg._build_header_bar()
    dlg._spec_bar = dlg._build_spec_bar()
    root.addWidget(dlg._beta_banner)
    root.addWidget(dlg._header_bar)
    root.addWidget(dlg._spec_bar)

    dlg._stack = QVBoxLayout()
    dlg._stack.setSpacing(0)
    dlg._stack.setContentsMargins(0, 0, 0, 0)
    dlg._normal_panel = dlg._build_normal_panel()
    dlg._wish_panel = dlg._build_wish_panel()
    dlg._stack.addWidget(dlg._normal_panel)
    dlg._stack.addWidget(dlg._wish_panel)
    root.addLayout(dlg._stack, 1)

    dlg._build_template_selector()
    dlg._template_bar.set_library(dlg._prompt_library)
    dlg._template_bar.template_applied.connect(dlg._on_template_applied)
    dlg._template_bar.history_applied.connect(dlg._on_history_applied)
    dlg.topic_edit.textChanged.connect(dlg._on_topic_text_changed)
    dlg.extra_edit.textChanged.connect(dlg._on_topic_text_changed)

    buttons = QDialogButtonBox(
        QDialogButtonBox.StandardButton.Ok
        | QDialogButtonBox.StandardButton.Cancel
    )
    buttons.button(QDialogButtonBox.StandardButton.Ok).setText("导入到课程")
    buttons.accepted.connect(dlg._on_accept)
    buttons.rejected.connect(dlg.reject)
    dlg._button_box = buttons
    root.addWidget(buttons)

    dlg._update_mode_ui()
    dlg._set_tab_order()


def set_tab_order(dlg) -> None:
    """Keyboard tab order for the wish-mode input cluster."""
    from PySide6.QtWidgets import QWidget as _W

    _W.setTabOrder(dlg.input_edit, dlg.attach_btn)
    _W.setTabOrder(dlg.attach_btn, dlg.send_btn)
    _W.setTabOrder(dlg.send_btn, dlg.wish_btn)
    _W.setTabOrder(dlg.wish_btn, dlg._enter_to_send)
    _W.setTabOrder(dlg._enter_to_send, dlg.expand_btn)


def build_beta_banner(dlg) -> QWidget:
    widget = QWidget()
    layout = QHBoxLayout(widget)
    layout.setContentsMargins(10, 8, 10, 8)
    layout.setSpacing(8)
    widget.setStyleSheet(
        f"background-color: {dlg._pal('ai_beta_bg', '#664400')}; "
        f"color: {dlg._pal('ai_beta_text', '#FFD93D')}; border-radius: 6px;"
    )
    label = QLabel(
        "AI 生成结果仅供参考，请人工校验。本功能会消耗大量 token，"
        "且建议模型支持 1M 上下文窗口。"
    )
    label.setWordWrap(True)
    layout.addWidget(label)
    return widget


def build_header_bar(dlg) -> QWidget:
    widget = QWidget()
    layout = QHBoxLayout(widget)
    layout.setContentsMargins(0, 0, 0, 0)
    layout.setSpacing(12)

    mode_label = QLabel("<b>生成模式</b>")
    layout.addWidget(mode_label)

    dlg.mode_combo = QComboBox()
    dlg.mode_combo.addItem("普通模式", "normal")
    dlg.mode_combo.addItem("许愿模式", "wish")
    dlg.mode_combo.currentIndexChanged.connect(dlg._on_mode_changed)
    layout.addWidget(dlg.mode_combo)

    layout.addStretch()

    dlg.api_status = QLabel(f"<font color='{dlg._pal('error', '#E74C3C')}'>未配置</font>")
    dlg.api_status.setStyleSheet("font-size: 12px;")
    layout.addWidget(dlg.api_status)

    dlg.api_hint = QLabel("AI 配置请在工具栏「设置」中管理。")
    dlg.api_hint.setObjectName("hintLabel")
    layout.addWidget(dlg.api_hint)
    return widget


def build_spec_bar(dlg) -> QWidget:
    widget = QWidget()
    layout = QHBoxLayout(widget)
    layout.setContentsMargins(0, 0, 0, 0)
    layout.setSpacing(12)

    form = QFormLayout()
    form.setContentsMargins(0, 0, 0, 0)
    form.setSpacing(6)

    dlg.language_edit = QLineEdit("Turkish")
    dlg.language_edit.setMaximumWidth(120)
    form.addRow("目标语言:", dlg.language_edit)

    dlg.source_language_edit = QLineEdit("Chinese")
    dlg.source_language_edit.setMaximumWidth(120)
    form.addRow("源语言:", dlg.source_language_edit)

    dlg.level_combo = QComboBox()
    for lvl in ("A1", "A2", "B1", "B2", "C1"):
        dlg.level_combo.addItem(lvl)
    form.addRow("等级:", dlg.level_combo)
    layout.addLayout(form)

    row = QHBoxLayout()
    row.setSpacing(8)
    dlg.unit_spin = QSpinBox()
    dlg.unit_spin.setRange(1, 5)
    dlg.unit_spin.setValue(1)
    row.addWidget(QLabel("单元数:"))
    row.addWidget(dlg.unit_spin)
    dlg.lessons_spin = QSpinBox()
    dlg.lessons_spin.setRange(1, 5)
    dlg.lessons_spin.setValue(3)
    row.addWidget(QLabel("课时:"))
    row.addWidget(dlg.lessons_spin)
    layout.addLayout(row)

    layout.addStretch()

    dlg.extra_edit = QLineEdit()
    dlg.extra_edit.setPlaceholderText("可选：额外指令")
    dlg.extra_edit.setMaximumWidth(220)
    layout.addWidget(QLabel("额外:"))
    layout.addWidget(dlg.extra_edit)
    return widget


def build_template_selector(dlg) -> QWidget:
    if getattr(dlg, "_template_bar", None) is not None:
        return dlg._template_bar
    bar = PromptTemplateBar()
    bar.template_changed.connect(dlg._on_template_changed_value)
    bar.genre_toggled.connect(dlg._on_genre_toggled)
    dlg._template_bar = bar
    dlg.template_combo = bar.template_combo
    dlg._template_cards = bar._template_cards
    dlg.genre_switch = bar.genre_switch
    return bar


def build_normal_panel(dlg) -> QWidget:
    widget = QWidget()
    layout = QVBoxLayout(widget)
    layout.setSpacing(12)
    layout.setContentsMargins(0, 0, 0, 0)

    dlg.normal_tabs = QTabWidget()
    dlg._topic_panel = dlg._build_topic_panel()
    dlg._wizard_panel = dlg._build_wizard_panel()
    dlg.normal_tabs.addTab(dlg._topic_panel, "主题生成")
    dlg.normal_tabs.addTab(dlg._wizard_panel, "向导生成")
    dlg.normal_tabs.currentChanged.connect(dlg._on_normal_tab_changed)
    result_group = dlg._build_result_group()

    dlg._normal_splitter = QSplitter(Qt.Orientation.Horizontal)
    dlg._normal_splitter.setContentsMargins(0, 0, 0, 0)
    dlg._normal_splitter.addWidget(dlg.normal_tabs)
    dlg._normal_splitter.addWidget(result_group)
    dlg._normal_splitter.setStretchFactor(0, 2)
    dlg._normal_splitter.setStretchFactor(1, 3)
    dlg._normal_splitter.setCollapsible(0, False)
    dlg._normal_splitter.setCollapsible(1, False)
    dlg._normal_splitter.setSizes([460, 580])
    layout.addWidget(dlg._normal_splitter, 1)
    return widget


def build_topic_panel(dlg) -> QWidget:
    widget = QWidget()
    layout = QVBoxLayout(widget)
    layout.setSpacing(12)
    layout.setContentsMargins(0, 0, 0, 0)

    dlg._normal_template_slot = QVBoxLayout()
    dlg._normal_template_slot.setContentsMargins(0, 0, 0, 0)
    layout.addLayout(dlg._normal_template_slot)

    if dlg._edit_mode is not None:
        from PySide6.QtWidgets import QPlainTextEdit
        scope = dlg._edit_mode.get("scope", "section")
        scope_id = dlg._edit_mode.get("scope_id", "")

        info_lbl = QLabel(f"<b>正在编辑 {scope.upper()} : {scope_id}</b>")
        from src.theme import current_palette as _cp
        info_lbl.setStyleSheet(f"color: {_cp()['info']};")
        layout.addWidget(info_lbl)

        layout.addWidget(QLabel("修改要求/指令 (例如：增加两个练习题，补充单词Merhaba)："))
        dlg.edit_instruction_input = QPlainTextEdit()
        dlg.edit_instruction_input.setPlaceholderText("你想对该节点做出什么具体的改变？AI 将根据此指令进行精确重写。")
        dlg.edit_instruction_input.setMaximumHeight(80)
        layout.addWidget(dlg.edit_instruction_input)

    layout.addWidget(dlg._build_topic_row())
    return widget


def build_topic_row(dlg) -> QWidget:
    widget = QWidget()
    layout = QHBoxLayout(widget)
    layout.setContentsMargins(0, 0, 0, 0)
    layout.setSpacing(8)

    dlg.topic_edit = QLineEdit()
    dlg.topic_edit.setPlaceholderText("例如：旅行词汇 [intro]")
    layout.addWidget(QLabel("主题:"))
    layout.addWidget(dlg.topic_edit, 1)

    dlg.generate_btn = QPushButton("生成课程")
    dlg.generate_btn.setToolTip("按主题和规格直接生成 JSON")
    dlg.generate_btn.clicked.connect(dlg._on_generate_normal)
    layout.addWidget(dlg.generate_btn)
    return widget


def build_result_group(dlg) -> QGroupBox:
    grp = QGroupBox("生成结果（可编辑 JSON）")
    layout = QVBoxLayout(grp)
    layout.setSpacing(8)
    dlg.result_preview = ResultPreviewWidget(dlg.adapter, grp)
    dlg.result_preview.setVisible(False)
    dlg.result_preview.validity_changed.connect(dlg._on_preview_validity)
    dlg.result_preview.validate_btn.clicked.disconnect()
    dlg.result_preview.validate_btn.clicked.connect(dlg._on_validate_from_editor)
    layout.addWidget(dlg.result_preview)
    dlg.json_edit = JsonEditor()
    dlg.json_edit.restyle(dlg._chat_palette())
    dlg.result_preview.node_activated.connect(dlg._on_preview_node_activated)

    dlg._normal_json_host = QVBoxLayout()
    dlg._normal_json_host.setContentsMargins(0, 0, 0, 0)
    dlg._normal_json_host.addWidget(dlg.json_edit)
    layout.addLayout(dlg._normal_json_host, 1)
    dlg._json_window_btn = QPushButton("↗ JSON 独立窗口")
    dlg._json_window_btn.setToolTip("把 JSON 编辑器弹到独立窗口，腾出空间")
    dlg._json_window_btn.setCheckable(True)
    dlg._json_window_btn.toggled.connect(dlg._on_json_window_toggled)
    layout.addWidget(dlg._json_window_btn)

    row = QHBoxLayout()
    row.setSpacing(8)
    dlg.reset_btn = QPushButton("恢复 AI 原始输出")
    dlg.reset_btn.clicked.connect(dlg._on_reset)
    dlg.reset_btn.setEnabled(False)
    row.addWidget(dlg.reset_btn)
    dlg.validate_btn = QPushButton("校验 JSON")
    dlg.validate_btn.clicked.connect(dlg._on_validate_json)
    row.addWidget(dlg.validate_btn)
    dlg.diff_btn = QPushButton("查看 diff")
    dlg.diff_btn.setToolTip("对比编辑前后的单元/课时/资源增删改")
    dlg.diff_btn.clicked.connect(dlg._on_view_diff)
    dlg.diff_btn.setVisible(False)
    row.addWidget(dlg.diff_btn)
    dlg.try_btn = QPushButton("试做")
    dlg.try_btn.setToolTip("挑一节课试做，检查题目与答案是否正确")
    dlg.try_btn.clicked.connect(dlg._on_try_preview)
    dlg.try_btn.setVisible(False)
    row.addWidget(dlg.try_btn)
    row.addStretch()
    layout.addLayout(row)

    dlg.progress = QProgressBar()
    dlg.progress.setRange(0, 0)
    dlg.progress.setVisible(False)
    progress_row = QHBoxLayout()
    progress_row.setSpacing(8)
    progress_row.addWidget(dlg.progress)
    dlg.stage_label = QLabel("")
    dlg.stage_label.setStyleSheet(
        f"color: {dlg._pal('ai_accent', BRAND_REED)}; font-size: 12px;"
    )
    dlg.stage_label.setVisible(False)
    progress_row.addWidget(dlg.stage_label)
    progress_row.addStretch()
    dlg.usage_label = QLabel("")
    dlg.usage_label.setStyleSheet(
        f"color: {dlg._pal('text_secondary', '#9CA3AF')}; font-size: 11px;"
    )
    dlg.usage_label.setVisible(False)
    progress_row.addWidget(dlg.usage_label)
    layout.addLayout(progress_row)
    return grp


def build_wish_panel(dlg) -> QWidget:
    widget = QWidget()
    layout = QVBoxLayout(widget)
    layout.setSpacing(12)
    layout.setContentsMargins(0, 0, 0, 0)

    hint_row = QHBoxLayout()
    hint_row.setContentsMargins(0, 0, 0, 0)
    hint_row.setSpacing(8)
    hint = QLabel(
        "许愿模式：像聊天一样描述课程需求，把图片、PDF、Word 或文本文件直接拖入窗口作为参考。"
    )
    hint.setWordWrap(True)
    hint.setStyleSheet(
        f"color: {dlg._pal('text_secondary', '#9CA3AF')}; font-size: 12px;"
    )
    hint_row.addWidget(hint, 1)
    dlg.expand_btn = QPushButton("↕ 放大聊天")
    dlg.expand_btn.setToolTip("把聊天区放大成独立可缩放窗口（再次点击还原）")
    dlg.expand_btn.setCursor(Qt.CursorShape.PointingHandCursor)
    dlg.expand_btn.setStyleSheet(
        "QPushButton {"
        f"  background-color: {dlg._pal('ai_card_bg', '#1F232C')};"
        f"  color: {dlg._pal('ai_accent', BRAND_REED)};"
        f"  border: 1px solid {dlg._pal('ai_bubble_bg', '#2C313C')};"
        "  border-radius: 6px;"
        "  padding: 4px 10px;"
        "  font-size: 12px;"
        "}"
        f"QPushButton:hover {{ border: 1px solid {dlg._pal('ai_accent_border', BRAND_TEAL)}; }}"
    )
    dlg.expand_btn.setCheckable(True)
    dlg.expand_btn.toggled.connect(dlg._on_expand_toggled)
    hint_row.addWidget(dlg.expand_btn)
    layout.addLayout(hint_row)

    dlg._wish_template_slot = QVBoxLayout()
    dlg._wish_template_slot.setContentsMargins(0, 0, 0, 0)
    layout.addLayout(dlg._wish_template_slot)

    chat_container = QWidget()
    chat_container.setStyleSheet(
        f"background-color: {dlg._pal('ai_chat_bg', '#1A1D23')}; "
        f"border: 1px solid {dlg._pal('ai_bubble_bg', '#2C313C')}; border-radius: 8px;"
    )
    chat_layout = QVBoxLayout(chat_container)
    chat_layout.setSpacing(0)
    chat_layout.setContentsMargins(0, 0, 0, 0)

    dlg.chat_view = ChatView()
    dlg.chat_view.setPlaceholderText("对话记录会显示在这里...")
    dlg.chat_view.restyle(dlg._chat_palette())
    chat_layout.addWidget(dlg.chat_view)

    dlg.wish_progress = QProgressBar()
    dlg.wish_progress.setRange(0, 0)
    dlg.wish_progress.setVisible(False)
    dlg.wish_stage_label = QLabel("")
    dlg.wish_stage_label.setStyleSheet(
        f"color: {dlg._pal('ai_accent', BRAND_REED)}; font-size: 12px;"
    )
    dlg.wish_stage_label.setVisible(False)
    dlg.wish_usage_label = QLabel("")
    dlg.wish_usage_label.setStyleSheet(
        f"color: {dlg._pal('text_secondary', '#9CA3AF')}; font-size: 11px;"
    )
    dlg.wish_usage_label.setVisible(False)
    progress_row = QHBoxLayout()
    progress_row.setSpacing(8)
    progress_row.setContentsMargins(0, 0, 0, 0)
    progress_row.addWidget(dlg.wish_progress)
    progress_row.addWidget(dlg.wish_stage_label)
    progress_row.addStretch()
    progress_row.addWidget(dlg.wish_usage_label)

    dlg._result_frame = QFrame()
    dlg._result_frame.setStyleSheet(
        f"QFrame {{ border: 1px solid {dlg._pal('ai_bubble_bg', '#2C313C')}; "
        f"border-radius: 6px; background-color: {dlg._pal('ai_card_bg', '#1F232C')}; }}"
    )
    result_v = QVBoxLayout(dlg._result_frame)
    result_v.setContentsMargins(8, 6, 8, 6)
    result_v.setSpacing(6)
    result_header = QHBoxLayout()
    result_header.setSpacing(8)
    dlg._result_summary = QLabel("生成后这里显示课程概要")
    dlg._result_summary.setStyleSheet(
        f"color: {dlg._pal('text_secondary', '#9CA3AF')}; font-size: 12px;"
    )
    result_header.addWidget(dlg._result_summary, 1)
    dlg._result_toggle = QPushButton("展开")
    dlg._result_toggle.setToolTip("展开/收起课程预览")
    dlg._result_toggle.setCursor(Qt.CursorShape.PointingHandCursor)
    dlg._result_toggle.setCheckable(True)
    dlg._result_toggle.toggled.connect(dlg._on_result_toggle)
    result_header.addWidget(dlg._result_toggle)
    result_v.addLayout(result_header)

    dlg.wish_result_preview = ResultPreviewWidget(dlg.adapter, widget)
    dlg.wish_result_preview.setVisible(False)
    dlg.wish_result_preview.validity_changed.connect(dlg._on_preview_validity)
    dlg.wish_result_preview.validate_btn.clicked.disconnect()
    dlg.wish_result_preview.validate_btn.clicked.connect(dlg._on_validate_from_editor)
    dlg.wish_result_preview.node_activated.connect(dlg._on_preview_node_activated)
    result_v.addWidget(dlg.wish_result_preview)

    dlg.wish_json_edit = JsonEditor()
    dlg.wish_json_edit.restyle(dlg._chat_palette())
    dlg.wish_json_edit.setVisible(False)
    dlg._wish_json_host = QVBoxLayout()
    dlg._wish_json_host.setContentsMargins(0, 0, 0, 0)
    dlg._wish_json_host.addWidget(dlg.wish_json_edit)
    result_v.addLayout(dlg._wish_json_host, 1)
    dlg._wish_json_window_btn = QPushButton("↗ JSON 独立窗口")
    dlg._wish_json_window_btn.setToolTip("把 JSON 编辑器弹到独立窗口，腾出空间")
    dlg._wish_json_window_btn.setCheckable(True)
    dlg._wish_json_window_btn.toggled.connect(dlg._on_json_window_toggled)
    dlg._wish_json_window_btn.setVisible(False)
    result_v.addWidget(dlg._wish_json_window_btn)

    dlg.explain_group = QGroupBox("AI 通俗解释")
    explain_layout = QVBoxLayout(dlg.explain_group)
    explain_layout.setContentsMargins(8, 8, 8, 8)
    explain_layout.setSpacing(4)
    dlg.explain_label = QTextBrowser()
    dlg.explain_label.setOpenExternalLinks(True)
    dlg.explain_label.setStyleSheet(
        "QTextBrowser {"
        "  border: none;"
        f"  background-color: {dlg._pal('ai_card_bg', '#1F232C')};"
        f"  color: {dlg._pal('ai_accent', BRAND_REED)};"
        "  font-family: system-ui, sans-serif;"
        "  font-size: 13px;"
        "  padding: 8px;"
        "}"
    )
    dlg.explain_label.setPlaceholderText("生成课程后，AI 会在这里用通俗语言解释课程设计。")
    dlg.explain_label.setMaximumHeight(180)
    explain_layout.addWidget(dlg.explain_label)
    dlg.explain_group.setVisible(False)
    result_v.addWidget(dlg.explain_group)

    dlg._result_frame.setVisible(False)

    dlg._attachment_bar = AttachmentBar()
    dlg._attachment_bar.attachments_changed.connect(dlg._on_attachments_changed)

    input_row = QHBoxLayout()
    input_row.setSpacing(10)
    dlg.input_edit = QTextEdit()
    dlg.input_edit.setPlaceholderText("输入你想说的，Ctrl+Enter 发送...")
    dlg.input_edit.setMaximumHeight(80)
    dlg.input_edit.setStyleSheet(
        "QTextEdit {"
        f"  border: 1px solid {dlg._pal('ai_bubble_bg', '#2C313C')};"
        "  border-radius: 8px;"
        f"  background-color: {dlg._pal('ai_card_bg', '#1F232C')};"
        "  font-family: system-ui, sans-serif;"
        "  font-size: 14px;"
        "  padding: 8px;"
        "}"
    )
    dlg.input_edit.keyPressEvent = dlg._input_key_press  # type: ignore[method-assign]
    input_row.addWidget(dlg.input_edit, 1)

    action_layout = QVBoxLayout()
    action_layout.setSpacing(8)
    dlg.attach_btn = QPushButton("附件")
    dlg.attach_btn.setToolTip("上传图片 / PDF / Word / 文本文件")
    dlg.attach_btn.clicked.connect(dlg._on_attach_files)
    action_layout.addWidget(dlg.attach_btn)

    dlg.send_btn = QPushButton("发送")
    dlg.send_btn.setToolTip("Ctrl+Enter 快捷发送")
    dlg.send_btn.clicked.connect(dlg._on_send_message)
    action_layout.addWidget(dlg.send_btn)

    dlg.wish_btn = QPushButton("我感觉差不多了")
    dlg.wish_btn.setToolTip("让 AI 根据对话生成课程")
    dlg.wish_btn.setStyleSheet(
        "QPushButton {"
        f"  background-color: {dlg._pal('ai_user_bubble', BRAND_TEAL_DARK)};"
        "  color: #FFFFFF;"
        "  border: none;"
        "  border-radius: 6px;"
        "  padding: 6px 12px;"
        "}"
        f"QPushButton:hover {{ background-color: {dlg._pal('ai_accent_border', BRAND_TEAL)}; }}"
    )
    dlg.wish_btn.clicked.connect(dlg._on_wish_generate)
    action_layout.addWidget(dlg.wish_btn)
    dlg._enter_to_send = QCheckBox("Enter 发送")
    dlg._enter_to_send.setChecked(True)
    dlg._enter_to_send.setToolTip("勾选后按 Enter 直接发送（Shift+Enter 换行）；Ctrl+Enter 始终发送")
    action_layout.addWidget(dlg._enter_to_send)
    action_layout.addStretch()
    input_row.addLayout(action_layout)

    input_widget = QWidget()
    input_widget.setLayout(input_row)
    dlg._wish_input_widget = input_widget

    input_stack = QWidget()
    input_stack_layout = QVBoxLayout(input_stack)
    input_stack_layout.setContentsMargins(0, 0, 0, 0)
    input_stack_layout.setSpacing(4)
    input_stack_layout.addWidget(dlg._attachment_bar)
    input_stack_layout.addWidget(input_widget)

    left_col = QSplitter(Qt.Orientation.Vertical)
    left_col.setContentsMargins(0, 0, 0, 0)
    left_col.addWidget(chat_container)
    left_col.addWidget(input_stack)
    left_col.setStretchFactor(0, 1)
    left_col.setStretchFactor(1, 0)
    left_col.setCollapsible(0, False)
    left_col.setCollapsible(1, False)
    left_col.setSizes([520, 150])

    dlg.wish_splitter = QSplitter(Qt.Orientation.Horizontal)
    dlg.wish_splitter.setContentsMargins(0, 0, 0, 0)
    dlg.wish_splitter.addWidget(left_col)
    dlg.wish_splitter.addWidget(dlg._result_frame)
    dlg.wish_splitter.setStretchFactor(0, 3)
    dlg.wish_splitter.setStretchFactor(1, 2)
    dlg.wish_splitter.setCollapsible(0, False)
    dlg.wish_splitter.setCollapsible(1, False)
    dlg.wish_splitter.setSizes([620, 420])
    dlg._wish_left_col = left_col

    layout.addLayout(progress_row)
    layout.addWidget(dlg.wish_splitter, 1)
    return widget
