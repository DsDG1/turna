"""Wizard page builders for TextbookImportDialog (extracted, api-preserving)."""
from __future__ import annotations

from PySide6.QtCore import Qt
from PySide6.QtWidgets import (
    QButtonGroup,
    QComboBox,
    QGroupBox,
    QHBoxLayout,
    QLabel,
    QListWidget,
    QProgressBar,
    QPushButton,
    QRadioButton,
    QSpinBox,
    QSplitter,
    QStackedWidget,
    QTextEdit,
    QVBoxLayout,
    QWidget,
)

from src.dialogs.textbook_import.constants import (
    _STEP_TITLES,
    _STEPPER_STAGES,
    _STRATEGY_OPTIONS,
)
from src.theme import ai_color, current_palette
from src.widgets.bulk_import_preview_panel import BulkImportPreviewPanel
from src.widgets.resource_review_table import ResourceReviewTable


def build_ui(dlg) -> None:
    root = QVBoxLayout(dlg)
    root.setContentsMargins(16, 16, 16, 16)
    root.setSpacing(12)

    # Left stepper + right stacked pages.
    body = QHBoxLayout()
    dlg._stepper_widget = QWidget()
    stepper_col = QVBoxLayout(dlg._stepper_widget)
    stepper_col.setContentsMargins(0, 0, 0, 0)
    stepper_col.setSpacing(6)
    dlg._stepper_labels: dict[int, QLabel] = {}
    for step in _STEPPER_STAGES:
        lbl = QLabel(_STEP_TITLES[step])
        lbl.setFixedWidth(120)
        dlg._stepper_labels[step] = lbl
        stepper_col.addWidget(lbl)
    stepper_col.addStretch()
    body.addWidget(dlg._stepper_widget)

    dlg._stack = QStackedWidget()
    dlg._stack.addWidget(dlg._build_source_page())
    dlg._stack.addWidget(dlg._build_knowledge_page())
    dlg._stack.addWidget(dlg._build_import_page())
    body.addWidget(dlg._stack, 1)
    root.addLayout(body, 1)

    # Bottom progress row + cancel (wrappable so hosts can hide it).
    dlg._bottom_bar = QWidget()
    bottom = QHBoxLayout(dlg._bottom_bar)
    bottom.setContentsMargins(0, 0, 0, 0)
    dlg._progress = QProgressBar()
    dlg._progress.setRange(0, 0)
    dlg._progress.setVisible(False)
    bottom.addWidget(dlg._progress)
    dlg._stage_label = QLabel("")
    dlg._stage_label.setStyleSheet(f"color: {ai_color('ai_accent')}; font-size: 12px;")
    bottom.addWidget(dlg._stage_label)
    bottom.addStretch()
    dlg._usage_label = QLabel("")
    dlg._usage_label.setStyleSheet(
        f"color: {current_palette()['text_secondary']}; font-size: 11px;"
    )
    bottom.addWidget(dlg._usage_label)
    dlg._autosave_label = QLabel("")
    dlg._autosave_label.setStyleSheet(
        f"color: {current_palette()['text_secondary']}; font-size: 11px;"
    )
    bottom.addWidget(dlg._autosave_label)
    dlg._cancel_btn = QPushButton("取消")
    dlg._cancel_btn.clicked.connect(dlg._on_cancel)
    bottom.addWidget(dlg._cancel_btn)
    root.addWidget(dlg._bottom_bar)



