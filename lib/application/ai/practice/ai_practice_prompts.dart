// Dart imports:
import 'dart:convert';

// Project imports:
import 'package:turna/application/ai/ai_genre.dart';
import 'package:turna/application/ai/practice/ai_practice_models.dart';
import 'package:turna/domain/ai/ai_course.dart';

/// Prompt blocks for AI practice / course generation.
///
/// Mirrors the semantics of tool-gui's authoring prompts
/// (`tool/gui/src/backend/ai/prompts.py`, `ai_phased.py`, `ai_pedagogy.py`)
/// without importing Python code: one section contract
/// (`docs/authoring/course-layout.md`), phased generation (outline → lesson
/// fill), design brief / resource grounding, and the pedagogy block.
///
/// Every generator call is JSON-only. The schema lives in the user message so
/// the system prompt can stay a short role/boundary statement (mirroring the
/// GUI's split).
abstract final class AiPracticePrompts {
  /// Text-only interaction types that do not need pre-generated audio or a
  /// vocabulary row. `listenAndPick` / `typeTheWord` / `listenOnly` are
  /// deliberately excluded: generated drafts have no audio asset and are not
  /// seeded into the vocabulary table, so those renderers would surface an
  /// empty audio control.
  static const List<String> textInteractionTypes = [
    'showWord',
    'multipleChoice',
    'multiSelect',
    'fillBlank',
    'translateSentence',
    'reorderSentence',
    'readingMcq',
    'readingTrueFalse',
    'readingShortAnswer',
  ];

  static String outlinePrompt(
    AiPracticeRequest request, {
    String? groundedContext,
  }) {
    final spec = request.spec;
    final buf = StringBuffer()
      ..writeln('Generate an OUTLINE JSON for a Turna course section.')
      ..writeln()
      ..writeln('Target language: ${spec.language}')
      ..writeln('Prompt/source language: ${spec.sourceLanguage}')
      ..writeln(
          'Topic / theme: ${spec.topic.isEmpty ? '(not specified)' : spec.topic}')
      ..writeln('Learner level: ${spec.level}')
      ..writeln(
          'Units: ${spec.unitCount}, each with ${spec.lessonsPerUnit} lessons.');
    if (spec.template == 'mixed') {
      buf.writeln('Template: mixed — choose a sensible template per lesson '
          'from intro / practice / review / reading / mastery (never '
          'listening).');
    } else {
      buf.writeln('Template for every lesson: ${spec.template} '
          '(${templateLabel(spec.template)})');
    }
    buf.writeln();

    if (request.source == AiPracticeSource.mistakes) {
      buf.writeln('This is a short remediation drill built ONLY from the '
          'learner mistakes below. Keep it to one unit and one lesson.');
    } else if (request.source == AiPracticeSource.weakWords) {
      buf.writeln('This is a short weak-word drill. Keep it to one unit and '
          'one lesson, and recycle the weak words in graded items.');
    } else if (request.source == AiPracticeSource.difficult) {
      buf.writeln('This is a short drill on the grammar points / confusing '
          'items below. Keep it to one unit and one lesson.');
    } else {
      buf.writeln('This is a custom course requested by the learner.');
    }

    if (spec.designBrief.trim().isNotEmpty) {
      buf
        ..writeln()
        ..writeln('Design intent (follow it):')
        ..writeln(spec.designBrief.trim());
    }
    if (spec.extraInstructions.trim().isNotEmpty) {
      buf
        ..writeln()
        ..writeln('Extra instructions:')
        ..writeln(spec.extraInstructions.trim());
    }
    if (request.sourceContext.trim().isNotEmpty) {
      buf
        ..writeln()
        ..writeln('Learner evidence (use these exact items; do not invent '
            'unrelated vocabulary):')
        ..writeln(request.sourceContext.trim());
    }
    if (groundedContext != null && groundedContext.trim().isNotEmpty) {
      buf
        ..writeln()
        ..writeln('Existing course resources (reuse their ids when the concept '
            'matches; only add new ids for genuinely new concepts):')
        ..writeln(groundedContext.trim());
    }

    buf
      ..writeln()
      ..writeln('Return STRICT JSON only (no markdown, no code fences):')
      ..writeln('''
{
  "id": "${request.id}",
  "name": "${request.title}",
  "description": "one sentence",
  "words": [
    {"id": "w-ai-...", "term": "...", "translation": "...", "pronunciation": null, "audioAsset": null, "tags": []}
  ],
  "expressions": [],
  "grammarPoints": [],
  "units": [
    {
      "id": "${request.id}-u1",
      "name": "...",
      "lessons": [
        {
          "id": "${request.id}-u1-l1",
          "name": "...",
          "template": "${spec.template}",
          "targetWordIds": ["w-ai-..."],
          "targetExpressionIds": [],
          "targetGrammarPointIds": []
        }
      ]
    }
  ]
}
''')
      ..writeln('Hard rules:')
      ..writeln('1. Output resources BEFORE units: words, then expressions, '
          'then grammarPoints.')
      ..writeln('2. Every id is lowercase kebab-case and globally unique; '
          'use the "ai-" prefix.')
      ..writeln('3. Exactly ${spec.unitCount} unit(s) and '
          '${spec.lessonsPerUnit} lesson(s) per unit.')
      ..writeln('4. Every lesson has a unique id and a template.')
      ..writeln('5. targetWordIds may only reference ids defined in this '
          'outline words array.')
      ..writeln('6. Do NOT write lesson content in the outline.')
      ..writeln('7. Every word/expression must have a non-empty term and '
          'translation.');
    return buf.toString();
  }

