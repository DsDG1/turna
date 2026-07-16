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
from src.backend import ai_stream, ai_usage


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


# --- Shared system prompts (P1-4) ------------------------------------------
# Single source for the three system prompts used by every request helper in
# this module. Text must stay byte-identical to the strings the Dart side
# mirrors (lib/application/ai/ai_course_service.dart).
SYSTEM_AUTHORING = (
    "You are a language-course authoring assistant. "
    "You output ONLY valid JSON, no prose, no markdown fences."
)
SYSTEM_EDITING = (
    "You are a language-course editing assistant. "
    "You output ONLY valid JSON, no prose, no markdown fences."
)
SYSTEM_CORRECTION = (
    "You are a course-data correction assistant. "
    "You output ONLY valid JSON, no prose, no markdown fences."
)
# Wish-mode chat → generation: history carries the requirements.
SYSTEM_AUTHORING_CHAT = (
    "You are a language-course authoring assistant. "
    "You output ONLY valid JSON, no prose, no markdown fences. "
    "The conversation history below captures the teacher's requirements. "
    "Generate the final course JSON based on those requirements."
)
# Section edit mode: preserve unchanged structure.
SYSTEM_AUTHORING_EDIT = (
    "You are a language-course authoring assistant. "
    "You output ONLY valid JSON, no prose, no markdown fences. "
    "You are editing an EXISTING course section; preserve unchanged "
    "structure and reuse existing ids where possible."
)


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
    # Existing course vocab/expressions/grammarPoints (already trimmed by the
    # caller). When set, build_prompt includes a reuse-these-ids context block
    # so the model stops re-creating duplicates (connectplan P0-5).
    course_resources: dict[str, list] | None = None
    # Grounded design (connectplan §3.4): the project's resource pool. When
    # non-empty, the model must pick words from the pool and copy them
    # verbatim into the top-level arrays — course design only, no invention.
    resource_pool: list[dict] | None = None
    # Free-form orchestration intent from the teacher (e.g. "前两章做
    # intro+listening，语法点单独一个 review 单元"); usually distilled from chat.
    design_brief: str = ""


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


def _course_context_block(spec: AiCourseSpec) -> str:
    """Render a compact summary of the course's existing resources (P0-5).

    Lets the model reuse existing word/expression/grammar ids instead of
    re-creating duplicates. The caller is expected to trim the lists
    (see ``AiGeneratorDialog._course_resource_summary``).
    """
    res = spec.course_resources or {}
    lines: list[str] = ["课程已有资源（id | 词条 | 释义）："]
    for key in ("words", "expressions", "grammarPoints"):
        entries = res.get(key) or []
        if not entries:
            continue
        lines.append(f"  {key}:")
        for e in entries:
            if not isinstance(e, dict):
                continue
            rid = e.get("id", "")
            term = e.get("term") or e.get("title") or ""
            trans = e.get("translation") or e.get("explanation") or ""
            lines.append(f"    {rid} | {term} | {trans}")
    lines.extend([
        "",
        "复用规则：优先引用上述已有词条的 id；不要在顶层 words/expressions/"
        "grammarPoints 中重复定义已存在的 id。确需新词时使用不与上述冲突的新 id"
        "（建议 ai- 前缀）。",
    ])
    return "\n".join(lines)


#: Character budget for the resource-pool prompt block (§3.4); overflow is
#: truncated in pool order with a note, mirroring ``max_chapter_chars``.
_POOL_CHAR_BUDGET = 6000


