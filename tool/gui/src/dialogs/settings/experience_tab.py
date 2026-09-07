"""Experience OS tab for SettingsDialog — intrusiveness ladder entry point.

Exposes ``experience_mode`` (observer/copilot/active/immersive), the immersive
sub-switches, and the feature gates that policy deny-messages point at
(设置 ▸ 体验 OS): goal planner, ⌘K LLM intent, dangerous skills, daily budget.
"""
from __future__ import annotations

from PySide6.QtWidgets import (
    QCheckBox,
    QComboBox,
    QFormLayout,
    QGroupBox,
    QLabel,
    QSpinBox,
    QVBoxLayout,
    QWidget,
)

# Display labels paired with policy mode ids (presence_level 0–3).
EXPERIENCE_MODE_ITEMS: tuple[tuple[str, str], ...] = (
    ("观察者 Observer（只诊断，零 AI 写）", "observer"),
    ("副驾驶 Copilot（默认：建议 + 确认后执行）", "copilot"),
    ("主动 Active（Soft 自动修 + 伴随建议 + 战役队列）", "active"),
    ("沉浸 Immersive（白名单静默执行，仍可 Undo）", "immersive"),
)


def build_experience_tab(dlg) -> QWidget:
    tab, layout = dlg._make_tab()

    mode_group = QGroupBox("体验模式（侵入度阶梯）")
    mode_form = QFormLayout(mode_group)
    mode_form.setSpacing(10)

    dlg.experience_mode_combo = QComboBox()
    for label, mode in EXPERIENCE_MODE_ITEMS:
        dlg.experience_mode_combo.addItem(label, mode)
    dlg.experience_mode_combo.setToolTip(
        "AI 在编辑器中的介入档位。\n"
        "· Observer：只诊断，零 AI 写操作。\n"
        "· Copilot（默认）：建议 + 芯片，人确认后执行。\n"
        "· Active：捆绑开启 Soft 自动修 / 伴随建议 / 战役队列。\n"
        "· Immersive：白名单技能可跳过确认静默改课（仍入 Undo；\n"
        "  出站 publish / git.push / 删课根 / 密钥等禁区始终拒绝）。\n"
        "随时可用 Ctrl+Shift+D 一键降档回 Copilot。"
    )
    mode_form.addRow("体验模式:", dlg.experience_mode_combo)

    dlg.experience_mode_hint = QLabel(
        "切换到 Immersive 会弹出风险确认；Ctrl+Shift+D 可随时降档。"
    )
    dlg.experience_mode_hint.setObjectName("hintLabel")
    mode_form.addRow(dlg.experience_mode_hint)
    layout.addWidget(mode_group)

    immersive_group = QGroupBox("Immersive 子开关（仅 Immersive 档生效）")
    immersive_form = QFormLayout(immersive_group)
    immersive_form.setSpacing(10)

    dlg.experience_immersive_full_auto_check = QCheckBox("全权自动应用（跳过确认，仍可 Ctrl+Z 撤销）")
    dlg.experience_immersive_full_auto_check.setToolTip(
        "Immersive 档下允许 AI 跳过确认自动应用改动；绝对禁区（出站/删除/密钥）仍拒绝。"
    )
    immersive_form.addRow(dlg.experience_immersive_full_auto_check)

    dlg.experience_immersive_opaque_check = QCheckBox("运行时不透明（状态栏仅提示计数，不列明细）")
    dlg.experience_immersive_opaque_check.setToolTip(
        "关闭后静默改动的状态栏提示会带技能名称明细。审计环始终记录。"
    )
    immersive_form.addRow(dlg.experience_immersive_opaque_check)
    layout.addWidget(immersive_group)

    gates_group = QGroupBox("体验能力开关")
    gates_form = QFormLayout(gates_group)
    gates_form.setSpacing(10)

    dlg.experience_goal_check = QCheckBox("启用 Goal 目标规划（多步目标沙箱草稿）")
    dlg.experience_goal_check.setToolTip("Observer 档不可用；合并进课程仍需人工确认。")
    gates_form.addRow(dlg.experience_goal_check)

    dlg.experience_llm_intent_check = QCheckBox("⌘K 自然语言意图分类（调用 chat 小模型）")
    dlg.experience_llm_intent_check.setToolTip("关闭时 ⌘K 仅斜杠命令 + 本地规则路由。")
    gates_form.addRow(dlg.experience_llm_intent_check)

    dlg.experience_dangerous_check = QCheckBox("允许危险技能（删 id / 跨节改写 / Hard import）")
    dlg.experience_dangerous_check.setToolTip(
        "⚠️ 高风险：解锁结构性重写类动作。默认关闭；Observer 档强制关闭。"
    )
    gates_form.addRow(dlg.experience_dangerous_check)

    dlg.experience_budget_spin = QSpinBox()
    dlg.experience_budget_spin.setRange(0, 100000)
    dlg.experience_budget_spin.setSpecialValueText("0 = 不限")
    dlg.experience_budget_spin.setToolTip(
        "今日 AI 请求配额（M-08 熔断）。超限只拦 AI 写技能，不拦手编/保存/Soft。"
    )
    gates_form.addRow("日 AI 配额（次）:", dlg.experience_budget_spin)
    layout.addWidget(gates_group)

    layout.addStretch(1)
    return tab
