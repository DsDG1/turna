"""AI course generator backend (OpenAI-compatible) for the GUI editor.

Pure-Python, no third-party dependencies for the network call — uses
``urllib.request`` so the GUI does not need to add a new dependency to its
PySide6-only lock file.

The API key / base URL / model are held in memory by the dialog and are NEVER
persisted to disk (per product requirement: lost on app exit).

Wish mode adds multi-turn chat plus optional file attachments. The chat flow
has two phases:
1. Alignment: the AI explains course design in plain language, no JSON.
2. Generation: the AI returns the final section JSON.

Beta note: the improved prompts can be very long and are intended for models
that support ~1M token context windows.
"""
from __future__ import annotations

import json
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass, field, replace
from datetime import datetime
from typing import Any, Callable

class AiCancelled(Exception):
    """Raised when an in-flight AI request is cancelled by the user."""

from src.backend.ai_genre import (
    genre_prompt_block,
    genre_tags_in_text,
    genre_to_template,
    template_label,
)


@dataclass
class AiApiConfig:
    base_url: str = "https://api.deepseek.com"
    api_key: str = ""
    model: str = "deepseek-v4-pro"
    # Whether the endpoint accepts ``reasoning_effort`` / ``thinking``. ``None``
    # (the default) infers this from the host via ``is_deepseek`` — DeepSeek's
    # documented behavior — so the common case needs no extra config. Set
    # explicitly to override: a reasoning-capable endpoint on a non-DeepSeek
    # host, or to suppress reasoning for a DeepSeek-host endpoint that
    # shouldn't use it. Mirrors the Dart ``AiApiConfig.supports_reasoning``.
    supports_reasoning: bool | None = None

    @property
    def is_complete(self) -> bool:
        return all(
            v.strip() for v in (self.base_url, self.api_key, self.model)
        )

    @property
    def chat_completions_url(self) -> str:
        b = self.base_url.strip().rstrip("/")
        if b.endswith("/chat/completions"):
            return b
        return f"{b}/chat/completions"

    @property
    def is_deepseek(self) -> bool:
        """True when the endpoint host points at DeepSeek.

        DeepSeek's ``/chat/completions`` endpoint accepts the
        ``reasoning_effort`` / ``thinking`` payload fields (returned reasoning
        lives in a separate ``reasoning_content`` field and never leaks into
        ``message.content``); other OpenAI-compatible endpoints (OpenAI,
        Ollama, Moonshot) reject or error on unknown fields. This is the single
        host-detection predicate for the Python side and mirrors the Dart
        ``is_deep_seek_host`` so the two clients agree on when the reasoning
        controls are safe to send by default.
        """
        host = urllib.parse.urlparse(self.base_url).hostname or ""
        return host == "api.deepseek.com" or host.endswith(".deepseek.com")

    @property
    def reasoning_enabled(self) -> bool:
        """Whether to send the reasoning payload fields.

        Falls back to [is_deepseek] when [supports_reasoning] is ``None``.
        """
        if self.supports_reasoning is not None:
            return self.supports_reasoning
        return self.is_deepseek


@dataclass
class AiCourseSpec:
    language: str = "Turkish"          # Target language being taught
    source_language: str = "Chinese"   # Language used for prompts/hints
    topic: str = ""
    level: str = "A1"
    unit_count: int = 1
    lessons_per_unit: int = 3
    template: str = "mixed"              # Lesson template applied when not using genre batch
    use_genre_batch: bool = False        # Enable [genre] tag batch multi-template generation
    extra_instructions: str = ""


@dataclass
class ChatMessage:
    """A single message in the wish-mode conversation."""

    role: str = "user"
    content: str | list[dict[str, Any]] = field(default_factory=str)
    timestamp: str = field(default_factory=lambda: datetime.now().strftime("%H:%M"))

    def to_api_dict(self) -> dict[str, Any]:
        return {"role": self.role, "content": self.content}


