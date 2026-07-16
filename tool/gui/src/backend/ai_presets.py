"""AI provider/model presets and local pricing table for cost estimation.

Pure Python, no PySide6 dependency. The module provides ready-made provider
configurations (DeepSeek, OpenAI, Moonshot, Ollama) plus a fallback "custom"
preset, so users can switch vendors without manually typing Base URL and default
model every time.

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


#: Built-in presets keyed by machine name.
BUILTIN_PRESETS: dict[str, ProviderPreset] = {
    "deepseek": ProviderPreset(
        name="deepseek",
        label="DeepSeek",
        base_url="https://api.deepseek.com",
        default_model="deepseek-v4-pro",
        supported_models=[
            "deepseek-v4-pro",
            "deepseek-chat",
            "deepseek-reasoner",
        ],
        supports_reasoning=True,
        docs_url="https://platform.deepseek.com/",
    ),
    "openai": ProviderPreset(
        name="openai",
        label="OpenAI",
        base_url="https://api.openai.com/v1",
        default_model="gpt-4o",
        supported_models=[
            "gpt-4o",
            "gpt-4o-mini",
            "gpt-4-turbo",
            "gpt-3.5-turbo",
        ],
        supports_reasoning=False,
        docs_url="https://platform.openai.com/",
    ),
    "moonshot": ProviderPreset(
        name="moonshot",
        label="Moonshot AI",
        base_url="https://api.moonshot.cn/v1",
        default_model="moonshot-v1-8k",
        supported_models=[
            "moonshot-v1-8k",
            "moonshot-v1-32k",
            "moonshot-v1-128k",
        ],
        supports_reasoning=False,
        docs_url="https://platform.moonshot.cn/",
    ),
    "ollama": ProviderPreset(
        name="ollama",
        label="Ollama (本地)",
        base_url="http://localhost:11434/v1",
        default_model="qwen2.5",
        supported_models=[
            "qwen2.5",
            "llama3",
            "deepseek-coder-v2",
        ],
        supports_reasoning=False,
        docs_url="https://ollama.com/",
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

#: Pricing table: model -> {in, out, currency}. Rates are per 1M tokens.
#: ``in`` = prompt/input tokens, ``out`` = completion/output tokens.
#: Currency is CNY for Chinese-hosted models and USD for others.
PRICING: dict[str, dict[str, Any]] = {
    # DeepSeek
    "deepseek-v4-pro": {"in": 2.0, "out": 8.0, "currency": "CNY"},
    "deepseek-chat": {"in": 1.0, "out": 4.0, "currency": "CNY"},
    "deepseek-reasoner": {"in": 4.0, "out": 16.0, "currency": "CNY"},
    # OpenAI (USD)
    "gpt-4o": {"in": 2.5, "out": 10.0, "currency": "USD"},
    "gpt-4o-mini": {"in": 0.15, "out": 0.6, "currency": "USD"},
    "gpt-4-turbo": {"in": 10.0, "out": 30.0, "currency": "USD"},
    "gpt-3.5-turbo": {"in": 0.5, "out": 1.5, "currency": "USD"},
    # Moonshot (CNY)
    "moonshot-v1-8k": {"in": 1.2, "out": 1.2, "currency": "CNY"},
    "moonshot-v1-32k": {"in": 2.4, "out": 2.4, "currency": "CNY"},
    "moonshot-v1-128k": {"in": 6.0, "out": 6.0, "currency": "CNY"},
    # Ollama local: no remote billing; show tokens only.
}

#: Prefix fallback for models not explicitly listed but from known families.
_PREFIX_FALLBACK: dict[str, dict[str, Any]] = {
    "deepseek": {"in": 1.0, "out": 4.0, "currency": "CNY"},
    "gpt": {"in": 2.5, "out": 10.0, "currency": "USD"},
    "moonshot": {"in": 2.4, "out": 2.4, "currency": "CNY"},
    "qwen": {"in": 1.0, "out": 4.0, "currency": "CNY"},
}

_CURRENCY_SYMBOL = {"CNY": "¥", "USD": "$"}


def preset_for_provider(name: str) -> ProviderPreset:
    """Return the preset for ``name``, falling back to ``custom``."""
    return BUILTIN_PRESETS.get(name, BUILTIN_PRESETS["custom"])


def provider_names() -> list[str]:
    """Return all built-in provider machine names in a stable order."""
    return ["deepseek", "openai", "moonshot", "ollama", "custom"]


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
