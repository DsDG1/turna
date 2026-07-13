"""Dialog for one-click initialization of a new course repository."""
from __future__ import annotations

from pathlib import Path

from PySide6.QtCore import QSettings
from PySide6.QtWidgets import (
    QDialog,
    QDialogButtonBox,
    QFileDialog,
    QFormLayout,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QMessageBox,
    QPushButton,
    QSpinBox,
    QVBoxLayout,
)

from src.backend.course_adapter import CourseAdapter


class InitCourseDialog(QDialog):
    """Create a new course directory outside the repo with sample content."""

    def __init__(self, adapter: CourseAdapter, parent=None) -> None:
        super().__init__(parent)
        self.adapter = adapter
        self.setWindowTitle("新建课程目录")
        self.resize(520, 260)
        self._init_dir: Path | None = None
        self._build_ui()
        self._load_defaults()

    def _build_ui(self) -> None:
        layout = QVBoxLayout(self)
        layout.setSpacing(14)
        layout.setContentsMargins(16, 16, 16, 16)

        form = QFormLayout()
        form.setSpacing(10)

        dir_row = QHBoxLayout()
        dir_row.setSpacing(8)
        self.dir_edit = QLineEdit()
        self.dir_edit.setPlaceholderText("选择要创建课程目录的父文件夹")
        dir_row.addWidget(self.dir_edit, 1)
        self.browse_btn = QPushButton("浏览...")
        self.browse_btn.clicked.connect(self._on_browse)
        dir_row.addWidget(self.browse_btn)
        form.addRow("目标目录:", dir_row)

        self.name_edit = QLineEdit("My Chinese-English Course")
        form.addRow("课程显示名:", self.name_edit)

        self.target_lang_edit = QLineEdit("en")
        self.target_lang_edit.setMaximumWidth(120)
        form.addRow("目标语言代码:", self.target_lang_edit)

        self.source_lang_edit = QLineEdit("Chinese")
        self.source_lang_edit.setMaximumWidth(120)
        form.addRow("源语言（提示语）:", self.source_lang_edit)

        self.section_spin = QSpinBox()
        self.section_spin.setRange(1, 8)
        self.section_spin.setValue(3)
        form.addRow("Section 数量:", self.section_spin)

        self.lessons_spin = QSpinBox()
        self.lessons_spin.setRange(1, 10)
        self.lessons_spin.setValue(3)
        form.addRow("每单元课时数:", self.lessons_spin)

        layout.addLayout(form)

        hint = QLabel(
            "将创建 index.json、vocab.json、expressions.json、grammar_points.json "
            "以及 sections/ 目录。默认内容为中教英样例，非常随意，仅供参考。"
        )
        hint.setWordWrap(True)
        hint.setStyleSheet("color: gray; font-size: 11px;")
        layout.addWidget(hint)

        buttons = QDialogButtonBox(
            QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel
        )
        buttons.button(QDialogButtonBox.StandardButton.Ok).setText("初始化")
        buttons.accepted.connect(self._on_accept)
        buttons.rejected.connect(self.reject)
        layout.addWidget(buttons)

    def _load_defaults(self) -> None:
        settings = QSettings("Varnamala", "CourseEditor")
        last_dir = settings.value("last_init_dir", "")
        if last_dir and isinstance(last_dir, str):
            self.dir_edit.setText(last_dir)

    def _on_browse(self) -> None:
        start = self.dir_edit.text().strip() or str(Path.home())
        chosen = QFileDialog.getExistingDirectory(self, "选择父目录", start)
        if not chosen:
            return
        self.dir_edit.setText(chosen)

    def _on_accept(self) -> None:
        parent_dir = self.dir_edit.text().strip()
        display_name = self.name_edit.text().strip()
        if not parent_dir:
            QMessageBox.warning(self, "缺少目录", "请选择目标目录。")
            return
        if not display_name:
            QMessageBox.warning(self, "缺少课程名", "请填写课程显示名。")
            return

        parent_path = Path(parent_dir)
        course_dir = parent_path / display_name
        if course_dir.exists() and any(course_dir.iterdir()):
            QMessageBox.warning(
                self,
                "目录已存在",
                f"目录 {course_dir} 已存在且非空，请选择其他位置或课程名。",
            )
            return

        meta = {
            "display_name": display_name,
            "language": self.target_lang_edit.text().strip() or "en",
            "source_language": self.source_lang_edit.text().strip() or "Chinese",
            "section_count": self.section_spin.value(),
            "lessons_per_unit": self.lessons_spin.value(),
        }
        try:
            self.adapter.init_new(course_dir, meta)
        except Exception as exc:  # noqa: BLE001
            QMessageBox.critical(self, "初始化失败", str(exc))
            return

        self._init_dir = course_dir
        settings = QSettings("Varnamala", "CourseEditor")
        settings.setValue("last_init_dir", str(parent_path))
        self.accept()

    def init_dir(self) -> Path | None:
        return self._init_dir