def _template_schema_block() -> str:
    """Return a prompt block describing allowed templates and their shapes."""
    return """课程结构层级：section → units → lessons → content。

可用课模板（template）及对应的 content 主键：
- intro: 认识新词。content 主键为 subLessons。每个 subLesson 含 stages，每个 stage 含 items。
- practice: 巩固练习。content 主键为 subLessons。
- review: 复习。content 主键为 subLessons，可额外包含 stages。
- listening: 听力训练。content 主键为 listeningPhases。每个 phase 可含 items（wordPairing/dialogue）或只听不答（summary）。
- reading: 阅读理解。content 包含 readingPassage（title + paragraphs）和 stages（理解题）。
- mastery: 综合测验。content 主键为 stages，一个 stage 即可。
- mixed: 混合。可在不同单元/课时中使用不同模板。

常用题型（runtimeType）说明：
- showWord: { wordId, context? } — 展示生词。wordId 必须在顶层 words 数组中定义。
- multipleChoice: { prompt, options(4), correctIndex } — 单选题。
- multiSelect: { prompt, options, correctIndices, minSelections?, maxSelections? } — 多选题。
- fillBlank: { sentence（含 ____ 空白）, answer, hint? } — 填空。
- translateSentence: { source（源语言句子）, expected（目标语言翻译）, hints? } — 翻译。
- listenAndPick: { audioAsset, prompt, options(4), correctIndex } — 听音选择。
- typeTheWord: { audioAsset, prompt, expected } — 听写。
- listenOnly: { audioAsset?, transcript?, prompt? } — 只听不答。
- reorderSentence: { scrambled（打乱词数组）, correct（正确词数组） } — 排序。
- readingMcq: { prompt, options(4), correctIndex } — 阅读选择。
- readingTrueFalse: { statement, answer(true/false) } — 阅读判断。
- readingShortAnswer: { prompt, expectedAnswer } — 阅读简答。

模板与题型对应建议：
- intro: showWord + translateSentence + fillBlank
- practice: multipleChoice + fillBlank + translateSentence + reorderSentence
- listening: listenAndPick + typeTheWord + listenOnly（phase 结构）
- reading: readingPassage + readingMcq + readingTrueFalse + readingShortAnswer
- mastery: multipleChoice + multiSelect + translateSentence + fillBlank
"""


def _resource_schema_block() -> str:
    """Describe the top-level resource arrays the AI must output alongside units.

    The course stores vocabulary / expressions / grammar points in separate
    resource files (vocab.json, expressions.json, grammar_points.json), not
    inside the section. A showWord item only stores a ``wordId`` foreign key,
    so the word must already exist. To keep AI-generated sections self-
    contained, the AI is required to emit the resources it uses as top-level
    arrays; the importer merges them into the course resource files.
    """
    return """顶层资源数组（与 units 同级，必须输出）：

words: 本课程用到的所有生词。每个条目结构：
{
  "id": "w-merhaba",            // 全局唯一，小写 kebab-case，建议前缀 w-
  "term": "Merhaba",            // 目标语言原文（如土耳其语单词）
  "translation": "你好",         // 源语言译文（如中文）
  "pronunciation": null,        // 可选，音标或拉丁转写；没有就填 null
  "audioAsset": null,           // 可选，音频资源路径；没有就填 null
  "tags": ["greeting"]          // 可选标签数组
}

expressions: 本课程用到的所有惯用表达。每个条目结构：
{
  "id": "e-ben-adim",           // 全局唯一，建议前缀 e-
  "term": "Adım ...",            // 目标语言原文
  "translation": "我叫……",       // 源语言译文
  "pronunciation": null,
  "audioAsset": null,
  "tags": []
}

grammarPoints: 本课程用到的所有语法点。每个条目结构：
{
  "id": "g-suffix-dan",         // 全局唯一，建议前缀 g-
  "title": "来源格 -dan",
  "explanation": "表示“从……”，加在名词后。",
  "exampleExpressionIds": [],   // 引用 expressions 中的 id
  "exampleSentenceIds": [],
  "practiceItems": []
}

自洽规则（最重要）：
1. 任何 showWord 的 wordId 必须出现在顶层 words 数组的某个条目 id 中。
2. 任何 expressionId 必须出现在顶层 expressions 数组的某个条目 id 中。
3. 任何 grammarPointId 必须出现在顶层 grammarPoints 数组的某个条目 id 中。
4. 只输出本课程真正用到的资源，不要输出未被引用的条目。
5. 资源 id 不能与现有词库冲突（导入时会自动跳过已存在的 id，但建议用 ai- / w-ai- 等前缀避免碰撞）。
"""


def _id_rules_block() -> str:
    return """ID 规则：
1. 所有 id 必须全局唯一，包括 section id、unit id、lesson id、stage id、subLesson id、item id。
2. 使用小写 kebab-case，前缀建议为 "ai-"，例如 ai-travel-u1-l1、ai-travel-u1-l1-st1。
3. 不要包含空格或特殊字符。
"""


