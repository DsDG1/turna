"""Server-Sent Events (SSE) streaming parsing for OpenAI-compatible endpoints.

Pure-Python, no third-party dependencies. Reads the HTTP response body
line-by-line (``urllib`` response objects are iterable over their lines) and
yields ``choices[0].delta.content`` fragments so the UI can render tokens as
they arrive.

The OpenAI streaming protocol sends one JSON object per ``data:`` line and a
terminal ``data: [DONE]`` sentinel. Endpoints that do not support streaming
return a normal buffered JSON body (no ``data:`` prefix); the caller detects
this via :func:`looks_like_sse` and falls back to a single bulk read.

This module deliberately has no PySide6 dependency so it is unit-testable in
the sandbox.
"""
from __future__ import annotations

import json
from typing import Any, Callable, Iterator

# Sentinel yielded by :func:`iter_sse` when the stream ends with ``[DONE]``.
# An empty string is a legitimate (if unusual) content fragment, so we cannot
# use "" as the terminal marker.
DONE = "__DONE__"


def parse_sse_line(line: str) -> str | None:
    """Parse a single SSE line into a content fragment.

    Returns the ``choices[0].delta.content`` string, or ``None`` when the line
    is not a content-bearing ``data:`` line (blank line, comment, keep-alive,
    or a ``data:`` line whose delta has no ``content`` field).

    Returns :data:`DONE` for the terminal ``data: [DONE]`` sentinel so the
    caller can stop iteration.
    """
    if not line:
        return None
    line = line.strip()
    if not line.startswith("data:"):
        # ``:`` comment lines, ``event:``, ``id:``, etc. are not content.
        return None
    payload = line[len("data:"):].strip()
    if payload == "[DONE]":
        return DONE
    if not payload:
        return None
    try:
        obj = json.loads(payload)
    except json.JSONDecodeError:
        # Tolerate non-JSON ``data:`` lines (some proxies inject them).
        return None
    choices = obj.get("choices") or []
    if not choices:
        return None
    delta = choices[0].get("delta") or {}
    content = delta.get("content")
    if content is None:
        return None
    return content


def parse_sse_usage(line: str) -> dict[str, Any] | None:
    """Parse a single SSE line into a usage dict, if it carries one.

    Some endpoints append a terminal chunk like
    ``data: {"choices": [], "usage": {...}}`` before ``[DONE]``. Returns the
    ``usage`` object, or ``None`` for any other line.
    """
    if not line:
        return None
    line = line.strip()
    if not line.startswith("data:"):
        return None
    payload = line[len("data:"):].strip()
    if not payload or payload == "[DONE]":
        return None
    try:
        obj = json.loads(payload)
    except json.JSONDecodeError:
        return None
    usage = obj.get("usage")
    return usage if isinstance(usage, dict) else None


def looks_like_sse(first_line: str) -> bool:
    """Heuristic: does the first response line look like an SSE stream?

    Used to decide between the streaming path and the bulk-read fallback for
    endpoints that ignore ``stream: true``.
    """
    if not first_line:
        return False
    return first_line.lstrip().startswith("data:")


def _iter_lines(resp: Any) -> Iterator[str]:
    """Yield decoded text lines from a urllib response object.

    urllib response objects are iterable and yield ``bytes`` lines that may or
    may not include the trailing newline. We normalize by stripping the
    trailing newline only.
    """
    for raw in resp:
        if isinstance(raw, bytes):
            yield raw.decode("utf-8", errors="replace")
        else:
            yield str(raw)


def iter_sse(
    resp: Any,
    cancel_check: Callable[[], bool] | None = None,
) -> Iterator[str]:
    """Yield content fragments from an SSE streaming response.

    ``cancel_check`` is polled before each line is read so a user cancel takes
    effect promptly (fixes B6: previously cancellation only polled between
    buffered-body chunk reads, so a long server-side generation phase could
    not be interrupted until the first byte arrived).

    Stops after yielding :data:`DONE` (the ``[DONE]`` sentinel) or when the
    response is exhausted. Non-``data:`` lines are skipped silently.
    """
    for line in _iter_lines(resp):
        if cancel_check is not None and cancel_check():
            raise _CancelInterrupt()
        fragment = parse_sse_line(line)
        if fragment is None:
            continue
        yield fragment
        if fragment == DONE:
            return


class _CancelInterrupt(Exception):
    """Internal sentinel raised inside :func:`iter_sse` on cancellation.

    :func:`request_chat` translates this into :class:`AiCancelled` so callers
    keep their existing exception contract. Kept module-private rather than
    reusing ``AiCancelled`` to avoid importing the config-bearing module here.
    """


def read_all(resp: Any) -> str:
    """Bulk-read the entire response body as text (non-streaming fallback)."""
    raw = resp.read()
    if isinstance(raw, bytes):
        return raw.decode("utf-8", errors="replace")
    return str(raw)