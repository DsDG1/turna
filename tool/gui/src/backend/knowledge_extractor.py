"""Extract per-chapter knowledge points from a textbook via the LLM.

The ③->④ step of the textbook-import pipeline (bookplan.md): given a chopped
``Chapter``, ask the model for ``{words, expressions, grammarPoints}`` and
coerce them into a schema-valid ``KnowledgePoints`` for
``build_section_from_chapter``.

Design notes:
- Routes through ``ai_generator.generate_with_validate_loop`` (第三枪 批次①
  P1-3 unification) so retry / parse / correction behaviour matches the
  course-generation path. The loop's correction user-turn carries the
  validator error list (P1-4).
- JSON extraction via ``ai_fixer.extract_json_object`` (handles fences/trailing
  text), then ``knowledge_schema.coerce_knowledge_points`` for schema coercion.
- ``cancel_check``/``on_chunk``/``usage_callback`` are forwarded to
  ``request_chat`` so the GUI can wrap this with ``AiRequestWorker`` without
  this module knowing anything about Qt.
- Dual-model routing: knowledge extraction is a JSON-path call, so the loop is
  invoked with ``model=config.select_model("json")``.
- ``response_format`` is forced to ``json_object`` (knowledge output is a
  permissive ``{words, expressions, grammarPoints}`` shape, not the section
  schema; sending the section json_schema would over-constrain the model).
"""
from __future__ import annotations

from typing import Any, Callable, Literal

from src.backend.ai_fixer import extract_json_object
from src.backend.ai_generator import AiApiConfig, AiCancelled, generate_with_validate_loop
from src.backend.knowledge_merger import resource_key
from src.backend.knowledge_prompt import (
    _MAX_CHAPTER_CHARS,
    build_extraction_messages,
    build_targeted_reextract_messages,
    build_vocab_only_extraction_messages,
)
from src.backend.knowledge_schema import KnowledgePoints, coerce_knowledge_points
from src.backend.markdown_chopper import Chapter, split_chapter_windows

ExtractionStrategy = Literal["standard", "vocab_only"]


def _content(body: dict[str, Any]) -> str:
    """Pull the assistant content string out of an OpenAI-style response body."""
    try:
        return body["choices"][0]["message"]["content"] or ""
    except (KeyError, IndexError, TypeError):
        return ""


