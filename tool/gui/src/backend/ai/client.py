"""OpenAI-compatible HTTP client (urllib).

Extracted from ``ai_generator`` (M1 refactor). Single network entry: ``request_chat``.

Monkeypatch note (M1): many tests patch ``src.backend.ai_generator.request_chat``
and ``src.backend.ai_generator.urllib.request.urlopen``. Internal callers should
prefer :func:`resolved_request_chat` (or import ``request_chat`` from the
``ai_generator`` shim at *call* time). ``urlopen`` is routed through the shim's
``urllib`` when present so legacy patches keep working.
"""
from __future__ import annotations

import json
import urllib.error
import urllib.request
from typing import Any, Callable

from src.backend import ai_stream, ai_usage
from src.backend.ai.config import AiApiConfig, AiCancelled
from src.backend.ai.parse import content_text
import logging
logger = logging.getLogger(__name__)


def _urlopen(req: urllib.request.Request, timeout: float | None = None):
    """``urlopen`` that honors monkeypatches on ``ai_generator.urllib``.

    Only import/lookup failures fall back to local ``urllib``; HTTP/URL errors
    from the chosen ``urlopen`` must propagate (never swallow).
    """
    urlopen_fn = urllib.request.urlopen
    try:
        from src.backend import ai_generator as ag

        u = getattr(ag, "urllib", None)
        if u is not None:
            urlopen_fn = u.request.urlopen
    except ImportError:
        logger.debug("backend/ai/client.py:_urlopen best-effort step failed", exc_info=True)
    return urlopen_fn(req, timeout=timeout)  # noqa: S310


def resolved_request_chat(*args: Any, **kwargs: Any) -> dict:
    """Call ``request_chat`` via the ``ai_generator`` shim when available.

    Ensures ``mock.patch("src.backend.ai_generator.request_chat", ...)`` still
    intercepts generate / fill / transform loops after the M1 split.

    Exceptions raised by the (possibly mocked) callable propagate unchanged —
    do not catch ``AiCancelled`` / ``RuntimeError`` here.
    """
    try:
        from src.backend import ai_generator as ag

        fn = getattr(ag, "request_chat", None)
    except ImportError:
        fn = None
    if callable(fn):
        return fn(*args, **kwargs)
    return request_chat(*args, **kwargs)


def looks_like_json_schema_rejection(exc: urllib.error.HTTPError, detail: str) -> bool:
    """Heuristic: does this HTTP error indicate the provider rejected
    ``response_format.type == "json_schema"``?

    Matches on:
    - HTTP 400 (Bad Request)
    - body contains any of: ``"schema"``, ``"response_format"``, ``"unsupported"``,
      ``"unknown"`` (case-insensitive)
    """
    if exc.code != 400:
        return False
    lowered = detail.lower()
    return any(
        marker in lowered
        for marker in ("schema", "response_format", "unsupported", "unknown field")
    )

def chat_json(
    config: AiApiConfig,
    messages: list[dict[str, Any]],
    *,
    temperature: float,
    timeout: float,
    cancel_check: Callable[[], bool] | None,
    on_chunk: Callable[[str], None] | None,
    usage_callback: Callable[[dict[str, int]], None] | None,
    response_format: bool = True,
    model: str | None = None,
) -> dict:
    """request_chat with the standard streaming/usage kwargs (JSON mode by default).

    第三枪 批次①: ``model`` overrides ``config.model`` for dual-model routing
    (``config.select_model("chat"|"json")``). When ``None``, falls back to
    ``config.model``.
    """
    return resolved_request_chat(
        config,
        messages,
        temperature=temperature,
        response_format={"type": "json_object"} if response_format else None,
        timeout=timeout,
        cancel_check=cancel_check,
        stream=on_chunk is not None,
        on_chunk=on_chunk,
        usage_callback=usage_callback,
        model=model,
    )

