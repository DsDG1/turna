// Dart imports:
import 'dart:convert';

// Project imports:
import 'package:turna/application/ai/ai_genre.dart';
import 'package:turna/application/ai/practice/ai_practice_models.dart';
import 'package:turna/application/ai/practice/ai_practice_pedagogy.dart';
import 'package:turna/domain/ai/ai_course.dart';

/// Prompt blocks for AI practice / course generation.
///
/// Mirrors the semantics of tool-gui's authoring prompts
/// (`tool/gui/src/backend/ai/prompts.py`, `ai_phased.py`, `ai_pedagogy.py`)
/// without importing Python code: one section contract
/// (`docs/authoring/course-layout.md`), phased generation (outline → lesson
/// fill), design brief / resource grounding, and the full pedagogy block.
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
    final exampleTemplate = spec.template == 'mixed' ? 'intro' : spec.template;
    final buf = StringBuffer()
      ..writeln('Generate an OUTLINE JSON for a Turna course section.')
      ..writeln()
      ..writeln('Target language: ${spec.language}')
      ..writeln('Prompt/source language: ${spec.sourceLanguage}')
      ..writeln(
          'Topic / theme: ${spec.topic.isEmpty ? '(not specified)' : spec.topic}')
      ..writeln('Learner level: ${spec.level}')
      ..writeln(
          'Units: ${spec.unitCount}, each with ${spec.lessonsPerUnit} lessons.')
      ..writeln('Target questions per lesson: ~${spec.itemsPerLesson}');
    if (spec.template == 'mixed') {
      buf.writeln('Template: mixed — choose a sensible concrete template per '
          'lesson from intro / practice / review / reading / dialogue / guide '
          '/ mastery (NEVER emit "mixed" or "listening" as a lesson template).');
    } else {
      buf.writeln('Template for every lesson: ${spec.template} '
          '(${templateLabel(spec.template)})');
    }
    buf
      ..writeln()
      ..writeln(AiPracticePedagogy.fullBlock(
        level: spec.level,
        language: spec.language,
        template: spec.template,
      ))
      ..writeln();

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

    if (spec.focusItems.trim().isNotEmpty) {
      buf
        ..writeln()
        ..writeln('Required focus vocabulary / grammar points (must cover):')
        ..writeln(spec.focusItems.trim());
    }
    if (spec.preferredInteractionTypes.isNotEmpty) {
      buf
        ..writeln()
        ..writeln('Learner preferred interaction types: '
            '${spec.preferredInteractionTypes.join(', ')}');
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
          "template": "$exampleTemplate",
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
      ..writeln('4. Every lesson has a unique id and a concrete template from '
          '{intro, practice, review, reading, dialogue, guide, mastery} — '
          'never "mixed" or "listening".')
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
    bool compactForTruncation = false,
  }) {
    final spec = request.spec;
    final lessonId = lessonOutline['id']?.toString() ?? '${request.id}-l1';
    final lessonName = lessonOutline['name']?.toString() ?? lessonId;
    final template = lessonOutline['template']?.toString() ?? spec.template;

    final targetIds = <String>[
      for (final id in (lessonOutline['targetWordIds'] as List? ?? const []))
        id.toString(),
    ];
    final wordById = <String, Map<String, dynamic>>{
      for (final w in (outline['words'] as List? ?? const []))
        if (w is Map && w['id'] != null)
          w['id'].toString(): Map<String, dynamic>.from(w),
    };
    final targetLines = [
      for (final id in targetIds)
        wordById[id] == null
            ? '- $id'
            : '- $id: ${wordById[id]!['term']} = '
                '${wordById[id]!['translation']}',
    ];

    final desiredItems =
        compactForTruncation ? 5 : spec.itemsPerLesson.clamp(4, 18);

    final buf = StringBuffer()
      ..writeln('Fill the complete content of ONE lesson for a Turna course '
          'section.')
      ..writeln()
      ..writeln('Target language: ${spec.language}')
      ..writeln('Prompt/source language: ${spec.sourceLanguage}')
      ..writeln('Learner level: ${spec.level}')
      ..writeln('Section: ${outline['name'] ?? request.title}')
      ..writeln('Unit id: $unitId')
      ..writeln('Lesson id (must stay): $lessonId')
      ..writeln('Lesson name: $lessonName')
      ..writeln('Template (must stay): $template')
      ..writeln()
      ..writeln('Target words for this lesson:')
      ..writeln(targetLines.isEmpty
          ? '- (none specified; use the section '
              'topic and the outlined words)'
          : targetLines.join('\n'))
      ..writeln()
      ..writeln(AiPracticePedagogy.fullBlock(
        level: spec.level,
        language: spec.language,
        template: template,
      ));

    if (spec.focusItems.trim().isNotEmpty) {
      buf
        ..writeln()
        ..writeln('Focus items to reinforce: ${spec.focusItems.trim()}');
    }
    if (spec.preferredInteractionTypes.isNotEmpty && template != 'guide') {
      buf
        ..writeln()
        ..writeln('Preferred interaction types (prioritize these when '
            'compatible with $template): '
            '${spec.preferredInteractionTypes.join(', ')}');
    }
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
    if (compactForTruncation) {
      buf
        ..writeln()
        ..writeln('IMPORTANT: The previous response hit the output length '
            'limit. Keep stems concise and emit 4-6 high-quality items so '
            'the JSON closes cleanly.');
    }

    if (template != 'guide') {
      buf
        ..writeln()
        ..writeln('Allowed interaction runtimeTypes (TEXT ONLY — never emit '
            'listenAndPick, typeTheWord, listenOnly, dictation, imageRecall, '
            'ankiCard or ankiHtmlCard):')
        ..writeln('- showWord: {id, runtimeType, wordId, term, translation, '
            'context?} — wordId MUST exist in the outline words array.')
        ..writeln('- multipleChoice: {id, runtimeType, prompt, options (4 '
            'unique), correctIndex (0..3)}')
        ..writeln('- multiSelect: {id, runtimeType, prompt, options (3-5 '
            'unique), correctIndices, minSelections?, maxSelections?}')
        ..writeln('- fillBlank: {id, runtimeType, sentence (with one ____ '
            'blank), answer, hint?, choices?}')
        ..writeln('- translateSentence: {id, runtimeType, source (in '
            '${spec.sourceLanguage}), expected (in ${spec.language}), hints?}')
        ..writeln('- reorderSentence: {id, runtimeType, scrambled (shuffled '
            'tokens), correct (ordered tokens), prompt?}')
        ..writeln('- readingMcq / readingTrueFalse / readingShortAnswer: '
            'reading comprehension items.');
    } else {
      buf
        ..writeln()
        ..writeln('Allowed guide block runtimeTypes (UNGRADED — no stages, no '
            'items):')
        ..writeln('- text: {id, runtimeType: "text", title, body}')
        ..writeln('- terms: {id, runtimeType: "terms", title, items: '
            '[{text, translation, note}]}')
        ..writeln(
            '- classification: {id, runtimeType: "classification", title, '
            'categories: [{id, label, description}], cards: [{id, text, '
            'categoryId, hint}]}')
        ..writeln('- wordOrder: {id, runtimeType: "wordOrder", title, tokens: '
            '[{id, text, role, meaning, optional}], optionalToggleLabel?}');
    }

    buf
      ..writeln()
      ..writeln('Hard rules:')
      ..writeln('1. Do NOT change the lesson id ($lessonId) or template '
          '($template).');
    if (template == 'guide') {
      buf.writeln('2. Produce 2-4 concise pages; each page has non-empty '
          'title and 1-3 blocks. Never include stages or subLessons.');
    } else if (template == 'dialogue') {
      buf
        ..writeln('2. Emit dialogueScene (characters + alternating partner '
            'text turns & learner interactionId turns) AND stages.')
        ..writeln(
            '3. Every learner turn declares ONLY interactionId (no text); '
            'every partner turn declares ONLY text (no interactionId).')
        ..writeln(
            '4. Each interactionId must match a stage item in exact order '
            'using multipleChoice / multiSelect / fillBlank / '
            'translateSentence / reorderSentence ($desiredItems turns/items '
            'preferred, at least 4).');
    } else {
      buf
        ..writeln('2. Produce around $desiredItems items (at least 4 graded '
            'items).')
        ..writeln('3. Every target word should recur in at least one '
            'non-showWord exercise item.')
        ..writeln('4. Distractors must be plausible and unique; correctIndex '
            'must point to the single unambiguously right option.');
    }
    buf
      ..writeln('5. Follow the EXACT canonical content shape shown below for '
          'template "$template".')
      ..writeln('6. Return the complete lesson JSON object only — no prose, '
          'no markdown fences.')
      ..writeln()
      ..writeln('Canonical JSON shape for template "$template":')
      ..writeln(_lessonShapeExample(
        lessonId: lessonId,
        lessonName: lessonName,
        template: template,
      ));
    return buf.toString();
  }

  static String _lessonShapeExample({
    required String lessonId,
    required String lessonName,
    required String template,
  }) {
    final contentJson = switch (template) {
      'intro' => '''{
    "subLessons": [
      {
        "id": "$lessonId-sl1",
        "name": "New words & context",
        "stages": [
          {
            "id": "$lessonId-sl1-st1",
            "name": "Learn & produce",
            "items": [
              { "runtimeType": "showWord", "id": "$lessonId-q1", "wordId": "w-ai-...", "term": "...", "translation": "...", "context": "..." },
              { "runtimeType": "fillBlank", "id": "$lessonId-q2", "sentence": "____ ...", "answer": "...", "hint": "..." },
              { "runtimeType": "translateSentence", "id": "$lessonId-q3", "source": "...", "expected": "...", "hints": [] }
            ]
          }
        ]
      }
    ]
  }''',
      'practice' => '''{
    "subLessons": [
      {
        "id": "$lessonId-sl1",
        "name": "Practice",
        "stages": [
          {
            "id": "$lessonId-sl1-st1",
            "name": "Sentence drills",
            "items": [
              { "runtimeType": "fillBlank", "id": "$lessonId-q1", "sentence": "____ ...", "answer": "...", "hint": "..." },
              { "runtimeType": "reorderSentence", "id": "$lessonId-q2", "scrambled": ["b", "a"], "correct": ["a", "b"], "prompt": "..." },
              { "runtimeType": "translateSentence", "id": "$lessonId-q3", "source": "...", "expected": "...", "hints": [] }
            ]
          }
        ]
      }
    ]
  }''',
      'reading' => '''{
    "readingPassage": {
      "title": "...",
      "paragraphs": ["Paragraph 1 in target language.", "Paragraph 2 in target language."],
      "difficulty": 1,
      "linkedWordIds": [],
      "linkedExpressionIds": []
    },
    "stages": [
      {
        "id": "$lessonId-st1",
        "name": "Comprehension",
        "items": [
          { "runtimeType": "readingMcq", "id": "$lessonId-q1", "prompt": "...", "options": ["...", "...", "...", "..."], "correctIndex": 0 },
          { "runtimeType": "readingTrueFalse", "id": "$lessonId-q2", "statement": "...", "answer": true },
          { "runtimeType": "readingShortAnswer", "id": "$lessonId-q3", "prompt": "...", "expectedAnswer": "..." }
        ]
      }
    ]
  }''',
      'dialogue' => '''{
    "dialogueScene": {
      "id": "$lessonId-scene",
      "title": "$lessonName",
      "characters": [
        { "id": "partner", "name": "Partner" },
        { "id": "learner", "name": "You" }
      ],
      "turns": [
        { "id": "$lessonId-t1", "speakerId": "partner", "text": "..." },
        { "id": "$lessonId-t2", "speakerId": "learner", "interactionId": "$lessonId-q1" }
      ]
    },
    "stages": [
      {
        "id": "$lessonId-st1",
        "name": "Responses",
        "items": [
          { "runtimeType": "multipleChoice", "id": "$lessonId-q1", "prompt": "...", "options": ["...", "...", "...", "..."], "correctIndex": 0 }
        ]
      }
    ]
  }''',
      'guide' => '''{
    "pages": [
      {
        "id": "$lessonId-p1",
        "title": "...",
        "kicker": "",
        "intro": "...",
        "blocks": [
          { "runtimeType": "text", "id": "$lessonId-b1", "title": "...", "body": "..." },
          { "runtimeType": "terms", "id": "$lessonId-b2", "title": "...", "items": [{ "text": "...", "translation": "...", "note": "..." }] }
        ]
      }
    ]
  }''',
      _ => '''{
    "stages": [
      {
        "id": "$lessonId-st1",
        "name": "Practice",
        "items": [
          { "runtimeType": "multipleChoice", "id": "$lessonId-q1", "prompt": "...", "options": ["...", "...", "...", "..."], "correctIndex": 0 }
        ]
      }
    ]
  }''',
    };

    final lessonType = switch (template) {
      'reading' => 'reading',
      'dialogue' => 'dialogue',
      'review' => 'review',
      'mastery' => 'challenge',
      _ => 'normal',
    };

    return '''
{
  "id": "$lessonId",
  "name": "$lessonName",
  "description": "",
  "type": "$lessonType",
  "template": "$template",
  "prerequisiteLessonIds": [],
  "content": $contentJson
}
''';
  }

  static String repairPrompt(List<String> errors) {
    final shown = errors.take(8).map((e) => '- $e').join('\n');
    return 'The previous JSON failed validation:\n$shown\n\n'
        'Fix EVERY listed error and return the complete corrected JSON object '
        'only. No prose, no markdown fences.';
  }

  static String jsonSyntaxRepairPrompt(String errorMessage) {
    return 'The previous reply could not be parsed as valid JSON '
        '($errorMessage).\n\n'
        'Return ONLY one complete, valid JSON object with double-quoted keys '
        'and no trailing commas, no prose, and no markdown fences.';
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
        'Preserve each template\'s canonical content shape '
        '(intro/practice → subLessons, reading → readingPassage + stages, '
        'dialogue → dialogueScene + stages, guide → pages, mastery → single '
        'stage, review → stages) and text-only interaction types '
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

  static String fillNeedsReviewPrompt({
    required String language,
    required String sourceLanguage,
    required List<Map<String, dynamic>> entries,
  }) {
    return 'Complete the missing glosses/translations for these course '
        'glossary entries.\n'
        'Target language: $language; Gloss language: $sourceLanguage.\n'
        'Return ONLY JSON: {"entries":[{"id":"...","term":"...",'
        '"translation":"...","title":"...","explanation":"..."}]}.\n'
        'Keep every id unchanged; never leave translation/explanation empty.\n\n'
        '${jsonEncode({'entries': entries})}';
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