def _collect_errors(content: str, id_prefix: str) -> tuple[list[str], KnowledgePoints | None]:
    """Parse ``content`` and coerce it; return (error_messages, kp_or_None).

    Kept as a module-private helper so unit tests can exercise the parse +
    coerce pipeline without going through ``generate_with_validate_loop``
    (which would require mocking the network).
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
    return [], kp


def _make_parse_fn() -> Callable[[dict[str, Any]], dict[str, Any]]:
    """Return a ``parse(body) -> dict`` closure for the validate loop.

    Pulls the assistant content string, then runs ``extract_json_object`` so
    markdown-fenced or trailing-prose responses still yield a clean dict. A
    empty content raises ``ValueError`` so the loop surfaces a parse failure
    rather than feeding ``{}`` to the validator.
    """

    def _parse(body: dict[str, Any]) -> dict[str, Any]:
        content = _content(body)
        if not content.strip():
            raise ValueError("模型返回空内容。")
        return extract_json_object(content)

    return _parse


def _make_validator(
    id_prefix: str,
    sink: list[KnowledgePoints | None],
) -> Callable[[dict[str, Any]], list[str]]:
    """Return a validator that coerces the parsed dict and stashes the result.

    On success the coerced ``KnowledgePoints`` is stored in ``sink[0]`` and an
    empty error list is returned. On coercion failure the error message is
    returned (and ``sink[0]`` is left untouched).
    """

    def _validate(parsed: dict[str, Any]) -> list[str]:
        try:
            kp = coerce_knowledge_points(parsed, id_prefix=id_prefix)
        except (ValueError, TypeError) as exc:
            return [f"知识点规整失败：{exc}"]
        sink[0] = kp
        return []

    return _validate


def _run_extraction_loop(
    config: AiApiConfig,
    messages: list[dict[str, str]],
    id_prefix: str,
    *,
    temperature: float,
    timeout: float,
    cancel_check: Callable[[], bool] | None,
    on_chunk: Callable[[str], None] | None,
    usage_callback: Callable[[dict[str, int]], None] | None,
    max_retries: int,
    max_tokens: int | None,
) -> KnowledgePoints:
    """Run ``generate_with_validate_loop`` for one extraction prompt.

    Shared by ``extract_knowledge_points`` and
    ``reextract_knowledge_targeted`` so retry / parse / correction behaviour is
    identical on both paths. Raises ``RuntimeError`` when no attempt produced a
    coercible result; ``AiCancelled`` and ``RuntimeError`` from ``request_chat``
    propagate.
    """
    sink: list[KnowledgePoints | None] = [None]

    try:
        generate_with_validate_loop(
            config,
            messages,
            _make_validator(id_prefix, sink),
            max_retries=max_retries,
            temperature=temperature,
            temperature_decay=0.2,
            timeout=timeout,
            cancel_check=cancel_check,
            on_chunk=on_chunk,
            usage_callback=usage_callback,
            response_format={"type": "json_object"},
            parse=_make_parse_fn(),
            model=config.select_model("json"),
            max_tokens=max_tokens,
        )
    except ValueError as exc:
        # Loop's parse_fn raised (empty content / JSON parse failure) on the
        # final attempt -> surface as a knowledge-extraction RuntimeError so
        # the caller's except clause still matches.
        raise RuntimeError(f"知识点抽取失败：{exc}") from exc

    kp = sink[0]
    if kp is None:
        # Validator never succeeded -> coerce once more to raise the precise
        # error (the loop swallowed it as a retryable error string).
        # This is defensive: in practice the loop's final result is the last
        # parsed dict and the validator would have stashed kp on success.
        raise RuntimeError(
            "知识点抽取失败：模型输出未通过 schema 校验，已重试仍无法得到有效结果。"
        )
    return kp


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
    """Extract knowledge points for ``chapter`` via the LLM, with retries.

    Routes through ``generate_with_validate_loop`` so retry / correction
    behaviour matches the rest of the AI subsystem (第三枪 批次① P1-3).

    - ``strategy="vocab_only"`` asks the model for words only; expressions and
      grammar points are left empty.
    - First attempt streams when ``on_chunk`` is set; retries never stream.
    - On parse/coerce failure, the loop appends an assistant turn (the last
      JSON) plus a user correction turn carrying the validator errors, then
      retries at a lower temperature.
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

    kp = _run_extraction_loop(
        config,
        messages,
        id_prefix,
        temperature=temperature,
        timeout=timeout,
        cancel_check=cancel_check,
        on_chunk=on_chunk,
        usage_callback=usage_callback,
        max_retries=max_retries,
        max_tokens=max_tokens,
    )

    if strategy == "vocab_only":
        # Ensure downstream consumers see empty expression/grammar lists.
        kp.expressions = []
        kp.grammarPoints = []
    return kp


def merge_window_knowledge(
    window_results: list[KnowledgePoints], *, id_prefix: str
) -> KnowledgePoints:
    """Merge per-window ``KnowledgePoints`` into one deduplicated result (P4-1).

    Dedup uses the same resource keys as ``knowledge_merger`` /
    ``extraction_quality`` (normalised term+translation for words/expressions,
    title for grammar points); the first occurrence across windows wins, which
    collapses the intentional overlap between adjacent windows. Ids are then
    regenerated by ``coerce_knowledge_points`` under ``id_prefix`` (the parent
    chapter's ``ch-{slug}-`` prefix), so the merged result is deterministic and
    compatible with the cross-chapter merge path on re-import.
    """
    seen: set[tuple] = set()
    raw: dict[str, list[dict[str, Any]]] = {
        "words": [],
        "expressions": [],
        "grammarPoints": [],
    }
    for kp in window_results:
        for resource_type, entries, target in (
            ("word", kp.words, raw["words"]),
            ("expression", kp.expressions, raw["expressions"]),
            ("grammarPoint", kp.grammarPoints, raw["grammarPoints"]),
        ):
            for entry in entries:
                key = resource_key(resource_type, entry)
                if key in seen:
                    continue
                seen.add(key)
                # Strip the per-window id so coerce regenerates it under the
                # parent chapter's prefix.
                target.append({k: v for k, v in entry.items() if k != "id"})
    return coerce_knowledge_points(raw, id_prefix=id_prefix)


