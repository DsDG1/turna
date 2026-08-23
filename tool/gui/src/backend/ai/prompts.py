"""Prompt builders and JSON response_format helpers.

Extracted from ``ai_generator`` (M1 refactor). Prompt text is byte-stable.
"""
from __future__ import annotations

import json
from dataclasses import replace
from typing import Any

from src.backend.ai.config import (
    SYSTEM_AUTHORING,
    SYSTEM_AUTHORING_CHAT,
    SYSTEM_AUTHORING_EDIT,
    SYSTEM_CORRECTION,
    SYSTEM_EDITING,
    AiApiConfig,
    AiCourseSpec,
)
from src.backend.ai_genre import (
    genre_prompt_block,
    genre_tags_in_text,
    genre_to_template,
    template_label,
)
from src.backend.ai_pedagogy import pedagogy_prompt_block

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
- showWord: { wordId, context?, term?, translation?, pronunciation?, audioAsset?, imageAsset?, example? } — 展示生词。wordId 必须在顶层 words 数组中定义。内联字段（term/translation 等）仅在该卡需要覆盖词表默认显示时填写，通常留空。
- multipleChoice: { prompt, options(4), correctIndex, audioAssets? } — 单选题。
- multiSelect: { prompt, options, correctIndices, minSelections?, maxSelections? } — 多选题。
- fillBlank: { sentence（含 ____ 空白）, answer, hint?, audioAssets?, imageAssets? } — 填空。
- translateSentence: { source（源语言句子）, expected（目标语言翻译）, hints? } — 翻译。
- listenAndPick: { audioAsset, prompt, options(4), correctIndex } — 听音选择。
- typeTheWord: { audioAsset, prompt, expected } — 听写。
- listenOnly: { audioAsset?, transcript?, prompt? } — 只听不答。
- reorderSentence: { scrambled（打乱词数组）, correct（正确词数组） } — 排序。
- readingMcq: { prompt, options(4), correctIndex } — 阅读选择。
- readingTrueFalse: { statement, answer(true/false) } — 阅读判断。
- readingShortAnswer: { prompt, expectedAnswer } — 阅读简答。
- ankiCard: { front, back, audioAssets?, imageAssets?, hint?, sourceNoteId? } — Anki 翻卡（仅限导入内容再编排，AI 不主动生成）。
- ankiHtmlCard: { frontHtml, backHtml, css?, mediaBasePath?, allowJs?, audioAssets? } — Anki HTML 卡（同上，AI 不主动生成）。

