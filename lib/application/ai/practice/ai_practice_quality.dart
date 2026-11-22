// Dart imports:
import 'dart:convert';

/// Verification of AI-generated practice content.
///
/// The structural validator (`CourseValidator`) only enforces the *contract*
/// (ids resolve, templates are known, references exist). It says nothing about
/// whether a question is answerable — a choice item with two identical options,
/// a `correctIndex` past the end of the list, a fill-in-the-blank whose answer
/// never appears, or a lesson whose stages are empty all pass it. Those are the
/// failures a learner actually hits, and they are exactly what the model gets
/// wrong when it is rushed.
///
/// Two levels, deliberately:
/// - **blocking** — the content is broken (unplayable or unanswerable). The
///   generator repairs once, then fails the job. Never stored as ready.
/// - **advisory** — quality smells (short stages, repeated stems, non-4 option
///   counts). Recorded in the version report and shown in the library detail
///   page, never used to block. Grading generated content on style would make
///   the feature reject perfectly usable drills.
abstract final class AiPracticeQualityChecker {
  /// Text that means the model left a hole instead of content.
  static final RegExp _placeholder = RegExp(
    r'(TODO|待补|待填写|待生成|PLACEHOLDER|__TODO__)',
    caseSensitive: false,
  );

  /// Analyze one section JSON (canonical shape from
  /// `docs/authoring/course-layout.md`).
  ///
  /// [wordCoverage] is only meaningful for a whole section: the generator also
  /// checks single lessons mid-flight, and there every outline word except the
  /// lesson's own would look unused.
  static AiPracticeQualityReport check(
    Map<String, dynamic> section, {
    bool wordCoverage = true,
  }) {
    final issues = <AiPracticeQualityIssue>[];
    final words = _listOf(section['words']);
    final showsUsed = <String>{};
    final corpus = StringBuffer();
    final lessons = _iterLessons(section);

    if (lessons.isEmpty) {
      issues.add(const AiPracticeQualityIssue(
        code: 'section.no-lessons',
        where: 'section',
        message: '整节没有任何课时。',
      ));
    }

    for (final entry in lessons) {
      _checkLesson(entry, issues, showsUsed, corpus);
    }

    // Vocabulary coverage across showWord AND all exercise/passage/guide text.
    // Advisory (not blocking): a review/mastery drill or a large section may
    // legitimately leave one outline word unmentioned without being unplayable.
    if (wordCoverage) {
      final corpusLower = corpus.toString().toLowerCase();
      for (final word in words) {
        if (word is! Map) continue;
        final id = (word['id'] ?? '').toString();
        if (id.isEmpty) continue;
        final term = (word['term'] ?? '').toString().trim().toLowerCase();
        final seenByShowWord = showsUsed.contains(id);
        final seenByText = term.isNotEmpty && corpusLower.contains(term);
        if (!seenByShowWord && !seenByText) {
          issues.add(AiPracticeQualityIssue(
            code: 'word.unused',
            where: 'word:$id',
            message: '生词「${word['term'] ?? id}」未在课时练习中出现。',
            advisory: true,
          ));
        }
      }
    }

    return AiPracticeQualityReport(issues: issues);
  }