def _build_json_schema_example(spec: AiCourseSpec) -> str:
    """Return a JSON schema example adapted to the requested template."""
    template = spec.template
    if template == "listening":
        content_example = '''"content": {
  "listeningPhases": [
    {
      "id": "ai-topic-u1-l1-lp1",
      "name": "Phase 1",
      "type": "wordPairing",
      "items": [
        { "runtimeType": "listenAndPick", "id": "...", "audioAsset": "", "prompt": "...", "options": ["...", "...", "...", "..."], "correctIndex": 0 }
      ]
    }
  ]
}'''
    elif template == "reading":
        content_example = '''"content": {
  "readingPassage": {
    "title": "...",
    "paragraphs": ["..."],
    "difficulty": 1,
    "linkedWordIds": [],
    "linkedExpressionIds": []
  },
  "stages": [
    {
      "id": "ai-topic-u1-l1-st1",
      "name": "Reading check",
      "items": [
        { "runtimeType": "readingMcq", "id": "...", "prompt": "...", "options": ["...", "...", "...", "..."], "correctIndex": 0 }
      ]
    }
  ]
}'''
    elif template == "mastery":
        content_example = '''"content": {
  "stages": [
    {
      "id": "ai-topic-u1-l1-st1",
      "name": "Quiz",
      "items": [
        { "runtimeType": "multipleChoice", "id": "...", "prompt": "...", "options": ["...", "...", "...", "..."], "correctIndex": 0 }
      ]
    }
  ]
}'''
    else:
        # intro / practice / review / mixed default to subLessons
        content_example = '''"content": {
  "subLessons": [
    {
      "id": "ai-topic-u1-l1-sl1",
      "name": "New words",
      "stages": [
        {
          "id": "ai-topic-u1-l1-sl1-st1",
          "name": "Learn & produce",
          "items": [
            { "runtimeType": "showWord", "id": "...", "wordId": "...", "context": "..." },
            { "runtimeType": "translateSentence", "id": "...", "source": "...", "expected": "...", "hints": ["..."] },
            { "runtimeType": "fillBlank", "id": "...", "sentence": "_____, ...", "answer": "...", "hint": "..." }
          ]
        }
      ]
    }
  ]
}'''
    return f"""返回 JSON 形状示例（顶层 section）：
{{
  "id": "ai-topic",
  "name": "...",
  "description": "...",
  "prerequisiteSectionIds": [],
  "words": [
    {{ "id": "w-merhaba", "term": "Merhaba", "translation": "你好", "pronunciation": null, "audioAsset": null, "tags": ["greeting"] }}
  ],
  "expressions": [
    {{ "id": "e-ben-adim", "term": "Adım ...", "translation": "我叫……", "pronunciation": null, "audioAsset": null, "tags": [] }}
  ],
  "grammarPoints": [],
  "units": [
    {{
      "id": "ai-topic-u1",
      "name": "...",
      "description": "",
      "prerequisiteUnitIds": [],
      "lessons": [
        {{
          "id": "ai-topic-u1-l1",
          "name": "...",
          "description": "",
          "type": "normal",
          "template": "{template}",
          "prerequisiteLessonIds": [],
          {content_example}
        }}
      ]
    }}
  ]
}}

Rules:
1. Every lesson MUST have at least one stage/phase with at least 3 items when the template supports items.
2. Multiple choice items: exactly 4 options, correctIndex in 0..3.
3. translateSentence: source in {spec.source_language}, expected in {spec.language}.
4. fillBlank: sentence in {spec.language} with a single ____ blank; answer is the missing word.
5. Every showWord.wordId / expressionId / grammarPointId MUST reference an id defined in the top-level words / expressions / grammarPoints arrays. Do NOT invent ids that are not defined there.
6. Output JSON object only — no surrounding text, no markdown fences.
"""


def build_prompt(spec: AiCourseSpec) -> str:
    """Build the generation prompt for the AI model."""
    parts = [
        f"Generate a language learning course section as JSON.",
        "",
        f"Target language: {spec.language}",
        f"Prompt/source language: {spec.source_language}",
        f"Topic / theme: {spec.topic}",
        f"Learner level: {spec.level}",
        f"Units: {spec.unit_count}, each with {spec.lessons_per_unit} lessons.",
    ]

    if spec.use_genre_batch:
        parts.extend([
            "",
            f"Default fallback template: {spec.template} ({template_label(spec.template)})",
            "",
            genre_prompt_block(),
            "",
            "You are in multi-template batch mode. When a genre tag like [intro] or [listening] appears "
            "in the topic or extra instructions, generate the corresponding lesson(s) using that template. "
            "Lessons without a tag should use the default fallback template.",
        ])
    else:
        parts.extend([
            "",
            f"Template for all lessons: {spec.template} ({template_label(spec.template)})",
            "All lessons in this section MUST use this template uniformly.",
        ])

    if spec.extra_instructions:
        parts.extend(["", f"Extra instructions: {spec.extra_instructions}"])

    parts.extend([
        "",
        "Return STRICT JSON only (no markdown, no code fences).",
        "",
        _template_schema_block(),
        "",
        _resource_schema_block(),
        "",
        _id_rules_block(),
        "",
        _build_json_schema_example(spec),
    ])
    return "\n".join(parts)