def build_source_page(dlg) -> QWidget:
    """素材页: file pick + inline preview + chapter selection (P2-1)."""
    page = QWidget()
    lay = QVBoxLayout(page)
    lay.addWidget(QLabel("拖入教材文件，或点击「选择文件」。支持 .md / .txt / .pdf（文本原生 PDF）。"))
    row = QHBoxLayout()
    dlg._pick_btn = QPushButton("选择文件…")
    dlg._pick_btn.clicked.connect(dlg._on_pick_file)
    row.addWidget(dlg._pick_btn)
    dlg._picked_label = QLabel("未选择")
    row.addWidget(dlg._picked_label, 1)
    dlg._load_busy_label = QLabel("解析中…（可关闭，进度已自动保存）")
    dlg._load_busy_label.setStyleSheet(
        f"color: {current_palette()['ai_accent']};"
    )
    dlg._load_busy_label.setVisible(False)
    row.addWidget(dlg._load_busy_label)
    lay.addLayout(row)
    dlg._parse_error_label = QLabel("")
    dlg._parse_error_label.setStyleSheet(f"color: {current_palette()['error']};")
    dlg._parse_error_label.setWordWrap(True)
    dlg._parse_error_label.setVisible(False)
    lay.addWidget(dlg._parse_error_label)
    dlg._preview_caption = QLabel("内容预览（前 2000 字）：")
    dlg._preview_caption.setVisible(False)
    lay.addWidget(dlg._preview_caption)
    dlg._parse_preview = QTextEdit()
    dlg._parse_preview.setReadOnly(True)
    dlg._parse_preview.setVisible(False)
    dlg._parse_preview.setMaximumHeight(140)
    lay.addWidget(dlg._parse_preview)

    # Chapter selection (formerly its own page).
    lay.addWidget(QLabel("勾选要导入的章节："))
    btns = QHBoxLayout()
    select_all = QPushButton("全选")
    select_all.clicked.connect(dlg._select_all_chapters)
    invert = QPushButton("反选")
    invert.clicked.connect(dlg._invert_chapters)
    btns.addWidget(select_all)
    btns.addWidget(invert)
    btns.addStretch()
    lay.addLayout(btns)
    dlg._chapter_list = QListWidget()
    lay.addWidget(dlg._chapter_list, 1)
    dlg._empty_chapters_label = QLabel("未切到章节（请确认标题层级 ≥ ##）")
    dlg._empty_chapters_label.setStyleSheet(
        f"color: {current_palette()['text_secondary']};"
    )
    dlg._empty_chapters_label.setVisible(False)
    lay.addWidget(dlg._empty_chapters_label)
    # Extraction options (bookplan2 Phase 5): textbook type + concurrency.
    from src.backend.textbook_presets import preset_names, preset_for

    opt_row = QHBoxLayout()
    opt_row.addWidget(QLabel("教材类型："))
    dlg._preset_combo = QComboBox()
    for name in preset_names():
        preset = preset_for(name)
        dlg._preset_combo.addItem(preset.label, name)
    dlg._preset_combo.currentIndexChanged.connect(dlg._apply_preset)
    opt_row.addWidget(dlg._preset_combo)
    opt_row.addSpacing(12)
    opt_row.addWidget(QLabel("并发："))
    dlg._concurrency_spin = QSpinBox()
    dlg._concurrency_spin.setRange(1, 3)
    dlg._concurrency_spin.setValue(1)
    dlg._concurrency_spin.setToolTip("同时抽取的章节数（1=串行，越大越快但 token 并发消耗更高）")
    dlg._concurrency_spin.valueChanged.connect(dlg._on_concurrency_changed)
    opt_row.addWidget(dlg._concurrency_spin)
    opt_row.addStretch()
    lay.addLayout(opt_row)

    next_btn = QPushButton("提取知识点 →")
    next_btn.clicked.connect(dlg._start_extraction)
    lay.addWidget(next_btn)
    return page