  static void _checkLesson(
    _LessonRef lesson,
    List<AiPracticeQualityIssue> issues,
    Set<String> showsUsed,
    StringBuffer corpus,
  ) {
    final content = lesson.lesson['content'];
    final where = 'lesson:${lesson.id}';
    if (content is! Map) {
      issues.add(AiPracticeQualityIssue(
        code: 'lesson.no-content',
        where: where,
        message: '课时「${lesson.name}」没有内容。',
      ));
      return;
    }
    final template = lesson.lesson['template']?.toString() ?? '';

    if (template == 'guide') {
      final pages = _listOf(content['pages']);
      if (pages.isEmpty) {
        issues.add(AiPracticeQualityIssue(
          code: 'guide.no-pages',
          where: where,
          message: '导览课「${lesson.name}」没有页面。',
        ));
        return;
      }
      for (var p = 0; p < pages.length; p++) {
        final page = pages[p];
        if (page is! Map) continue;
        final blocks = _listOf(page['blocks']);
        if (blocks.isEmpty) {
          issues.add(AiPracticeQualityIssue(
            code: 'guide.empty-page',
            where: '$where/p$p',
            message: '导览课「${lesson.name}」第 ${p + 1} 页没有任何内容块。',
          ));
        }
        corpus
          ..write(' ')
          ..write(page['title'] ?? '')
          ..write(' ')
          ..write(page['intro'] ?? '');
        for (final block in blocks) {
          if (block is! Map) continue;
          corpus
            ..write(' ')
            ..write(jsonEncode(block));
        }
      }
      return;
    }

    if (template == 'reading') {
      final passage = content['readingPassage'];
      final paragraphs =
          passage is Map ? _stringsOf(passage['paragraphs']) : null;
      if (paragraphs == null || paragraphs.isEmpty) {
        issues.add(AiPracticeQualityIssue(
          code: 'reading.no-passage',
          where: where,
          message: '阅读课「${lesson.name}」没有正文段落。',
        ));
      } else {
        for (final para in paragraphs) {
          corpus
            ..write(' ')
            ..write(para);
        }
      }
    }

    if (template == 'dialogue') {
      final scene = content['dialogueScene'];
      final turns = scene is Map ? _listOf(scene['turns']) : const [];
      if (scene is! Map || turns.isEmpty) {
        issues.add(AiPracticeQualityIssue(
          code: 'dialogue.no-scene',
          where: where,
          message: '情景对话课「${lesson.name}」缺少对话轮次。',
        ));
      } else {
        for (final turn in turns) {
          if (turn is Map && turn['text'] != null) {
            corpus
              ..write(' ')
              ..write(turn['text']);
          }
        }
      }
    }

    // Collect stages from both flat `content.stages` AND `content.subLessons[].stages`
    // (intro / practice lessons author canonical `subLessons`).
    final stages = <Map>[];
    for (final st in _listOf(content['stages'])) {
      if (st is Map) stages.add(st);
    }
    for (final sub in _listOf(content['subLessons'])) {
      if (sub is! Map) continue;
      for (final st in _listOf(sub['stages'])) {
        if (st is Map) stages.add(st);
      }
    }
    if (stages.isEmpty) {
      issues.add(AiPracticeQualityIssue(
        code: 'lesson.no-stages',
        where: where,
        message: '课时「${lesson.name}」没有练习阶段。',
      ));
      return;
    }

    var itemCount = 0;
    final stems = <String>{};
    for (var s = 0; s < stages.length; s++) {
      final stage = stages[s];
      final stageName = stage['id']?.toString() ?? 'stage$s';
      final items = _listOf(stage['items']);
      if (items.isEmpty) {
        issues.add(AiPracticeQualityIssue(
          code: 'stage.empty',
          where: '$where/$stageName',
          message: '课时「${lesson.name}」的阶段 $stageName 是空的。',
        ));
        continue;
      }
      if (items.length < 3) {
        issues.add(AiPracticeQualityIssue(
          code: 'stage.short',
          where: '$where/$stageName',
          message: '课时「${lesson.name}」的阶段 $stageName 只有 ${items.length} 道题。',
          advisory: true,
        ));
      }
      for (var i = 0; i < items.length; i++) {
        final item = items[i];
        if (item is! Map) {
          issues.add(AiPracticeQualityIssue(
            code: 'item.not-object',
            where: '$where/$stageName#$i',
            message: '课时「${lesson.name}」存在无法解析的题目。',
          ));
          continue;
        }
        itemCount++;
        _appendItemCorpus(item, corpus);
        _checkItem(
          item,
          where: '$where/$stageName#$i',
          issues: issues,
          showsUsed: showsUsed,
          stems: stems,
        );
      }
    }

    if (itemCount == 0) {
      issues.add(AiPracticeQualityIssue(
        code: 'lesson.no-items',
        where: where,
        message: '课时「${lesson.name}」没有任何题目。',
      ));
    }
  }

  static void _appendItemCorpus(Map item, StringBuffer corpus) {
    for (final key in const [
      'term',
      'translation',
      'context',
      'prompt',
      'sentence',
      'answer',
      'source',
      'expected',
      'statement',
      'expectedAnswer',
    ]) {
      final val = item[key];
      if (val is String && val.isNotEmpty) {
        corpus
          ..write(' ')
          ..write(val);
      }
    }
    for (final listKey in const ['options', 'correct', 'scrambled']) {
      final list = item[listKey];
      if (list is List) {
        for (final entry in list) {
          if (entry != null) {
            corpus
              ..write(' ')
              ..write(entry);
          }
        }
      }
    }
  }

