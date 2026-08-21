"""Token usage + cost estimation for AI requests.

Pure-Python, no third-party dependencies. The OpenAI-compatible response body
includes a ``usage`` object (``prompt_tokens`` / ``completion_tokens`` /
``total_tokens``); this module extracts it and maps it to an estimated cost via
a built-in price table.

This is an *estimate only* — it is not a billing source. The price table covers
the common DeepSeek models with placeholder per-million-token rates and falls
back to ``None`` (token count only, no cost) for unknown models so the UI never
shows a misleading number.

No PySide6 dependency so the module is unit-testable in the sandbox.
"""
from __future__ import annotations

from typing import Any

from src.backend import ai_presets

# Re-export the centralized pricing table so legacy callers keep working.
PRICING: dict[str, dict[str, Any]] = ai_presets.PRICING


def estimate_usage(body: dict[str, Any] | None) -> dict[str, int]:
    """Extract the ``usage`` block from an OpenAI-compatible response body.

    Returns ``{"prompt_tokens": int, "completion_tokens": int,
    "total_tokens": int}`` with zeros when the body has no ``usage`` (some
    streaming endpoints omit it, or the field name differs).
    """
    if not body:
        return {"prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0}
    usage = body.get("usage") or {}
    prompt = int(usage.get("prompt_tokens", 0) or 0)
    completion = int(usage.get("completion_tokens", 0) or 0)
    total = int(usage.get("total_tokens", 0) or 0)
    if total == 0:
        total = prompt + completion
    return {
        "prompt_tokens": prompt,
        "completion_tokens": completion,
        "total_tokens": total,
    }


def estimate_tokens_from_text(text: str) -> int:
    """Very rough token estimate for when the API omits usage (e.g. SSE).

    Heuristic: ~4 chars/token for ASCII, ~2 chars/token for CJK and other
    non-ASCII scripts. Good enough for a cost *estimate* display; never used
    when the endpoint reports real usage.
    """
    if not text:
        return 0
    ascii_chars = sum(1 for c in text if ord(c) < 128)
    non_ascii = len(text) - ascii_chars
    return max(1, ascii_chars // 4 + non_ascii // 2)


def estimate_cost(usage: dict[str, int], model: str) -> tuple[float | None, str]:
    """Estimate the cost of a request from its usage and model.

    Returns ``(amount, currency_code)``. ``amount`` is ``None`` when the model
    is unknown to the price table (and not matched by a prefix fallback), so
    the UI can show tokens only rather than a wrong price.
    """
    return ai_presets.estimate_cost(usage, model)


def _format_tokens(n: int) -> str:
    """Compact token count: 12340 -> "12.3k", 1234000 -> "1.2M"."""
    if n >= 1_000_000:
        return f"{n / 1_000_000:.1f}M"
    if n >= 1000:
        return f"{n / 1000:.1f}k"
    return str(n)


def format_usage_line(usage: dict[str, int], model: str) -> str:
    """Format a human-readable single-line usage summary for the UI.

    Known model: ``"≈ 12.3k tokens · ¥0.04（估算）"``.
    Unknown model: ``"≈ 12.3k tokens（无价目表）"``.
    Zero usage: ``"≈ 0 tokens"``.
    """
    total = usage.get("total_tokens", 0)
    token_part = f"≈ {_format_tokens(total)} tokens"
    if total == 0:
        return "≈ 0 tokens"
    cost, currency = estimate_cost(usage, model)
    if cost is None:
        return f"{token_part}（无价目表）"
    symbol = ai_presets.currency_symbol(currency)
    return f"{token_part} · {symbol}{cost:.2f}（估算）"