def request_chat(
    config: AiApiConfig,
    messages: list[dict[str, Any]],
    temperature: float = 0.7,
    response_format: dict[str, str] | None = None,
    timeout: float = 120.0,
    cancel_check: Callable[[], bool] | None = None,
    stream: bool = False,
    on_chunk: Callable[[str], None] | None = None,
    usage_callback: Callable[[dict[str, int]], None] | None = None,
    max_tokens: int | None = None,
    model: str | None = None,
) -> dict:
    """Call the OpenAI-compatible endpoint and return the parsed JSON body.

    Raises ``RuntimeError`` with a human-readable message on network / HTTP /
    parse errors. If ``cancel_check`` is supplied and returns True while the
    response body is being read, raises ``AiCancelled``.

    When ``stream=True`` and ``on_chunk`` is provided, the request is sent with
    ``"stream": true`` and the response is read line-by-line; each content
    fragment is delivered to ``on_chunk`` as it arrives so the UI can render
    tokens incrementally. The full assembled text is still returned as a normal
    completion body (``{"choices": [{"message": {"content": full}}], ...}``) so
    downstream callers (``parse_completion`` etc.) need no changes. If the
    endpoint ignores ``stream: true`` and returns a buffered body, this falls
    back to a bulk read and delivers the whole content to ``on_chunk`` at once.

    ``cancel_check`` is polled before each line read during streaming, so a
    cancel takes effect promptly even mid-generation (fixes B6); previously it
    only polled between buffered-body chunk reads.

    If ``usage_callback`` is provided, it receives the extracted ``usage`` dict
    (``prompt_tokens``/``completion_tokens``/``total_tokens``) for cost display,
    whether or not streaming is used. Streaming endpoints that omit usage get a
    rough text-based estimate instead of zeros.

    第三枪 批次①: ``model`` overrides ``config.model`` in the payload so the
    caller can route chat/explain vs JSON generation to different models
    (``AiApiConfig.select_model("chat"|"json")``). When ``None``, falls back
    to ``config.model``.
    """
    # Support legacy tests monkeypatching src.backend.ai_generator.request_chat
    import sys

    _legacy_mod = sys.modules.get("src.backend.ai_generator")
    if _legacy_mod is not None:
        _patched = getattr(_legacy_mod, "request_chat", None)
        if _patched is not None and _patched is not request_chat and callable(_patched):
            return _patched(
                config,
                messages,
                temperature=temperature,
                response_format=response_format,
                timeout=timeout,
                cancel_check=cancel_check,
                stream=stream,
                on_chunk=on_chunk,
                usage_callback=usage_callback,
                max_tokens=max_tokens,
                model=model,
            )

    if hasattr(config, "is_complete") and not config.is_complete:
        raise RuntimeError("API 配置不完整，请填写 Base URL / API Key / Model。")

    payload_obj: dict[str, Any] = {
        "model": model or config.model,
        "messages": messages,
        "temperature": temperature,
    }
    if max_tokens is not None:
        payload_obj["max_tokens"] = max_tokens
    # Reasoning controls, gated on the endpoint's declared capability
    # (config.supports_reasoning, defaulting to the DeepSeek host check — see
    # AiApiConfig.reasoning_enabled). Other OpenAI-compatible endpoints (OpenAI,
    # Ollama, Moonshot) reject or error on unknown payload fields. For
    # reasoning-capable endpoints, reasoning output is returned in a separate
    # ``reasoning_content`` field and never leaks into ``message.content``, so
    # JSON-course-generation parsing is unaffected.
    if config.reasoning_enabled:
        payload_obj["reasoning_effort"] = "high"
        payload_obj["thinking"] = {"type": "enabled"}
    if response_format is not None:
        payload_obj["response_format"] = response_format
    # Streaming is only meaningful if the caller wants incremental chunks.
    if stream and on_chunk is not None:
        payload_obj["stream"] = True
    payload = json.dumps(payload_obj).encode("utf-8")

    req = urllib.request.Request(
        config.chat_completions_url,
        data=payload,
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {config.api_key}",
            # Disable urllib's transparent Accept-Encoding gzip so that the
            # streamed SSE lines are plain text we can iterate by line. (urllib
            # does not auto-decompress streamed reads.)
            "Accept-Encoding": "identity",
        },
        method="POST",
    )
    streaming_requested = bool(payload_obj.get("stream"))
    try:
        with _urlopen(req, timeout=timeout) as resp:
            if streaming_requested:
                body = read_streaming(resp, config, cancel_check, on_chunk)
            elif cancel_check is None:
                body = resp.read().decode("utf-8")
            else:
                chunks: list[bytes] = []
                while True:
                    if cancel_check():
                        raise AiCancelled("用户取消了请求。")
                    chunk = resp.read(65536)
                    if not chunk:
                        break
                    chunks.append(chunk)
                body = b"".join(chunks).decode("utf-8")
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")[:300]
        # 第三枪 批次① Step 6: auto-fallback when the provider rejects
        # ``response_format.type == "json_schema"``. Only trigger on the
        # strict_schema=auto path; explicit "on" surfaces the error to the
        # user so they can fix their config.
        if (
            response_format is not None
            and isinstance(response_format, dict)
            and response_format.get("type") == "json_schema"
            and config.strict_schema == "auto"
            and looks_like_json_schema_rejection(exc, detail)
        ):
            config.mark_json_schema_unsupported()
            # Retry once with json_object (the loosest JSON mode).
            payload_obj["response_format"] = {"type": "json_object"}
            payload = json.dumps(payload_obj).encode("utf-8")
            retry_req = urllib.request.Request(
                config.chat_completions_url,
                data=payload,
                headers={
                    "Content-Type": "application/json",
                    "Authorization": f"Bearer {config.api_key}",
                    "Accept-Encoding": "identity",
                },
                method="POST",
            )
            try:
                with _urlopen(retry_req, timeout=timeout) as resp:
                    if streaming_requested:
                        body = read_streaming(resp, config, cancel_check, on_chunk)
                    elif cancel_check is None:
                        body = resp.read().decode("utf-8")
                    else:
                        chunks2: list[bytes] = []
                        while True:
                            if cancel_check():
                                raise AiCancelled("用户取消了请求。")
                            chunk2 = resp.read(65536)
                            if not chunk2:
                                break
                            chunks2.append(chunk2)
                        body = b"".join(chunks2).decode("utf-8")
            except urllib.error.HTTPError as exc2:
                detail2 = exc2.read().decode("utf-8", errors="replace")[:300]
                raise RuntimeError(f"HTTP {exc2.code}: {detail2}") from exc2
            except urllib.error.URLError as exc2:
                raise RuntimeError(f"网络错误: {exc2.reason}") from exc2
        else:
            raise RuntimeError(f"HTTP {exc.code}: {detail}") from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(f"网络错误: {exc.reason}") from exc

    try:
        parsed = json.loads(body) if isinstance(body, str) else body
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"无法解析 API 响应: {exc}") from exc

    if usage_callback is not None:
        usage = ai_usage.estimate_usage(parsed if isinstance(parsed, dict) else None)
        if not any(usage.values()) and streaming_requested and isinstance(parsed, dict):
            # SSE endpoints often omit usage; fall back to a rough text-based
            # estimate so the cost display is not silently zero (P0-6).
            usage = estimate_usage_from_messages(messages, parsed)
        usage_callback(usage)
    return parsed


