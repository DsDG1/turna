"""OCR / git skill implementations (M7)."""
from __future__ import annotations

from typing import Any

from src.application.ui_guard import safe_information, safe_question, safe_warning
import logging
logger = logging.getLogger(__name__)

def _experience_git_skill(host, action: str) -> None:
    """K-24: read-only git skill (commit message / explain diff).

    Reads the working-tree diff for the current course dir via
    ``GitLibrary.diff_working_vs_head`` and asks the chat model for a
    commit message or a natural-language explanation. Result is shown in a
    read-only dialog with a copy button; nothing is written to the course
    tree (no ConflictGuard / sandbox / undo). Timeline records only a short
    summary — never the diff or reply body (§14.5.3).
    """
    from src.backend.experience.git_skill import gather_diff_text, run_git_skill

    local_dir = getattr(host, "course_dir", None) or getattr(
        host, "_git_clone_dir", None
    )
    if not local_dir:
        host.statusBar().showMessage("先打开一个课程 / Git 仓库", 5000)
        return
    config = getattr(host, "_ai_config", None)
    if config is None or not getattr(config, "is_complete", False):
        host.statusBar().showMessage("AI 配置不完整：设置 ▸ AI 填写 Key/Model", 5000)
        return
    git_lib = getattr(host, "_git_library", None)
    if git_lib is None:
        try:
            from src.backend.git_library import GitLibrary

            git_lib = GitLibrary()
        except Exception:
            git_lib = None
    diff_text, err = gather_diff_text(git_lib, local_dir)
    if err:
        host.statusBar().showMessage(err, 6000)
        return

    job_id = f"git-{action}"
    job_label = "生成提交信息" if action == "git.commit_message" else "解释 Diff"
    tray = getattr(host, "job_tray", None)
    metrics = getattr(host, "experience_metrics", None)
    if tray is not None:
        tray.start(job_id, f"{job_label}：正在生成 …", kind="ai")
    if metrics is not None:
        metrics.inc_job("ai", "started")
        metrics.inc_suggestion(action, "accepted")
    host._refresh_experience(immediate=False, focus_only=True)

    worker = host._make_ai_worker(run_git_skill, config, action, diff_text)

    def _on_ok(text: object) -> None:
        if tray is not None:
            tray.finish(job_id)
        if metrics is not None:
            metrics.inc_job("ai", "finished")
        reply = str(text) if text is not None else ""
        if not reply.strip():
            host.statusBar().showMessage(f"{job_label}：AI 返回为空", 5000)
            return
        try:
            host._record_experience_event(
                action,
                job_label,
                action_id=action,
                scope={},
            )
        except Exception:
            logger.debug("application/experience_handlers/multimodal.py:_on_ok best-effort step failed", exc_info=True)
        if metrics is not None:
            metrics.inc_suggestion(action, "applied")
        host._show_git_skill_result(job_label, reply)

    def _on_err(msg: str) -> None:
        if tray is not None:
            tray.finish(job_id)
        if metrics is not None:
            metrics.inc_job("ai", "failed")
        # Non-modal: avoid hanging headless runners on unclicked MessageBox.
        host.statusBar().showMessage(f"{job_label}失败：{msg}", 8000)

    worker.result_ready.connect(_on_ok)
    worker.error_occurred.connect(_on_err)
    worker.start()
    host._experience_worker = worker

handle_git_skill = _experience_git_skill

