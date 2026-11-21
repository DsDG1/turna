"""Media preview widgets (raster + SVG image rendering and local audio playback).

Pure PySide6 (``QtGui`` / ``QtSvg`` / ``QtMultimedia``) with graceful fallback
when a media file is missing, uses an app-only scheme (``anki://`` /
``turnapack://``), or when the headless test environment has no audio backend.
"""
from __future__ import annotations

import logging
from pathlib import Path

from PySide6.QtCore import QSize, Qt, QUrl
from PySide6.QtGui import QImage, QPainter, QPixmap
from PySide6.QtWidgets import QHBoxLayout, QLabel, QPushButton, QVBoxLayout, QWidget

from src.application.media_service import resolve_audio_asset
from src.theme import current_palette

logger = logging.getLogger(__name__)


def resolve_course_media_path(course_dir: Path | None, asset_ref: str) -> Path | None:
    """Resolve a course-relative or repo-relative media ref to an existing file."""
    ref = str(asset_ref or "").strip().replace("\\", "/")
    if not ref or ref.startswith(("anki://", "turnapack://", "http://", "https://")):
        return None
    candidates: list[Path] = []
    if course_dir is not None:
        base = Path(course_dir)
        candidates.append(base / ref)
        # Author workspace layout: workspace/course/ + workspace/assets/...
        candidates.append(base.parent / ref)
        # Repo layout: repo/assets/courses/<dir>/ -> repo/assets/...
        for ancestor in base.parents:
            if (ancestor / "pubspec.yaml").is_file() or (ancestor / "assets").is_dir():
                candidates.append(ancestor / ref)
                break
    for cand in candidates:
        try:
            if cand.is_file():
                return cand
        except OSError:
            logger.debug("preview_media: stat failed for %s", cand, exc_info=True)
    return None


def _render_svg_pixmap(path: Path, max_width: int, max_height: int) -> QPixmap | None:
    try:
        from PySide6.QtSvg import QSvgRenderer
    except ImportError:
        logger.debug("preview_media: PySide6.QtSvg unavailable", exc_info=True)
        return None
    renderer = QSvgRenderer(str(path))
    if not renderer.isValid():
        return None
    default_size = renderer.defaultSize()
    if default_size.isEmpty():
        target = QSize(min(max_width, 240), min(max_height, 180))
    else:
        target = default_size.scaled(
            max_width, max_height, Qt.AspectRatioMode.KeepAspectRatio
        )
    image = QImage(
        max(1, target.width()),
        max(1, target.height()),
        QImage.Format.Format_ARGB32_Premultiplied,
    )
    image.fill(Qt.GlobalColor.transparent)
    painter = QPainter(image)
    try:
        renderer.render(painter)
    finally:
        painter.end()
    return QPixmap.fromImage(image)


def load_preview_pixmap(
    path: Path, *, max_width: int = 360, max_height: int = 200
) -> QPixmap | None:
    if path.suffix.lower() == ".svg":
        return _render_svg_pixmap(path, max_width, max_height)
    pix = QPixmap(str(path))
    if pix.isNull():
        return None
    return pix.scaled(
        max_width,
        max_height,
        Qt.AspectRatioMode.KeepAspectRatio,
        Qt.TransformationMode.SmoothTransformation,
    )


class PreviewImageWidget(QWidget):
    """Display a local raster/SVG image or a clean placeholder badge."""

    def __init__(
        self,
        course_dir: Path | None,
        asset_ref: str,
        *,
        alt_text: str = "",
        max_width: int = 360,
        max_height: int = 200,
        parent: QWidget | None = None,
    ) -> None:
        super().__init__(parent)
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(4)
        pal = current_palette()

        resolved = resolve_course_media_path(course_dir, asset_ref)
        pix = (
            load_preview_pixmap(resolved, max_width=max_width, max_height=max_height)
            if resolved is not None
            else None
        )
        if pix is not None and not pix.isNull():
            img = QLabel()
            img.setPixmap(pix)
            img.setAlignment(Qt.AlignmentFlag.AlignLeft)
            layout.addWidget(img)
        else:
            badge = QLabel(f"🖼 图片占位：{asset_ref}")
            badge.setWordWrap(True)
            badge.setStyleSheet(
                f"color: {pal['text_secondary']};"
                f" background-color: {pal['bg_secondary']};"
                f" border: 1px dashed {pal['border']};"
                " border-radius: 6px; padding: 6px 8px; font-size: 12px;"
            )
            layout.addWidget(badge)
        if alt_text:
            alt = QLabel(f"alt：{alt_text}")
            alt.setWordWrap(True)
            alt.setStyleSheet(f"color: {pal['text_secondary']}; font-size: 11px;")
            layout.addWidget(alt)


class PreviewAudioBar(QWidget):
    """Play a local course audio file via QtMultimedia, degrading cleanly if unavailable."""

    def __init__(
        self,
        course_dir: Path | None,
        asset_ref: str,
        *,
        label: str = "音频",
        parent: QWidget | None = None,
    ) -> None:
        super().__init__(parent)
        self._resolved = resolve_audio_asset(course_dir, asset_ref)
        self._player = None
        self._audio_output = None

        row = QHBoxLayout(self)
        row.setContentsMargins(0, 0, 0, 0)
        row.setSpacing(8)
        pal = current_palette()

        self.play_btn = QPushButton(f"▶ 试听{label}")
        self.stop_btn = QPushButton("⏹ 停止")
        self.stop_btn.setVisible(False)
        self.info_lbl = QLabel(asset_ref)
        self.info_lbl.setStyleSheet(f"color: {pal['text_secondary']}; font-size: 11px;")
        self.info_lbl.setWordWrap(True)

        if self._resolved is None:
            self.play_btn.setEnabled(False)
            self.play_btn.setText(f"🔇 未找到{label}")
        else:
            self.play_btn.clicked.connect(self._on_play)
            self.stop_btn.clicked.connect(self._on_stop)

        row.addWidget(self.play_btn)
        row.addWidget(self.stop_btn)
        row.addWidget(self.info_lbl, 1)

    def _ensure_player(self) -> bool:
        if self._player is not None:
            return True
        try:
            from PySide6.QtMultimedia import QAudioOutput, QMediaPlayer

            self._audio_output = QAudioOutput(self)
            self._player = QMediaPlayer(self)
            self._player.setAudioOutput(self._audio_output)
            return True
        except (ImportError, RuntimeError, OSError):
            logger.debug("preview_media: QtMultimedia unavailable", exc_info=True)
            self.play_btn.setEnabled(False)
            self.play_btn.setText("🔇 当前环境不支持播放")
            return False

    def _on_play(self) -> None:
        if self._resolved is None or not self._ensure_player():
            return
        try:
            self._player.setSource(QUrl.fromLocalFile(str(self._resolved)))
            self._player.play()
            self.stop_btn.setVisible(True)
        except (RuntimeError, OSError):
            logger.debug("preview_media: playback failed", exc_info=True)
            self.play_btn.setEnabled(False)
            self.play_btn.setText("🔇 播放失败")

    def _on_stop(self) -> None:
        if self._player is not None:
            try:
                self._player.stop()
            except RuntimeError:
                logger.debug("preview_media: stop failed", exc_info=True)
        self.stop_btn.setVisible(False)
