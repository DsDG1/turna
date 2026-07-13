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
import urllib.request
from dataclasses import dataclass, field
from typing import Any

from src.backend.ai_genre import (
    genre_prompt_block,
    genre_tags_in_text,
    genre_to_template,
    template_label,
)


@dataclass
class AiApiConfig:
    base_url: str = "https://api.openai.com/v1"
    api_key: str = ""
    model: str = "gpt-4o-mini"

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
- showWord: { wordId, context? } — 展示生词。
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
5. Output JSON object only — no surrounding text, no markdown fences.
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
        "4. Do NOT output the final course JSON. The teacher will click \"我感觉差不多了\" when ready.",
        "5. If the teacher asks to change the course, acknowledge the change and explain how it affects the design.",
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
) -> dict:
    """Call the OpenAI-compatible endpoint and return the parsed JSON body.

    Raises ``RuntimeError`` with a human-readable message on network / HTTP /
    parse errors.
    """
    if not config.is_complete:
        raise RuntimeError("API 配置不完整，请填写 Base URL / API Key / Model。")

    payload_obj: dict[str, Any] = {
        "model": config.model,
        "messages": messages,
        "temperature": temperature,
    }
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
            body = resp.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")[:300]
        raise RuntimeError(f"HTTP {exc.code}: {detail}") from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(f"网络错误: {exc.reason}") from exc

    try:
        return json.loads(body)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"无法解析 API 响应: {exc}") from exc


def request_course(config: AiApiConfig, spec: AiCourseSpec, timeout: float = 120.0) -> dict:
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
    )
    return parse_completion(body)


def request_alignment_reply(
    config: AiApiConfig,
    spec: AiCourseSpec,
    messages: list[ChatMessage],
    timeout: float = 120.0,
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
    )
    return parse_completion(body)


def explain_course(
    config: AiApiConfig,
    spec: AiCourseSpec,
    section_json: dict[str, Any],
    timeout: float = 120.0,
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
    """If a genre tag is present and batch mode is on, update the spec template."""
    if not spec.use_genre_batch:
        return spec
    tag = detect_genre_from_spec(spec)
    if tag:
        spec.template = genre_to_template(tag)
    return spec