def _experience_ocr(
    host, scope: dict | None = None, *, records=None, unlink_after: bool = False
) -> None:
    """M-03: OCR image/scanned-PDF attachments -> text AttachmentRecords.

    Two modes:
    * ``records is None`` (``/ocr`` OCR-all): OCR every image-kind
      attachment in the workshop bar, skipping images that already have a
      ``{name}.ocr.txt`` text record (dedup hardening).
    * ``records=[...]`` (per-chip button / scanned-PDF add-time offer):
      OCR the given record(s) only (image or PDF, by ``temp_path`` ext).

    Local OCR (pytesseract + tesseract, lazy; PyMuPDF for PDF) runs in an
    ``AiRequestWorker`` (``kind=local`` job); each successful result becomes
    a new text-class AttachmentRecord pushed back via
    ``add_attachment_record`` -> ``attachments_changed`` -> M-01 link + Dock
    refresh. ``unlink_after`` cleans up orphan scanned-PDF temp files after
    OCR (bar-owned image temp files are left intact). Nothing is written to
    the course tree (no Guard/sandbox/Undo); OCR text/paths never enter
    Context/telemetry (§14.5.3). Never raises - all failure paths degrade
    to a non-modal statusBar message (offscreen-safe).
    """
    from src.backend.experience.ocr_skill import (
        ACTION_ID,
        is_ocr_enabled,
        ocr_available,
        ocr_records,
    )

    if not is_ocr_enabled(getattr(host, "_settings_obj", None)):
        host.statusBar().showMessage(
            "OCR 未开启（设置 ▸ 体验 OS 勾选「OCR 图片附件转文本」）", 6000
        )
        return
    win = getattr(host, "_workshop_window", None)
    if win is None or not hasattr(win, "add_attachment_record"):
        host.statusBar().showMessage("先打开工坊并添加图片附件", 5000)
        return

    if records is None:
        # /ocr-all: image attachments, dedup-skip already-OCR'd images.
        all_records = (
            win.attachment_records() if hasattr(win, "attachment_records") else []
        )
        existing_names = {
            getattr(r, "original_name", "") for r in all_records
        }
        target = [
            r
            for r in all_records
            if isinstance(getattr(r, "content", None), dict)
            and r.content.get("type") == "image_url"
            and f"{getattr(r, 'original_name', '')}.ocr.txt"
            not in existing_names
        ]
        if not target:
            host.statusBar().showMessage(
                "无图片附件可 OCR（仅支持 png/jpg 等图片附件）", 5000
            )
            return
    else:
        target = list(records)

    avail, reason = ocr_available()
    if not avail:
        tip = {
            "missing_dep": "缺少 pytesseract（pip install pytesseract）",
            "missing_binary": "缺少系统 tesseract（安装 tesseract-ocr）",
        }.get(reason, "OCR 不可用")
        host.statusBar().showMessage(f"OCR 不可用：{tip}", 8000)
        return

    # OCR lang follows course index.language (e.g. tur); falls back to eng.
    lang = "eng"
    adapter = getattr(host, "adapter", None)
    if adapter is not None:
        try:
            lang = str(
                (getattr(adapter, "index", {}) or {}).get("language") or ""
            ) or "eng"
        except Exception:
            lang = "eng"

    job_id = "ocr-images"
    job_label = "OCR 图片附件"
    tray = getattr(host, "job_tray", None)
    metrics = getattr(host, "experience_metrics", None)
    if tray is not None:
        tray.start(job_id, f"{job_label}：正在识别 …", kind="local")
    if metrics is not None:
        metrics.inc_job("local", "started")
        metrics.inc_suggestion(ACTION_ID, "accepted")
    if hasattr(host, "_refresh_experience"):
        try:
            host._refresh_experience(immediate=False, focus_only=True)
        except Exception:
            logger.debug("application/experience_handlers/multimodal.py:_experience_ocr best-effort step failed", exc_info=True)

    worker = host._make_ai_worker(ocr_records, target, lang=lang)

    def _on_ok(results: object) -> None:
        added = 0
        try:
            for item in results or []:
                try:
                    record, text, status = item
                except Exception:
                    continue
                if status == "ok" and (text or "").strip():
                    try:
                        import tempfile
                        import uuid
                        from pathlib import Path

                        from src.application.ai_request_worker import AttachmentRecord

                        base_name = Path(
                            getattr(record, "original_name", "image")
                        ).name
                        tmp = Path(tempfile.gettempdir()) / (
                            f"turna_ocr_{uuid.uuid4().hex[:8]}_{base_name}.txt"
                        )
                        tmp.write_text(text, encoding="utf-8")
                        new_rec = AttachmentRecord(
                            temp_path=tmp,
                            original_name=f"{base_name}.ocr.txt",
                            content={"type": "text", "text": text},
                        )
                        if win.add_attachment_record(new_rec):
                            added += 1
                    except Exception:
                        logger.debug("application/experience_handlers/multimodal.py:_on_ok best-effort step failed", exc_info=True)
                # Orphan scanned-PDF temp files (signal path) are cleaned
                # up after OCR; bar-owned image temp files are left intact.
                if unlink_after:
                    try:
                        from pathlib import Path

                        Path(getattr(record, "temp_path", "")).unlink(
                            missing_ok=True
                        )
                    except Exception:
                        logger.debug("application/experience_handlers/multimodal.py:_on_ok best-effort step failed", exc_info=True)
        except Exception:
            logger.debug("application/experience_handlers/multimodal.py:_on_ok best-effort step failed", exc_info=True)
        if tray is not None:
            tray.finish(job_id)
        if metrics is not None:
            metrics.inc_job("local", "finished")
        if hasattr(host, "_sync_experience_attachments"):
            try:
                host._sync_experience_attachments()
            except Exception:
                logger.debug("application/experience_handlers/multimodal.py:_on_ok best-effort step failed", exc_info=True)
        if hasattr(host, "experience"):
            try:
                host.experience.invalidate()
            except Exception:
                logger.debug("application/experience_handlers/multimodal.py:_on_ok best-effort step failed", exc_info=True)
        try:
            # §14.5.3: Timeline records only action_id + closed-set scope
            # (count + status); never OCR text or file paths.
            host._record_experience_event(
                ACTION_ID,
                job_label,
                action_id=ACTION_ID,
                scope={"count": added, "status": "ok" if added else "no_text"},
            )
        except Exception:
            logger.debug("application/experience_handlers/multimodal.py:_on_ok best-effort step failed", exc_info=True)
        if metrics is not None and added:
            metrics.inc_suggestion(ACTION_ID, "applied")
        if added:
            host.statusBar().showMessage(
                f"OCR 完成，已添加 {added} 个文本附件", 6000
            )
        else:
            host.statusBar().showMessage(
                "OCR 未识别到文本（可能缺 lang 包或图片无文字）", 7000
            )

    def _on_err(msg: str) -> None:
        if tray is not None:
            tray.finish(job_id)
        if metrics is not None:
            metrics.inc_job("local", "failed")
        # Non-modal: avoid hanging headless runners on unclicked MessageBox.
        host.statusBar().showMessage(f"{job_label}失败：{msg}", 8000)

    worker.result_ready.connect(_on_ok)
    worker.error_occurred.connect(_on_err)
    worker.start()
    host._experience_worker = worker