  static void _checkItem(
    Map item, {
    required String where,
    required List<AiPracticeQualityIssue> issues,
    required Set<String> showsUsed,
    required Set<String> stems,
  }) {
    final type = item['runtimeType']?.toString() ?? '';

    void block(String code, String message) => issues.add(
          AiPracticeQualityIssue(code: code, where: where, message: message),
        );
    void advise(String code, String message) => issues.add(
          AiPracticeQualityIssue(
            code: code,
            where: where,
            message: message,
            advisory: true,
          ),
        );

    void checkText(dynamic value, String field) {
      final text = value?.toString() ?? '';
      if (text.trim().isEmpty) {
        block('item.empty-$field', '题目缺少 $field。');
        return;
      }
      if (_placeholder.hasMatch(text)) {
        block('item.placeholder', '题目里有未填写的占位文本（$field）。');
      }
    }

    switch (type) {
      case 'showWord':
        final wordId = item['wordId']?.toString() ?? '';
        if (wordId.isEmpty) {
          block('item.empty-word', '展示卡片没有关联生词。');
        } else {
          showsUsed.add(wordId);
        }
      case 'multipleChoice':
      case 'readingMcq':
      case 'listenAndPick':
        checkText(item['prompt'], 'prompt');
        _checkChoices(
          item,
          where: where,
          issues: issues,
          block: block,
          advise: advise,
        );
        final prompt = item['prompt']?.toString().trim() ?? '';
        if (prompt.isNotEmpty && !stems.add(prompt)) {
          advise('item.duplicate-prompt', '同一课时里出现重复题干：$prompt');
        }
      case 'multiSelect':
        checkText(item['prompt'], 'prompt');
        final options = _stringsOf(item['options']) ?? const <String>[];
        if (options.length < 3) {
          block('item.too-few-options', '多选题只有 ${options.length} 个选项。');
        }
        if (_hasDuplicates(options)) {
          block('item.duplicate-options', '多选题存在完全相同的选项。');
        }
        final indices = _listOf(item['correctIndices'])
            .map((value) => value is int ? value : int.tryParse('$value'))
            .toList();
        if (indices.isEmpty || indices.any((index) => index == null)) {
          block('item.empty-answer', '多选题没有正确答案。');
        } else if (indices
            .any((index) => index! < 0 || index >= options.length)) {
          block('item.bad-index', '多选题的正确答案下标越界。');
        }
      case 'fillBlank':
        checkText(item['sentence'], 'sentence');
        checkText(item['answer'], 'answer');
        final sentence = item['sentence']?.toString() ?? '';
        final answer = item['answer']?.toString().trim() ?? '';
        if (sentence.isNotEmpty && !sentence.contains('___')) {
          block('fillBlank.no-blank', '填空题的句子里没有空格占位（___）。');
        }
        if (sentence.isNotEmpty &&
            answer.isNotEmpty &&
            !sentence.toLowerCase().replaceAll('_', ' ').contains(
                  answer.toLowerCase(),
                )) {
          // Agglutinative target languages legitimately change the surface
          // form (Turkish suffixation), so this is a smell, not a defect.
          advise('fillBlank.answer-not-in-sentence', '答案「$answer」没有原样出现在句子里。');
        }
      case 'reorderSentence':
        final scrambled = _stringsOf(item['scrambled']) ?? const <String>[];
        final correct = _stringsOf(item['correct']) ?? const <String>[];
        if (correct.isEmpty) {
          block('reorder.empty-answer', '排序题没有目标句子。');
        } else if (scrambled.isEmpty) {
          block('reorder.empty-tokens', '排序题没有可拖动的词块。');
        } else if (!_sameMultiset(scrambled, correct)) {
          block('reorder.token-mismatch', '排序题的词块与目标句子不一致。');
        } else if (scrambled.join(' ') == correct.join(' ')) {
          advise('reorder.not-scrambled', '排序题的词块顺序与答案相同，等于没打乱。');
        }
      case 'translateSentence':
        checkText(item['source'], 'source');
        checkText(item['expected'], 'expected');
      case 'readingTrueFalse':
        checkText(item['statement'], 'statement');
        if (item['answer'] is! bool) {
          block('readingTrueFalse.no-answer', '判断题没有布尔答案。');
        }
      case 'readingShortAnswer':
        checkText(item['prompt'], 'prompt');
        checkText(item['expectedAnswer'], 'expectedAnswer');
      case 'typeTheWord':
        checkText(item['expected'], 'expected');
      case 'listenOnly':
        break;
      default:
        if (type.isEmpty) {
          block('item.no-type', '题目缺少 runtimeType。');
        }
    }
  }

