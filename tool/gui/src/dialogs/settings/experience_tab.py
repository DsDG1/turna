"""Experience OS tab for SettingsDialog — intrusiveness ladder entry point.

Exposes ``experience_mode`` (observer/copilot/active/immersive), the immersive
sub-switches, and the feature gates that policy deny-messages point at
(设置 ▸ 体验 OS): goal planner, ⌘K LLM intent, dangerous skills, daily budget.
"""
from __future__ import annotations

import logging

from PySide6.QtWidgets import (
    QCheckBox,
    QComboBox,
    QFormLayout,
    QGroupBox,
    QLabel,
    QPushButton,
    QSpinBox,
    QVBoxLayout,
    QWidget,
)

logger = logging.getLogger(__name__)

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

    dlg.experience_screenshot_explain_check = QCheckBox("截图解释（⌘K 输入「截图解释」，走 AI）")
    dlg.experience_screenshot_explain_check.setToolTip(
        "允许把当前编辑器截图发给 AI 做状态审阅与建议（/screenshot-explain）。\n"
        "截图会上传到所配置的 AI 服务商，介意隐私请保持关闭。"
    )
    gates_form.addRow(dlg.experience_screenshot_explain_check)

    dlg.experience_voice_palette_check = QCheckBox("⌘K 语音输入（本地离线识别，需 SpeechRecognition）")
    dlg.experience_voice_palette_check.setToolTip(
        "命令面板显示麦克风按钮，本地 Sphinx 离线识别转文字。\n"
        "音频不出本机；未安装依赖时按钮自动隐藏。"
    )
    gates_form.addRow(dlg.experience_voice_palette_check)

    dlg.experience_preview_fix_suggest_check = QCheckBox("预览修题建议栏（教师预览内 AI 改题）")
    dlg.experience_preview_fix_suggest_check.setToolTip(
        "课程预览窗口显示「AI 修题」建议栏，逐题给出修改建议并确认后应用。"
    )
    gates_form.addRow(dlg.experience_preview_fix_suggest_check)
    layout.addWidget(gates_group)

    memory_group = QGroupBox("记忆与 OCR")
    memory_form = QFormLayout(memory_group)
    memory_form.setSpacing(10)

    dlg.experience_ocr_check = QCheckBox("OCR 图片附件转文本（需系统安装 tesseract）")
    dlg.experience_ocr_check.setToolTip(
        "工坊附件中的图片 / 扫描件 PDF 可经本地 tesseract 转成文本附件。\n"
        "OCR 结果只进附件栏，不写课程树；纯本地处理，不走 API。"
    )
    memory_form.addRow(dlg.experience_ocr_check)

    dlg.experience_memory_project_check = QCheckBox("项目记忆落盘（近期技能 / 模板偏好）")
    dlg.experience_memory_project_check.setToolTip(
        "按课程记住最近用过的技能与偏好模板，写入 tool/var/experience_memory/。\n"
        "关闭时记忆仅存活于当前进程。"
    )
    memory_form.addRow(dlg.experience_memory_project_check)

    dlg.experience_memory_author_check = QCheckBox("作者画像落盘（跨课程风格 / 语言偏好）")
    dlg.experience_memory_author_check.setToolTip(
        "跨课程沉淀改写风格提示与语言偏好，供上下文和建议使用。\n"
        "关闭时画像仅存活于当前进程。"
    )
    memory_form.addRow(dlg.experience_memory_author_check)
    layout.addWidget(memory_group)

    # T12: after several AI failures the breaker opens and auto-apply stops
    # for a minute. There was no way to clear it early — the user had to
    # wait out the timeout with no idea why nothing was happening.
    breaker_group = QGroupBox("AI 自动应用熔断器")
    breaker_form = QFormLayout(breaker_group)
    breaker_form.setSpacing(10)
    dlg.experience_reset_breaker_btn = QPushButton("重置熔断器")
    dlg.experience_reset_breaker_btn.setToolTip(
        "连续失败会自动暂停 AI 自动应用（约 1 分钟后自动恢复）。\n"
        "如果已经修好了问题，可以在这里立即恢复，不必等待。"
    )
    dlg.experience_reset_breaker_btn.clicked.connect(_on_reset_breaker)
    breaker_form.addRow(dlg.experience_reset_breaker_btn)
    layout.addWidget(breaker_group)

    layout.addStretch(1)
    return tab


def _on_reset_breaker() -> None:
    """T12: wire the already-exported manual reset to a button."""
    from src.backend.experience.circuit_breaker import get_circuit_breaker

    try:
        get_circuit_breaker().reset()
    except Exception:  # pragma: no cover - reset() already swallows internally
        logger.warning("settings/experience_tab.py:reset breaker failed", exc_info=True)
    from PySide6.QtWidgets import QMessageBox

    QMessageBox.information(
        None, "重置熔断器", "熔断器已重置，AI 自动应用已恢复。"
    )