def estimate_usage_from_messages(
    messages: list[dict[str, Any]], result_body: dict[str, Any]
) -> dict[str, int]:
    """Estimate prompt/completion tokens from message + result text (P0-6)."""
    prompt_text = "\n".join(
        content_text(m.get("content")) for m in messages if isinstance(m, dict)
    )
    completion_text = ""
    choices = result_body.get("choices") or []
    if choices:
        completion_text = content_text((choices[0].get("message") or {}).get("content"))
    prompt = ai_usage.estimate_tokens_from_text(prompt_text)
    completion = ai_usage.estimate_tokens_from_text(completion_text)
    return {
        "prompt_tokens": prompt,
        "completion_tokens": completion,
        "total_tokens": prompt + completion,
    }


def verify_connection(
    config: AiApiConfig,
    timeout: float = 10.0,
) -> dict[str, Any]:
    """Send a minimal request to verify the configured endpoint works.

    Returns a dict ``{"ok": bool, "error": str, "model": str, "usage": dict}``.
    On success ``error`` is empty and ``usage`` contains token counts.
    """
    try:
        body = resolved_request_chat(
            config,
            messages=[{"role": "user", "content": "hi"}],
            temperature=0.0,
            timeout=timeout,
            max_tokens=1,
        )
    except Exception as exc:  # noqa: BLE001
        return {"ok": False, "error": str(exc), "model": "", "usage": {}}

    choices = body.get("choices") or []
    model = body.get("model", "")
    usage = ai_usage.estimate_usage(body)
    if not choices:
        return {"ok": False, "error": "API 返回为空 choices", "model": model, "usage": usage}
    return {"ok": True, "error": "", "model": model, "usage": usage}