def build_alignment_prompt(spec: AiCourseSpec) -> str:
    """Build the alignment-phase prompt for wish mode."""
    parts = [
        "You are a language-course design assistant helping a non-technical beginner teacher.",
        "",
        f"The teacher wants to create a {spec.language} course section at level {spec.level}.",
        f"Source / prompt language: {spec.source_language}.",
        f"Topic: {spec.topic or '(not specified yet — ask the teacher)'}.",
        f"Target structure: {spec.unit_count} units, each with {spec.lessons_per_unit} lessons.",
    ]

    if spec.use_genre_batch:
        parts.extend([
            "",
            "Multi-template batch mode is enabled. The teacher can insert genre tags like [intro], [practice], "
            "[listening], [reading], [mastery] to request different templates for different lessons.",
            genre_prompt_block(),
        ])
    else:
        parts.extend([
            "",
            f"All lessons will use the '{spec.template}' template ({template_label(spec.template)}).",
        ])

    if spec.extra_instructions:
        parts.extend(["", f"Extra notes: {spec.extra_instructions}"])

    parts.extend([
        "",
        "Your job is to ALIGN with the teacher through conversation. Follow these rules:",
        "1. Use friendly, plain Chinese. No jargon, no JSON, no code, no markdown fences.",
        "2. In each reply, briefly summarize what you understand, then give 2-3 concrete suggestions or clarifying questions.",
        "3. If the teacher uploads files, incorporate them into your suggestions naturally.",
        "4. When suggesting vocabulary or expressions, also tell the teacher that these will be added to the course's vocabulary list automatically — they don't need to prepare a separate word bank.",
        "5. Do NOT output the final course JSON. The teacher will click \"我感觉差不多了\" when ready.",
        "6. If the teacher asks to change the course, acknowledge the change and explain how it affects the design.",
    ])
    return "\n".join(parts)


def _strip_code_fences(text: str) -> str:
    s = text.strip()
    if s.startswith("```"):
        nl = s.find("\n")
        if nl >= 0:
            s = s[nl + 1 :]
        if s.endswith("```"):
            s = s[: -3]
    return s.strip()


def _normalize_resources(parsed: dict[str, Any]) -> None:
    """Ensure words/expressions/grammarPoints are lists (default empty)."""
    for key in ("words", "expressions", "grammarPoints"):
        val = parsed.get(key)
        if val is None:
            parsed[key] = []
        elif not isinstance(val, list):
            raise ValueError(f"顶层 '{key}' 必须是数组。")


def _iter_items(lesson: dict[str, Any]):
    """Yield every interaction item dict inside a lesson's content."""
    content = lesson.get("content") or {}
    stages = content.get("stages") or []
    for stage in stages:
        for item in stage.get("items") or []:
            if isinstance(item, dict):
                yield item
    for sub in content.get("subLessons") or []:
        for stage in sub.get("stages") or []:
            for item in stage.get("items") or []:
                if isinstance(item, dict):
                    yield item
    for phase in content.get("listeningPhases") or []:
        for item in phase.get("items") or []:
            if isinstance(item, dict):
                yield item


def _slugify_for_stub(text: str) -> str:
    """Best-effort slug from arbitrary text for synthesizing resource ids."""
    import re

    s = re.sub(r"[^a-zA-Z0-9]+", "-", text or "").strip("-").lower()
    return s or "stub"


