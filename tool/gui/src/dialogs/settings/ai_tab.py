"""AI provider configuration tab for SettingsDialog (extracted)."""
from __future__ import annotations

from PySide6.QtWidgets import (
    QCheckBox,
    QComboBox,
    QDialogButtonBox,
    QDoubleSpinBox,
    QFormLayout,
    QGroupBox,
    QLabel,
    QLineEdit,
    QPushButton,
    QSpinBox,
    QVBoxLayout,
    QWidget,
)

from src.backend import ai_presets
from src.backend.ai import verify_connection
from src.theme import current_palette


def build_ai_tab(dlg) -> QWidget:
    tab, layout = dlg._make_tab()

    provider_group = QGroupBox("AI 服务提供商")
    provider_form = QFormLayout(provider_group)
    provider_form.setSpacing(10)

    dlg.ai_provider_combo = QComboBox()
    for name in ai_presets.provider_names():
        preset = ai_presets.preset_for_provider(name)
        dlg.ai_provider_combo.addItem(preset.label, name)
    dlg.ai_provider_combo.currentIndexChanged.connect(dlg._on_provider_changed)
    provider_form.addRow("提供商:", dlg.ai_provider_combo)

    dlg.ai_url_edit = QLineEdit()
    dlg.ai_url_edit.setPlaceholderText("https://api.example.com/v1")
    provider_form.addRow("Base URL:", dlg.ai_url_edit)

    dlg.ai_key_edit = QLineEdit()
    dlg.ai_key_edit.setEchoMode(QLineEdit.EchoMode.Password)
    dlg.ai_key_edit.setPlaceholderText("sk-...")
    provider_form.addRow("API Key:", dlg.ai_key_edit)

    dlg.ai_model_edit = QLineEdit()
    dlg.ai_model_edit.setPlaceholderText("模型名称，例如 gpt-4o")
    provider_form.addRow("模型:", dlg.ai_model_edit)

    dlg.ai_reasoning_check = QCheckBox("启用 reasoning / thinking 字段")
    dlg.ai_reasoning_check.setToolTip(
        "DeepSeek 等支持 reasoning 的端点需要发送 thinking/reasoning_effort 字段；"
        "其他 OpenAI 兼容端点通常会因未知字段报错。"
    )
    provider_form.addRow(dlg.ai_reasoning_check)

    hint = QLabel(
        "配置保存在本地 QSettings；API Key 仅在当前会话内存中保留，退出后清空。"
    )
    hint.setObjectName("hintLabel")
    hint.setWordWrap(True)
    provider_form.addRow(hint)

    layout.addWidget(provider_group)

    params_group = QGroupBox("生成参数")
    params_form = QFormLayout(params_group)
    params_form.setSpacing(10)

    dlg.ai_timeout_spin = QSpinBox()
    dlg.ai_timeout_spin.setRange(5, 600)
    dlg.ai_timeout_spin.setSuffix(" 秒")
    params_form.addRow("请求超时:", dlg.ai_timeout_spin)

    dlg.ai_temperature_spin = QDoubleSpinBox()
    dlg.ai_temperature_spin.setRange(0.0, 2.0)
    dlg.ai_temperature_spin.setSingleStep(0.1)
    dlg.ai_temperature_spin.setDecimals(1)
    params_form.addRow("生成温度:", dlg.ai_temperature_spin)

    dlg.ai_retry_spin = QSpinBox()
    dlg.ai_retry_spin.setRange(0, 5)
    dlg.ai_retry_spin.setToolTip(
        "生成 section 校验失败时，自动把错误回灌给 AI 重新生成的最大轮数。"
    )
    params_form.addRow("自动重试次数:", dlg.ai_retry_spin)

    layout.addWidget(params_group)

    # --- 第三枪 批次①: Advanced AI options (collapsible) ---
    adv_group, adv_form = dlg._build_ai_advanced_group()
    layout.addWidget(adv_group)

    test_group = QGroupBox("连接测试")
    test_layout = QVBoxLayout(test_group)
    test_layout.setSpacing(10)

    dlg.ai_connection_status = QLabel("点击「测试连接」验证当前配置。")
    dlg.ai_connection_status.setWordWrap(True)
    dlg.ai_connection_status.setObjectName("hintLabel")
    test_layout.addWidget(dlg.ai_connection_status)

    dlg.ai_test_btn = QPushButton("测试连接")
    dlg.ai_test_btn.setToolTip("发送一个 1-token 的最小请求验证配置是否正确。")
    dlg.ai_test_btn.clicked.connect(dlg._on_test_connection)
    test_layout.addWidget(dlg.ai_test_btn)

    layout.addWidget(test_group)
    layout.addStretch(1)
    return tab



