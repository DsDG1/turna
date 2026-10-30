"""Audio generation controller.

Coordinates listening-lesson audio generation (MiniMax TTS) for the loaded course.
Decoupled from MainWindow to keep src/app.py lean and testable.
"""
from __future__ import annotations

import logging
from typing import Any

from PySide6.QtCore import Qt
from PySide6.QtWidgets import QDialog, QMessageBox, QProgressDialog, QWidget

from src.infrastructure.telemetry import telemetry

logger = logging.getLogger(__name__)


class AudioController:
    """Controller for course audio generation workflows."""

    def handle_generate_audio(self, window: Any) -> None:
        """Generate listening-lesson audio (MiniMax TTS) for the loaded course."""
        from src.backend import generate_audio_client
        from src.application.audio_worker import GenerateAudioWorker
        from src.dialogs.generate_audio_dialog import GenerateAudioDialog

        course_dir = getattr(window, "course_dir", None)
        if not course_dir:
            QMessageBox.warning(window, "生成听力音频", "请先打开课程目录。")
            return

        adapter = getattr(window, "adapter", None)

        settings_obj = getattr(window, "_settings_obj", None)
        settings = getattr(window, "_settings", None)
        parent_widget = window if isinstance(window, QWidget) else None

        sounds_dir = generate_audio_client.sounds_dir_for(
            course_dir, settings_obj
        )
        preview = generate_audio_client.preview_generation(
            course_dir, settings_obj
        )
        telemetry.record_event(
            "tts.open",
            payload={
                "total": int(preview.get("total", 0)),
                "existing": int(preview.get("existing", 0)),
                "sounds_dir": str(sounds_dir),
            },
        )
        dlg = GenerateAudioDialog(settings_obj, preview, parent=parent_widget)
        if dlg.exec() != QDialog.DialogCode.Accepted:
            return

        # #22: save only after the user commits — merely opening the dialog
        # used to write the course to disk even when the user then cancelled.
        # collect_entries (worker side) still reads the latest transcripts.
        #
        # The save runs on a worker: ``adapter.save()`` does two full CLI
        # validate/lint scans, two deep copies of the course and a full
        # backup copy, which froze the GUI thread for the whole chain.
        opts = generate_audio_client.TtsOptions(
            voice_id=dlg.voice_id(),
            model=dlg.model(),
            speed=dlg.speed(),
            force=dlg.force(),
            language_boost=dlg.language_boost(),
            text_normalization=dlg.text_normalization(),
            emotion=dlg.emotion(),
        )
        if not dlg.api_key():
            QMessageBox.warning(parent_widget, "生成听力音频", "请填写 MiniMax API Key。")
            return

        if settings_obj is not None and hasattr(settings_obj, "save_to_qsettings") and settings is not None:
            settings_obj.save_to_qsettings(settings)

        def _start_tts() -> None:
            worker = GenerateAudioWorker(
                course_dir, sounds_dir, opts, dlg.api_key(), parent=parent_widget
            )

            progress = QProgressDialog("正在生成听力音频…", "取消", 0, 0, parent_widget)
            progress.setWindowModality(Qt.WindowModality.NonModal)
            progress.setWindowTitle("生成听力音频")
            progress.setValue(0)

            # Duck-typed job tray: absent on some MainWindow variants — guard it.
            tray = getattr(window, "job_tray", None)
            try:
                if tray is not None:
                    tray.start_job("tts-generate", "生成听力音频…")
            except Exception:
                logger.debug("audio_controller: best-effort tray start failed", exc_info=True)
                tray = None

            def _on_progress(done: int, total: int) -> None:
                if total > 0:
                    progress.setMaximum(total)
                    progress.setValue(done)
                    progress.setLabelText(f"正在生成听力音频… {done}/{total}")

            def _on_finished_ok(generated: int, skipped: int, total: int) -> None:
                progress.close()
                try:
                    if tray is not None:
                        tray.finish_job("tts-generate")
                except Exception:
                    logger.debug("audio_controller:_on_finished_ok best-effort failed", exc_info=True)
                tree = getattr(window, "tree", None)
                if tree is not None and hasattr(tree, "refresh"):
                    tree.refresh()
                telemetry.record_event(
                    "tts.generate",
                    payload={"generated": generated, "skipped": skipped, "total": total},
                )
                QMessageBox.information(
                    parent_widget,
                    "生成听力音频",
                    f"完成：生成 {generated} 条，跳过 {skipped} 条，共 {total} 条。",
                )

            def _on_failed(msg: str) -> None:
                progress.close()
                try:
                    if tray is not None:
                        tray.finish_job("tts-generate")
                except Exception:
                    logger.debug("audio_controller:_on_failed best-effort failed", exc_info=True)
                telemetry.record_error(
                    RuntimeError(msg), context={"event": "tts.generate_failed"}
                )
                QMessageBox.warning(parent_widget, "生成听力音频失败", msg)

            progress.canceled.connect(worker.cancel)
            worker.progress.connect(_on_progress)
            worker.finished_ok.connect(_on_finished_ok)
            worker.failed.connect(_on_failed)
            window._generate_worker = worker  # keep strong ref until finished
            worker.start()

        def _on_save_done(result) -> None:
            if hasattr(result, "ok") and not result.ok:
                QMessageBox.warning(
                    window, "生成听力音频", "课程保存失败，已取消生成。"
                )
                return
            # B3: this direct save bypasses the SavePipeline — mark the
            # session clean so the title/save indicator follow the disk.
            undo_stack = getattr(window, "undo_stack", None)
            if undo_stack is not None:
                undo_stack.setClean()
            mark = getattr(window, "_mark_saved", None)
            if callable(mark):
                mark()
            _start_tts()

        def _on_save_error(message: str) -> None:
            logger.debug("audio_controller: background save failed", exc_info=True)
            QMessageBox.warning(
                window, "生成听力音频", f"课程保存失败，已取消生成：{message}"
            )

        if adapter is not None and hasattr(adapter, "save"):
            try:
                sb = getattr(window, "statusBar", None)
                if callable(sb):
                    sb().showMessage("正在保存课程…", 3000)
            except Exception:
                logger.debug("audio_controller: best-effort status failed", exc_info=True)
            from src.application.ai_request_worker import AiRequestWorker

            save_worker = AiRequestWorker(adapter.save)
            save_worker.result_ready.connect(_on_save_done)
            save_worker.error_occurred.connect(_on_save_error)
            window._audio_save_worker = save_worker  # keep strong ref
            save_worker.start()
            return

        _start_tts()