def _auto_fix_resources(parsed: dict[str, Any]) -> None:
    """Auto-fix dangling resource references by adding stub entries.

    When the AI model forgets to define a word/expression/grammar point in
    the top-level arrays while still referencing it from a lesson item, this
    function synthesizes a minimal stub entry so the section can be imported.
    The stub is populated best-effort from nearby item fields (context,
    expected, source, prompt); the author can refine it later in the editor.
    """
    words = parsed.setdefault("words", [])
    expressions = parsed.setdefault("expressions", [])
    grammar_points = parsed.setdefault("grammarPoints", [])

    word_ids = {w.get("id") for w in words if isinstance(w, dict)}
    expr_ids = {e.get("id") for e in expressions if isinstance(e, dict)}
    grammar_ids = {g.get("id") for g in grammar_points if isinstance(g, dict)}

    for unit in parsed.get("units") or []:
        if not isinstance(unit, dict):
            continue
        for lesson in unit.get("lessons") or []:
            if not isinstance(lesson, dict):
                continue
            for item in _iter_items(lesson):
                rt = item.get("runtimeType")
                if rt == "showWord":
                    wid = item.get("wordId")
                    if wid and wid not in word_ids:
                        context = item.get("context") or ""
                        term = ""
                        translation = ""
                        if context:
                            parts = context.split("—", 1)
                            if len(parts) == 2:
                                term = parts[0].strip()
                                translation = parts[1].strip()
                            else:
                                term = context.strip()
                        words.append(
                            {
                                "id": wid,
                                "term": term or wid,
                                "translation": translation,
                                "pronunciation": None,
                                "audioAsset": None,
                                "tags": ["auto-fix"],
                            }
                        )
                        word_ids.add(wid)
                eid = item.get("expressionId")
                if eid and eid not in expr_ids:
                    prompt = item.get("prompt") or item.get("source") or ""
                    expected = item.get("expected") or item.get("expectedAnswer") or ""
                    expressions.append(
                        {
                            "id": eid,
                            "term": expected or eid,
                            "translation": prompt,
                            "pronunciation": None,
                            "audioAsset": None,
                            "tags": ["auto-fix"],
                        }
                    )
                    expr_ids.add(eid)
                gid = item.get("grammarPointId")
                if gid and gid not in grammar_ids:
                    grammar_points.append(
                        {
                            "id": gid,
                            "title": gid,
                            "explanation": "",
                            "exampleExpressionIds": [],
                            "exampleSentenceIds": [],
                            "practiceItems": [],
                        }
                    )
                    grammar_ids.add(gid)


def _check_resource_self_consistency(parsed: dict[str, Any]) -> None:
    """Verify every wordId/expressionId/grammarPointId is defined in the
    top-level resource arrays. Raises ValueError listing all dangling refs.
    """
    word_ids = {w.get("id") for w in parsed.get("words") or [] if isinstance(w, dict)}
    expr_ids = {e.get("id") for e in parsed.get("expressions") or [] if isinstance(e, dict)}
    grammar_ids = {
        g.get("id") for g in parsed.get("grammarPoints") or [] if isinstance(g, dict)
    }

    missing: list[str] = []
    for unit in parsed.get("units") or []:
        if not isinstance(unit, dict):
            continue
        for lesson in unit.get("lessons") or []:
            if not isinstance(lesson, dict):
                continue
            for item in _iter_items(lesson):
                lid = lesson.get("id", "?")
                rt = item.get("runtimeType")
                if rt == "showWord":
                    wid = item.get("wordId")
                    if wid and wid not in word_ids:
                        missing.append(f"lesson {lid}: showWord 引用了未定义的 wordId「{wid}」")
                eid = item.get("expressionId")
                if eid and eid not in expr_ids:
                    missing.append(f"lesson {lid}: 引用了未定义的 expressionId「{eid}」")
                gid = item.get("grammarPointId")
                if gid and gid not in grammar_ids:
                    missing.append(f"lesson {lid}: 引用了未定义的 grammarPointId「{gid}」")
    if missing:
        raise ValueError(
            "资源自洽校验失败（引用的资源 id 未在顶层 words/expressions/grammarPoints 中定义）:\n"
            + "\n".join(missing[:20])
        )


def parse_completion(body: str | dict[str, Any]) -> dict:
    """Parse an OpenAI-compatible chat completion response body.

    Accepts either the raw response string or an already-parsed dict.
    Returns the decoded course JSON dict. Raises ``ValueError`` on malformed
    output so the dialog can surface a human-readable message.
    """
    if isinstance(body, dict):
        decoded = body
    else:
        try:
            decoded = json.loads(body)
        except json.JSONDecodeError as exc:
            raise ValueError(f"无法解析 API 响应 JSON: {exc}") from exc
    choices = decoded.get("choices") or []
    if not choices:
        raise ValueError("API 返回的 choices 为空。")
    message = choices[0].get("message") or {}
    content = message.get("content") or ""
    cleaned = _strip_code_fences(content)
    try:
        parsed = json.loads(cleaned)
    except json.JSONDecodeError as exc:
        raise ValueError(
            f"无法解析模型输出的 JSON: {exc}\n原始内容前 200 字: {cleaned[:200]}"
        ) from exc
    if not isinstance(parsed, dict) or "units" not in parsed:
        raise ValueError("模型输出缺少顶层 'units' 数组。")
    _normalize_resources(parsed)
    _auto_fix_resources(parsed)
    _check_resource_self_consistency(parsed)
    return parsed