def extract_knowledge_points_windowed(
    config: AiApiConfig,
    language: str,
    source_language: str,
    chapter: Chapter,
    *,
    max_window_chars: int | None = None,
    overlap_chars: int = 500,
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
    """Extract knowledge points, sliding-windowing over-long chapters (P4-1).

    - ``max_window_chars`` falsy, or the chapter already fits within it:
      delegates to ``extract_knowledge_points`` unchanged (short-chapter
      behaviour is byte-for-byte identical to the pre-windowed path).
    - Longer chapters are split by ``split_chapter_windows`` and extracted
      sequentially through the same validate loop; ``cancel_check`` /
      ``on_chunk`` / ``usage_callback`` are forwarded per window so usage
      accumulates and cancellation stays responsive.
    - A failing window is recorded and skipped; the remaining windows still
      merge. Only when *every* window fails is ``RuntimeError`` raised (the
      same exception contract as the single-shot path). ``AiCancelled``
      always propagates immediately.
    - Per-window results are merged by ``merge_window_knowledge``: dedup by
      normalised resource key and ids regenerated under the parent chapter's
      ``ch-{slug}-`` prefix.
    """
    if max_window_chars and max_window_chars > 0:
        windows = split_chapter_windows(chapter, max_window_chars, overlap_chars)
    else:
        windows = [chapter]
    if len(windows) <= 1:
        return extract_knowledge_points(
            config,
            language,
            source_language,
            chapter,
            strategy=strategy,
            temperature=temperature,
            timeout=timeout,
            cancel_check=cancel_check,
            on_chunk=on_chunk,
            usage_callback=usage_callback,
            max_retries=max_retries,
            max_tokens=max_tokens,
            max_chapter_chars=max_chapter_chars,
        )

    # Windows are pre-sized to ~max_window_chars plus up to overlap_chars of
    # repeated tail; use that sum as the per-window truncation cap so the
    # overlap is never cut (only a single pathological over-cap paragraph
    # still hits the truncation fallback, matching the old behaviour).
    window_cap = max_window_chars + max(0, overlap_chars)
    results: list[KnowledgePoints] = []
    errors: list[str] = []
    for n, window in enumerate(windows, start=1):
        try:
            results.append(
                extract_knowledge_points(
                    config,
                    language,
                    source_language,
                    window,
                    strategy=strategy,
                    temperature=temperature,
                    timeout=timeout,
                    cancel_check=cancel_check,
                    on_chunk=on_chunk,
                    usage_callback=usage_callback,
                    max_retries=max_retries,
                    max_tokens=max_tokens,
                    max_chapter_chars=window_cap,
                )
            )
        except AiCancelled:
            raise
        except Exception as exc:  # noqa: BLE001 - one window failed; keep the rest
            errors.append(f"第 {n}/{len(windows)} 窗：{exc}")
    if not results:
        raise RuntimeError("知识点抽取失败：" + "；".join(errors))

    merged = merge_window_knowledge(results, id_prefix=f"ch-{chapter.slug}-")
    if strategy == "vocab_only":
        merged.expressions = []
        merged.grammarPoints = []
    return merged


def reextract_knowledge_targeted(
    config: AiApiConfig,
    language: str,
    source_language: str,
    chapter: Chapter,
    kp: KnowledgePoints,
    issues: list[Any],
    *,
    temperature: float = 0.3,
    timeout: float = 120.0,
    cancel_check: Callable[[], bool] | None = None,
    on_chunk: Callable[[str], None] | None = None,
    usage_callback: Callable[[dict[str, int]], None] | None = None,
    max_retries: int = 1,
    max_tokens: int | None = None,
    max_chapter_chars: int = _MAX_CHAPTER_CHARS,
) -> KnowledgePoints:
    """Re-extract one chapter guided by its quality issues (P4-4).

    Builds a targeted prompt (current extraction + concrete issues) via
    ``build_targeted_reextract_messages`` and runs the same validate loop as a
    fresh extraction, so parse / retry / coerce behaviour is identical. The
    returned ``KnowledgePoints`` is a complete corrected result intended to
    replace the chapter's previous extraction wholesale. Ids keep the
    deterministic ``ch-{slug}-`` prefix.
    """
    id_prefix = f"ch-{chapter.slug}-"
    messages = build_targeted_reextract_messages(
        language, source_language, chapter, kp, issues, max_chars=max_chapter_chars
    )
    return _run_extraction_loop(
        config,
        messages,
        id_prefix,
        temperature=temperature,
        timeout=timeout,
        cancel_check=cancel_check,
        on_chunk=on_chunk,
        usage_callback=usage_callback,
        max_retries=max_retries,
        max_tokens=max_tokens,
    )
