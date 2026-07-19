"""Extract per-chapter knowledge points from a textbook via the LLM.

The ③→④ step of the textbook-import pipeline (bookplan.md): given a chopped
``Chapter``, ask the model for ``{words, expressions, grammarPoints}`` and
coerce them into a schema-valid ``KnowledgePoints`` for
``build_section_from_chapter``.

Design notes (verified against existing code):
- Uses ``ai_generator.request_chat`` (not ``parse_completion`` — the latter
  requires a top-level ``units`` array which we deliberately do not request).
- JSON extraction via ``ai_fixer.extract_json_object`` (handles fences/trailing
  text), then ``knowledge_schema.coerce_knowledge_points`` for schema coercion.
- Retry mirrors ``request_course_with_retry`` (ai_generator.py:926): on a
  coercion/parse failure we append an assistant turn (the last JSON) plus a
  user correction turn and retry once at a lower temperature.
- ``cancel_check``/``on_chunk``/``usage_callback`` are forwarded to
  ``request_chat`` so the GUI can wrap this with ``AiRequestWorker`` without
  this module knowing anything about Qt.
"""
from __future__ import annotations

from typing import Any, Callable, Literal

from src.backend.ai_fixer import extract_json_object
from src.backend.ai_generator import AiApiConfig, request_chat
from src.backend.knowledge_prompt import (
    _MAX_CHAPTER_CHARS,
    build_correction_prompt,
    build_extraction_messages,
    build_vocab_only_extraction_messages,
)
from src.backend.knowledge_schema import KnowledgePoints, coerce_knowledge_points
from src.backend.markdown_chopper import Chapter

ExtractionStrategy = Literal["standard", "vocab_only"]


def _content(body: dict[str, Any]) -> str:
    """Pull the assistant content string out of an OpenAI-style response body."""
    try:
        return body["choices"][0]["message"]["content"] or ""
    except (KeyError, IndexError, TypeError):
        return ""


def _collect_errors(content: str, id_prefix: str) -> tuple[list[str], KnowledgePoints | None]:
    """Parse ``content`` and coerce it; return (error_messages, kp_or_None).

    On success returns ``([], KnowledgePoints)``. On any parse/coerce failure
    returns a non-empty list of human-readable error strings and ``None``.
    """
    if not content.strip():
        return ["模型返回空内容。"], None
    try:
        parsed = extract_json_object(content)
    except ValueError as exc:
        return [f"无法解析 JSON：{exc}"], None
    try:
        kp = coerce_knowledge_points(parsed, id_prefix=id_prefix)
    except (ValueError, TypeError) as exc:
        return [f"知识点规整失败：{exc}"], None
    # coerce succeeds, but an all-empty extraction is a soft failure we surface
    # — the caller may still import an empty section; we don't treat it as an
    # error here (the GUI marks empty chapters to skip).
    return [], kp


def _call_and_parse(
    config: AiApiConfig,
    messages: list[dict[str, str]],
    temperature: float,
    *,
    timeout: float,
    cancel_check: Callable[[], bool] | None,
    on_chunk: Callable[[str], None] | None,
    usage_callback: Callable[[dict[str, int]], None] | None,
    id_prefix: str,
    max_tokens: int | None = None,
) -> tuple[KnowledgePoints | None, list[str], str]:
    """One attempt: request_chat → parse → coerce.

    Returns ``(kp_or_None, errors, last_content)``. ``last_content`` is the raw
    model content of this attempt (used as the assistant turn on retry). Any
    ``RuntimeError`` from ``request_chat`` (config/network/JSON) propagates;
    ``AiCancelled`` propagates.
    """
    body = request_chat(
        config,
        messages,
        temperature=temperature,
        response_format={"type": "json_object"},
        timeout=timeout,
        cancel_check=cancel_check,
        stream=on_chunk is not None,
        on_chunk=on_chunk,
        usage_callback=usage_callback,
        max_tokens=max_tokens,
    )
    content = _content(body)
    errors, kp = _collect_errors(content, id_prefix)
    return kp, errors, content


def extract_knowledge_points(
    config: AiApiConfig,
    language: str,
    source_language: str,
    chapter: Chapter,
    *,
    strategy: ExtractionStrategy = "standard",
    temperature: float = 0.3,
    timeout: float = 120.0,
    cancel_check: Callable[[], bool] | None = None,
    on_chunk: Callable[[str], None] | None = None,
    usage_callback: Callable[[dict[str, int]], None] | None = None,
    max_retries: int = 1,
    max_tokens: int | None = None,
    max_chapter_chars: int = _MAX_CHAPTER_CHARS,
) -> KnowledgePoints:
    """Extract knowledge points for ``chapter`` via the LLM, with one retry.

    - ``strategy="vocab_only"`` asks the model for words only; expressions and
      grammar points are left empty. This is used as a manual fallback when the
      full extraction fails.
    - First attempt streams when ``on_chunk`` is set.
    - On parse/coerce failure, appends an assistant turn (the last content) and
      a user correction turn, then retries once at ``temperature - 0.2`` without
      streaming (mirrors ``request_course_with_retry``).
    - ``AiCancelled`` and ``RuntimeError`` from ``request_chat`` propagate.
    - If all attempts fail to produce a coercible result, raises
      ``RuntimeError`` describing the last errors.
    - ``id_prefix`` is ``"ch-{slug}-"`` so resource ids are deterministic and
      route through the merge path on re-import.
    """
    id_prefix = f"ch-{chapter.slug}-"
    if strategy == "vocab_only":
        messages = build_vocab_only_extraction_messages(
            language, source_language, chapter, max_chars=max_chapter_chars
        )
    else:
        messages = build_extraction_messages(
            language, source_language, chapter, max_chars=max_chapter_chars
        )

    kp, errors, content = _call_and_parse(
        config, messages, temperature,
        timeout=timeout, cancel_check=cancel_check, on_chunk=on_chunk,
        usage_callback=usage_callback, id_prefix=id_prefix, max_tokens=max_tokens,
    )
    if kp is not None:
        if strategy == "vocab_only":
            # Ensure downstream consumers see empty expression/grammar lists.
            kp.expressions = []
            kp.grammarPoints = []
        return kp

    for _ in range(max(0, max_retries)):
        messages.append({"role": "assistant", "content": content})
        messages.append({"role": "user", "content": build_correction_prompt(errors)})
        kp, errors, content = _call_and_parse(
            config, messages, max(0.0, temperature - 0.2),
            timeout=timeout, cancel_check=cancel_check, on_chunk=None,
            usage_callback=usage_callback, id_prefix=id_prefix, max_tokens=max_tokens,
        )
        if kp is not None:
            if strategy == "vocab_only":
                kp.expressions = []
                kp.grammarPoints = []
            return kp

    raise RuntimeError(
        "知识点抽取失败，已重试仍无法得到有效结果。最后错误：\n- "
        + "\n- ".join(errors)
    )