def _content_text(content: str | list[dict[str, Any]] | None) -> str:
    """Best-effort extract plain text from a message content for preview."""
    if content is None:
        return ""
    if isinstance(content, str):
        return content
    parts: list[str] = []
    for piece in content:
        if isinstance(piece, dict):
            if piece.get("type") == "text":
                parts.append(str(piece.get("text", "")))
            elif piece.get("type") == "image_url":
                parts.append("[图片]")
    return "\n".join(parts)


def request_chat(
    config: AiApiConfig,
    messages: list[dict[str, Any]],
    temperature: float = 0.7,
    response_format: dict[str, str] | None = None,
    timeout: float = 120.0,
    cancel_check: Callable[[], bool] | None = None,
) -> dict:
    """Call the OpenAI-compatible endpoint and return the parsed JSON body.

    Raises ``RuntimeError`` with a human-readable message on network / HTTP /
    parse errors. If ``cancel_check`` is supplied and returns True while the
    response body is being read, raises ``AiCancelled``.
    """
    if not config.is_complete:
        raise RuntimeError("API 配置不完整，请填写 Base URL / API Key / Model。")

    payload_obj: dict[str, Any] = {
        "model": config.model,
        "messages": messages,
        "temperature": temperature,
    }
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
    payload = json.dumps(payload_obj).encode("utf-8")

    req = urllib.request.Request(
        config.chat_completions_url,
        data=payload,
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {config.api_key}",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:  # noqa: S310
            if cancel_check is None:
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
        raise RuntimeError(f"HTTP {exc.code}: {detail}") from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(f"网络错误: {exc.reason}") from exc

    try:
        return json.loads(body)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"无法解析 API 响应: {exc}") from exc


def request_course(config: AiApiConfig, spec: AiCourseSpec, timeout: float = 120.0, cancel_check: Callable[[], bool] | None = None) -> dict:
    """Single-shot course generation (legacy normal mode)."""
    messages = [
        {
            "role": "system",
            "content": (
                "You are a language-course authoring assistant. "
                "You output ONLY valid JSON, no prose, no markdown fences."
            ),
        },
        {"role": "user", "content": build_prompt(spec)},
    ]
    body = request_chat(
        config,
        messages,
        temperature=0.4,
        response_format={"type": "json_object"},
        timeout=timeout,
        cancel_check=cancel_check,
    )
    return parse_completion(body)


def request_course_with_retry(
    config: AiApiConfig,
    spec: AiCourseSpec,
    validator,
    timeout: float = 120.0,
    max_retries: int = 1,
    cancel_check: Callable[[], bool] | None = None,
) -> dict:
    """Generate a course and, if ``validator(section_json)`` returns error
    strings, re-prompt the model with those errors once (C3).

    ``validator`` is a callable ``(section_json: dict) -> list[str]`` returning
    a list of human-readable error strings (empty == valid). The original
    generation is retried at most ``max_retries`` times by appending an
    assistant turn + a correction turn to the conversation.
    """
    messages = [
        {
            "role": "system",
            "content": (
                "You are a language-course authoring assistant. "
                "You output ONLY valid JSON, no prose, no markdown fences."
            )
        },
        {"role": "user", "content": build_prompt(spec)},
    ]
    section = parse_completion(
        request_chat(
            config, messages, temperature=0.4,
            response_format={"type": "json_object"}, timeout=timeout,
            cancel_check=cancel_check,
        )
    )
    for _ in range(max(0, max_retries)):
        errors = list(validator(section) or [])
        if not errors:
            break
        correction = (
            "上一版有以下校验错误，请修正后只输出完整的修正 JSON：\n- "
            + "\n- ".join(errors)
        )
        assistant_turn = {"role": "assistant", "content": json.dumps(section, ensure_ascii=False)}
        messages.append(assistant_turn)
        messages.append({"role": "user", "content": correction})
        section = parse_completion(
            request_chat(
                config, messages, temperature=0.2,
                response_format={"type": "json_object"}, timeout=timeout,
                cancel_check=cancel_check,
            )
        )
    return section


def request_alignment_reply(
    config: AiApiConfig,
    spec: AiCourseSpec,
    messages: list[ChatMessage],
    timeout: float = 120.0,
    cancel_check: Callable[[], bool] | None = None,
) -> str:
    """Get a plain-language alignment reply from the AI.

    ``messages`` must not include the system prompt; it will be prepended.
    """
    api_messages = [
        {"role": "system", "content": build_alignment_prompt(spec)}
    ] + [m.to_api_dict() for m in messages]
    body = request_chat(
        config,
        api_messages,
        temperature=0.7,
        timeout=timeout,
        cancel_check=cancel_check,
    )
    choices = body.get("choices") or []
    if not choices:
        raise ValueError("API 返回的 choices 为空。")
    content = choices[0].get("message", {}).get("content", "")
    return content.strip()


