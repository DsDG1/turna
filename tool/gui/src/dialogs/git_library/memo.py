"""Team memo board domain: .collaboration_memo.json + search/pagination (G)."""
from __future__ import annotations

import logging
from datetime import datetime

from PySide6.QtWidgets import (
    QComboBox,
    QHBoxLayout,
    QInputDialog,
    QLabel,
    QLineEdit,
    QMessageBox,
    QPushButton,
    QTextEdit,
    QVBoxLayout,
    QWidget,
)

from src.theme import current_palette

logger = logging.getLogger(__name__)

MEMO_FILE = ".collaboration_memo.json"


def build_memo_tab(dlg) -> QWidget:
    """Tab 3: Team Memo Board."""
    dlg.memo_tab = QWidget()
    memo_layout = QVBoxLayout(dlg.memo_tab)
    memo_layout.setSpacing(10)
    memo_layout.setContentsMargins(8, 8, 8, 8)

    memo_layout.addWidget(QLabel("团队协作留言板（通过 Git 仓库自动同步，支持回复/编辑/删除）:"))

    # Search bar
    search_row = QHBoxLayout()
    dlg.memo_search_edit = QLineEdit()
    dlg.memo_search_edit.setPlaceholderText("搜索留言...")
    dlg.memo_search_edit.textChanged.connect(dlg._refresh_memos)
    search_row.addWidget(dlg.memo_search_edit, 1)
    memo_layout.addLayout(search_row)

    dlg.memo_text = QTextEdit()
    dlg.memo_text.setReadOnly(True)
    dlg.memo_text.setStyleSheet(f"background-color: {current_palette()['bg_input']}; color: {current_palette()['text']}; font-size: 13px;")
    memo_layout.addWidget(dlg.memo_text)

    # Pagination
    dlg._memo_page = 0
    dlg._memo_page_size = 20
    page_row = QHBoxLayout()
    dlg.memo_prev_btn = QPushButton("上一页")
    dlg.memo_prev_btn.clicked.connect(dlg._on_memo_prev_page)
    page_row.addWidget(dlg.memo_prev_btn)
    dlg.memo_next_btn = QPushButton("下一页")
    dlg.memo_next_btn.clicked.connect(dlg._on_memo_next_page)
    page_row.addWidget(dlg.memo_next_btn)
    dlg.memo_page_label = QLabel("第 1 页")
    page_row.addWidget(dlg.memo_page_label)
    page_row.addStretch()
    memo_layout.addLayout(page_row)

    memo_input_row = QHBoxLayout()
    reply_row = QHBoxLayout()
    reply_row.addWidget(QLabel("回复:"))
    dlg.memo_reply_combo = QComboBox()
    dlg.memo_reply_combo.addItem("（新留言）", "")
    reply_row.addWidget(dlg.memo_reply_combo, 1)
    memo_input_row.addLayout(reply_row, 1)

    dlg.memo_input = QLineEdit()
    dlg.memo_input.setPlaceholderText("输入留言，按回车发送...")
    dlg.memo_input.returnPressed.connect(dlg._on_send_memo)
    memo_input_row.addWidget(dlg.memo_input, 2)

    dlg.send_memo_btn = QPushButton("发送")
    dlg.send_memo_btn.clicked.connect(dlg._on_send_memo)
    memo_input_row.addWidget(dlg.send_memo_btn)
    memo_layout.addLayout(memo_input_row)

    # Edit / delete buttons for own memos
    edit_row = QHBoxLayout()
    dlg.memo_edit_btn = QPushButton("编辑选中留言")
    dlg.memo_edit_btn.clicked.connect(dlg._on_edit_memo)
    edit_row.addWidget(dlg.memo_edit_btn)
    dlg.memo_del_btn = QPushButton("删除选中留言")
    dlg.memo_del_btn.clicked.connect(dlg._on_del_memo)
    edit_row.addWidget(dlg.memo_del_btn)
    edit_row.addStretch()
    memo_layout.addLayout(edit_row)

    return dlg.memo_tab


def on_memo_prev_page(dlg) -> None:
    if dlg._memo_page > 0:
        dlg._memo_page -= 1
        refresh_memos(dlg)


