"""Generate → validate → re-prompt loop with optional response cache.

Extracted from ``ai_generator`` (M1 refactor).
"""
from __future__ import annotations

import json
from typing import Any, Callable

from src.backend.ai.client import resolved_request_chat
from src.backend.ai.config import AiApiConfig
from src.backend.ai.parse import parse_completion
from src.backend.ai.prompts import build_response_format

def coerce_problem_messages(items) -> list[str]:
    """Normalize a validator's return value to human-readable error strings.

    ``validate_section_json`` returns ``list[dict]`` (Problem dicts with
    ``level``/``message``/``path``), but the retry contract historically
    documented ``list[str]``. Accept either: for a dict, take ``message``
    (and ``path`` when present) and only keep it when ``level`` is missing
    or ``"error"`` (warnings are not re-fed to the model); for a plain
    string, treat it as an error.
    """
    messages: list[str] = []
    for item in items or []:
        if isinstance(item, dict):
            level = item.get("level", "error")
            if level and level != "error":
                continue
            msg = item.get("message") or ""
            if not msg:
                continue
            path = item.get("path") or ""
            if path:
                messages.append(f"{path}: {msg}")
            else:
                messages.append(str(msg))
        elif item:
            messages.append(str(item))
    return messages


def build_correction_user_turn(errors: list[str]) -> str:
    return (
        "上一版有以下校验错误，请修正后只输出完整的修正 JSON：\n- "
        + "\n- ".join(errors)
    )


def generate_with_validate_loop(
    config: AiApiConfig,
    messages: list[dict[str, Any]],
    validator: Callable[[dict], Any] | None,
    *,
    max_retries: int = 1,
    temperature: float = 0.4,
    temperature_decay: float = 0.2,
    timeout: float = 120.0,
    cancel_check: Callable[[], bool] | None = None,
    on_chunk: Callable[[str], None] | None = None,
    usage_callback: Callable[[dict[str, int]], None] | None = None,
    response_format: dict[str, Any] | None = None,
    parse: Callable[[Any], dict] | None = None,
    stream_first_only: bool = True,
    cache: "AiCache | None" = None,
    model: str | None = None,
    max_tokens: int | None = None,
) -> dict:
    """Request JSON, parse, and re-prompt on validator errors (aiEnhance P1).

    Shared by course generation, chat generation, edit, and lesson transform.
    When ``validator`` is ``None`` or ``max_retries`` is 0, behaves as a single
    request + parse. First attempt may stream; retries never stream when
    ``stream_first_only`` is True.

    第三枪 批次① additions:
    - ``cache``: optional :class:`src.backend.ai_cache.AiCache`. When supplied
      and enabled, the *first* attempt consults the cache before hitting the
      network. A cache hit still runs ``validator`` so a stale-but-invalid
      entry triggers the normal correction loop. Successful results are
      written back to the cache. Retries (which carry a correction user turn)
      never consult the cache.
    - ``model``: explicit model id to send in the payload. When ``None``, the
      caller's ``config.model`` is used (dual-model routing happens at the
      call site, not here).
    - ``max_tokens``: forwarded to every ``request_chat`` call. Used by
      knowledge extraction (preset-capped responses).
    """
    parse_fn = parse or parse_completion
    # Resolve the response_format. The caller may pass an explicit dict
    # (takes precedence); otherwise we consult ``config.strict_schema`` via
    # ``build_response_format`` so the loop respects the auto-fallback probe.
    if response_format is not None:
        fmt = response_format
    else:
        fmt = build_response_format(config, schema_name="section", use_schema=True)
    # Mutate a local copy so callers can reuse their message list safely.
    msgs: list[dict[str, Any]] = list(messages)

    # Fall back to the process-wide default cache when the caller didn't supply
    # one explicitly. Callers that want to disable caching can pass an
    # explicitly-disabled ``AiCache(enabled=False)`` instance.
    from src.backend.ai_cache import get_default_cache

    effective_cache = cache if cache is not None else get_default_cache()

    # --- Cache lookup (first attempt only) ---
    cache_hit = False
    if effective_cache is not None and effective_cache.enabled:
        cached = effective_cache.get(model or config.model, msgs, fmt)
        if cached is not None:
            cache_hit = True
            # Re-validate the cached body; if it passes (or there's no
            # validator), skip the network entirely. If it fails, fall
            # through to a live request so the correction loop can repair.
            try:
                result = parse_fn({"choices": [{"message": {"content": json.dumps(cached, ensure_ascii=False)}}]})
            except Exception:
                result = cached
            if validator is None or max_retries <= 0:
                return result
            problems = list(validator(result) or [])
            errors = coerce_problem_messages(problems)
            if not errors:
                return result
            # else: cached but invalid -> fall through and re-issue live

    if not cache_hit:
        body = resolved_request_chat(
            config,
            msgs,
            temperature=temperature,
            response_format=fmt,
            timeout=timeout,
            cancel_check=cancel_check,
            stream=on_chunk is not None,
            on_chunk=on_chunk,
            usage_callback=usage_callback,
            model=model,
            max_tokens=max_tokens,
        )
        result = parse_fn(body)
    # else: we already have `result` from the cache branch above.

    if validator is None or max_retries <= 0:
        if effective_cache is not None and effective_cache.enabled and not cache_hit:
            effective_cache.put(model or config.model, list(messages), fmt, result)
        return result

    temp = temperature
    for _ in range(max(0, max_retries)):
        problems = list(validator(result) or [])
        errors = coerce_problem_messages(problems)
        if not errors:
            break
        msgs.append(
            {"role": "assistant", "content": json.dumps(result, ensure_ascii=False)}
        )
        msgs.append({"role": "user", "content": build_correction_user_turn(errors)})
        temp = max(0.0, temp - temperature_decay)
        body = resolved_request_chat(
            config,
            msgs,
            temperature=temp,
            response_format=fmt,
            timeout=timeout,
            cancel_check=cancel_check,
            stream=False if stream_first_only else on_chunk is not None,
            on_chunk=None if stream_first_only else on_chunk,
            usage_callback=usage_callback,
            model=model,
            max_tokens=max_tokens,
        )
        result = parse_fn(body)
    else:
        # Loop completed without `break` -> last attempt still had errors.
        # Don't cache invalid results.
        return result

    # Loop broke with no errors -> cache the final valid result.
    if effective_cache is not None and effective_cache.enabled and not cache_hit:
        effective_cache.put(model or config.model, list(messages), fmt, result)
    return result


# Back-compat
_coerce_problem_messages = coerce_problem_messages
_build_correction_user_turn = build_correction_user_turn