  static String lessonPrompt({
    required AiPracticeRequest request,
    required Map<String, dynamic> outline,
    required Map<String, dynamic> lessonOutline,
    required String unitId,
  }) {
    final spec = request.spec;
    final targetIds = <String>[
      for (final id in (lessonOutline['targetWordIds'] as List? ?? const []))
        id.toString(),
    ];
    final wordById = <String, Map<String, dynamic>>{
      for (final w in (outline['words'] as List? ?? const []))
        if (w is Map<String, dynamic> && w['id'] != null) w['id'].toString(): w,
    };
    final targetLines = [
      for (final id in targetIds)
        wordById[id] == null
            ? '- $id'
            : '- $id: ${wordById[id]!['term']} = '
                '${wordById[id]!['translation']}',
    ];

    final buf = StringBuffer()
      ..writeln('Fill the complete content of ONE lesson for a Turna course '
          'section.')
      ..writeln()
      ..writeln('Target language: ${spec.language}')
      ..writeln('Prompt/source language: ${spec.sourceLanguage}')
      ..writeln('Learner level: ${spec.level}')
      ..writeln('Section: ${outline['name'] ?? request.title}')
      ..writeln('Unit id: $unitId')
      ..writeln('Lesson id (must stay): ${lessonOutline['id']}')
      ..writeln('Lesson name: ${lessonOutline['name']}')
      ..writeln('Template (must stay): ${lessonOutline['template']}')
      ..writeln()
      ..writeln('Target words for this lesson:')
      ..writeln(targetLines.isEmpty
          ? '- (none specified; use the section '
              'topic and the outlined words)'
          : targetLines.join('\n'))
      ..writeln()
      ..writeln(_pedagogyBlock(
          spec.level, lessonOutline['template']?.toString() ?? spec.template));

    if (spec.designBrief.trim().isNotEmpty) {
      buf
        ..writeln()
        ..writeln('Design intent: ${spec.designBrief.trim()}');
    }
    if (request.sourceContext.trim().isNotEmpty) {
      buf
        ..writeln()
        ..writeln('Learner evidence to target (reuse these exact items):')
        ..writeln(request.sourceContext.trim());
    }

    buf
      ..writeln()
      ..writeln('Allowed interaction runtimeTypes (TEXT ONLY — never emit '
          'listenAndPick, typeTheWord, listenOnly, ankiCard or ankiHtmlCard):')
      ..writeln('- showWord: {wordId, term, translation, context?} — inline '
          'term/translation are required; wordId must be defined in the '
          'outline words array.')
      ..writeln('- multipleChoice: {prompt, options (exactly 4, unique), '
          'correctIndex (0..3)}')
      ..writeln('- multiSelect: {prompt, options, correctIndices, '
          'minSelections?, maxSelections?}')
      ..writeln('- fillBlank: {sentence with one ____ blank, answer, hint?}')
      ..writeln('- translateSentence: {source (in ${spec.sourceLanguage}), '
          'expected (in ${spec.language}), hints?}')
      ..writeln('- reorderSentence: {scrambled (shuffled words), correct '
          '(correct word order)}')
      ..writeln('- readingMcq / readingTrueFalse / readingShortAnswer: reading '
          'comprehension items.')
      ..writeln()
      ..writeln('Hard rules:')
      ..writeln('1. Do not change the lesson id, template, or unit id.')
      ..writeln('2. Produce at least 4 graded items (6-10 preferred).')
      ..writeln('3. Every target word must recur in at least one non-showWord '
          'item.')
      ..writeln('4. Distractors must be plausible (same part of speech / '
          'length); never fill options with gibberish or placeholder text.')
      ..writeln('5. Use the canonical content shape for the template '
          '(mastery/practice/review → stages; if a different template is '
          'requested, follow its canonical shape).')
      ..writeln('6. Return the complete lesson JSON object only — no prose, no '
          'markdown fences.')
      ..writeln()
      ..writeln('Shape:')
      ..writeln('''
{
  "id": "${lessonOutline['id']}",
  "name": "${lessonOutline['name']}",
  "description": "",
  "type": "normal",
  "template": "${lessonOutline['template']}",
  "prerequisiteLessonIds": [],
  "content": {
    "stages": [
      {
        "id": "${lessonOutline['id']}-st1",
        "name": "Practice",
        "items": [
          { "runtimeType": "multipleChoice", "id": "${lessonOutline['id']}-q1", "prompt": "...", "options": ["...", "...", "...", "..."], "correctIndex": 0 }
        ]
      }
    ]
  }
}
''');
    return buf.toString();
  }