def on_memo_next_page(dlg) -> None:
    dlg._memo_page += 1
    refresh_memos(dlg)


def on_edit_memo(dlg) -> None:
    if dlg._clone_dir is None:
        return
    memo_id, ok = QInputDialog.getText(dlg, "编辑留言", "留言 ID:")
    if not ok or not memo_id.strip():
        return
    new_text, ok2 = QInputDialog.getText(dlg, "编辑留言", "新内容:")
    if not ok2 or not new_text.strip():
        return
    edit_or_delete_memo(dlg, memo_id.strip(), action="edit", new_text=new_text.strip())


def on_del_memo(dlg) -> None:
    if dlg._clone_dir is None:
        return
    memo_id, ok = QInputDialog.getText(dlg, "删除留言", "留言 ID:")
    if not ok or not memo_id.strip():
        return
    reply = QMessageBox.question(
        dlg, "删除留言", f"确定要删除留言 {memo_id.strip()} 吗？",
        QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.Cancel,
        QMessageBox.StandardButton.Cancel,
    )
    if reply != QMessageBox.StandardButton.Yes:
        return
    edit_or_delete_memo(dlg, memo_id.strip(), action="delete")


def edit_or_delete_memo(dlg, memo_id: str, action: str, new_text: str = "") -> None:
    if dlg._clone_dir is None:
        return
    memo_file = dlg._clone_dir / MEMO_FILE
    import json
    import getpass
    user = getpass.getuser()
    try:
        data = json.loads(memo_file.read_text(encoding="utf-8")) if memo_file.is_file() else {"messages": []}
    except Exception:
        data = {"messages": []}
    messages = data.get("messages", [])
    found = False
    for m in messages:
        if m.get("id") == memo_id:
            if m.get("user") != user:
                QMessageBox.warning(dlg, "无权限", "只能编辑/删除自己的留言。")
                return
            if action == "edit":
                m["text"] = new_text
                m["edited_at"] = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            elif action == "delete":
                messages.remove(m)
            found = True
            break
    if not found:
        QMessageBox.warning(dlg, "未找到", f"未找到 ID 为 {memo_id} 的留言。")
        return
    data["messages"] = messages
    # Atomic write: tmp + os.replace so a crash mid-write cannot
    # corrupt the collaborator's memo file (B19).
    import os
    tmp = memo_file.with_suffix(memo_file.suffix + ".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    os.replace(tmp, memo_file)
    refresh_memos(dlg)
    # Push.
    dlg._run_git_async(
        "推送留言",
        dlg.git.commit_and_push_file,
        dlg._clone_dir,
        MEMO_FILE,
        f"留言{action}: {memo_id}",
        ok_title="已同步",
        ok_message="留言变更已推送。",
        error_title="留言同步失败",
    )


def refresh_memos(dlg) -> None:
    if dlg._clone_dir is None:
        dlg.memo_text.setPlainText("请先在“远程协作”中连接或克隆仓库。")
        dlg.memo_input.setEnabled(False)
        dlg.send_memo_btn.setEnabled(False)
        return

    dlg.memo_input.setEnabled(True)
    dlg.send_memo_btn.setEnabled(True)

    memo_file = dlg._clone_dir / MEMO_FILE
    if not memo_file.is_file():
        dlg.memo_text.setPlainText("留言板目前为空。发布第一条留言来开始协作吧！")
        dlg.memo_reply_combo.clear()
        dlg.memo_reply_combo.addItem("（新留言）", "")
        dlg.memo_page_label.setText("第 1 页")
        return

    try:
        import json
        data = json.loads(memo_file.read_text(encoding="utf-8"))
        messages = data.get("messages", [])

        # Search filter.
        search = dlg.memo_search_edit.text().strip().lower()
        if search:
            messages = [
                m for m in messages
                if search in m.get("text", "").lower()
                or search in m.get("user", "").lower()
            ]

        # Build threaded display: top-level messages + their replies.
        by_parent: dict[str, list] = {}
        for m in messages:
            parent = m.get("parent_id", "")
            by_parent.setdefault(parent, []).append(m)

        # Top-level messages (parent_id == "").
        top_level = sorted(by_parent.get("", []), key=lambda m: m.get("time", ""))

        # Pagination.
        total = len(top_level)
        start = dlg._memo_page * dlg._memo_page_size
        end = start + dlg._memo_page_size
        page_items = top_level[start:end]
        total_pages = max(1, (total + dlg._memo_page_size - 1) // dlg._memo_page_size)
        dlg.memo_page_label.setText(f"第 {dlg._memo_page + 1} / {total_pages} 页（共 {total} 条）")
        dlg.memo_prev_btn.setEnabled(dlg._memo_page > 0)
        dlg.memo_next_btn.setEnabled(end < total)

        # Reply combo.
        dlg.memo_reply_combo.clear()
        dlg.memo_reply_combo.addItem("（新留言）", "")
        for m in top_level:
            label = f"{m.get('id', '?')}: {m.get('text', '')[:30]}"
            dlg.memo_reply_combo.addItem(label, m.get("id", ""))

        # Render threaded.
        lines = []
        def _render(msg: dict, indent: str) -> None:
            lines.append(f"{indent}【{msg.get('time', '')}】 {msg.get('user', '?')} (ID: {msg.get('id', '?')[:8]}):")
            lines.append(f"{indent}  {msg.get('text', '')}")
            if msg.get("edited_at"):
                lines.append(f"{indent}  (编辑于 {msg['edited_at']})")
            for reply in sorted(by_parent.get(msg.get("id", ""), []), key=lambda m: m.get("time", "")):
                _render(reply, indent + "    ")
        for m in page_items:
            _render(m, "")
        if lines:
            dlg.memo_text.setPlainText("\n".join(lines))
            dlg.memo_text.verticalScrollBar().setValue(
                dlg.memo_text.verticalScrollBar().maximum()
            )
        else:
            dlg.memo_text.setPlainText("（无匹配留言）")
    except Exception as exc:
        dlg.memo_text.setPlainText(f"读取留言板失败：{exc}")


def on_send_memo(dlg) -> None:
    text = dlg.memo_input.text().strip()
    if not text or dlg._clone_dir is None:
        return

    import getpass
    import uuid
    user = getpass.getuser()
    try:
        from src.dialogs.git_library.lan_share import get_local_ips
        ips = get_local_ips()
        ip = ips[0] if ips else "未知"
    except Exception:
        ip = "未知"

    parent_id = dlg.memo_reply_combo.currentData() or ""
    memo_id = uuid.uuid4().hex[:12]

    memo_file = dlg._clone_dir / MEMO_FILE

    import json
    messages = []
    if memo_file.is_file():
        try:
            data = json.loads(memo_file.read_text(encoding="utf-8"))
            messages = data.get("messages", [])
        except Exception:
            logger.debug("dialogs/git_library/memo.py:on_send_memo best-effort step failed", exc_info=True)

    messages.append({
        "id": memo_id,
        "parent_id": parent_id,
        "time": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "user": user,
        "ip": ip,
        "text": text,
    })

    try:
        memo_file.write_text(json.dumps({"messages": messages}, ensure_ascii=False, indent=2), encoding="utf-8")
        dlg.memo_input.clear()
        refresh_memos(dlg)

        # Pull-rebase first so a teammate's earlier push does not cause a
        # non-fast-forward rejection, then commit + push the memo file.
        def _push_memo(_result: object) -> None:
            dlg._run_git_async(
                "推送留言",
                dlg.git.commit_and_push_file,
                dlg._clone_dir,
                MEMO_FILE,
                f"留言: {text[:20]}",
                ok_title="已同步留言",
                ok_message="留言已推送到远程仓库。",
                error_title="留言同步失败",
            )

        dlg._run_git_async(
            "拉取最新留言",
            dlg.git.pull_rebase,
            dlg._clone_dir,
            on_ok=_push_memo,
            error_title="留言同步失败",
        )
    except Exception as exc:
        QMessageBox.critical(dlg, "发送失败", f"无法写入并推送留言：{exc}")