def read_streaming(resp: Any, config: AiApiConfig, cancel_check, on_chunk) -> str:
    """Read an SSE streaming response, delivering fragments to ``on_chunk``.

    Falls back to a bulk read if the endpoint returns a non-SSE body (it
    ignored ``stream: true``). Returns the assembled text body in either case,
    normalized to the non-streaming completion shape so callers stay uniform.
    """
    # Peek the first line without consuming the rest: read one line via the
    # response's iterator, then stream the remainder.
    line_iter = ai_stream._iter_lines(resp)
    try:
        first_line = next(line_iter)
    except StopIteration:
        first_line = ""

    if not ai_stream.looks_like_sse(first_line):
        # Non-SSE fallback: assemble the body from the first line plus the
        # remaining lines from the iterator (do NOT call resp.read(), which
        # would re-return the already-consumed first chunk on some fake
        # responses and double the body). Poll cancel_check between reads so
        # a slow non-SSE endpoint can still be interrupted; without this, a
        # user cancel during a slow bulk response would block until the
        # server-side timeout because "".join(line_iter) consumes the whole
        # iterator with no cancellation hook. (B18)
        pieces: list[str] = [first_line]
        for line in line_iter:
            if cancel_check is not None and cancel_check():
                raise AiCancelled("用户取消了请求。")
            pieces.append(line)
        full_body = "".join(pieces)
        # The whole body is a normal completion JSON; on_chunk gets the message
        # content so the UI still shows something, but callers parse the body.
        try:
            obj = json.loads(full_body)
            content = (obj.get("choices") or [{}])[0].get("message", {}).get("content", "")
            if content:
                on_chunk(content)
            return full_body
        except (json.JSONDecodeError, IndexError, KeyError):
            on_chunk(full_body)
            return full_body

    # True SSE path: stitch the first line back in front of the iterator.
    fragments: list[str] = []
    usage: dict[str, Any] | None = None
    done = False

    def _emit(fragment: str) -> bool:
        nonlocal done, usage
        if fragment == ai_stream.DONE:
            done = True
            return True
        fragments.append(fragment)
        on_chunk(fragment)
        return False

    # The first line is already consumed; process it then continue.
    first_usage = ai_stream.parse_sse_usage(first_line)
    if first_usage:
        usage = first_usage
    first_fragment = ai_stream.parse_sse_line(first_line)
    if first_fragment is not None:
        _emit(first_fragment)
    if not done:
        for line in line_iter:
            if cancel_check is not None and cancel_check():
                raise AiCancelled("用户取消了请求。")
            chunk_usage = ai_stream.parse_sse_usage(line)
            if chunk_usage:
                usage = chunk_usage
            fragment = ai_stream.parse_sse_line(line)
            if fragment is None:
                continue
            if _emit(fragment):
                break

    full_content = "".join(fragments)
    # Endpoints that send a terminal usage chunk get real counts here; the
    # rest leave ``usage`` empty and request_chat falls back to a rough
    # text-based estimate so cost display is not silently zero (P0-6).
    return json.dumps(
        {
            "choices": [
                {"message": {"role": "assistant", "content": full_content}, "finish_reason": "stop"}
            ],
            "usage": usage or {},
            "model": config.model,
        },
        ensure_ascii=False,
    )


# Back-compat
_looks_like_json_schema_rejection = looks_like_json_schema_rejection
_chat_json = chat_json
_estimate_usage_from_messages = estimate_usage_from_messages
_read_streaming = read_streaming