def _resource_pool_block(spec: AiCourseSpec) -> str:
    """Render the project's resource pool for grounded generation (§3.4).

    The model must design lessons around these entries: pick from the pool,
    copy chosen entries verbatim (same id/term/translation) into the top-level
    arrays, and invent nothing outside the pool except ``new``-tagged extras.
    """
    pool = [e for e in (spec.resource_pool or []) if isinstance(e, dict)]
    lines = ["资源池（本课必须使用的词条来源）："]
    budget = _POOL_CHAR_BUDGET
    shown = 0
    for e in pool:
        rid = e.get("id", "")
        if not rid:
            continue
        kind = e.get("_kind", "word")
        term = e.get("term") or e.get("title") or ""
        trans = e.get("translation") or e.get("explanation") or ""
        tags = e.get("tags") or []
        tag_text = f" [{','.join(str(t) for t in tags)}]" if tags else ""
        line = f"  {kind}: {rid} | {term} | {trans}{tag_text}"
        if budget - len(line) < 0 and shown:
            break
        lines.append(line)
        budget -= len(line)
        shown += 1
    if shown < len(pool):
        lines.append(f"  …(共 {len(pool)} 条，已按顺序截取前 {shown} 条)")
    lines.extend([
        "",
        "编排规则（grounded 模式）：",
        "1. 从资源池挑选本课所需词条，按原 id / term / translation 原样复制到顶层 "
        "words / expressions / grammarPoints 数组（pronunciation/audioAsset 可填 null）。",
        "2. 禁止修改资源池条目的 id 或内容；禁止编造与资源池无关的词条。",
        "3. 确需池外新词时，在顶层数组定义完整条目并打上 \"new\" tag。",
        "4. lesson 中的 wordId / expressionId / grammarPointId 必须引用顶层数组中已定义的 id。",
    ])
    return "\n".join(lines)


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
        tags = detect_genre_from_spec(spec)
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
        if len(tags) > 1:
            distribution = _distribute_genres_to_lessons(
                tags, spec.unit_count, spec.lessons_per_unit
            )
            parts.extend([
                "",
                "Genre tag distribution (apply per unit/lesson in order):",
            ])
            for u_idx, unit_templates in enumerate(distribution, start=1):
                unit_line = f"  Unit {u_idx}: " + ", ".join(
                    f"Lesson {l_idx}={tpl}"
                    for l_idx, tpl in enumerate(unit_templates, start=1)
                )
                parts.append(unit_line)
    else:
        parts.extend([
            "",
            f"Template for all lessons: {spec.template} ({template_label(spec.template)})",
            "All lessons in this section MUST use this template uniformly.",
        ])

    if spec.extra_instructions:
        parts.extend(["", f"Extra instructions: {spec.extra_instructions}"])

    if spec.design_brief:
        parts.extend(["", f"编排意图（老师的课程设计要求）: {spec.design_brief}"])

    grounded = bool(spec.resource_pool)
    if spec.course_resources:
        parts.extend(["", _course_context_block(spec)])
    if grounded:
        parts.extend(["", _resource_pool_block(spec)])

    parts.extend([
        "",
        "Return STRICT JSON only (no markdown, no code fences).",
        "",
        _template_schema_block(),
    ])
    if not grounded:
        # Grounded mode drops the full resource schema (~1/3 of the prompt):
        # entries are copied from the pool, whose listing shows their shape.
        parts.extend(["", _resource_schema_block()])
    parts.extend([
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
                        # Fall back to nearby item fields before giving up,
                        # and never emit an empty translation (B4): a dirty
                        # "[待补]" placeholder flagged needs-review is safer
                        # than an entry the learner sees as a blank.
                        if not term:
                            term = (
                                item.get("expected")
                                or item.get("source")
                                or item.get("prompt")
                                or wid
                            )
                        if not translation:
                            translation = (
                                item.get("expectedAnswer")
                                or item.get("expected")
                                or item.get("source")
                                or "[待补]"
                            )
                        words.append(
                            {
                                "id": wid,
                                "term": term or wid,
                                "translation": translation,
                                "pronunciation": None,
                                "audioAsset": None,
                                "tags": ["auto-fix", "needs-review"],
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
                            "translation": prompt or "[待补]",
                            "pronunciation": None,
                            "audioAsset": None,
                            "tags": ["auto-fix", "needs-review"],
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
    stream: bool = False,
    on_chunk: Callable[[str], None] | None = None,
    usage_callback: Callable[[dict[str, int]], None] | None = None,
    max_tokens: int | None = None,
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
    """
    if not config.is_complete:
        raise RuntimeError("API 配置不完整，请填写 Base URL / API Key / Model。")

    payload_obj: dict[str, Any] = {
        "model": config.model,
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
        with urllib.request.urlopen(req, timeout=timeout) as resp:  # noqa: S310
            if streaming_requested:
                body = _read_streaming(resp, config, cancel_check, on_chunk)
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
            usage = _estimate_usage_from_messages(messages, parsed)
        usage_callback(usage)
    return parsed


def _estimate_usage_from_messages(
    messages: list[dict[str, Any]], result_body: dict[str, Any]
) -> dict[str, int]:
    """Estimate prompt/completion tokens from message + result text (P0-6)."""
    prompt_text = "\n".join(
        _content_text(m.get("content")) for m in messages if isinstance(m, dict)
    )
    completion_text = ""
    choices = result_body.get("choices") or []
    if choices:
        completion_text = _content_text((choices[0].get("message") or {}).get("content"))
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
        body = request_chat(
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


def _read_streaming(resp: Any, config: AiApiConfig, cancel_check, on_chunk) -> str:
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
        # responses and double the body).
        remainder = "".join(line_iter)
        full_body = first_line + remainder
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
        if _emit(first_fragment):
            pass
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


def request_course(config: AiApiConfig, spec: AiCourseSpec, timeout: float = 120.0, cancel_check: Callable[[], bool] | None = None, on_chunk: Callable[[str], None] | None = None, usage_callback: Callable[[dict[str, int]], None] | None = None) -> dict:
    """Single-shot course generation (legacy normal mode)."""
    messages = [
        {
            "role": "system",
            "content": SYSTEM_AUTHORING,
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
        stream=on_chunk is not None,
        on_chunk=on_chunk,
        usage_callback=usage_callback,
    )
    return parse_completion(body)


def _coerce_problem_messages(items) -> list[str]:
    """Normalize a validator's return value to human-readable error strings.

    ``validate_section_json`` returns ``list[dict]`` (Problem dicts with
    ``level``/``message``/``path``), but the retry contract historically
    documented ``list[str]``. Accept either: for a dict, take ``message`` and
    only keep it when ``level`` is missing or ``"error"`` (warnings are not
    re-fed to the model); for a plain string, treat it as an error.
    """
    messages: list[str] = []
    for item in items or []:
        if isinstance(item, dict):
            level = item.get("level", "error")
            if level and level != "error":
                continue
            msg = item.get("message") or ""
            if msg:
                messages.append(str(msg))
        elif item:
            messages.append(str(item))
    return messages


def request_course_with_retry(
    config: AiApiConfig,
    spec: AiCourseSpec,
    validator,
    timeout: float = 120.0,
    max_retries: int = 1,
    temperature: float = 0.4,
    cancel_check: Callable[[], bool] | None = None,
    on_chunk: Callable[[str], None] | None = None,
    usage_callback: Callable[[dict[str, int]], None] | None = None,
) -> dict:
    """Generate a course and, if ``validator(section_json)`` reports errors,
    re-prompt the model with those errors up to ``max_retries`` times (C3).

    ``validator`` is a callable ``(section_json: dict) -> list[dict] | list[str]``
    returning either Problem dicts (with ``level``/``message``) or plain error
    strings; empty == valid. Problem dicts whose ``level`` is not ``"error"``
    (e.g. warnings) are not re-fed to the model. The original generation is
    retried by appending an assistant turn (the last JSON) plus a correction
    turn to the conversation.
    """
    messages = [
        {
            "role": "system",
            "content": SYSTEM_AUTHORING
        },
        {"role": "user", "content": build_prompt(spec)},
    ]
    section = parse_completion(
        request_chat(
            config, messages, temperature=temperature,
            response_format={"type": "json_object"}, timeout=timeout,
            cancel_check=cancel_check,
            stream=on_chunk is not None, on_chunk=on_chunk,
            usage_callback=usage_callback,
        )
    )
    for _ in range(max(0, max_retries)):
        problems = list(validator(section) or [])
        errors = _coerce_problem_messages(problems)
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
                config, messages, temperature=max(0.0, temperature - 0.2),
                response_format={"type": "json_object"}, timeout=timeout,
                cancel_check=cancel_check,
                # Only stream the first attempt; retries are usually short.
                stream=False, on_chunk=None,
            )
        )
    return section


def request_alignment_reply(
    config: AiApiConfig,
    spec: AiCourseSpec,
    messages: list[ChatMessage],
    timeout: float = 120.0,
    temperature: float = 0.7,
    cancel_check: Callable[[], bool] | None = None,
    on_chunk: Callable[[str], None] | None = None,
    usage_callback: Callable[[dict[str, int]], None] | None = None,
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
        temperature=temperature,
        timeout=timeout,
        cancel_check=cancel_check,
        stream=on_chunk is not None,
        on_chunk=on_chunk,
        usage_callback=usage_callback,
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
    temperature: float = 0.4,
    cancel_check: Callable[[], bool] | None = None,
    on_chunk: Callable[[str], None] | None = None,
    usage_callback: Callable[[dict[str, int]], None] | None = None,
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
            "content": SYSTEM_AUTHORING_CHAT,
        }
    ] + [m.to_api_dict() for m in messages]
    api_messages.append({"role": "user", "content": generation_prompt})

    body = request_chat(
        config,
        api_messages,
        temperature=temperature,
        response_format={"type": "json_object"},
        timeout=timeout,
        cancel_check=cancel_check,
        stream=on_chunk is not None,
        on_chunk=on_chunk,
        usage_callback=usage_callback,
    )
    return parse_completion(body)


def explain_course(
    config: AiApiConfig,
    spec: AiCourseSpec,
    section_json: dict[str, Any],
    timeout: float = 120.0,
    temperature: float = 0.6,
    cancel_check: Callable[[], bool] | None = None,
    on_chunk: Callable[[str], None] | None = None,
    usage_callback: Callable[[dict[str, int]], None] | None = None,
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
        temperature=temperature,
        timeout=timeout,
        cancel_check=cancel_check,
        stream=on_chunk is not None,
        on_chunk=on_chunk,
        usage_callback=usage_callback,
    )
    choices = body.get("choices") or []
    if not choices:
        raise ValueError("AI 未返回解释")
    content = choices[0].get("message", {}).get("content", "").strip()
    if not content:
        raise ValueError("AI 未返回解释")
    return content


def detect_genre_from_spec(spec: AiCourseSpec) -> list[str]:
    """Detect all explicit genre tags in the spec's topic or extra instructions.

    Returns a de-duplicated, ordered list of bracketed tags such as
    ``["[intro]", "[listening]"]``.
    """
    combined = f"{spec.topic} {spec.extra_instructions}"
    return genre_tags_in_text(combined)


def apply_genre_to_spec(spec: AiCourseSpec) -> AiCourseSpec:
    """If a single genre tag is present and batch mode is on, update the spec template.

    When multiple genre tags are present, the spec template is left untouched
    and the distribution is handled in :func:`build_prompt` so the caller can
    still see the original fallback template.

    Returns a new spec (via :func:`dataclasses.replace`) rather than mutating
    the input in place, mirroring the Dart side
    (``AiCourseService.applyGenreToSpec`` which uses ``copyWith``). Callers
    reuse ``AiCourseSpec`` objects across calls, so an in-place mutation would
    leak the genre template into a later call with a different tag.
    """
    if not spec.use_genre_batch:
        return spec
    tags = detect_genre_from_spec(spec)
    if len(tags) == 1:
        return replace(spec, template=genre_to_template(tags[0]))
    return spec


def _distribute_genres_to_lessons(
    tags: list[str],
    unit_count: int,
    lessons_per_unit: int,
) -> list[list[str]]:
    """Distribute genre tags across units in round-robin order.

    Returns a nested list ``[unit][lesson] -> template``. If there are no tags,
    every lesson uses ``"mixed"``. If there is one tag, every lesson uses that
    tag's template. If there are multiple tags, tags cycle per unit; all
    lessons within a unit share the same tag.
    """
    if not tags:
        return [["mixed" for _ in range(lessons_per_unit)] for _ in range(unit_count)]
    templates = [genre_to_template(tag) for tag in tags]
    return [
        [templates[u_idx % len(templates)] for _ in range(lessons_per_unit)]
        for u_idx in range(unit_count)
    ]


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
    temperature: float = 0.4,
    cancel_check: Callable[[], bool] | None = None,
    on_chunk: Callable[[str], None] | None = None,
    usage_callback: Callable[[dict[str, int]], None] | None = None,
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
            "content": SYSTEM_AUTHORING_EDIT,
        }
    ]
    if messages:
        api_messages += [m.to_api_dict() for m in messages]
    api_messages.append({"role": "user", "content": edit_prompt})

    body = request_chat(
        config,
        api_messages,
        temperature=temperature,
        response_format={"type": "json_object"},
        timeout=timeout,
        cancel_check=cancel_check,
        stream=on_chunk is not None,
        on_chunk=on_chunk,
        usage_callback=usage_callback,
    )
    parsed = parse_completion(body)
    # In edit mode the returned section must keep the same id.
    existing_id = existing_section.get("id", "")
    if existing_id and parsed.get("id") != existing_id:
        parsed["id"] = existing_id
    return parsed


# --- Local regeneration (P2.3 / C5) ----------------------------------------


def _section_unit_ids(section: dict[str, Any]) -> set[str]:
    return {u.get("id") for u in (section.get("units") or []) if isinstance(u, dict) and u.get("id")}


def _section_lesson_ids(section: dict[str, Any]) -> set[str]:
    ids: set[str] = set()
    for unit in section.get("units") or []:
        if not isinstance(unit, dict):
            continue
        for lesson in unit.get("lessons") or []:
            if isinstance(lesson, dict) and lesson.get("id"):
                ids.add(lesson["id"])
    return ids


def _top_level_ids(section: dict[str, Any], key: str) -> set[str]:
    return {r.get("id") for r in (section.get(key) or []) if isinstance(r, dict) and r.get("id")}


def structural_diff(existing: dict[str, Any], parsed: dict[str, Any]) -> dict[str, set[str]]:
    """Compare id sets of an existing section vs an AI-edited one (B3).

    Returns a dict of *removed* ids only (before minus after) at the unit,
    lesson, word, expression and grammar-point levels. Additions and renames
    are not reported here — only deletions the dialog must confirm, since a
    silent drop of units/words by the model is the failure mode we guard
    against. An all-empty dict means no structural removals.
    """
    return {
        "removed_units": _section_unit_ids(existing) - _section_unit_ids(parsed),
        "removed_lessons": _section_lesson_ids(existing) - _section_lesson_ids(parsed),
        "removed_words": _top_level_ids(existing, "words") - _top_level_ids(parsed, "words"),
        "removed_expressions": _top_level_ids(existing, "expressions")
        - _top_level_ids(parsed, "expressions"),
        "removed_grammar": _top_level_ids(existing, "grammarPoints")
        - _top_level_ids(parsed, "grammarPoints"),
    }


def _entries_by_id(section: dict[str, Any], key: str) -> dict[str, dict[str, Any]]:
    """Top-level resource entries keyed by id (e.g. words/expressions/grammarPoints)."""
    out: dict[str, dict[str, Any]] = {}
    for r in section.get(key) or []:
        if isinstance(r, dict) and r.get("id"):
            out[r["id"]] = r
    return out


def _units_by_id(section: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {u.get("id"): u for u in (section.get("units") or []) if isinstance(u, dict) and u.get("id")}


def _lessons_by_id(section: dict[str, Any]) -> dict[str, dict[str, Any]]:
    out: dict[str, dict[str, Any]] = {}
    for unit in section.get("units") or []:
        if not isinstance(unit, dict):
            continue
        for lesson in unit.get("lessons") or []:
            if isinstance(lesson, dict) and lesson.get("id"):
                out[lesson["id"]] = lesson
    return out


def _entry_fingerprint(entry: dict[str, Any]) -> str:
    """Stable serialized form for deep-equality comparison (changed detection)."""
    return json.dumps(entry, sort_keys=True, ensure_ascii=False)


def full_section_diff(
    existing: dict[str, Any], generated: dict[str, Any]
) -> dict[str, dict[str, list[str]]]:
    """Full add/remove/change diff between two sections (P3.4).

    Returns ``{category: {"added": [...], "removed": [...], "changed": [...]}}``
    for categories ``units``/``lessons``/``words``/``expressions``/``grammar``.
    ``added`` = ids in generated but not existing; ``removed`` = ids in existing
    but not generated; ``changed`` = ids present in both whose serialized
    content differs. Lists are sorted for stable display.
    """
    spec: list[tuple[str, dict[str, dict], dict[str, dict]]] = [
        ("units", _units_by_id(existing), _units_by_id(generated)),
        ("lessons", _lessons_by_id(existing), _lessons_by_id(generated)),
        ("words", _entries_by_id(existing, "words"), _entries_by_id(generated, "words")),
        ("expressions", _entries_by_id(existing, "expressions"), _entries_by_id(generated, "expressions")),
        ("grammar", _entries_by_id(existing, "grammarPoints"), _entries_by_id(generated, "grammarPoints")),
    ]
    result: dict[str, dict[str, list[str]]] = {}
    for category, before, after in spec:
        before_ids = set(before)
        after_ids = set(after)
        added = sorted(after_ids - before_ids)
        removed = sorted(before_ids - after_ids)
        changed = sorted(
            bid
            for bid in (before_ids & after_ids)
            if _entry_fingerprint(before[bid]) != _entry_fingerprint(after[bid])
        )
        result[category] = {"added": added, "removed": removed, "changed": changed}
    return result


def _build_local_regen_instruction(spec: AiCourseSpec, scope_label: str) -> str:
    """Pure helper: build a local-regeneration instruction from the spec.

    The teacher's edit intent is derived from ``spec.topic`` and
    ``spec.extra_instructions`` (the same prompt material used for full
    generation), scoped to the selected lesson/unit. Extracted as a pure
    function so it can be unit-tested without PySide6.
    """
    parts = [f"请在此课程主题下{scope_label}：保持 id 与题型不变，改进内容质量。"]
    if spec.topic:
        parts.append(f"课程主题：{spec.topic}")
    if spec.extra_instructions:
        parts.append(f"额外要求：{spec.extra_instructions}")
    return "\n".join(parts)


def _find_lesson(section: dict[str, Any], lesson_id: str) -> tuple[dict | None, dict | None]:
    """Return (unit, lesson) for ``lesson_id`` in ``section``, or (None, None)."""
    for unit in section.get("units") or []:
        if not isinstance(unit, dict):
            continue
        for lesson in unit.get("lessons") or []:
            if isinstance(lesson, dict) and lesson.get("id") == lesson_id:
                return unit, lesson
    return None, None


def _splice_lesson(
    existing_section: dict[str, Any], lesson_id: str, new_lesson: dict[str, Any]
) -> dict[str, Any]:
    """Return a deep-ish copy of ``existing_section`` with ``lesson_id``
    replaced by ``new_lesson`` (matched by id). If the id is not found, the
    new lesson is appended to the first unit. Other lessons/units are
    preserved verbatim.
    """
    import copy

    section = copy.deepcopy(existing_section)
    # Ensure the new lesson keeps its identity id.
    new_lesson = dict(new_lesson)
    new_lesson["id"] = lesson_id
    units = section.get("units") or []
    replaced = False
    for unit in units:
        lessons = unit.get("lessons") or []
        for i, lesson in enumerate(lessons):
            if isinstance(lesson, dict) and lesson.get("id") == lesson_id:
                lessons[i] = new_lesson
                replaced = True
                break
        if replaced:
            break
    if not replaced:
        first_unit = next((u for u in units if isinstance(u, dict)), None)
        if first_unit is None:
            first_unit = {"id": "u-ai", "lessons": []}
            section.setdefault("units", []).append(first_unit)
        first_unit.setdefault("lessons", []).append(new_lesson)
    return section


def regenerate_lesson_in_section(
    config: AiApiConfig,
    spec: AiCourseSpec,
    existing_section: dict[str, Any],
    lesson_id: str,
    instruction: str | None = None,
    timeout: float = 120.0,
    temperature: float = 0.5,
    cancel_check: Callable[[], bool] | None = None,
    on_chunk: Callable[[str], None] | None = None,
    usage_callback: Callable[[dict[str, int]], None] | None = None,
) -> dict[str, Any]:
    """Regenerate a single lesson in place and splice it back (C5).

    Only the targeted lesson is sent to the model via
    ``request_lesson_transform`` (which validates and preserves identity
    fields), so unchanged units/lessons cost no tokens. Returns the
    reassembled full section JSON.
    """
    _, lesson = _find_lesson(existing_section, lesson_id)
    if lesson is None:
        raise ValueError(f"未找到课时「{lesson_id}」。")
    instr = instruction or _build_local_regen_instruction(spec, "重写该课时")
    new_lesson = request_lesson_transform(
        config,
        lesson,
        instr,
        timeout=timeout,
        temperature=temperature,
        cancel_check=cancel_check,
        on_chunk=on_chunk,
        usage_callback=usage_callback,
    )
    return _splice_lesson(existing_section, lesson_id, new_lesson)


def regenerate_unit_in_section(
    config: AiApiConfig,
    spec: AiCourseSpec,
    existing_section: dict[str, Any],
    unit_id: str,
    instruction: str | None = None,
    timeout: float = 120.0,
    temperature: float = 0.5,
    cancel_check: Callable[[], bool] | None = None,
    on_chunk: Callable[[str], None] | None = None,
    usage_callback: Callable[[dict[str, int]], None] | None = None,
) -> dict[str, Any]:
    """Regenerate every lesson in a unit in place and splice them back (C5).

    Iterates the unit's lessons, calling ``request_lesson_transform`` on each
    (reusing the already-validated single-lesson path and fine-grained token
    usage), then splices each result back. The section id and other units are
    untouched. ``cancel_check`` is honoured between lessons.
    """
    unit = next(
        (u for u in (existing_section.get("units") or []) if isinstance(u, dict) and u.get("id") == unit_id),
        None,
    )
    if unit is None:
        raise ValueError(f"未找到单元「{unit_id}」。")
    instr = instruction or _build_local_regen_instruction(spec, "重写该单元内的课时")
    section = existing_section
    for lesson in list(unit.get("lessons") or []):
        if not isinstance(lesson, dict) or not lesson.get("id"):
            continue
        if cancel_check and cancel_check():
            raise AiCancelled("请求已取消。")
        new_lesson = request_lesson_transform(
            config,
            lesson,
            instr,
            timeout=timeout,
            temperature=temperature,
            cancel_check=cancel_check,
            on_chunk=on_chunk,
            usage_callback=usage_callback,
        )
        section = _splice_lesson(section, lesson["id"], new_lesson)
    return section


# --- Teacher-view inline AI helpers ----------------------------------------


def _allowed_interactions_block() -> str:
    from src.backend.lesson_content import ALLOWED_RUNTIME_TYPES, INTERACTION_LABELS

    lines = ["- 可用 interaction runtimeType："]
    for rt in ALLOWED_RUNTIME_TYPES:
        lines.append(f"  • {rt}（{INTERACTION_LABELS.get(rt, rt)}）")
    return "\n".join(lines)


def request_lesson_transform(
    config: AiApiConfig,
    lesson: dict[str, Any],
    instruction: str,
    timeout: float = 120.0,
    temperature: float = 0.5,
    cancel_check: Callable[[], bool] | None = None,
    on_chunk: Callable[[str], None] | None = None,
    usage_callback: Callable[[dict[str, int]], None] | None = None,
) -> dict[str, Any]:
    """Transform a single lesson in-place according to a teacher instruction.

    The returned lesson keeps the same ``id`` and ``template`` as the input
    unless the instruction explicitly asks to change the template. Content
    shape (subLessons / stages / listeningPhases / readingPassage) must remain
    valid for the template.
    """
    from src.backend import api

    template = lesson.get("template", "legacy")
    prompt = (
        "你是一位语言课程编辑助手。请根据教师的指令改写下面这门课。\n\n"
        f"课程模板：{template}\n"
        f"课程 id（必须保留）：{lesson.get('id', '')}\n"
        f"课程名称：{lesson.get('name', '')}\n"
        f"课程描述：{lesson.get('description', '')}\n\n"
        "当前课程完整 JSON：\n"
        f"```json\n{json.dumps(lesson, ensure_ascii=False, indent=2)}\n```\n\n"
        "教师指令：\n"
        f"{instruction}\n\n"
        "要求：\n"
        "1. 只返回完整的课程 JSON，不要任何解释、markdown 代码块标记或额外文字。\n"
        "2. 必须保留顶层 id、name、template、prerequisiteLessonIds 字段。\n"
        "3. content 结构必须符合该模板的规范（intro/practice/review 用 subLessons；"
        "listening 用 listeningPhases；reading 用 readingPassage + stages；mastery 用 stages）。\n"
        f"{_allowed_interactions_block()}\n"
        "5. 引用的 wordId / expressionId / grammarPointId 必须在课程现有资源中存在；"
        "如果没有合适资源，宁可留空也不要编造。\n"
    )

    messages = [
        {
            "role": "system",
            "content": SYSTEM_EDITING,
        },
        {"role": "user", "content": prompt},
    ]
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
    )
    choices = body.get("choices") or []
    if not choices:
        raise ValueError("API 返回的 choices 为空。")
    content = choices[0].get("message", {}).get("content", "")
    cleaned = _strip_code_fences(content)
    try:
        parsed = json.loads(cleaned)
    except json.JSONDecodeError as exc:
        raise ValueError(f"无法解析模型输出的 JSON: {exc}") from exc
    if not isinstance(parsed, dict):
        raise ValueError("模型输出不是 JSON 对象。")
    if "content" not in parsed:
        raise ValueError("模型输出不是合法的课程 JSON（缺少 content）。")

    # Preserve identity fields.
    for key in ("id", "name", "template", "prerequisiteLessonIds"):
        if key in lesson:
            parsed[key] = lesson[key]

    # Basic lesson-level validation against empty resource sets; the caller
    # can do a stronger validation with the actual course vocab/expressions.
    problems = api.validate_lesson(parsed, set(), set(), set())
    errors = [p.to_dict() for p in problems if p.level == "error"]
    if errors:
        raise ValueError(
            "AI 返回的课程校验失败：\n" + "\n".join(p["message"] for p in errors[:5])
        )
    return parsed


def request_item_transform(
    config: AiApiConfig,
    item: dict[str, Any],
    instruction: str,
    vocab_ids: set[str] | None = None,
    expression_ids: set[str] | None = None,
    grammar_ids: set[str] | None = None,
    timeout: float = 120.0,
    temperature: float = 0.5,
    cancel_check: Callable[[], bool] | None = None,
    on_chunk: Callable[[str], None] | None = None,
    usage_callback: Callable[[dict[str, int]], None] | None = None,
) -> dict[str, Any]:
    """Transform a single interaction item in-place.

    Preserves the item ``id`` and ``runtimeType`` unless the instruction asks
    to switch type.
    """
    from src.backend.lesson_content import INTERACTION_SCHEMA, normalize_item

    rt = item.get("runtimeType", "")
    prompt = (
        "你是一位语言课程编辑助手。请根据教师的指令改写下面这道题目。\n\n"
        f"题目 id（必须保留）：{item.get('id', '')}\n"
        f"当前 runtimeType：{rt}\n"
        "当前题目 JSON：\n"
        f"```json\n{json.dumps(item, ensure_ascii=False, indent=2)}\n```\n\n"
        "教师指令：\n"
        f"{instruction}\n\n"
        "要求：\n"
        "1. 只返回完整的题目 JSON，不要任何解释、markdown 代码块标记或额外文字。\n"
        "2. 必须保留 id 字段；如未要求改题型，请保留 runtimeType。\n"
        f"{_allowed_interactions_block()}\n"
        "4. 引用的 wordId / expressionId / grammarPointId 必须在可用资源中存在；"
        "没有则留空。\n"
    )

    messages = [
        {
            "role": "system",
            "content": SYSTEM_EDITING,
        },
        {"role": "user", "content": prompt},
    ]
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
    )
    choices = body.get("choices") or []
    if not choices:
        raise ValueError("API 返回的 choices 为空。")
    content = choices[0].get("message", {}).get("content", "")
    cleaned = _strip_code_fences(content)
    try:
        parsed = json.loads(cleaned)
    except json.JSONDecodeError as exc:
        raise ValueError(f"无法解析模型输出的 JSON: {exc}") from exc
    if not isinstance(parsed, dict):
        raise ValueError("模型输出不是 JSON 对象。")

    # Preserve id and default runtimeType if missing.
    parsed["id"] = item.get("id", parsed.get("id", ""))
    if "runtimeType" not in parsed:
        parsed["runtimeType"] = rt

    # Normalize against the schema to fill missing fields and catch unknown types.
    try:
        parsed = normalize_item(parsed)
    except ValueError as exc:
        raise ValueError(f"AI 返回的题目格式不正确: {exc}") from exc

    # Reference check.
    wid = parsed.get("wordId")
    if wid and vocab_ids and wid not in vocab_ids:
        parsed["wordId"] = ""
    eid = parsed.get("expressionId")
    if eid and expression_ids and eid not in expression_ids:
        parsed["expressionId"] = ""
    gid = parsed.get("grammarPointId")
    if gid and grammar_ids and gid not in grammar_ids:
        parsed["grammarPointId"] = ""
    return parsed


def request_correction(
    config: AiApiConfig,
    prompt: str,
    timeout: float = 120.0,
    temperature: float = 0.2,
    cancel_check: Callable[[], bool] | None = None,
    on_chunk: Callable[[str], None] | None = None,
    usage_callback: Callable[[dict[str, int]], None] | None = None,
) -> dict[str, Any]:
    """Ask the model to correct a JSON node and return the parsed dict.

    The prompt is expected to contain the problematic JSON node and a list of
    validation problems. The model must return only a JSON object.
    """
    from src.backend.ai_fixer import extract_json_object

    messages = [
        {
            "role": "system",
            "content": SYSTEM_CORRECTION,
        },
        {"role": "user", "content": prompt},
    ]
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
    )
    choices = body.get("choices") or []
    if not choices:
        raise ValueError("API 返回的 choices 为空。")
    content = choices[0].get("message", {}).get("content", "")
    return extract_json_object(content)