def generate_from_chat(
    config: AiApiConfig,
    spec: AiCourseSpec,
    messages: list[ChatMessage],
    draft_json: dict[str, Any] | None = None,
    timeout: float = 180.0,
    cancel_check: Callable[[], bool] | None = None,
) -> dict:
    """Generate the final course section JSON from the conversation history.

    If ``draft_json`` is provided, it is included as context so the model can
    produce a modified version of the course.
    """
    generation_prompt = build_prompt(spec)
    if draft_json is not None:
        generation_prompt += (
            "\n\n以下是目前已生成的课程草稿，请根据对话中的修改意见进行调整，"
            "返回完整的新的课程 JSON（不要只返回 diff）。\n\n"
            f"```json\n{json.dumps(draft_json, ensure_ascii=False, indent=2)}\n```"
        )

    api_messages = [
        {
            "role": "system",
            "content": (
                "You are a language-course authoring assistant. "
                "You output ONLY valid JSON, no prose, no markdown fences. "
                "The conversation history below captures the teacher's requirements. "
                "Generate the final course JSON based on those requirements."
            ),
        }
    ] + [m.to_api_dict() for m in messages]
    api_messages.append({"role": "user", "content": generation_prompt})

    body = request_chat(
        config,
        api_messages,
        temperature=0.4,
        response_format={"type": "json_object"},
        timeout=timeout,
        cancel_check=cancel_check,
    )
    return parse_completion(body)


def explain_course(
    config: AiApiConfig,
    spec: AiCourseSpec,
    section_json: dict[str, Any],
    timeout: float = 120.0,
    cancel_check: Callable[[], bool] | None = None,
) -> str:
    """Ask the AI to explain the generated course in plain language."""
    prompt = (
        "你刚刚为一位没有技术背景的教师生成了以下课程。"
        "请用通俗易懂的中文简要解释这门课的教学目标、单元划分、重点词汇/句型，"
        "以及为什么这样设计。不要输出 JSON 或代码。\n\n"
        f"课程语言：{spec.language}\n"
        f"提示语言：{spec.source_language}\n"
        f"等级：{spec.level}\n"
        f"课程名称：{section_json.get('name', '')}\n"
        f"课程描述：{section_json.get('description', '')}\n"
    )
    api_messages = [
        {"role": "system", "content": "你是语言课程设计助手，用中文通俗解释课程内容。"},
        {"role": "user", "content": prompt},
    ]
    body = request_chat(
        config,
        api_messages,
        temperature=0.6,
        timeout=timeout,
        cancel_check=cancel_check,
    )
    choices = body.get("choices") or []
    if not choices:
        return "（AI 未返回解释）"
    return choices[0].get("message", {}).get("content", "").strip()


def detect_genre_from_spec(spec: AiCourseSpec) -> str | None:
    """Detect the first explicit genre tag in the spec's topic or extra instructions."""
    combined = f"{spec.topic} {spec.extra_instructions}"
    tags = genre_tags_in_text(combined)
    return tags[0] if tags else None


def apply_genre_to_spec(spec: AiCourseSpec) -> AiCourseSpec:
    """If a genre tag is present and batch mode is on, update the spec template.

    Returns a new spec (via :func:`dataclasses.replace`) rather than mutating
    the input in place, mirroring the Dart side
    (``AiCourseService.applyGenreToSpec`` which uses ``copyWith``). Callers
    reuse ``AiCourseSpec`` objects across calls, so an in-place mutation would
    leak the genre template into a later call with a different tag.
    """
    if not spec.use_genre_batch:
        return spec
    tag = detect_genre_from_spec(spec)
    if tag:
        return replace(spec, template=genre_to_template(tag))
    return spec


# --- Edit mode: revise an existing section --------------------------------


