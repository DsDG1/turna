// Dart imports:
import 'dart:convert';

// Project imports:
import 'package:turna/application/ai/ai_json_text.dart';

/// Deterministic, network-free JSON recovery and structural self-healing for
/// AI-generated course outlines and lessons.
///
/// Mirrors and extends `tool/gui/src/backend/ai/resource_fix.py` and the
/// rule-based pre-fix pass in `tool/gui/src/backend/ai_pipeline.py`: fixing
/// common LLM formatting slips deterministically before running the validator
/// prevents wasted repair calls and eliminates structural mismatches between
/// templates (`intro`/`practice` → `subLessons`, `mastery` → single `stage`,
/// `reading` → `readingPassage`, `dialogue` → `dialogueScene`, `guide` →
/// `pages`).
abstract final class AiPracticeNormalizer {
  /// Templates the in-app generator may emit. `listening` (needs pre-generated
  /// audio) and `legacy` (fallback only) are excluded.
  static const Set<String> allowedTemplates = {
    'intro',
    'practice',
    'review',
    'reading',
    'dialogue',
    'guide',
    'mastery',
  };

  /// Interaction types forbidden in AI-generated text practices (require
  /// pre-generated audio assets or imported deck metadata).
  static const Set<String> forbiddenInteractionTypes = {
    'listenAndPick',
    'typeTheWord',
    'listenOnly',
    'ankiCard',
    'ankiHtmlCard',
    'dictation',
    'imageRecall',
  };

  /// Interaction types valid as learner response turns in `dialogue` scenes.
  static const Set<String> dialogueResponseTypes = {
    'multipleChoice',
    'multiSelect',
    'fillBlank',
    'translateSentence',
    'reorderSentence',
  };

