"""AI provider/model presets and local pricing table for cost estimation.

Pure Python, no PySide6 dependency. Mirrors the app-side contract in
``lib/application/ai/engine/ai_provider_preset.dart``: the product keeps
**DeepSeek** and **MiMo** as named presets plus a free-form ``custom`` one.
Providers that were retired (OpenAI / Moonshot / Kimi / Qwen / Ollama) survive
only as migration entries: an old settings row is translated into ``custom``
with its Base URL preserved, so the connection keeps working instead of
silently pointing at DeepSeek with a foreign model id.

Pricing rates are local estimates only and are **not** a billing source. They
are used by ``src/backend/ai_usage.py`` to show an approximate cost next to the
token counter.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any


@dataclass(frozen=True)
class ProviderPreset:
    """A provider preset carrying enough information to fill the Settings UI."""

    name: str
    label: str
    base_url: str
    default_model: str
    supported_models: list[str] = field(default_factory=list)
    supports_reasoning: bool = False
    docs_url: str = ""


#: Built-in presets keyed by machine name. Kept in lockstep with the Dart
#: ``kBuiltinPresets`` table - changing one without the other makes the two
#: editors disagree about the default model.
BUILTIN_PRESETS: dict[str, ProviderPreset] = {
    "deepseek": ProviderPreset(
        name="deepseek",
        label="DeepSeek",
        base_url="https://api.deepseek.com",
        default_model="deepseek-v4.1-flash",
        supported_models=[
            "deepseek-v4.1-flash",
            "deepseek-v4.1-pro",
        ],
        supports_reasoning=True,
        docs_url="https://platform.deepseek.com/",
    ),
    "mimo": ProviderPreset(
        name="mimo",
        label="MiMo",
        base_url="https://api.xiaomimimo.com/v1",
        default_model="mimo-v2.6-pro",
        supported_models=[
            "mimo-v2.6-pro",
            "mimo-v2.6",
        ],
        supports_reasoning=True,
        docs_url="https://mimo.mi.com/docs/zh-CN/quick-start/summary/model",
    ),
    "custom": ProviderPreset(
        name="custom",
        label="自定义",
        base_url="",
        default_model="",
        supported_models=[],
        supports_reasoning=False,
    ),
}

#: Retired providers: ``provider name -> (base_url, last known default model)``.
#: Only used to migrate persisted settings into ``custom``; never offered in the
#: dropdown. Mirrors ``kRetiredPresets`` on the Dart side.
RETIRED_PRESETS: dict[str, tuple[str, str]] = {
    "openai": ("https://api.openai.com/v1", ""),
    "moonshot": ("https://api.moonshot.cn/v1", ""),
    "kimi": ("https://api.moonshot.cn/v1", "kimi-k3"),
    "qwen": ("https://dashscope.aliyuncs.com/compatible-mode/v1", "qwen3.8-max"),
    "ollama": ("http://localhost:11434/v1", ""),
}

#: Model rename table: old id -> current id. Only exact matches are rewritten,
#: so a user's proxy alias is never touched. Mirrors ``kRetiredModelAliases``.
MODEL_ALIASES: dict[str, str] = {
    "deepseek-v4-flash": "deepseek-v4.1-flash",
    "deepseek-v4-pro": "deepseek-v4.1-pro",
    "deepseek-chat": "deepseek-v4.1-flash",
    "deepseek-reasoner": "deepseek-v4.1-pro",
    "mimo-v2.5-pro": "mimo-v2.6-pro",
    "mimo-v2.5": "mimo-v2.6",
}

#: Pricing table: model -> {in, out, currency}. Rates are per 1M tokens.
#: ``in`` = prompt/input tokens, ``out`` = completion/output tokens.
#: Currency is CNY for Chinese-hosted models and USD for others.
PRICING: dict[str, dict[str, Any]] = {
    # DeepSeek (current generation + historical ids kept for the cost display
    # of runs recorded before the rename).
    "deepseek-v4.1-flash": {"in": 0.5, "out": 2.0, "currency": "CNY"},
    "deepseek-v4.1-pro": {"in": 2.0, "out": 8.0, "currency": "CNY"},
    "deepseek-v4-pro": {"in": 2.0, "out": 8.0, "currency": "CNY"},
    "deepseek-chat": {"in": 1.0, "out": 4.0, "currency": "CNY"},
    "deepseek-reasoner": {"in": 4.0, "out": 16.0, "currency": "CNY"},
    # MiMo (CNY)
    "mimo-v2.6-pro": {"in": 1.0, "out": 4.0, "currency": "CNY"},
    "mimo-v2.6": {"in": 0.5, "out": 2.0, "currency": "CNY"},
}

#: Prefix fallback for models not explicitly listed but from known families.
_PREFIX_FALLBACK: dict[str, dict[str, Any]] = {
    "deepseek": {"in": 1.0, "out": 4.0, "currency": "CNY"},
    "mimo": {"in": 1.0, "out": 4.0, "currency": "CNY"},
    "gpt": {"in": 2.5, "out": 10.0, "currency": "USD"},
}

_CURRENCY_SYMBOL = {"CNY": "¥", "USD": "$"}


def normalize_model_id(model: str) -> str:
    """Return the current id for a renamed model, else ``model`` unchanged."""
    text = (model or "").strip()
    return MODEL_ALIASES.get(text, text)


def migrate_provider(name: str) -> tuple[str, str, str]:
    """Translate a persisted provider name into ``(provider, base_url, model)``.

    A live provider is returned as ``(name, "", "")`` so the caller keeps the
    stored Base URL / model. A retired provider becomes ``custom`` plus the
    retired entry's Base URL and (possibly empty) default model, preserving the
    user's connection instead of dropping them on DeepSeek's endpoint.
    """
    key = (name or "").strip().lower()
    if key in BUILTIN_PRESETS:
        return key, "", ""
    retired = RETIRED_PRESETS.get(key)
    if retired is None:
        return "custom", "", ""
    base_url, default_model = retired
    return "custom", base_url, default_model


def preset_for_provider(name: str) -> ProviderPreset:
    """Return the preset for ``name``, falling back to ``custom``."""
    return BUILTIN_PRESETS.get(name, BUILTIN_PRESETS["custom"])


def provider_names() -> list[str]:
    """Return all built-in provider machine names in a stable order."""
    return ["deepseek", "mimo", "custom"]


def pricing_for_model(model: str) -> dict[str, Any] | None:
    """Return a pricing entry for ``model`` or ``None`` for token-only display.

    Exact matches take precedence over prefix fallbacks. Local models such as
    Ollama return ``None`` so the UI shows tokens without a misleading cost.
    """
    if not model:
        return None
    if model in PRICING:
        return dict(PRICING[model])
    prefix = model.split("-", 1)[0].lower()
    fallback = _PREFIX_FALLBACK.get(prefix)
    return dict(fallback) if fallback else None


def estimate_cost(usage: dict[str, int], model: str) -> tuple[float | None, str]:
    """Estimate cost from usage and model.

    Mirrors the contract of ``src.backend.ai_usage.estimate_cost`` but sources
    the price table from this module so presets and pricing live together.
    Returns ``(None, "")`` for unknown/local models.
    """
    if not model:
        return None, ""
    entry = pricing_for_model(model)
    if entry is None:
        return None, ""
    in_rate = float(entry.get("in", 0))
    out_rate = float(entry.get("out", 0))
    cost = (
        usage.get("prompt_tokens", 0) * in_rate
        + usage.get("completion_tokens", 0) * out_rate
    ) / 1_000_000
    return round(cost, 4), str(entry.get("currency", "CNY"))


def currency_symbol(currency_code: str) -> str:
    """Return the display symbol for a currency code."""
    return _CURRENCY_SYMBOL.get(currency_code, "")


def apply_preset(
    base_url: str,
    model: str,
    supports_reasoning: bool,
    preset_name: str,
) -> tuple[str, str, bool]:
    """Apply a preset to the current URL/model/reasoning triplet.

    Returns ``(new_base_url, new_model, new_supports_reasoning)``. For the
    ``custom`` preset the existing values are preserved so the user keeps
    whatever they typed.
    """
    preset = preset_for_provider(preset_name)
    if preset.name == "custom":
        return base_url, model, supports_reasoning
    return preset.base_url, preset.default_model, preset.supports_reasoning