def _existing_context_block(existing_section: dict[str, Any]) -> str:
    """Render a compact summary of the existing section for the AI.

    Lists units, lessons (with ids + names), and the top-level vocab /
    expressions so the AI can reuse existing ids and avoid collisions.
    """
    lines: list[str] = []
    lines.append("现有 section 概览：")
    lines.append(f"  section id: {existing_section.get('id', '')}")
    lines.append(f"  section name: {existing_section.get('name', '')}")
    units = existing_section.get("units") or []
    for u in units:
        if not isinstance(u, dict):
            continue
        lines.append(f"  - unit id={u.get('id', '')} name={u.get('name', '')}")
        for l in u.get("lessons") or []:
            if isinstance(l, dict):
                lines.append(
                    f"      • lesson id={l.get('id', '')} "
                    f"name={l.get('name', '')} template={l.get('template', '')}"
                )
    words = existing_section.get("words") or []
    if words:
        lines.append("  现有 words（id | term | translation）：")
        for w in words[:80]:
            if isinstance(w, dict):
                lines.append(
                    f"    {w.get('id', '')} | {w.get('term', '')} | {w.get('translation', '')}"
                )
        if len(words) > 80:
            lines.append(f"    …(共 {len(words)} 个，已省略)")
    exprs = existing_section.get("expressions") or []
    if exprs:
        lines.append("  现有 expressions（id | term | translation）：")
        for e in exprs[:40]:
            if isinstance(e, dict):
                lines.append(
                    f"    {e.get('id', '')} | {e.get('term', '')} | {e.get('translation', '')}"
                )
    return "\n".join(lines)


def build_edit_prompt(
    spec: AiCourseSpec,
    existing_section: dict[str, Any],
    edit_scope: str,
    scope_id: str,
) -> str:
    """Build a prompt that asks the AI to edit an existing section in place.

    ``edit_scope`` is one of "section" / "unit" / "lesson" and ``scope_id``
    is the id of the unit or lesson to focus on (ignored for section scope).
    The AI must return the FULL section JSON (with unchanged parts preserved).
    """
    base = build_prompt(spec)
    scope_hint = {
        "section": "本次为 section 级编辑：可在该 section 范围内任意修改/新增/删除 unit 与 lesson。",
        "unit": f"本次为 unit 级编辑：请只修改 unit「{scope_id}」内的 lessons（可新增/编辑/删除 lesson），"
        "其余 unit 与 lesson 保持不变。",
        "lesson": f"本次为 lesson 级编辑：请只修改 lesson「{scope_id}」的 content/题目，"
        "其余结构保持不变。",
    }.get(edit_scope, "section 级编辑。")

    existing_json = json.dumps(existing_section, ensure_ascii=False, indent=2)
    parts = [
        base,
        "",
        "==== 编辑模式指令 ====",
        scope_hint,
        "",
        _existing_context_block(existing_section),
        "",
        "下面是该 section 的完整当前 JSON。请在其基础上编辑，保留未改动部分，"
        "并返回完整的新的 section JSON（顶层必须仍是 section 对象，id 必须保持为 "
        f"{existing_section.get('id', '')}）。",
        "复用现有 id 以保持引用稳定；新增的 id 用 ai- 前缀并避免与现有 id 冲突。",
        "",
        "```json",
        existing_json,
        "```",
    ]
    return "\n".join(parts)


def generate_edit(
    config: AiApiConfig,
    spec: AiCourseSpec,
    existing_section: dict[str, Any],
    edit_scope: str,
    scope_id: str,
    messages: list[ChatMessage] | None = None,
    draft_json: dict[str, Any] | None = None,
    timeout: float = 180.0,
    cancel_check: Callable[[], bool] | None = None,
) -> dict:
    """Generate an edited section JSON based on an existing section.

    In normal mode ``messages`` is None and the edit prompt is the sole user
    turn. In wish mode the conversation history is prepended and the edit
    prompt is appended as the final user turn (so the model incorporates the
    teacher's latest instructions).
    """
    edit_prompt = build_edit_prompt(spec, existing_section, edit_scope, scope_id)
    if draft_json is not None:
        edit_prompt += (
            "\n\n以下是目前已生成的课程草稿，请根据对话中的修改意见进行调整，"
            "返回完整的新的课程 JSON（不要只返回 diff）。\n\n"
            f"```json\n{json.dumps(draft_json, ensure_ascii=False, indent=2)}\n```"
        )

    api_messages: list[dict[str, Any]] = [
        {
            "role": "system",
            "content": (
                "You are a language-course authoring assistant. "
                "You output ONLY valid JSON, no prose, no markdown fences. "
                "You are editing an EXISTING course section; preserve unchanged "
                "structure and reuse existing ids where possible."
            ),
        }
    ]
    if messages:
        api_messages += [m.to_api_dict() for m in messages]
    api_messages.append({"role": "user", "content": edit_prompt})

    body = request_chat(
        config,
        api_messages,
        temperature=0.4,
        response_format={"type": "json_object"},
        timeout=timeout,
        cancel_check=cancel_check,
    )
    parsed = parse_completion(body)
    # In edit mode the returned section must keep the same id.
    existing_id = existing_section.get("id", "")
    if existing_id and parsed.get("id") != existing_id:
        parsed["id"] = existing_id
    return parsed