  /// Recover a JSON object from raw model output:
  ///   1. Strip `<think>...</think>` reasoning blocks (DeepSeek / MiMo).
  ///   2. Strip markdown code fences.
  ///   3. Direct `jsonDecode`.
  ///   4. Extract first balanced `{...}` object and retry.
  ///   5. Strip trailing commas before `}` / `]` and retry.
  ///
  /// Throws [FormatException] only if all recovery attempts fail.
  static Map<String, dynamic> decodeObject(String input) {
    var text = _stripThinkingBlocks(input);
    text = AiJsonText.stripCodeFences(text);
    final firstTry = _tryDecodeMap(text);
    if (firstTry != null) return firstTry;

    final balanced = _extractBalancedObject(text);
    if (balanced != null) {
      final decoded = _tryDecodeMap(balanced) ??
          _tryDecodeMap(_stripTrailingCommas(balanced));
      if (decoded != null) return decoded;
    }

    final noTrailing = _tryDecodeMap(_stripTrailingCommas(text));
    if (noTrailing != null) return noTrailing;

    // Preserve a clear FormatException for the caller's repair loop.
    final decoded = jsonDecode(balanced ?? text);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Model output is not a JSON object.');
    }
    return decoded;
  }

  static String _stripThinkingBlocks(String input) {
    return input
        .replaceAll(
          RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false),
          '',
        )
        .trim();
  }

  static Map<String, dynamic>? _tryDecodeMap(String candidate) {
    try {
      final decoded = jsonDecode(candidate);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } on FormatException {
      // Fall through to next recovery step.
    }
    return null;
  }

  /// Scan for the first balanced top-level `{...}` respecting string literals
  /// and escape sequences.
  static String? _extractBalancedObject(String text) {
    final start = text.indexOf('{');
    if (start < 0) return null;
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = start; i < text.length; i++) {
      final ch = text.codeUnitAt(i);
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (ch == 0x5C /* \ */) {
          escaped = true;
        } else if (ch == 0x22 /* " */) {
          inString = false;
        }
        continue;
      }
      if (ch == 0x22 /* " */) {
        inString = true;
      } else if (ch == 0x7B /* { */) {
        depth++;
      } else if (ch == 0x7D /* } */) {
        depth--;
        if (depth == 0) {
          return text.substring(start, i + 1);
        }
      }
    }
    // Fallback to outer slice if the object was slightly malformed.
    final last = text.lastIndexOf('}');
    if (last > start) return text.substring(start, last + 1);
    return null;
  }

  static String _stripTrailingCommas(String text) {
    return text.replaceAllMapped(
      RegExp(r',\s*([}\]])'),
      (match) => match.group(1)!,
    );
  }

  /// Deterministically normalize an outline before validation:
  ///   - ensures top-level `id`, `words`, `expressions`, `grammarPoints`, `units`;
  ///   - resolves `"mixed"` or missing lesson templates into valid concrete
  ///     templates (progression: intro → practice → reading/dialogue → mastery);
  ///   - ensures unique kebab-case unit/lesson ids;
  ///   - prunes dangling `targetWordIds` that were not defined in `words`.
  static Map<String, dynamic> normalizeOutline(
    Map<String, dynamic> raw, {
    required String fallbackSectionId,
    required String fallbackTitle,
    required String requestedTemplate,
  }) {
    final outline = Map<String, dynamic>.from(raw);
    if ((outline['id']?.toString().trim() ?? '').isEmpty) {
      outline['id'] = fallbackSectionId;
    }
    if ((outline['name']?.toString().trim() ?? '').isEmpty) {
      outline['name'] = fallbackTitle;
    }
    outline['description'] ??= '';

    final words = <Map<String, dynamic>>[];
    final wordIds = <String>{};
    if (outline['words'] is List) {
      for (var i = 0; i < (outline['words'] as List).length; i++) {
        final entry = (outline['words'] as List)[i];
        if (entry is! Map) continue;
        final w = Map<String, dynamic>.from(entry);
        var id = (w['id']?.toString().trim() ?? '');
        if (id.isEmpty) id = 'w-ai-${i + 1}';
        if (wordIds.contains(id)) id = '$id-${i + 1}';
        w['id'] = id;
        w['tags'] = w['tags'] is List
            ? List<dynamic>.from(w['tags'] as List)
            : <dynamic>[];
        wordIds.add(id);
        words.add(w);
      }
    }
    outline['words'] = words;
    outline['expressions'] = outline['expressions'] is List
        ? [
            for (final e in (outline['expressions'] as List))
              if (e is Map) Map<String, dynamic>.from(e),
          ]
        : <Map<String, dynamic>>[];
    outline['grammarPoints'] = outline['grammarPoints'] is List
        ? [
            for (final g in (outline['grammarPoints'] as List))
              if (g is Map) Map<String, dynamic>.from(g),
          ]
        : <Map<String, dynamic>>[];

    final rawUnits = outline['units'];
    if (rawUnits is! List) return outline;

    final sectionId = outline['id'].toString();
    final seenUnitIds = <String>{};
    final seenLessonIds = <String>{};
    final normalizedUnits = <Map<String, dynamic>>[];

    for (var u = 0; u < rawUnits.length; u++) {
      final rawUnit = rawUnits[u];
      if (rawUnit is! Map) continue;
      final unit = Map<String, dynamic>.from(rawUnit);
      var unitId = (unit['id']?.toString().trim() ?? '');
      if (unitId.isEmpty || !seenUnitIds.add(unitId)) {
        unitId = '$sectionId-u${u + 1}';
        seenUnitIds.add(unitId);
      }
      unit['id'] = unitId;
      unit['name'] = (unit['name']?.toString().trim().isNotEmpty == true)
          ? unit['name'].toString().trim()
          : '第 ${u + 1} 单元';

      final rawLessons = unit['lessons'];
      final normalizedLessons = <Map<String, dynamic>>[];
      if (rawLessons is List) {
        final count = rawLessons.length;
        for (var l = 0; l < count; l++) {
          final rawLesson = rawLessons[l];
          if (rawLesson is! Map) continue;
          final lesson = Map<String, dynamic>.from(rawLesson);
          var lessonId = (lesson['id']?.toString().trim() ?? '');
          if (lessonId.isEmpty || !seenLessonIds.add(lessonId)) {
            lessonId = '$unitId-l${l + 1}';
            seenLessonIds.add(lessonId);
          }
          lesson['id'] = lessonId;
          lesson['name'] =
              (lesson['name']?.toString().trim().isNotEmpty == true)
                  ? lesson['name'].toString().trim()
                  : '第 ${l + 1} 课';

          final rawTemplate = (lesson['template']?.toString().trim() ?? '');
          lesson['template'] = _resolveConcreteTemplate(
            rawTemplate: rawTemplate,
            requestedTemplate: requestedTemplate,
            lessonIndex: l,
            lessonCount: count,
          );

          final targets = <String>[
            for (final rawId in (lesson['targetWordIds'] as List? ?? const []))
              if (wordIds.contains(rawId.toString())) rawId.toString(),
          ];
          lesson['targetWordIds'] = targets;
          lesson['targetExpressionIds'] = lesson['targetExpressionIds'] is List
              ? List<dynamic>.from(lesson['targetExpressionIds'] as List)
              : <dynamic>[];
          lesson['targetGrammarPointIds'] =
              lesson['targetGrammarPointIds'] is List
                  ? List<dynamic>.from(lesson['targetGrammarPointIds'] as List)
                  : <dynamic>[];
          normalizedLessons.add(lesson);
        }
      }
      unit['lessons'] = normalizedLessons;
      normalizedUnits.add(unit);
    }
    outline['units'] = normalizedUnits;
    return outline;
  }

  static String _resolveConcreteTemplate({
    required String rawTemplate,
    required String requestedTemplate,
    required int lessonIndex,
    required int lessonCount,
  }) {
    if (allowedTemplates.contains(rawTemplate)) return rawTemplate;
    if (allowedTemplates.contains(requestedTemplate)) return requestedTemplate;
    // Mixed progression inside a unit.
    if (lessonCount <= 1) return 'mastery';
    if (lessonIndex == 0) return 'intro';
    if (lessonIndex == lessonCount - 1) return 'mastery';
    if (lessonCount >= 4 && lessonIndex == lessonCount - 2) return 'reading';
    return 'practice';
  }

  /// Build a structurally valid empty content shell matching [template].
  static Map<String, dynamic> emptyContentFor(String template) {
    return switch (template) {
      'intro' || 'practice' => {
          'subLessons': [
            {
              'id': 'sl-placeholder',
              'name': 'Part 1',
              'stages': [
                {
                  'id': 'st-placeholder',
                  'name': 'Practice',
                  'items': <dynamic>[]
                },
              ],
            },
          ],
        },
      'reading' => {
          'readingPassage': {
            'title': 'Reading',
            'paragraphs': const <String>[],
            'difficulty': 1,
            'linkedWordIds': const <String>[],
            'linkedExpressionIds': const <String>[],
          },
          'stages': [
            {
              'id': 'st-placeholder',
              'name': 'Comprehension',
              'items': <dynamic>[]
            },
          ],
        },
      'dialogue' => {
          'dialogueScene': {
            'id': 'scene-placeholder',
            'title': 'Dialogue',
            'characters': <dynamic>[],
            'turns': <dynamic>[],
          },
          'stages': [
            {'id': 'st-placeholder', 'name': 'Dialogue', 'items': <dynamic>[]},
          ],
        },
      'guide' => {
          'pages': <dynamic>[],
        },
      _ => {
          'stages': [
            {'id': 'st-placeholder', 'name': 'Practice', 'items': <dynamic>[]},
          ],
        },
    };
  }

  /// Normalize a generated lesson body to match [template]'s canonical
  /// `course_validator.dart` contract and self-heal common item-level slips.
  static Map<String, dynamic> normalizeLessonJson(
    Map<String, dynamic> lesson, {
    required String lessonId,
    required String template,
    Map<String, Map<String, dynamic>> outlineWordById = const {},
  }) {
    final fixed = Map<String, dynamic>.from(lesson);
    fixed['id'] = lessonId;
    fixed['template'] = template;
    fixed['name'] = (fixed['name']?.toString().trim().isNotEmpty == true)
        ? fixed['name'].toString().trim()
        : lessonId;
    fixed['description'] ??= '';
    fixed['prerequisiteLessonIds'] = fixed['prerequisiteLessonIds'] is List
        ? List<dynamic>.from(fixed['prerequisiteLessonIds'] as List)
        : const <String>[];
    fixed['type'] = _lessonTypeForTemplate(
      fixed['type']?.toString(),
      template,
    );

    final rawContent = fixed['content'];
    if (rawContent is! Map) {
      fixed['content'] = emptyContentFor(template);
      return fixed;
    }
    final content = Map<String, dynamic>.from(rawContent);
    fixed['content'] = content;

    // 1. Convert flat `questions` array into one stage if present.
    final questions = content['questions'];
    if (questions is List &&
        content['stages'] == null &&
        content['subLessons'] == null) {
      content['stages'] = [
        {
          'id': '$lessonId-st1',
          'name': 'Practice',
          'items': questions,
        },
      ];
      content.remove('questions');
    }

    // 2. Template-specific canonical content shape alignment.
    switch (template) {
      case 'guide':
        _normalizeGuideContent(content, lessonId: lessonId);
      case 'intro':
      case 'practice':
        _normalizeSubLessonContent(
          content,
          lessonId: lessonId,
          lessonName: fixed['name'].toString(),
          outlineWordById: outlineWordById,
        );
      case 'mastery':
        _normalizeMasteryContent(
          content,
          lessonId: lessonId,
          outlineWordById: outlineWordById,
        );
      case 'reading':
        _normalizeReadingContent(
          content,
          lessonId: lessonId,
          lessonName: fixed['name'].toString(),
          outlineWordById: outlineWordById,
        );
      case 'dialogue':
        _normalizeDialogueContent(
          content,
          lessonId: lessonId,
          lessonName: fixed['name'].toString(),
          outlineWordById: outlineWordById,
        );
      default:
        // review / fallback
        _normalizeReviewContent(
          content,
          lessonId: lessonId,
          outlineWordById: outlineWordById,
        );
    }

    return fixed;
  }

  static String _lessonTypeForTemplate(String? existing, String template) {
    const validTypes = {
      'normal',
      'listening',
      'dialogue',
      'reading',
      'review',
      'challenge',
    };
    if (existing != null && validTypes.contains(existing)) return existing;
    return switch (template) {
      'reading' => 'reading',
      'dialogue' => 'dialogue',
      'review' => 'review',
      'mastery' => 'challenge',
      _ => 'normal',
    };
  }

  static void _normalizeSubLessonContent(
    Map<String, dynamic> content, {
    required String lessonId,
    required String lessonName,
    required Map<String, Map<String, dynamic>> outlineWordById,
  }) {
    content.remove('pages');
    content.remove('reviewPolicy');
    var subLessons = _asMapList(content['subLessons']);
    if (subLessons.isEmpty) {
      final flatStages = _asMapList(content['stages']);
      if (flatStages.isNotEmpty) {
        subLessons = [
          {
            'id': '$lessonId-sl1',
            'name': lessonName,
            'stages': flatStages,
          },
        ];
      }
    }
    content.remove('stages');

    final seenSubIds = <String>{};
    final cleanedSubs = <Map<String, dynamic>>[];
    for (var s = 0; s < subLessons.length; s++) {
      final sub = Map<String, dynamic>.from(subLessons[s]);
      var subId = (sub['id']?.toString().trim() ?? '');
      if (subId.isEmpty || !seenSubIds.add(subId)) {
        subId = '$lessonId-sl${s + 1}';
        seenSubIds.add(subId);
      }
      sub['id'] = subId;
      sub['name'] = (sub['name']?.toString().trim().isNotEmpty == true)
          ? sub['name'].toString().trim()
          : 'Part ${s + 1}';
      final stages = _normalizeStagesList(
        _asMapList(sub['stages']),
        idPrefix: subId,
        outlineWordById: outlineWordById,
      );
      if (stages.isNotEmpty) {
        sub['stages'] = stages;
        cleanedSubs.add(sub);
      }
    }
    content['subLessons'] = cleanedSubs;
  }

  static void _normalizeMasteryContent(
    Map<String, dynamic> content, {
    required String lessonId,
    required Map<String, Map<String, dynamic>> outlineWordById,
  }) {
    content.remove('pages');
    content.remove('reviewPolicy');
    final allRawItems = <Map<String, dynamic>>[];
    for (final stage in _asMapList(content['stages'])) {
      allRawItems.addAll(_asMapList(stage['items']));
    }
    for (final sub in _asMapList(content['subLessons'])) {
      for (final stage in _asMapList(sub['stages'])) {
        allRawItems.addAll(_asMapList(stage['items']));
      }
    }
    content.remove('subLessons');
    final items = _normalizeItemsList(
      allRawItems,
      idPrefix: '$lessonId-st1',
      outlineWordById: outlineWordById,
    );
    content['stages'] = items.isEmpty
        ? <Map<String, dynamic>>[]
        : [
            {
              'id': '$lessonId-st1',
              'name': 'Quiz',
              'items': items,
            },
          ];
  }

  static void _normalizeReadingContent(
    Map<String, dynamic> content, {
    required String lessonId,
    required String lessonName,
    required Map<String, Map<String, dynamic>> outlineWordById,
  }) {
    content.remove('pages');
    content.remove('reviewPolicy');
    final rawPassage = content['readingPassage'];
    if (rawPassage is Map) {
      final passage = Map<String, dynamic>.from(rawPassage);
      passage['title'] =
          (passage['title']?.toString().trim().isNotEmpty == true)
              ? passage['title'].toString().trim()
              : lessonName;
      final rawParas = passage['paragraphs'];
      if (rawParas is String && rawParas.trim().isNotEmpty) {
        passage['paragraphs'] = rawParas
            .split(RegExp(r'\n\s*\n|\n'))
            .map((p) => p.trim())
            .where((p) => p.isNotEmpty)
            .toList();
      } else if (rawParas is List) {
        passage['paragraphs'] = [
          for (final p in rawParas)
            if (p != null && p.toString().trim().isNotEmpty)
              p.toString().trim(),
        ];
      } else {
        passage['paragraphs'] = <String>[];
      }
      final diff = passage['difficulty'];
      passage['difficulty'] = diff is int ? diff : int.tryParse('$diff') ?? 1;
      passage['linkedWordIds'] = passage['linkedWordIds'] is List
          ? [
              for (final w in (passage['linkedWordIds'] as List)) w.toString(),
            ]
          : <String>[];
      passage['linkedExpressionIds'] = passage['linkedExpressionIds'] is List
          ? [
              for (final e in (passage['linkedExpressionIds'] as List))
                e.toString(),
            ]
          : <String>[];
      content['readingPassage'] = passage;
    } else if (content['passage'] is String &&
        (content['passage'] as String).trim().isNotEmpty) {
      final paras = (content['passage'] as String)
          .split(RegExp(r'\n\s*\n|\n'))
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty)
          .toList();
      content['readingPassage'] = {
        'title': lessonName,
        'paragraphs': paras,
        'difficulty': 1,
        'linkedWordIds': <String>[],
        'linkedExpressionIds': <String>[],
      };
    }

    var stages = _asMapList(content['stages']);
    if (stages.isEmpty) {
      for (final sub in _asMapList(content['subLessons'])) {
        stages.addAll(_asMapList(sub['stages']));
      }
    }
    content.remove('subLessons');
    content['stages'] = _normalizeStagesList(
      stages,
      idPrefix: lessonId,
      outlineWordById: outlineWordById,
    );
  }

  static void _normalizeDialogueContent(
    Map<String, dynamic> content, {
    required String lessonId,
    required String lessonName,
    required Map<String, Map<String, dynamic>> outlineWordById,
  }) {
    content.remove('pages');
    content.remove('reviewPolicy');
    var stages = _asMapList(content['stages']);
    if (stages.isEmpty) {
      for (final sub in _asMapList(content['subLessons'])) {
        stages.addAll(_asMapList(sub['stages']));
      }
    }
    content.remove('subLessons');

    final normalizedStages = _normalizeStagesList(
      stages,
      idPrefix: lessonId,
      outlineWordById: outlineWordById,
      onlyDialogueResponses: true,
    );
    content['stages'] = normalizedStages;

    final rawScene = content['dialogueScene'];
    if (rawScene is! Map) return;
    final scene = Map<String, dynamic>.from(rawScene);
    if ((scene['id']?.toString().trim() ?? '').isEmpty) {
      scene['id'] = '$lessonId-scene';
    }
    if ((scene['title']?.toString().trim() ?? '').isEmpty) {
      scene['title'] = lessonName;
    }

    // Characters.
    final rawChars = _asMapList(scene['characters']);
    final charIds = <String>{};
    final chars = <Map<String, dynamic>>[];
    for (var i = 0; i < rawChars.length; i++) {
      final c = Map<String, dynamic>.from(rawChars[i]);
      var cid = (c['id']?.toString().trim() ?? '');
      if (cid.isEmpty || !charIds.add(cid)) {
        cid = 'char-${i + 1}';
        charIds.add(cid);
      }
      c['id'] = cid;
      c['name'] = (c['name']?.toString().trim().isNotEmpty == true)
          ? c['name'].toString().trim()
          : cid;
      chars.add(c);
    }
    if (chars.isEmpty) {
      chars.add({'id': 'partner', 'name': '对方'});
      chars.add({'id': 'learner', 'name': '你'});
      charIds
        ..add('partner')
        ..add('learner');
    } else if (!charIds.contains('learner')) {
      chars.add({'id': 'learner', 'name': '你'});
      charIds.add('learner');
    }
    scene['characters'] = chars;

    // Collect items by id in stage order.
    final orderedItems = <Map<String, dynamic>>[
      for (final st in normalizedStages) ..._asMapList(st['items']),
    ];
    final itemById = <String, Map<String, dynamic>>{
      for (final item in orderedItems) item['id'].toString(): item,
    };

    // Normalize turns: enforce mutually exclusive text vs interactionId, valid
    // speakerId, unique turn ids, and unique valid interactionIds.
    final rawTurns = _asMapList(scene['turns']);
    final seenTurnIds = <String>{};
    final referencedIds = <String>[];
    final turns = <Map<String, dynamic>>[];
    final fallbackPartnerId = chars.first['id'].toString();
    final fallbackLearnerId =
        charIds.contains('learner') ? 'learner' : chars.last['id'].toString();

    for (var i = 0; i < rawTurns.length; i++) {
      final t = Map<String, dynamic>.from(rawTurns[i]);
      var tid = (t['id']?.toString().trim() ?? '');
      if (tid.isEmpty || !seenTurnIds.add(tid)) {
        tid = '$lessonId-t${i + 1}';
        seenTurnIds.add(tid);
      }
      t['id'] = tid;
      final iid = (t['interactionId']?.toString().trim() ?? '');
      final text = (t['text']?.toString().trim() ?? '');
      if (iid.isNotEmpty &&
          itemById.containsKey(iid) &&
          !referencedIds.contains(iid)) {
        t.remove('text');
        t['interactionId'] = iid;
        if (!charIds.contains(t['speakerId']?.toString())) {
          t['speakerId'] = fallbackLearnerId;
        }
        referencedIds.add(iid);
        turns.add(t);
      } else if (text.isNotEmpty) {
        t.remove('interactionId');
        t['text'] = text;
        if (!charIds.contains(t['speakerId']?.toString())) {
          t['speakerId'] = fallbackPartnerId;
        }
        turns.add(t);
      }
    }

    // Reorder stage items to match turn reference order, and append turns for
    // any unreferenced stage items so validator's 1-to-1 order invariant holds.
    final reorderedItems = <Map<String, dynamic>>[
      for (final id in referencedIds) itemById[id]!,
    ];
    for (final item in orderedItems) {
      final id = item['id'].toString();
      if (!referencedIds.contains(id)) {
        reorderedItems.add(item);
        var tid = '$lessonId-t${turns.length + 1}';
        while (!seenTurnIds.add(tid)) {
          tid = '$tid-x';
        }
        turns.add({
          'id': tid,
          'speakerId': fallbackLearnerId,
          'interactionId': id,
        });
      }
    }
    scene['turns'] = turns;
    content['dialogueScene'] = scene;
    content['stages'] = reorderedItems.isEmpty
        ? <Map<String, dynamic>>[]
        : [
            {
              'id': '$lessonId-st1',
              'name': 'Dialogue',
              'items': reorderedItems,
            },
          ];
  }

  static void _normalizeGuideContent(
    Map<String, dynamic> content, {
    required String lessonId,
  }) {
    content.remove('stages');
    content.remove('subLessons');
    content.remove('listeningPhases');
    content.remove('reviewPolicy');
    final rawPages = _asMapList(content['pages']);
    final seenPageIds = <String>{};
    final seenBlockIds = <String>{};
    final pages = <Map<String, dynamic>>[];

    for (var p = 0; p < rawPages.length; p++) {
      final page = Map<String, dynamic>.from(rawPages[p]);
      var pid = (page['id']?.toString().trim() ?? '');
      if (pid.isEmpty || !seenPageIds.add(pid)) {
        pid = '$lessonId-p${p + 1}';
        seenPageIds.add(pid);
      }
      page['id'] = pid;
      page['title'] = (page['title']?.toString().trim().isNotEmpty == true)
          ? page['title'].toString().trim()
          : '第 ${p + 1} 页';
      page['kicker'] ??= '';
      page['intro'] ??= '';
      if (page['nextSubLessonId'] != null && page['nextLessonId'] == null) {
        page.remove('nextSubLessonId');
      }

      final rawBlocks = _asMapList(page['blocks']);
      final blocks = <Map<String, dynamic>>[];
      for (var b = 0; b < rawBlocks.length; b++) {
        final block = Map<String, dynamic>.from(rawBlocks[b]);
        final rt = block['runtimeType']?.toString() ?? '';
        if (rt.isEmpty) continue;
        var bid = (block['id']?.toString().trim() ?? '');
        if (bid.isEmpty || !seenBlockIds.add(bid)) {
          bid = '$pid-b${b + 1}';
          seenBlockIds.add(bid);
        }
        block['id'] = bid;
        if (rt == 'wordOrder') {
          final tokens = _asMapList(block['tokens']);
          final hasOptional = tokens.any((t) => t['optional'] == true);
          if (hasOptional &&
              (block['optionalToggleLabel']?.toString().trim() ?? '').isEmpty) {
            block['optionalToggleLabel'] = '显示/隐藏可选成分';
          }
          for (var t = 0; t < tokens.length; t++) {
            final tok = Map<String, dynamic>.from(tokens[t]);
            if ((tok['id']?.toString().trim() ?? '').isEmpty) {
              tok['id'] = '$bid-tok${t + 1}';
            }
            tokens[t] = tok;
          }
          block['tokens'] = tokens;
        }
        blocks.add(block);
      }
      if (blocks.isEmpty) {
        final fallbackBody =
            (page['body'] ?? page['text'] ?? page['intro'] ?? '')
                .toString()
                .trim();
        if (fallbackBody.isNotEmpty) {
          var bid = '$pid-b1';
          while (!seenBlockIds.add(bid)) {
            bid = '$bid-x';
          }
          blocks.add({
            'id': bid,
            'runtimeType': 'callout',
            'title': page['title'],
            'body': fallbackBody,
          });
          page.remove('body');
          page.remove('text');
        }
      }
      if (blocks.isNotEmpty) {
        page['blocks'] = blocks;
        pages.add(page);
      }
    }
    content['pages'] = pages;
  }

  static void _normalizeReviewContent(
    Map<String, dynamic> content, {
    required String lessonId,
    required Map<String, Map<String, dynamic>> outlineWordById,
  }) {
    content.remove('pages');
    final hasSubLessons = _asMapList(content['subLessons']).isNotEmpty;
    if (hasSubLessons && content['reviewPolicy'] == null) {
      _normalizeSubLessonContent(
        content,
        lessonId: lessonId,
        lessonName: 'Review',
        outlineWordById: outlineWordById,
      );
      return;
    }
    // Flat stages (preferred for review).
    var stages = _asMapList(content['stages']);
    if (stages.isEmpty && hasSubLessons) {
      for (final sub in _asMapList(content['subLessons'])) {
        stages.addAll(_asMapList(sub['stages']));
      }
    }
    content.remove('subLessons');
    final normalized = _normalizeStagesList(
      stages,
      idPrefix: lessonId,
      outlineWordById: outlineWordById,
    );
    content['stages'] = normalized;
    if (content['reviewPolicy'] != null) {
      // Remove reviewPolicy if pool contains non-gradable items or exceeds pool.
      final pool = <Map<String, dynamic>>[
        for (final s in normalized) ..._asMapList(s['items']),
      ];
      final allGradable = pool.every(
        (item) => dialogueResponseTypes.contains(item['runtimeType']),
      );
      if (!allGradable || pool.isEmpty) {
        content.remove('reviewPolicy');
      } else if (content['reviewPolicy'] is Map) {
        final policy =
            Map<String, dynamic>.from(content['reviewPolicy'] as Map);
        var minItems = int.tryParse('${policy['minItems']}') ?? pool.length;
        var maxItems = int.tryParse('${policy['maxItems']}') ?? pool.length;
        if (maxItems > pool.length) maxItems = pool.length;
        if (minItems < 1) minItems = 1;
        if (minItems > maxItems) minItems = maxItems;
        policy['minItems'] = minItems;
        policy['maxItems'] = maxItems;
        content['reviewPolicy'] = policy;
      }
    }
  }

  static List<Map<String, dynamic>> _normalizeStagesList(
    List<Map<String, dynamic>> rawStages, {
    required String idPrefix,
    required Map<String, Map<String, dynamic>> outlineWordById,
    bool onlyDialogueResponses = false,
  }) {
    final seenStageIds = <String>{};
    final out = <Map<String, dynamic>>[];
    for (var s = 0; s < rawStages.length; s++) {
      final stage = Map<String, dynamic>.from(rawStages[s]);
      var stageId = (stage['id']?.toString().trim() ?? '');
      if (stageId.isEmpty || !seenStageIds.add(stageId)) {
        stageId = '$idPrefix-st${s + 1}';
        seenStageIds.add(stageId);
      }
      stage['id'] = stageId;
      stage['name'] = (stage['name']?.toString().trim().isNotEmpty == true)
          ? stage['name'].toString().trim()
          : 'Stage ${s + 1}';
      final items = _normalizeItemsList(
        _asMapList(stage['items']),
        idPrefix: stageId,
        outlineWordById: outlineWordById,
        onlyDialogueResponses: onlyDialogueResponses,
      );
      if (items.isNotEmpty) {
        stage['items'] = items;
        out.add(stage);
      }
    }
    return out;
  }

  static List<Map<String, dynamic>> _normalizeItemsList(
    List<Map<String, dynamic>> rawItems, {
    required String idPrefix,
    required Map<String, Map<String, dynamic>> outlineWordById,
    bool onlyDialogueResponses = false,
  }) {
    final seenItemIds = <String>{};
    final out = <Map<String, dynamic>>[];
    for (var i = 0; i < rawItems.length; i++) {
      final item = Map<String, dynamic>.from(rawItems[i]);
      final rt = item['runtimeType']?.toString().trim() ?? '';
      if (rt.isEmpty || forbiddenInteractionTypes.contains(rt)) continue;
      if (onlyDialogueResponses && !dialogueResponseTypes.contains(rt)) {
        continue;
      }
      var itemId = (item['id']?.toString().trim() ?? '');
      if (itemId.isEmpty || !seenItemIds.add(itemId)) {
        itemId = '$idPrefix-q${i + 1}';
        seenItemIds.add(itemId);
      }
      item['id'] = itemId;
      item['runtimeType'] = rt;

      switch (rt) {
        case 'showWord':
          _normalizeShowWord(item, outlineWordById);
        case 'multipleChoice':
        case 'readingMcq':
          _normalizeSingleChoice(item);
        case 'multiSelect':
          _normalizeMultiSelect(item);
        case 'fillBlank':
          _normalizeFillBlank(item);
        case 'reorderSentence':
          _normalizeReorder(item);
        case 'translateSentence':
          _normalizeTranslateSentence(item);
        case 'readingTrueFalse':
          _normalizeTrueFalse(item);
      }
      out.add(item);
    }
    return out;
  }

  static void _normalizeTranslateSentence(Map<String, dynamic> item) {
    if ((item['source']?.toString().trim() ?? '').isEmpty) {
      final alias =
          (item['prompt'] ?? item['sentence'] ?? '').toString().trim();
      if (alias.isNotEmpty) item['source'] = alias;
    }
    if ((item['expected']?.toString().trim() ?? '').isEmpty) {
      final alias = (item['correctAnswer'] ??
              item['answer'] ??
              item['target'] ??
              item['translation'] ??
              '')
          .toString()
          .trim();
      if (alias.isNotEmpty) item['expected'] = alias;
    }
  }

  static void _normalizeShowWord(
    Map<String, dynamic> item,
    Map<String, Map<String, dynamic>> outlineWordById,
  ) {
    final wid = item['wordId']?.toString().trim() ?? '';
    final def = outlineWordById[wid];
    if (def != null) {
      if ((item['term']?.toString().trim() ?? '').isEmpty &&
          def['term'] != null) {
        item['term'] = def['term'];
      }
      if ((item['translation']?.toString().trim() ?? '').isEmpty &&
          def['translation'] != null) {
        item['translation'] = def['translation'];
      }
    }
  }

  static void _normalizeSingleChoice(Map<String, dynamic> item) {
    final rawOptions = item['options'];
    if (rawOptions is! List) return;
    final options = [
      for (final o in rawOptions) (o?.toString() ?? '').trim(),
    ];
    final rawIndex = item['correctIndex'];
    var correctIdx = rawIndex is int ? rawIndex : int.tryParse('$rawIndex');
    if (correctIdx != null && correctIdx >= 0 && correctIdx < options.length) {
      final correctValue = options[correctIdx];
      final deduped = <String>[];
      final seen = <String>{};
      var nextCorrectIdx = 0;
      for (var i = 0; i < options.length; i++) {
        final opt = options[i];
        if (opt.isEmpty) continue;
        final key = opt.toLowerCase();
        if (!seen.add(key)) continue;
        if (i == correctIdx || opt == correctValue) {
          nextCorrectIdx = deduped.length;
        }
        deduped.add(opt);
      }
      item['options'] = deduped;
      item['correctIndex'] = nextCorrectIdx;
    } else {
      item['options'] = options;
      if (correctIdx != null) item['correctIndex'] = correctIdx;
    }
  }

  static void _normalizeMultiSelect(Map<String, dynamic> item) {
    final rawOptions = item['options'];
    if (rawOptions is List) {
      item['options'] = [
        for (final o in rawOptions) (o?.toString() ?? '').trim(),
      ];
    }
    final rawIndices = item['correctIndices'];
    if (rawIndices is List) {
      final parsed = <int>[];
      for (final v in rawIndices) {
        final idx = v is int ? v : int.tryParse('$v');
        if (idx != null && !parsed.contains(idx)) parsed.add(idx);
      }
      item['correctIndices'] = parsed;
    }
  }

  static void _normalizeFillBlank(Map<String, dynamic> item) {
    final sentence = item['sentence']?.toString() ?? '';
    if (sentence.isNotEmpty && !sentence.contains('____')) {
      final replaced = sentence
          .replaceFirst(RegExp(r'_{1,3}'), '____')
          .replaceFirst(
            RegExp(r'\[blank\]|\(blank\)|（\s*）|\(\s+\)', caseSensitive: false),
            '____',
          );
      item['sentence'] = replaced;
    }
  }

  static void _normalizeReorder(Map<String, dynamic> item) {
    final correct = _asStringList(item['correct']);
    var scrambled = _asStringList(item['scrambled']);
    if (correct.isEmpty) return;
    item['correct'] = correct;
    if (scrambled.isEmpty) {
      scrambled = List<String>.from(correct);
    }
    if (correct.length >= 2 && _sameList(scrambled, correct)) {
      // Deterministic non-identity rotation/swap so the learner actually has
      // to reorder the tokens.
      final rotated = <String>[
        ...correct.sublist(1),
        correct.first,
      ];
      if (_sameList(rotated, correct) && correct.length >= 2) {
        final swapped = List<String>.from(correct);
        final tmp = swapped[0];
        swapped[0] = swapped[swapped.length - 1];
        swapped[swapped.length - 1] = tmp;
        item['scrambled'] = swapped;
      } else {
        item['scrambled'] = rotated;
      }
    } else {
      item['scrambled'] = scrambled;
    }
  }

  static void _normalizeTrueFalse(Map<String, dynamic> item) {
    final raw = item['answer'];
    if (raw is bool) return;
    final lower = raw?.toString().trim().toLowerCase() ?? '';
    if (lower == 'true' || lower == 'yes' || lower == '1') {
      item['answer'] = true;
    } else if (lower == 'false' || lower == 'no' || lower == '0') {
      item['answer'] = false;
    }
  }

  static List<Map<String, dynamic>> _asMapList(dynamic value) {
    if (value is! List) return const <Map<String, dynamic>>[];
    return [
      for (final e in value)
        if (e is Map) Map<String, dynamic>.from(e),
    ];
  }

  static List<String> _asStringList(dynamic value) {
    if (value is! List) return const <String>[];
    return [
      for (final e in value)
        if (e != null && e.toString().trim().isNotEmpty) e.toString().trim(),
    ];
  }

  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
