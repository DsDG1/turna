"""Component gallery — dev walkthrough for the UI kit (``--gallery``).

Shows every ui-kit component in a scrollable page plus a theme switcher that
re-applies the global QSS live. Used for the 4-theme × all-components
walkthrough required by each wave's acceptance criteria.
"""
from __future__ import annotations

from PySide6.QtCore import Qt
from PySide6.QtWidgets import (
    QComboBox,
    QHBoxLayout,
    QLabel,
    QMainWindow,
    QScrollArea,
    QVBoxLayout,
    QWidget,
)

from src.theme_tokens import PALETTES
from src.widgets.ui import (
    ActivityBar,
    Badge,
    Card,
    EmptyState,
    Pill,
    SearchField,
    ToastHost,
    TurnaButton,
    TurnaDialog,
    ViewHeader,
)


def _section(title: str) -> QLabel:
    label = QLabel(title)
    label.setObjectName("ViewHeaderTitle")
    return label


class GalleryWindow(QMainWindow):
    """Standalone gallery host: theme switcher + one row per component."""

    def __init__(self) -> None:
        super().__init__()
        self.setWindowTitle("Turna UI Kit Gallery")
        self.resize(980, 760)

        central = QWidget(self)
        root = QVBoxLayout(central)
        root.setContentsMargins(12, 8, 12, 12)
        root.setSpacing(8)

        top = QHBoxLayout()
        top.addWidget(_section("组件画廊"))
        top.addStretch(1)
        top.addWidget(QLabel("主题:"))
        self._theme = QComboBox()
        self._theme.addItems(list(PALETTES.keys()))
        self._theme.currentTextChanged.connect(self._apply_theme)
        top.addWidget(self._theme)
        root.addLayout(top)

        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        root.addWidget(scroll, 1)
        page = QWidget()
        scroll.setWidget(page)
        col = QVBoxLayout(page)
        col.setSpacing(14)

        # --- TurnaButton variants -------------------------------------
        col.addWidget(_section("TurnaButton"))
        row = QHBoxLayout()
        for variant in ("primary", "secondary", "ghost", "danger"):
            row.addWidget(TurnaButton(variant, variant=variant))
        row.addWidget(TurnaButton("sm", variant="primary", size="sm"))
        row.addWidget(TurnaButton("icon", variant="secondary", icon_name="save"))
        row.addStretch(1)
        col.addLayout(row)

        # --- Badge / Pill ----------------------------------------------
        col.addWidget(_section("Badge / Pill"))
        row = QHBoxLayout()
        row.addWidget(Badge(3))
        row.addWidget(Badge(120, variant="danger"))
        row.addWidget(Badge(7, variant="muted"))
        row.addWidget(Pill("accent", variant="accent"))
        row.addWidget(Pill("success", variant="success"))
        row.addWidget(Pill("warning", variant="warning"))
        row.addWidget(Pill("danger", variant="danger"))
        row.addWidget(Pill("custom", color="#B85C3F"))
        row.addStretch(1)
        col.addLayout(row)

        # --- ViewHeader --------------------------------------------------
        col.addWidget(_section("ViewHeader"))
        header = ViewHeader("课程编辑")
        header.set_breadcrumb(["Section A1", "Unit 2", "Lesson 3"])
        header.add_action(TurnaButton("保存", variant="primary", size="sm", icon_name="save"))
        header.add_action(TurnaButton("AI 编辑", variant="secondary", size="sm", icon_name="sparkles"))
        header.add_action(TurnaButton("", variant="ghost", size="sm", icon_name="more-horizontal"))
        col.addWidget(header)

        # --- Card + SearchField + EmptyState -----------------------------
        col.addWidget(_section("Card / SearchField / EmptyState"))
        card = Card(shadow=True)
        card.add_widget(QLabel("Card · bg_elevated + e1 阴影"))
        card.add_widget(SearchField("过滤节点…"))
        col.addWidget(card)
        col.addWidget(
            EmptyState(
                icon_name="folder-open",
                title="还没有课程内容",
                description="新建或打开一个课程目录开始编辑",
                cta_text="新建课程目录…",
            )
        )

        # --- TurnaDialog -------------------------------------------------
        col.addWidget(_section("TurnaDialog"))
        dlg_btn = TurnaButton("打开示例对话框", variant="secondary")

        def _open() -> None:
            dlg = TurnaDialog(self, title="示例对话框", description="header / body / footer 三段式")
            dlg.add_widget(QLabel("body 区域"))
            dlg.add_standard_buttons()
            dlg.exec()

        dlg_btn.clicked.connect(_open)
        col.addWidget(dlg_btn)

        # --- ActivityBar -------------------------------------------------
        col.addWidget(_section("ActivityBar"))
        bar_host = QWidget()
        bar_row = QHBoxLayout(bar_host)
        bar_row.setContentsMargins(0, 0, 0, 0)
        bar = ActivityBar()
        bar.add_menu_button("应用菜单")
        bar.add_separator()
        bar.add_item("edit", "folder-open", "课程编辑  Ctrl+1", view=True)
        bar.add_item("workshop", "sparkles", "工坊  Ctrl+2", view=True)
        bar.add_item("overview", "map", "总览  Ctrl+3", view=True)
        bar.add_item("resources", "library", "资源  Ctrl+4", view=True)
        bar.add_separator()
        bar.add_item("copilot", "bot", "Copilot  Ctrl+J")
        bar.add_stretch()
        bar.add_item("teacher", "graduation-cap", "教师模式")
        bar.add_item("settings", "settings", "设置", checkable=False)
        bar.set_current("edit")
        bar.set_badge("overview", 4, danger=True)
        bar.set_badge("workshop", 12)
        bar.set_badge("copilot", 2)
        bar.setFixedHeight(380)
        bar_row.addWidget(bar)
        bar_row.addStretch(1)
        col.addWidget(bar_host)

        col.addStretch(1)
        self.setCentralWidget(central)
        self.toast_host = ToastHost(central)

        toast_row = QHBoxLayout()
        for sev in ("info", "success", "warning", "danger"):
            b = TurnaButton(f"toast:{sev}", variant="secondary", size="sm")

            def _demo_toast(_checked: bool = False, s: str = sev) -> None:
                self.toast_host.show_toast(f"这是一条 {s} 通知", severity=s)

            b.clicked.connect(_demo_toast)
            toast_row.addWidget(b)
        toast_row.addStretch(1)
        root.addLayout(toast_row)

    def _apply_theme(self, theme: str) -> None:
        from PySide6.QtWidgets import QApplication

        from src.theme import apply_theme
        from src.application.settings import Settings

        app = QApplication.instance()
        if app is not None:
            apply_theme(app, Settings(theme=theme))


def run_gallery() -> int:
    """Launch the gallery as a standalone app (``main.py --gallery``)."""
    import sys

    from PySide6.QtWidgets import QApplication

    from src.theme import apply_theme

    app = QApplication.instance() or QApplication(sys.argv)
    apply_theme(app)
    win = GalleryWindow()
    win.show()
    return app.exec()