  static void _checkChoices(
    Map item, {
    required String where,
    required List<AiPracticeQualityIssue> issues,
    required void Function(String, String) block,
    required void Function(String, String) advise,
  }) {
    final options = _stringsOf(item['options']) ?? const <String>[];
    if (options.length < 2) {
      block('item.too-few-options', '选择题只有 ${options.length} 个选项。');
      return;
    }
    final trimmed = [for (final option in options) option.trim()];
    if (trimmed.any((option) => option.isEmpty)) {
      block('item.empty-option', '选择题存在空选项。');
    }
    if (_hasDuplicates(trimmed)) {
      block('item.duplicate-options', '选择题存在完全相同的选项。');
    }
    if (options.length != 4) {
      advise('item.option-count', '选择题有 ${options.length} 个选项（常见是 4 个）。');
    }
    final rawIndex = item['correctIndex'];
    final index = rawIndex is int ? rawIndex : int.tryParse('$rawIndex');
    if (index == null) {
      block('item.empty-answer', '选择题没有正确答案下标。');
    } else if (index < 0 || index >= options.length) {
      // Rendering does `options[correctIndex]`; an out-of-range value throws
      // RangeError mid-exercise and loses the learner's place.
      block('item.bad-index', '选择题的正确答案下标 $index 越界。');
    }
  }

  static List<_LessonRef> _iterLessons(Map<String, dynamic> section) {
    final result = <_LessonRef>[];
    for (final unit in _listOf(section['units'])) {
      if (unit is! Map) continue;
      for (final lesson in _listOf(unit['lessons'])) {
        if (lesson is! Map) continue;
        final id = lesson['id']?.toString() ?? '';
        result.add(_LessonRef(
          id: id,
          name: lesson['name']?.toString().isNotEmpty == true
              ? lesson['name'].toString()
              : id,
          lesson: lesson,
        ));
      }
    }
    return result;
  }

  static List _listOf(dynamic value) => value is List ? value : const [];

  static List<String>? _stringsOf(dynamic value) {
    if (value is! List) return null;
    return [for (final item in value) item?.toString() ?? ''];
  }

  static bool _hasDuplicates(List<String> values) {
    final normalized = [for (final value in values) value.trim().toLowerCase()];
    return normalized.toSet().length != normalized.length;
  }

  static bool _sameMultiset(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    final left = [for (final value in a) value.trim()]..sort();
    final right = [for (final value in b) value.trim()]..sort();
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }
}

/// Lesson + id pair used while walking the tree.
class _LessonRef {
  const _LessonRef(
      {required this.id, required this.name, required this.lesson});

  final String id;
  final String name;
  final Map lesson;
}

/// One finding from [AiPracticeQualityChecker].
class AiPracticeQualityIssue {
  const AiPracticeQualityIssue({
    required this.code,
    required this.where,
    required this.message,
    this.advisory = false,
  });

  /// Stable machine code (`item.duplicate-options`, …) for tests and logs.
  final String code;

  /// Location inside the section (`lesson:u1-l1/st1#2`).
  final String where;

  /// Short, user-facing description.
  final String message;

  /// Advisory findings are recorded and shown, never blocking.
  final bool advisory;

  Map<String, dynamic> toJson() => {
        'code': code,
        'where': where,
        'message': message,
        'advisory': advisory,
      };

  static AiPracticeQualityIssue? fromJson(Map<String, dynamic> json) {
    final code = json['code']?.toString() ?? '';
    if (code.isEmpty) return null;
    return AiPracticeQualityIssue(
      code: code,
      where: json['where']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
      advisory: json['advisory'] == true,
    );
  }
}

/// Result of one verification pass over a generated section.
class AiPracticeQualityReport {
  const AiPracticeQualityReport({required this.issues});

  final List<AiPracticeQualityIssue> issues;

  List<AiPracticeQualityIssue> get blocking => [
        for (final issue in issues)
          if (!issue.advisory) issue
      ];

  List<AiPracticeQualityIssue> get advisory => [
        for (final issue in issues)
          if (issue.advisory) issue
      ];

  bool get passed => blocking.isEmpty;

  /// Messages for the repair prompt / failure card (capped so a broken reply
  /// cannot produce a 200-line error).
  List<String> get blockingMessages => [
        for (final issue in blocking.take(8))
          '${issue.where}: ${issue.message}',
      ];

  String toJsonString() => jsonEncode({
        'passed': passed,
        'issues': [for (final issue in issues) issue.toJson()],
      });

  static AiPracticeQualityReport? tryParse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final issues = <AiPracticeQualityIssue>[];
      for (final entry in (decoded['issues'] as List? ?? const [])) {
        if (entry is Map<String, dynamic>) {
          final issue = AiPracticeQualityIssue.fromJson(entry);
          if (issue != null) issues.add(issue);
        }
      }
      return AiPracticeQualityReport(issues: issues);
    } catch (_) {
      return null;
    }
  }
}
