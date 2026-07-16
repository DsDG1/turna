// Project imports:
import 'package:varnamala/application/ai/ai_course_spec.dart';
import 'package:varnamala/application/ai/ai_genre.dart';

/// Prompt schema blocks mirroring
/// `tool/gui/src/backend/ai_generator.py:_template_schema_block`,
/// `_resource_schema_block`, `_id_rules_block`, `_build_json_schema_example`.

String _templateSchemaBlock() {
  return '''Course structure hierarchy: section → units → lessons → content.

Available lesson templates and their content primary key:
- intro: New Words. content primary key is subLessons. Each subLesson contains stages; each stage contains items.
- practice: Practice. content primary key is subLessons.
- review: Review. content primary key is subLessons; may also include stages.
- listening: Listening. content primary key is listeningPhases. Each phase may contain items (wordPairing/dialogue) or be listen-only (summary).
- reading: Reading. content contains readingPassage (title + paragraphs) and stages (comprehension questions).
- mastery: Quiz. content primary key is stages; a single stage is enough.
- mixed: Mixed. Different units/lessons may use different templates.

Interaction types (runtimeType) reference:
- showWord: { wordId, context? } — display a new word. wordId must be defined in the top-level words array.
- multipleChoice: { prompt, options(4), correctIndex } — single-choice question.
- multiSelect: { prompt, options, correctIndices, minSelections?, maxSelections? } — multi-choice question.
- fillBlank: { sentence (with a ____ blank), answer, hint? } — fill-in-the-blank.
- translateSentence: { source (source-language sentence), expected (target-language translation), hints? } — translation.
- listenAndPick: { audioAsset, prompt, options(4), correctIndex } — listen and pick.
- typeTheWord: { audioAsset, prompt, expected } — dictation.
- listenOnly: { audioAsset?, transcript?, prompt? } — listen only, no answer.
- reorderSentence: { scrambled (shuffled word array), correct (correct word array) } — sentence ordering.
- readingMcq: { prompt, options(4), correctIndex } — reading multiple choice.
- readingTrueFalse: { statement, answer(true/false) } — reading true/false.
- readingShortAnswer: { prompt, expectedAnswer } — reading short answer.

Suggested template → interaction pairings:
- intro: showWord + translateSentence + fillBlank
- practice: multipleChoice + fillBlank + translateSentence + reorderSentence
- listening: listenAndPick + typeTheWord + listenOnly (phase structure)
- reading: readingPassage + readingMcq + readingTrueFalse + readingShortAnswer
- mastery: multipleChoice + multiSelect + translateSentence + fillBlank
''';
}

String _resourceSchemaBlock() {
  return '''Top-level resource arrays (same level as units, must be output):

words: all new words used in this course. Each entry structure:
{
  "id": "w-merhaba",            // globally unique, lower kebab-case, suggest prefix w-
  "term": "Merhaba",            // target-language original (e.g. the Turkish word)
  "translation": "hello",       // source-language translation (e.g. Chinese)
  "pronunciation": null,        // optional, phonetic or latin transliteration; null if none
  "audioAsset": null,           // optional, audio asset path; null if none
  "tags": ["greeting"]          // optional tag array
}

expressions: all idiomatic expressions used in this course. Each entry structure:
{
  "id": "e-ben-adim",           // globally unique, suggest prefix e-
  "term": "Adım ...",            // target-language original
  "translation": "My name is…",  // source-language translation
  "pronunciation": null,
  "audioAsset": null,
  "tags": []
}

grammarPoints: all grammar points used in this course. Each entry structure:
{
  "id": "g-suffix-dan",         // globally unique, suggest prefix g-
  "title": "Ablative case -dan",
  "explanation": "Means 'from…', appended to a noun.",
  "exampleExpressionIds": [],   // references ids in expressions
  "exampleSentenceIds": [],
  "practiceItems": []
}

Self-consistency rules (most important):
1. Any showWord's wordId must appear in the id of some entry in the top-level words array.
2. Any expressionId must appear in the id of some entry in the top-level expressions array.
3. Any grammarPointId must appear in the id of some entry in the top-level grammarPoints array.
4. Only output resources actually used in this course; do not output unreferenced entries.
5. Resource ids must not collide with the existing word bank (import will auto-skip existing ids, but prefer prefixes like ai- / w-ai- to avoid collisions).
''';
}

String _idRulesBlock() {
  return '''ID rules:
1. All ids must be globally unique, including section id, unit id, lesson id, stage id, subLesson id, and item id.
2. Use lower kebab-case; suggested prefix is "ai-", e.g. ai-travel-u1-l1, ai-travel-u1-l1-st1.
3. Do not include spaces or special characters.
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
  return '''Example of the JSON shape to return (top-level section):
{
  "id": "ai-topic",
  "name": "...",
  "description": "...",
  "prerequisiteSectionIds": [],
  "words": [
    { "id": "w-merhaba", "term": "Merhaba", "translation": "hello", "pronunciation": null, "audioAsset": null, "tags": ["greeting"] }
  ],
  "expressions": [
    { "id": "e-ben-adim", "term": "Adım ...", "translation": "My name is…", "pronunciation": null, "audioAsset": null, "tags": [] }
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
7. Any prose explanations (e.g. grammar explanations or context fields) MUST be written in the learner's source language (${spec.sourceLanguage}).
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
    '1. Use friendly, plain ${spec.sourceLanguage}. No jargon, no JSON, no code, no markdown fences.',
    '2. In each reply, briefly summarize what you understand, then give 2-3 concrete suggestions or clarifying questions.',
    '3. If the teacher uploads files, incorporate them into your suggestions naturally.',
    '4. When suggesting vocabulary or expressions, also tell the teacher that these will be added to the course\'s vocabulary list automatically — they don\'t need to prepare a separate word bank.',
    '5. Do NOT output the final course JSON. The teacher will click "I think that\'s about right" when ready.',
    '6. If the teacher asks to change the course, acknowledge the change and explain how it affects the design.',
  ]);
  return parts.join('\n');
}