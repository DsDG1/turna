"""Extraction-prompt overrides tab for SettingsDialog (extracted)."""
from __future__ import annotations

import logging

logger = logging.getLogger(__name__)

from PySide6.QtWidgets import (
    QFormLayout,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QMessageBox,
    QPlainTextEdit,
    QPushButton,
    QVBoxLayout,
    QWidget,
)

from src.backend.knowledge_prompt import (
    KnowledgePromptTemplates,
    default_library,
    load_overrides_from,
)


def build_extraction_prompt_tab(dlg) -> QWidget:
    from PySide6.QtWidgets import QScrollArea

    outer = QWidget()
    outer_layout = QVBoxLayout(outer)
    outer_layout.setContentsMargins(12, 12, 12, 12)

    pair_row = QHBoxLayout()
    dlg.extraction_lang_edit = QLineEdit("Turkish")
    dlg.extraction_lang_edit.setPlaceholderText("目标语言，如 Turkish")
    dlg.extraction_src_edit = QLineEdit("Chinese")
    dlg.extraction_src_edit.setPlaceholderText("讲解语言，如 Chinese")
    load_btn = QPushButton("载入")
    load_btn.clicked.connect(dlg._load_extraction_fields)
    pair_row.addWidget(QLabel("目标语言:"))
    pair_row.addWidget(dlg.extraction_lang_edit)
    pair_row.addWidget(QLabel("讲解语言:"))
    pair_row.addWidget(dlg.extraction_src_edit)
    pair_row.addWidget(load_btn)
    pair_row.addStretch(1)
    outer_layout.addLayout(pair_row)

    scroll = QScrollArea()
    scroll.setWidgetResizable(True)
    content = QWidget()
    form = QFormLayout(content)
    form.setSpacing(8)
    dlg._extraction_edits: dict[str, QPlainTextEdit] = {}
    for key, label in dlg._EXTRACTION_FIELDS:
        edit = QPlainTextEdit()
        edit.setPlaceholderText("留空则使用内置默认")
        edit.setMinimumHeight(60 if key in ("intro", "vocab_intro", "system") else 110)
        dlg._extraction_edits[key] = edit
        form.addRow(label, edit)
    scroll.setWidget(content)
    outer_layout.addWidget(scroll, 1)

    btn_row = QHBoxLayout()
    save_btn = QPushButton("保存覆盖")
    save_btn.clicked.connect(dlg._on_extraction_save)
    delete_btn = QPushButton("删除覆盖")
    delete_btn.setObjectName("dangerButton")
    delete_btn.clicked.connect(dlg._on_extraction_delete)
    reset_btn = QPushButton("重置为默认")
    reset_btn.clicked.connect(dlg._fill_extraction_defaults)
    btn_row.addWidget(save_btn)
    btn_row.addWidget(delete_btn)
    btn_row.addWidget(reset_btn)
    btn_row.addStretch(1)
    outer_layout.addLayout(btn_row)

    hint = QLabel(
        "按语言对覆盖教材知识点抽取的 Prompt 模板。点「保存覆盖」后暂存，"
        "随设置对话框的「确定」一起生效；点「取消」则丢弃本次改动。"
        "删除覆盖后回落到内置默认。"
    )
    hint.setObjectName("hintLabel")
    hint.setWordWrap(True)
    outer_layout.addWidget(hint)

    # T17: pending actions for this dialog session, keyed by (lang, src).
    # A dict, not a single slot: staging zh/en and then switching the pair to
    # en/de silently dropped the first, even though its toast had already
    # promised it would apply on 确定.
    dlg._extraction_pending: dict[tuple[str, str], tuple[str, object]] = {}
    dlg._load_extraction_fields()
    return outer



def extraction_pair(dlg) -> tuple[str, str]:
    return (
        dlg.extraction_lang_edit.text().strip() or "Turkish",
        dlg.extraction_src_edit.text().strip() or "Chinese",
    )



def current_extraction_templates(dlg) -> KnowledgePromptTemplates:
    language, source_language = dlg._extraction_pair()
    blocks = dlg._prompt_library.extraction_override(language, source_language)
    if blocks:
        return KnowledgePromptTemplates.from_dict(blocks)
    return KnowledgePromptTemplates()



def load_extraction_fields(dlg) -> None:
    tpl = dlg._current_extraction_templates()
    values = tpl.to_dict()
    for key, edit in dlg._extraction_edits.items():
        edit.setPlainText(values.get(key, ""))


def fill_extraction_defaults(dlg) -> None:
    values = KnowledgePromptTemplates().to_dict()
    for key, edit in dlg._extraction_edits.items():
        edit.setPlainText(values.get(key, ""))


def on_extraction_save(dlg) -> None:
    """T17: stage the override; it is written when the dialog is accepted.

    This used to write the override file immediately, so 「取消」 in the
    settings dialog left the change in place while the rest of the dialog
    was discarded — two different notions of "cancel" on one screen.
    """
    language, source_language = dlg._extraction_pair()
    blocks = {
        key: edit.toPlainText()
        for key, edit in dlg._extraction_edits.items()
    }
    dlg._extraction_pending[(language, source_language)] = ("save", blocks)
    from src.application.shell_views import notify_toast

    msg = f"已暂存 {language} / {source_language} 的覆盖模板，点「确定」后生效。"
    if not notify_toast(dlg, msg, title="提取 Prompt"):
        QMessageBox.information(dlg, "提取 Prompt", msg)


def on_extraction_delete(dlg) -> None:
    """T17: stage the delete; it is applied when the dialog is accepted.

    Says so when there is nothing to delete, instead of staging a delete and
    reporting success on accept (this used to toast a staged deletion for a
    pair that had no override, and the accept path then did nothing). It also
    no longer resets the fields to the built-in defaults: doing that meant a
    following 保存 persisted the defaults as if they were a custom override.
    """
    language, source_language = dlg._extraction_pair()
    from src.application.shell_views import notify_toast

    if not dlg._prompt_library.extraction_override(language, source_language):
        msg = "该语言对没有已保存的覆盖。"
        if not notify_toast(dlg, msg, title="提取 Prompt"):
            QMessageBox.information(dlg, "提取 Prompt", msg)
        return
    dlg._extraction_pending[(language, source_language)] = ("delete", None)
    msg = f"已暂存删除 {language} / {source_language} 的覆盖，点「确定」后生效。"
    if not notify_toast(dlg, msg, title="提取 Prompt"):
        QMessageBox.information(dlg, "提取 Prompt", msg)


def commit_extraction_pending(dlg) -> bool:
    """Write the staged override/delete. Called from the dialog's accept path.

    Returns True when something was written. Never raises.
    """
    pending = dict(getattr(dlg, "_extraction_pending", None) or {})
    if not pending:
        return False
    wrote = 0
    for (language, source_language), (kind, payload) in pending.items():
        try:
            if kind == "save":
                dlg._prompt_library.save_extraction_override(
                    language, source_language, dict(payload or {})
                )
                wrote += 1
            elif kind == "delete":
                if dlg._prompt_library.delete_extraction_override(
                    language, source_language
                ):
                    default_library().unregister_persisted(
                        language, source_language
                    )
                    wrote += 1
        except Exception:
            # One bad pair must not abandon the rest; the accept path logs.
            logger.warning(
                "extraction_prompt_tab.py:commit failed for %s/%s",
                language,
                source_language,
                exc_info=True,
            )
    # Refresh the in-memory default library so the next extraction uses it.
    load_overrides_from(dlg._prompt_library)
    dlg._extraction_pending = {}
    return wrote > 0