def build_knowledge_page(dlg) -> QWidget:
    """知识页: extraction log on top, review area below (P2-1)."""
    page = QWidget()
    lay = QVBoxLayout(page)

    splitter = QSplitter(Qt.Orientation.Vertical)

    # Top: extraction progress log.
    log_box = QWidget()
    log_lay = QVBoxLayout(log_box)
    log_lay.setContentsMargins(0, 0, 0, 0)
    log_lay.addWidget(QLabel("提取日志："))
    # U0-6: extract status light (window progress / cascade / reextract).
    dlg._extract_status_label = QLabel("抽取状态：空闲")
    dlg._extract_status_label.setWordWrap(True)
    dlg._extract_status_label.setStyleSheet(
        f"color: {current_palette()['text_secondary']}; font-size: 11px; font-weight: 600;"
    )
    log_lay.addWidget(dlg._extract_status_label)
    dlg._extract_log = QTextEdit()
    dlg._extract_log.setReadOnly(True)
    log_lay.addWidget(dlg._extract_log)
    splitter.addWidget(log_box)

    # Bottom: review area (formerly its own page).
    review_box = QWidget()
    review_lay = QVBoxLayout(review_box)
    review_lay.setContentsMargins(0, 0, 0, 0)
    review_lay.addWidget(
        QLabel("审校抽取结果：可编辑、批量删除；红色=错误，黄色=警告。")
    )

    review_splitter = QSplitter(Qt.Orientation.Horizontal)

    # Left: chapter quality list + recovery controls.
    left = QWidget()
    left_lay = QVBoxLayout(left)
    left_lay.addWidget(QLabel("章节质量"))
    dlg._chapter_quality_list = QListWidget()
    dlg._chapter_quality_list.currentRowChanged.connect(
        dlg._on_chapter_quality_selected
    )
    left_lay.addWidget(dlg._chapter_quality_list, 1)

    dlg._chapter_recovery_label = QLabel("")
    dlg._chapter_recovery_label.setStyleSheet(
        f"color: {current_palette()['text_secondary']}; font-size: 11px;"
    )
    dlg._chapter_recovery_label.setWordWrap(True)
    left_lay.addWidget(dlg._chapter_recovery_label)

    dlg._retry_btn = QPushButton("重试本章")
    dlg._retry_btn.clicked.connect(dlg._on_retry_standard_clicked)
    dlg._retry_vocab_btn = QPushButton("仅抽词汇")
    dlg._retry_vocab_btn.clicked.connect(dlg._on_retry_vocab_clicked)
    dlg._skip_btn = QPushButton("跳过本章")
    dlg._skip_btn.clicked.connect(dlg._on_skip_chapter)
    dlg._reextract_btn = QPushButton("按质量重抽")
    dlg._reextract_btn.setToolTip(
        "把本章的质量问题回灌给 AI，重新抽取并替换本章知识点"
    )
    dlg._reextract_btn.clicked.connect(dlg._on_reextract_chapter)
    for btn in (
        dlg._retry_btn,
        dlg._retry_vocab_btn,
        dlg._skip_btn,
        dlg._reextract_btn,
    ):
        btn.setVisible(False)
        left_lay.addWidget(btn)

    review_splitter.addWidget(left)

    # Right: unified review table.
    dlg._review_table = ResourceReviewTable()
    dlg._review_table.rows_changed.connect(dlg._on_review_rows_changed)
    dlg._review_table.fix_requested.connect(dlg._on_ai_fix_requested)
    review_splitter.addWidget(dlg._review_table)
    review_splitter.setStretchFactor(0, 1)
    review_splitter.setStretchFactor(1, 4)

    review_lay.addWidget(review_splitter, 1)

    dlg._quality_summary_label = QLabel("")
    review_lay.addWidget(dlg._quality_summary_label)

    splitter.addWidget(review_box)
    splitter.setStretchFactor(0, 1)
    splitter.setStretchFactor(1, 2)
    lay.addWidget(splitter, 1)

    # Navigate to the import / preview page (bookplan2 Phase 4).
    nav_row = QHBoxLayout()
    dlg._design_btn = QPushButton("AI 设计课程 →")
    dlg._design_btn.setToolTip("用资源池里的知识点，让 AI 编排成课程（课程工坊）")
    dlg._design_btn.clicked.connect(dlg._on_design_btn_clicked)
    # Only meaningful inside the workshop, which owns the design stage.
    dlg._design_btn.setVisible(dlg._embedded)
    nav_row.addWidget(dlg._design_btn)
    next_btn = QPushButton("下一步：预览导入 ->")
    next_btn.clicked.connect(dlg._goto_import_preview)
    nav_row.addWidget(next_btn)
    nav_row.addStretch(1)
    lay.addLayout(nav_row)
    return page



def build_import_page(dlg) -> QWidget:
    page = QWidget()
    lay = QVBoxLayout(page)
    lay.addWidget(QLabel("选择导入策略，预览每个章节将生成的 section 与冲突，确认后导入。"))

    # Strategy radio group.
    strategy_box = QGroupBox("导入策略")
    strategy_lay = QVBoxLayout(strategy_box)
    dlg._strategy_group = QButtonGroup(dlg)
    dlg._strategy_buttons: dict[str, QRadioButton] = {}
    for i, (value, label) in enumerate(_STRATEGY_OPTIONS):
        radio = QRadioButton(label)
        if i == 0:
            radio.setChecked(True)
        dlg._strategy_group.addButton(radio, i)
        dlg._strategy_buttons[value] = radio
        strategy_lay.addWidget(radio)
    dlg._strategy_group.idToggled.connect(dlg._on_strategy_id_toggled)
    lay.addWidget(strategy_box)

    # Bulk preview panel.
    dlg._preview_panel = BulkImportPreviewPanel()
    lay.addWidget(dlg._preview_panel, 1)

    btns = QHBoxLayout()
    back_btn = QPushButton("<- 返回审校")
    back_btn.clicked.connect(dlg._on_back_to_review_clicked)
    btns.addWidget(back_btn)
    btns.addStretch()
    dlg._import_btn = QPushButton("确认导入 ↗")
    dlg._import_btn.clicked.connect(dlg._on_import)
    btns.addWidget(dlg._import_btn)
    lay.addLayout(btns)
    return page

