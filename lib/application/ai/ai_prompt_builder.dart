// Project imports:
import 'package:varnamala/application/ai/ai_course_spec.dart';
import 'package:varnamala/application/ai/ai_genre.dart';

/// Prompt schema blocks mirroring
/// `tool/gui/src/backend/ai_generator.py:_template_schema_block`,
/// `_resource_schema_block`, `_id_rules_block`, `_build_json_schema_example`.

String _templateSchemaBlock() {
  return '''课程结构层级：section → units → lessons → content。

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
''';
}

String _resourceSchemaBlock() {
  return '''顶层资源数组（与 units 同级，必须输出）：

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
''';
}

String _idRulesBlock() {
  return '''ID 规则：
1. 所有 id 必须全局唯一，包括 section id、unit id、lesson id、stage id、subLesson id、item id。
2. 使用小写 kebab-case，前缀建议为 "ai-"，例如 ai-travel-u1-l1、ai-travel-u1-l1-st1。
3. 不要包含空格或特殊字符。
''';
}

String _buildJsonSchemaExample(AiCourseSpec spec) {
  final template = spec.template;
  String contentExample;
  if (template == 'listening') {
    contentExample = '''"content": {
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
}''';
  } else if (template == 'reading') {
    contentExample = '''"content": {
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
}''';
  } else if (template == 'mastery') {
    contentExample = '''"content": {
  "stages": [
    {
      "id": "ai-topic-u1-l1-st1",
      "name": "Quiz",
      "items": [
        { "runtimeType": "multipleChoice", "id": "...", "prompt": "...", "options": ["...", "...", "...", "..."], "correctIndex": 0 }
      ]
    }
  ]
}''';
  } else {
    // intro / practice / review / mixed default to subLessons
    contentExample = '''"content": {
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
}''';
  }
  return '''返回 JSON 形状示例（顶层 section）：
{
  "id": "ai-topic",
  "name": "...",
  "description": "...",
  "prerequisiteSectionIds": [],
  "words": [
    { "id": "w-merhaba", "term": "Merhaba", "translation": "你好", "pronunciation": null, "audioAsset": null, "tags": ["greeting"] }
  ],
  "expressions": [
    { "id": "e-ben-adim", "term": "Adım ...", "translation": "我叫……", "pronunciation": null, "audioAsset": null, "tags": [] }
  ],
  "grammarPoints": [],
  "units": [
    {
      "id": "ai-topic-u1",
      "name": "...",
      "description": "",
      "prerequisiteUnitIds": [],
      "lessons": [
        {
          "id": "ai-topic-u1-l1",
          "name": "...",
          "description": "",
          "type": "normal",
          "template": "$template",
          "prerequisiteLessonIds": [],
          $contentExample
        }
      ]
    }
  ]
}

Rules:
1. Every lesson MUST have at least one stage/phase with at least 3 items when the template supports items.
2. Multiple choice items: exactly 4 options, correctIndex in 0..3.
3. translateSentence: source in ${spec.sourceLanguage}, expected in ${spec.language}.
4. fillBlank: sentence in ${spec.language} with a single ____ blank; answer is the missing word.
5. Every showWord.wordId / expressionId / grammarPointId MUST reference an id defined in the top-level words / expressions / grammarPoints arrays. Do NOT invent ids that are not defined there.
6. Output JSON object only — no surrounding text, no markdown fences.
''';
}

/// Build the generation prompt for the AI model. Mirrors
/// `ai_generator.py:build_prompt`.
String buildPrompt(AiCourseSpec spec) {
  final parts = <String>[
    'Generate a language learning course section as JSON.',
    '',
    'Target language: ${spec.language}',
    'Prompt/source language: ${spec.sourceLanguage}',
    'Topic / theme: ${spec.topic}',
    'Learner level: ${spec.level}',
    'Units: ${spec.unitCount}, each with ${spec.lessonsPerUnit} lessons.',
  ];

  if (spec.useGenreBatch) {
    parts.addAll([
      '',
      'Default fallback template: ${spec.template} (${templateLabel(spec.template)})',
      '',
      genrePromptBlock(),
      '',
      'You are in multi-template batch mode. When a genre tag like [intro] or [listening] appears '
          'in the topic or extra instructions, generate the corresponding lesson(s) using that template. '
          'Lessons without a tag should use the default fallback template.',
    ]);
  } else {
    parts.addAll([
      '',
      'Template for all lessons: ${spec.template} (${templateLabel(spec.template)})',
      'All lessons in this section MUST use this template uniformly.',
    ]);
  }

  if (spec.extraInstructions.isNotEmpty) {
    parts.addAll(['', 'Extra instructions: ${spec.extraInstructions}']);
  }

  parts.addAll([
    '',
    'Return STRICT JSON only (no markdown, no code fences).',
    '',
    _templateSchemaBlock(),
    '',
    _resourceSchemaBlock(),
    '',
    _idRulesBlock(),
    '',
    _buildJsonSchemaExample(spec),
  ]);
  return parts.join('\n');
}

/// Build the alignment-phase prompt for wish mode. Mirrors
/// `ai_generator.py:build_alignment_prompt`.
String buildAlignmentPrompt(AiCourseSpec spec) {
  final parts = <String>[
    'You are a language-course design assistant helping a non-technical beginner teacher.',
    '',
    'The teacher wants to create a ${spec.language} course section at level ${spec.level}.',
    'Source / prompt language: ${spec.sourceLanguage}.',
    'Topic: ${spec.topic.isEmpty ? "(not specified yet — ask the teacher)" : spec.topic}.',
    'Target structure: ${spec.unitCount} units, each with ${spec.lessonsPerUnit} lessons.',
  ];

  if (spec.useGenreBatch) {
    parts.addAll([
      '',
      'Multi-template batch mode is enabled. The teacher can insert genre tags like [intro], [practice], '
          '[listening], [reading], [mastery] to request different templates for different lessons.',
      genrePromptBlock(),
    ]);
  } else {
    parts.addAll([
      '',
      "All lessons will use the '${spec.template}' template (${templateLabel(spec.template)}).",
    ]);
  }

  if (spec.extraInstructions.isNotEmpty) {
    parts.addAll(['', 'Extra notes: ${spec.extraInstructions}']);
  }

  parts.addAll([
    '',
    'Your job is to ALIGN with the teacher through conversation. Follow these rules:',
    '1. Use friendly, plain Chinese. No jargon, no JSON, no code, no markdown fences.',
    '2. In each reply, briefly summarize what you understand, then give 2-3 concrete suggestions or clarifying questions.',
    '3. If the teacher uploads files, incorporate them into your suggestions naturally.',
    '4. When suggesting vocabulary or expressions, also tell the teacher that these will be added to the course\'s vocabulary list automatically — they don\'t need to prepare a separate word bank.',
    '5. Do NOT output the final course JSON. The teacher will click "我感觉差不多了" when ready.',
    '6. If the teacher asks to change the course, acknowledge the change and explain how it affects the design.',
  ]);
  return parts.join('\n');
}