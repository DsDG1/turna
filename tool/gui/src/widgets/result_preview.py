"""Result preview widget for the AI course generator.

Shows a human-readable overview of a generated section (name/id, unit count,
lesson count, top-level resource counts) plus a one-click validation panel
that reuses ``CourseAdapter.validate_section_json`` and renders problems as
color-coded chips. Validation failures are surfaced via the ``validity_changed``
signal so the host dialog can enable/disable the import button.
"""
from __future__ import annotations

from typing import Any

from PySide6.QtCore import Qt, Signal
from PySide6.QtGui import QAction
from PySide6.QtWidgets import (
    QFrame,
    QHBoxLayout,
    QLabel,
    QMenu,
    QPushButton,
    QTreeWidget,
    QTreeWidgetItem,
    QVBoxLayout,
    QWidget,
)
from src.teacher.error_mapper import humanize_problem, parse_path
from src.theme import current_palette


class _StatCard(QFrame):
    """A small peacock-styled stat tile (label + value)."""

    def __init__(self, label: str, value: str, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.setObjectName("statCard")
        pal = current_palette()
        self.setStyleSheet(
            f"QFrame#statCard {{"
            f"  background-color: {pal['bg_elevated']};"
            f"  border: 1px solid {pal['border']};"
            f"  border-radius: 8px;"
            f"}}"
        )
        layout = QVBoxLayout(self)
        layout.setContentsMargins(10, 8, 10, 8)
        layout.setSpacing(2)
        value_label = QLabel(value)
        value_label.setStyleSheet(f"color: {pal['ai_accent']}; font-size: 16px; font-weight: 600; border: none;")
        value_label.setProperty("role", "value")
        layout.addWidget(value_label)
        caption = QLabel(label)
        caption.setStyleSheet(f"color: {pal['text_secondary']}; font-size: 11px; border: none;")
        layout.addWidget(caption)
        self._value_label = value_label

    def set_value(self, value: str) -> None:
        self._value_label.setText(value)


def _count_lessons(section: dict[str, Any]) -> int:
    total = 0
    for unit in section.get("units") or []:
        if not isinstance(unit, dict):
            continue
        for lesson in unit.get("lessons") or []:
            if isinstance(lesson, dict):
                total += 1
    return total


def _section_resource_counts(section: dict[str, Any]) -> dict[str, int]:
    """Count top-level resource entries declared on the section itself."""
    return {
        "vocab": len(section.get("words") or []),
        "expressions": len(section.get("expressions") or []),
        "grammar_points": len(section.get("grammarPoints") or []),
    }


class ResultPreviewWidget(QWidget):
    """Overview cards + validation chips for a generated section.

    ``validity_changed`` emits True when the current section validates with no
    errors (warnings are allowed), False otherwise. The host uses this to
    enable/disable the import button.
    """

    validity_changed = Signal(bool)
    # Emitted with a JSON-path string (e.g. "units/0/lessons/1") when the user
    # clicks a tree node, so the host can jump to the matching JSON line (P3.1).
    node_activated = Signal(str)
    #: (kind, id) kind is ``lesson`` or ``unit`` — workshop local regenerate.
    regenerate_requested = Signal(str, str)

    def __init__(self, adapter, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.adapter = adapter
        self._section: dict[str, Any] | None = None
        self._path_nodes: dict[str, QTreeWidgetItem] = {}
        self._build_ui()

    def _build_ui(self) -> None:
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(8)

        cards_row = QHBoxLayout()
        cards_row.setSpacing(8)
        self.card_section = _StatCard("课程", "—")
        self.card_units = _StatCard("单元", "0")
        self.card_lessons = _StatCard("课时", "0")
        self.card_vocab = _StatCard("词条", "0")
        self.card_expressions = _StatCard("表达", "0")
        self.card_grammar = _StatCard("语法点", "0")
        for card in (
            self.card_section,
            self.card_units,
            self.card_lessons,
            self.card_vocab,
            self.card_expressions,
            self.card_grammar,
        ):
            cards_row.addWidget(card)
        cards_row.addStretch()
        layout.addLayout(cards_row)

        action_row = QHBoxLayout()
        action_row.setSpacing(8)
        self.validate_btn = QPushButton("一键校验")
        self.validate_btn.setToolTip("校验当前生成结果，错误会显示为红色标签")
        self.validate_btn.clicked.connect(self._on_validate)
        action_row.addWidget(self.validate_btn)
        self.status_label = QLabel("")
        self.status_label.setStyleSheet(f"color: {current_palette()['text_secondary']}; font-size: 12px;")
        action_row.addWidget(self.status_label, 1)
        layout.addLayout(action_row)

        self.chip_row = QHBoxLayout()
        self.chip_row.setSpacing(6)
        self.chip_row.setContentsMargins(0, 0, 0, 0)
        self._chip_container = QWidget()
        self._chip_container.setLayout(self.chip_row)
        layout.addWidget(self._chip_container)

        # Structured tree (P3.1): Section→Unit→Lesson→stage/phase→item.
        self.tree = QTreeWidget()
        self.tree.setHeaderHidden(True)
        self.tree.setIndentation(16)
        self.tree.itemClicked.connect(self._on_tree_item_clicked)
        self.tree.setContextMenuPolicy(Qt.ContextMenuPolicy.CustomContextMenu)
        self.tree.customContextMenuRequested.connect(self._on_tree_context_menu)
        self.tree.setMaximumHeight(220)
        self.tree.setToolTip("右键课时/单元可请求 AI 局部重生成")
        layout.addWidget(self.tree)

    def show_section(self, section: dict[str, Any]) -> None:
        """Update the overview cards for ``section`` (does not validate)."""
        self._section = section
        if not isinstance(section, dict):
            self._clear_cards()
            return
        name = str(section.get("name") or section.get("id") or "—")
        self.card_section.set_value(name if len(name) <= 14 else name[:13] + "…")
        self.card_section.setToolTip(name)
        units = section.get("units") or []
        self.card_units.set_value(str(len(units)))
        self.card_lessons.set_value(str(_count_lessons(section)))
        counts = _section_resource_counts(section)
        self.card_vocab.set_value(str(counts["vocab"]))
        self.card_expressions.set_value(str(counts["expressions"]))
        self.card_grammar.set_value(str(counts["grammar_points"]))
        self._clear_chips()
        self._build_tree(section)
        self.status_label.setText("点击「一键校验」检查结果。")
        self.status_label.setStyleSheet(f"color: {current_palette()['text_secondary']}; font-size: 12px;")

    def _clear_cards(self) -> None:
        for card in (
            self.card_section,
            self.card_units,
            self.card_lessons,
            self.card_vocab,
            self.card_expressions,
            self.card_grammar,
        ):
            card.set_value("0" if card is not self.card_section else "—")
        self.tree.clear()
        self._path_nodes = {}

    def _clear_chips(self) -> None:
        while self.chip_row.count():
            item = self.chip_row.takeAt(0)
            w = item.widget()
            if w is not None:
                w.setParent(None)
                w.deleteLater()

    def _add_chip(self, problem: dict[str, Any], level: str) -> None:
        """Show a humanized validation chip; click focuses the related tree node."""
        human = humanize_problem(problem)
        raw = str(problem.get("message") or "")
        chip = QLabel(human)
        chip.setWordWrap(True)
        chip.setCursor(Qt.CursorShape.PointingHandCursor)
        if raw and raw != human:
            chip.setToolTip(raw)
        else:
            chip.setToolTip("点击定位到大纲中的相关节点")
        if level == "error":
            color = "#E74C3C"
            bg = "rgba(231, 76, 60, 0.12)"
        else:
            color = "#FF9F43"
            bg = "rgba(255, 159, 67, 0.12)"
        chip.setStyleSheet(
            f"color: {color}; background-color: {bg};"
            "border-radius: 6px; padding: 3px 8px; font-size: 12px;"
        )
        chip.setMaximumWidth(560)
        chip.mousePressEvent = (  # type: ignore[method-assign]
            lambda _e, p=problem: self._on_chip_clicked(p)
        )
        self.chip_row.addWidget(chip)

    def _on_chip_clicked(self, problem: dict[str, Any]) -> None:
        path = problem.get("path") or ""
        parsed = parse_path(path) if path else {}
        node = None
        for kind in ("lesson", "unit"):
            nid = parsed.get(kind)
            if nid:
                node = self._path_nodes.get(f"id:{nid}")
                if node is not None:
                    break
        if node is None and path:
            # Try structural path keys registered in _path_nodes.
            node = self._path_nodes.get(str(path))
        if node is not None:
            self.tree.setCurrentItem(node)
            self.tree.scrollToItem(node)
            self._on_tree_item_clicked(node, 0)

    def apply_validation(self, problems: list[dict[str, Any]]) -> None:
        """Render chips/status from a precomputed problem list (silent refresh)."""
        self._clear_chips()
        pal = current_palette()
        errors = [p for p in problems if p.get("level") == "error"]
        warnings = [p for p in problems if p.get("level") == "warning"]
        for p in problems:
            self._add_chip(p, p.get("level", "error"))
        self._highlight_problems(errors)
        if not problems:
            self.status_label.setText("✓ 校验通过，可以导入。")
            self.status_label.setStyleSheet(f"color: {pal['success']}; font-size: 12px;")
            self.validity_changed.emit(True)
        elif not errors:
            self.status_label.setText(f"⚠ {len(warnings)} 条警告，仍可导入。")
            self.status_label.setStyleSheet(f"color: {pal['warning']}; font-size: 12px;")
            self.validity_changed.emit(True)
        else:
            self.status_label.setText(f"✗ {len(errors)} 个错误，请修改后再导入。")
            self.status_label.setStyleSheet(f"color: {pal['error']}; font-size: 12px;")
            self.validity_changed.emit(False)

    def _on_validate(self) -> None:
        if self._section is None:
            return
        if self.adapter is None:
            self.status_label.setText("未加载课程，无法校验。")
            return
        problems = self.adapter.validate_section_json(self._section)
        self.apply_validation(problems)

    def section(self) -> dict[str, Any] | None:
        return self._section

    # --- structured tree (P3.1) -----------------------------------------

    def _build_tree(self, section: dict[str, Any]) -> None:
        self.tree.clear()
        self._path_nodes = {}
        if not isinstance(section, dict):
            return
        root = QTreeWidgetItem([f"📦 {section.get('name') or section.get('id') or '课程'}"])
        self.tree.addTopLevelItem(root)
        for ui, unit in enumerate(section.get("units") or []):
            if not isinstance(unit, dict):
                continue
            unit_path = f"units/{ui}"
            unit_node = QTreeWidgetItem([f"📙 {unit.get('name') or unit.get('id') or f'Unit {ui+1}'}"])
            unit_node.setData(0, Qt.ItemDataRole.UserRole, unit_path)
            if unit.get("id"):
                unit_node.setData(0, Qt.ItemDataRole.UserRole + 1, unit.get("id"))
            self._path_nodes[unit_path] = unit_node
            self._register_id_node(unit.get("id"), unit_node)
            root.addChild(unit_node)
            for li, lesson in enumerate(unit.get("lessons") or []):
                if not isinstance(lesson, dict):
                    continue
                lesson_path = f"{unit_path}/lessons/{li}"
                tpl = lesson.get("template", "")
                label = f"📘 {lesson.get('name') or lesson.get('id') or f'Lesson {li+1}'}"
                if tpl:
                    label += f"  · {tpl}"
                lesson_node = QTreeWidgetItem([label])
                lesson_node.setData(0, Qt.ItemDataRole.UserRole, lesson_path)
                if lesson.get("id"):
                    lesson_node.setData(0, Qt.ItemDataRole.UserRole + 1, lesson.get("id"))
                self._path_nodes[lesson_path] = lesson_node
                self._register_id_node(lesson.get("id"), lesson_node)
                unit_node.addChild(lesson_node)
                self._add_content_children(lesson_node, lesson, f"{lesson_path}/content")
        root.setExpanded(True)
        for i in range(root.childCount()):
            root.child(i).setExpanded(True)

    def _add_content_children(self, lesson_node: QTreeWidgetItem, lesson: dict[str, Any], base_path: str) -> None:
        content = lesson.get("content") or {}
        if not isinstance(content, dict):
            return
        # subLessons → stages → items
        for si, sub in enumerate(content.get("subLessons") or []):
            if not isinstance(sub, dict):
                continue
            sub_path = f"{base_path}/subLessons/{si}"
            sub_node = QTreeWidgetItem([f"🔹 {sub.get('name') or sub.get('id') or f'Sub {si+1}'}"])
            sub_node.setData(0, Qt.ItemDataRole.UserRole, sub_path)
            self._path_nodes[sub_path] = sub_node
            lesson_node.addChild(sub_node)
            self._add_stages(sub_node, sub, f"{sub_path}/stages")
        # direct stages (practice/review/mastery templates)
        if not (content.get("subLessons") or []):
            self._add_stages(lesson_node, content, f"{base_path}/stages")
        # listeningPhases
        for pi, phase in enumerate(content.get("listeningPhases") or []):
            if not isinstance(phase, dict):
                continue
            phase_path = f"{base_path}/listeningPhases/{pi}"
            phase_node = QTreeWidgetItem([f"🎧 {phase.get('name') or phase.get('id') or f'Phase {pi+1}'}"])
            phase_node.setData(0, Qt.ItemDataRole.UserRole, phase_path)
            self._path_nodes[phase_path] = phase_node
            lesson_node.addChild(phase_node)

    def _add_stages(self, parent_node: QTreeWidgetItem, holder: dict[str, Any], base_path: str) -> None:
        for sti, stage in enumerate(holder.get("stages") or []):
            if not isinstance(stage, dict):
                continue
            stage_path = f"{base_path}/{sti}"
            stage_node = QTreeWidgetItem([f"▪ {stage.get('name') or f'Stage {sti+1}'}"])
            stage_node.setData(0, Qt.ItemDataRole.UserRole, stage_path)
            self._path_nodes[stage_path] = stage_node
            parent_node.addChild(stage_node)
            for ii, item in enumerate(stage.get("items") or []):
                if not isinstance(item, dict):
                    continue
                item_path = f"{stage_path}/items/{ii}"
                rt = item.get("runtimeType", "item")
                prompt = (
                    item.get("prompt") or item.get("source") or item.get("sentence")
                    or item.get("statement") or item.get("id") or ""
                )
                short = (prompt[:18] + "…") if len(prompt) > 18 else prompt
                label = f"• {rt}" + (f"  {short}" if short else "")
                item_node = QTreeWidgetItem([label])
                item_node.setData(0, Qt.ItemDataRole.UserRole, item_path)
                self._path_nodes[item_path] = item_node
                stage_node.addChild(item_node)

    def _register_id_node(self, node_id: str | None, node: QTreeWidgetItem) -> None:
        if node_id:
            self._path_nodes[f"id:{node_id}"] = node

    def _on_tree_item_clicked(self, item: QTreeWidgetItem, _column: int) -> None:
        path = item.data(0, Qt.ItemDataRole.UserRole)
        if path:
            # Prefer the node's id (if any) for JSON-line jumping; fall back to
            # the structural path.
            id_data = item.data(0, Qt.ItemDataRole.UserRole + 1)
            payload = f"id:{id_data}" if id_data else str(path)
            self.node_activated.emit(payload)

    def _on_tree_context_menu(self, pos) -> None:
        item = self.tree.itemAt(pos)
        if item is None or self._section is None:
            return
        path = str(item.data(0, Qt.ItemDataRole.UserRole) or "")
        node_id = item.data(0, Qt.ItemDataRole.UserRole + 1)
        kind = None
        if node_id and "/lessons/" in path:
            kind = "lesson"
        elif node_id and path.startswith("units/") and "/lessons/" not in path:
            kind = "unit"
        if kind is None or not node_id:
            return
        menu = QMenu(self)
        label = "AI 重生成本课时" if kind == "lesson" else "AI 重生成该单元"
        act = QAction(label, menu)
        act.triggered.connect(
            lambda _=False, k=kind, i=str(node_id): self.regenerate_requested.emit(k, i)
        )
        menu.addAction(act)
        menu.exec(self.tree.viewport().mapToGlobal(pos))

    def _highlight_problems(self, problems: list[dict[str, Any]]) -> None:
        """Mark tree nodes whose unit/lesson id matches a problem path (P3.1)."""
        from PySide6.QtGui import QColor

        default = self.tree.palette().text().color()
        for node in self._path_nodes.values():
            node.setForeground(0, default)
            node.setToolTip(0, "")
        err_color = QColor("#E74C3C")
        for p in problems:
            path = p.get("path") or ""
            parsed = parse_path(path) if path else {}
            for kind in ("unit", "lesson"):
                nid = parsed.get(kind)
                if nid:
                    node = self._path_nodes.get(f"id:{nid}")
                    if node is not None:
                        node.setForeground(0, err_color)
                        node.setToolTip(0, humanize_problem(p))