  static String repairPrompt(List<String> errors) {
    final shown = errors.take(8).map((e) => '- $e').join('\n');
    return 'The previous JSON failed validation:\n$shown\n\n'
        'Return the complete corrected JSON only. Do not explain.';
  }

  /// Whole-section adjustment of an existing generated draft.
  ///
  /// Used by the library's "调整这份练习" action. Ids/templates stay locked so
  /// the draft keeps the same structure the learner already saw; only content
  /// (and, when necessary, the top-level resources) changes.
  static String adjustPrompt({
    required Map<String, dynamic> section,
    required String instruction,
  }) {
    return 'You are editing an EXISTING Turna practice section. '
        'Apply the learner instruction to the whole section.\n\n'
        'Keep the section id, unit ids, lesson ids and templates unchanged. '
        'Keep the canonical content shape and the text-only interaction types '
        '(no listenAndPick / typeTheWord / listenOnly / ankiCard / '
        'ankiHtmlCard). Update words / expressions / grammarPoints so every '
        'reference stays defined.\n\n'
        'Instruction:\n${instruction.trim()}\n\n'
        'Current section JSON:\n${jsonEncode(section)}\n\n'
        'Return the complete corrected section JSON only. No prose, no '
        'markdown fences.';
  }

  static String outlineRepairPrompt(List<String> errors) {
    final shown = errors.take(8).map((e) => '- $e').join('\n');
    return 'The previous OUTLINE JSON failed validation:\n$shown\n\n'
        'Return the complete corrected outline JSON only. No lesson content.';
  }

  static String explanationPrompt({
    required AiPracticeRequest request,
    required Map<String, dynamic> section,
  }) {
    final spec = request.spec;
    return 'Explain this generated practice in plain ${spec.sourceLanguage}. '
        'Cover the learning goal, which weak items it drills, and how to use '
        'it. Do not output JSON.\n\n'
        'Section: ${section['name'] ?? request.title}\n'
        'Description: ${section['description'] ?? ''}\n'
        'Level: ${spec.level}\n'
        'Source: ${request.source.name}\n'
        '${request.sourceContext.trim()}';
  }

  /// Compact explanation of what the model may emit, mirroring the GUI's
  /// pedagogy block. Kept short: the full GUI block is ~2k tokens and this
  /// prompt already carries the learner evidence.
  static String _pedagogyBlock(String level, String template) {
    final upper = level.trim().toUpperCase();
    final levelLine = upper.startsWith('A1')
        ? 'A1: short sentences (3-8 words), present tense, recognition + '
            'light production.'
        : upper.startsWith('A2')
            ? 'A2: simple compound sentences, common tense contrasts, '
                'fill-blank / ordering / short translation.'
            : upper.startsWith('B1')
                ? 'B1: medium sentences with reason/condition clauses, '
                    'reading + multi-select + situational translation.'
                : 'B2: longer texts, abstract topics, register awareness, '
                    'inference questions.';
    final templateLine = switch (template) {
      'intro' => 'intro: showWord first, then light recognition; avoid heavy '
          'production.',
      'practice' => 'practice: mostly graded production (choice, blank, '
          'translate, order); recycle the lesson words.',
      'review' => 'review: recycle and contrast; introduce few new words.',
      'mastery' => 'mastery: mixed quiz covering the core words and patterns.',
      'listening' => 'listening: word pairing → dialogue → summary.',
      'reading' => 'reading: passage + comprehension questions; words should '
          'be guessable from context.',
      _ => 'mixed: mix recognition and production in a sensible gradient.',
    };
    return 'Pedagogy constraints (soft):\n$levelLine\n$templateLine\n'
        'Distractors: 4 unique options, one correct; same part of speech and '
        'similar length; no nonsense strings.';
  }

  /// Serialize a grounded resource list into the prompt block.
  static String groundedBlock(List<Map<String, dynamic>> resources) {
    final slim = [
      for (final r in resources.take(80))
        {
          'id': r['id'],
          'term': r['term'],
          'translation': r['translation'],
          '_kind': r['_kind'],
        }
    ];
    return jsonEncode(slim);
  }
}