注意：ankiCard / ankiHtmlCard 来自设备端 Anki 导入，AI 生成课程时不要产出这两种题型（不要凭空编造 sourceNoteId 等来源字段）。

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
    return """顶层资源数组（与 units 同级，必须输出）。

输出顺序（硬性）：JSON 对象中先写 words，再写 expressions，再写 grammarPoints，
最后写 units。先定义资源，再在课时中引用，避免悬空 id。

words: 本课程用到的所有生词。每个条目结构：
{
  "id": "w-merhaba",            // 全局唯一，小写 kebab-case，建议前缀 w-
  "term": "Merhaba",            // 目标语言原文（如土耳其语单词）
  "translation": "你好",         // 源语言译文（如中文）；禁止空字符串或占位符
  "pronunciation": null,        // 可选，音标或拉丁转写；没有就填 null
  "audioAsset": null,           // 可选，音频资源路径；没有就填 null
  "tags": ["greeting"]          // 可选标签数组
}

expressions: 本课程用到的所有惯用表达。每个条目结构：
{
  "id": "e-ben-adim",           // 全局唯一，建议前缀 e-
  "term": "Adım ...",            // 目标语言原文
  "translation": "我叫……",       // 源语言译文；禁止空或「待补」
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
6. 每个 word/expression 必须有非空 term 与非空 translation（完整可教条目）。
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


def _build_section_json_schema() -> dict[str, Any]:
    """Return a strict JSON Schema for a section (第三枪 批次① Step 6).

    The schema is closed (``additionalProperties: false``) and lists every
    top-level field the model must return. Array items are left as
    ``{}`` (any object) so the model can fill in lessons/words/etc. without
    hitting a deeply-nested strictness wall. This shape satisfies OpenAI's
    ``json_schema`` strict-mode requirement (all properties required, no
    extras) while staying permissive at the item level.
    """
    return {
        "type": "object",
        "properties": {
            "id": {"type": "string"},
            "name": {"type": "string"},
            "description": {"type": "string"},
            "prerequisiteSectionIds": {
                "type": "array",
                "items": {"type": "string"},
            },
            "words": {"type": "array", "items": {"type": "object"}},
            "expressions": {"type": "array", "items": {"type": "object"}},
            "grammarPoints": {"type": "array", "items": {"type": "object"}},
            "units": {"type": "array", "items": {"type": "object"}},
        },
        "required": [
            "id",
            "name",
            "description",
            "prerequisiteSectionIds",
            "words",
            "expressions",
            "grammarPoints",
            "units",
        ],
        "additionalProperties": False,
    }


# Schemas for non-section JSON calls (lesson / item / correction / outline).
# These are intentionally permissive (no properties declared, only ``object``
# type) so the model has freedom over shape but the request still routes
# through the ``json_schema`` response-format path when enabled.
_PERMISSIVE_OBJECT_SCHEMA: dict[str, Any] = {
    "type": "object",
    "additionalProperties": True,
}


def build_response_format(
    config: AiApiConfig,
    *,
    schema_name: str = "section",
    use_schema: bool = True,
) -> dict[str, Any] | None:
    """Resolve the ``response_format`` payload for an OpenAI-compatible call.

    第三枪 批次① Step 6.

    - When ``config.strict_schema == "off"`` (or ``use_schema=False``):
      returns ``{"type": "json_object"}``.
    - When ``"on"``: returns ``{"type": "json_schema", "json_schema": {...}}``
      using the section schema (or a permissive object schema for non-section
      calls).
    - When ``"auto"``: consults the process-local capability probe
      (``config.effective_strict_schema()``). First call tries ``json_schema``;
      if the provider rejects it, ``request_chat`` marks the probe false and
      subsequent calls fall back to ``json_object`` automatically.

    ``schema_name`` selects which schema to send (``"section"`` for full-course
    generation, anything else for permissive object output). ``use_schema=False``
    forces ``json_object`` for callers that want JSON mode but no schema
    constraint (e.g. chat replies that happen to be JSON).
    """
    if not use_schema:
        return {"type": "json_object"}
    resolved = config.effective_strict_schema()
    if resolved == "off":
        return {"type": "json_object"}
    schema = _build_section_json_schema() if schema_name == "section" else _PERMISSIVE_OBJECT_SCHEMA
    return {
        "type": "json_schema",
        "json_schema": {
            "name": schema_name,
            "schema": schema,
            "strict": True,
        },
    }

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
        "2. 禁止修改资源池条目的 id 或内容；禁止编造与资源池无关的半残引用。",
        "3. 优先只使用池内 id。确需池外新词时：必须输出完整 term+translation，"
        "并打上 \"new\" tag；禁止只有 id 没有释义。",
        "4. lesson 中的 wordId / expressionId / grammarPointId 必须引用顶层数组中已定义的 id。",
        "5. 输出顺序：先完整写出 words/expressions/grammarPoints，再写 units。",
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
        pedagogy_prompt_block(
            level=spec.level,
            language=spec.language,
            template=spec.template,
        ),
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

def _draft_json_suffix(draft_json: dict) -> str:
    """Prompt suffix asking the model to revise an existing course draft."""
    return (
        "\n\n以下是目前已生成的课程草稿，请根据对话中的修改意见进行调整，"
        "返回完整的新的课程 JSON（不要只返回 diff）。\n\n"
        f"```json\n{json.dumps(draft_json, ensure_ascii=False, indent=2)}\n```"
    )

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

def _allowed_interactions_block() -> str:
    from src.backend.lesson_content import ALLOWED_RUNTIME_TYPES, INTERACTION_LABELS

    lines = ["- 可用 interaction runtimeType："]
    for rt in ALLOWED_RUNTIME_TYPES:
        lines.append(f"  • {rt}（{INTERACTION_LABELS.get(rt, rt)}）")
    return "\n".join(lines)