def build_ai_advanced_group(dlg) -> tuple[QGroupBox, QFormLayout]:
    """第三枪 批次① Step 8: collapsible advanced AI options.

    Returns the group box (which the caller adds to the AI tab layout)
    and its form layout (which the caller uses to read/write widgets).
    The group is collapsed by default so non-technical users are not
    overwhelmed.
    """
    group = QGroupBox("高级（双模型 / Schema / 缓存 / 流水线）")
    group.setCheckable(True)
    group.setChecked(False)
    form = QFormLayout(group)
    form.setSpacing(10)

    dlg.ai_model_chat_edit = QLineEdit()
    dlg.ai_model_chat_edit.setPlaceholderText("空 = 使用主模型；对话/解释走此模型")
    dlg.ai_model_chat_edit.setToolTip(
        "可选：用于 AI 对齐对话 / 课程解释的较小或更便宜模型。"
        "留空则使用上面的主模型。"
    )
    form.addRow("对话模型 (model_chat):", dlg.ai_model_chat_edit)

    dlg.ai_model_json_edit = QLineEdit()
    dlg.ai_model_json_edit.setPlaceholderText("空 = 使用主模型；JSON 生成/修复走此模型")
    dlg.ai_model_json_edit.setToolTip(
        "可选：用于课程 / 课时 / 题目 JSON 生成与修复的模型。"
        "留空则使用主模型。"
    )
    form.addRow("JSON 模型 (model_json):", dlg.ai_model_json_edit)

    dlg.ai_strict_schema_combo = QComboBox()
    dlg.ai_strict_schema_combo.addItem("自动探测（推荐）", "auto")
    dlg.ai_strict_schema_combo.addItem("强制 json_schema", "on")
    dlg.ai_strict_schema_combo.addItem("仅 json_object", "off")
    dlg.ai_strict_schema_combo.setToolTip(
        "json_schema 让模型严格按 section schema 输出 JSON。\n"
        "「自动探测」首次尝试 json_schema，若供应商拒绝则自动回退到 json_object。\n"
        "强制模式不会自动回退（出错请改回「自动」或「关闭」）。"
    )
    form.addRow("JSON Schema 严格度:", dlg.ai_strict_schema_combo)

    dlg.ai_cache_check = QCheckBox("启用响应缓存（同模型+同 prompt 复用结果）")
    dlg.ai_cache_check.setToolTip(
        "进程内 LRU 缓存，键为 (model, messages, response_format) 的 SHA-256。\n"
        "不存储 API Key 或原始 prompt；磁盘持久化可在配置文件中开启。\n"
        "默认关闭以便测试稳定；启用后可显著降低重复请求成本。"
    )
    form.addRow(dlg.ai_cache_check)

    dlg.ai_fill_needs_review_check = QCheckBox(
        "生成后自动补全 [待补] / needs-review 词条（额外调用）"
    )
    dlg.ai_fill_needs_review_check.setToolTip(
        "可选：生成 section 后再发一次 LLM 请求补全空翻译/释义。\n"
        "默认关闭以节省 token；启用后可减少人工扫尾。"
    )
    form.addRow(dlg.ai_fill_needs_review_check)

    dlg.ai_max_parallel_lessons_spin = QSpinBox()
    dlg.ai_max_parallel_lessons_spin.setRange(1, 8)
    dlg.ai_max_parallel_lessons_spin.setToolTip(
        "精修模式（大纲->分课）下并行生成课时的最大并发数。"
        "1 = 顺序（安全默认）。建议 2-4；超过 4 可能触发供应商速率限制。"
    )
    form.addRow("课时并行上限:", dlg.ai_max_parallel_lessons_spin)

    dlg.ai_pipeline_default_mode_combo = QComboBox()
    dlg.ai_pipeline_default_mode_combo.addItem("快速（整节一次生成）", "fast")
    dlg.ai_pipeline_default_mode_combo.addItem("精修（大纲->分课）", "refine")
    dlg.ai_pipeline_default_mode_combo.setToolTip(
        "新建项目时工坊默认的生成模式。用户仍可在工坊中切换。"
    )
    form.addRow("默认生成模式:", dlg.ai_pipeline_default_mode_combo)

    hint = QLabel(
        "这些选项为进阶用户准备；多数情况下保持默认即可。"
        "更改后下次 AI 请求生效。"
    )
    hint.setObjectName("hintLabel")
    hint.setWordWrap(True)
    form.addRow(hint)

    return group, form



def on_provider_changed(dlg, _index: int) -> None:
    """When a built-in provider is selected, fill its defaults.

    The ``custom`` preset leaves user input alone so manually entered
    endpoints are not overwritten.
    """
    name = dlg.ai_provider_combo.currentData()
    preset = ai_presets.preset_for_provider(name)
    if preset.name == "custom":
        return
    dlg.ai_url_edit.setText(preset.base_url)
    dlg.ai_model_edit.setText(preset.default_model)
    dlg.ai_reasoning_check.setChecked(preset.supports_reasoning)



def on_test_connection(dlg) -> None:
    from src.backend.ai import AiApiConfig

    dlg._sync_to_settings()
    config = AiApiConfig(
        base_url=dlg._settings.ai_base_url,
        api_key=dlg._settings.ai_api_key,
        model=dlg._settings.ai_model,
        supports_reasoning=dlg._settings.ai_supports_reasoning,
        model_chat=dlg._settings.ai_model_chat,
        model_json=dlg._settings.ai_model_json,
        strict_schema=dlg._settings.ai_strict_schema,
    )
    if not config.is_complete:
        dlg.ai_connection_status.setText(
            f"<font color='{current_palette()['error']}'>"
            "请先填写 Base URL、API Key 和 Model。</font>"
        )
        return

    dlg.ai_test_btn.setEnabled(False)
    dlg.ai_test_btn.setText("测试中…")
    dlg.ai_connection_status.setText("正在发送 1-token 测试请求…")

    try:
        result = verify_connection(config, timeout=15.0)
    except Exception as exc:  # noqa: BLE001
        result = {"ok": False, "error": str(exc)}

    dlg.ai_test_btn.setEnabled(True)
    dlg.ai_test_btn.setText("测试连接")
    if result.get("ok"):
        model = result.get("model") or config.model
        dlg.ai_connection_status.setText(
            f"<font color='{current_palette()['success']}'>连接成功：{model}</font>"
        )
    else:
        error = result.get("error", "未知错误")
        dlg.ai_connection_status.setText(
            f"<font color='{current_palette()['error']}'>连接失败：{error}</font>"
        )