handle_ocr = _experience_ocr

def _show_git_skill_result(host, title: str, text: str) -> None:
    """Read-only preview dialog with a copy button (no Qt in unit tests)."""
    try:
        from PySide6.QtWidgets import (
            QApplication,
            QDialog,
            QHBoxLayout,
            QPushButton,
            QTextEdit,
            QVBoxLayout,
        )

        app = QApplication.instance()
        if app is None or app.platformName() == "offscreen":
            host.statusBar().showMessage(text[:120], 8000)
            return
        dlg = QDialog(host)
        dlg.setWindowTitle(title)
        dlg.resize(520, 360)
        layout = QVBoxLayout(dlg)
        view = QTextEdit()
        view.setReadOnly(True)
        view.setPlainText(text)
        layout.addWidget(view)
        row = QHBoxLayout()
        copy_btn = QPushButton("复制")
        close_btn = QPushButton("关闭")

        def _copy() -> None:
            try:
                QApplication.clipboard().setText(text)
                host.statusBar().showMessage("已复制到剪贴板", 3000)
            except Exception:
                logger.debug("application/experience_handlers/multimodal.py:_copy best-effort step failed", exc_info=True)

        copy_btn.clicked.connect(_copy)
        close_btn.clicked.connect(dlg.accept)
        row.addStretch(1)
        row.addWidget(copy_btn)
        row.addWidget(close_btn)
        layout.addLayout(row)
        dlg.exec()
    except Exception:
        # Headless / no Qt: surface via status bar.
        host.statusBar().showMessage(text[:120], 8000)

handle_show_git_skill_result = _show_git_skill_result

