/// Result of parsing embedded options from card text.
class ParsedEmbeddedOptions {
  final String prompt;
  final List<String> options;

  const ParsedEmbeddedOptions({
    required this.prompt,
    required this.options,
  });
}

/// Parsed cardinality for choice questions.
enum PracticeChoiceCardinality { single, multi, unknown, conflict }

/// Detected MCQ field layout from field names.
class PracticeChoiceFieldLayout {
  final int promptIndex;
  final int answerIndex;
  final List<int> optionIndices;
  final bool multi;

  const PracticeChoiceFieldLayout({
    required this.promptIndex,
    required this.answerIndex,
    required this.optionIndices,
    this.multi = false,
  });
}

/// Utilities for detecting, parsing, and grading embedded options (A/B/C/D) in Anki cards.
class EmbeddedOptionsParser {
  /// Whether [text] looks like it contains lettered options (A./B. …), even
  /// when they are jammed into one paragraph without newlines.
  static bool looksLikeEmbeddedOptions(String text) {
    final letterHits = RegExp(
      r'(?<![A-Za-z0-9])([A-Da-d])\s*[.、．:：)）]',
    ).allMatches(text).length;
    if (letterHits >= 2) return true;
    final numHits = RegExp(
      r'(?<![A-Za-z0-9])([1-4])\s*[.、．:：)）]',
    ).allMatches(text).length;
    return numHits >= 2;
  }

  /// Extract `A. option` / `1) option` options from a front-face string.
  static ParsedEmbeddedOptions? extractEmbeddedOptions(String front) {
    // 1) Line-oriented parse
    final lines = front.split(RegExp(r'\r?\n'));
    final lineOptions = <String>[];
    final promptLines = <String>[];
    final optionLine = RegExp(
      r'^\s*(?:'
      r'([A-Fa-f])\s*[.、．:：)）]\s*'
      r'|\(([A-Fa-f])\)\s*'
      r'|([1-9])\s*[.、．:：)）]\s*'
      r')(.+)$',
    );

    for (final line in lines) {
      final m = optionLine.firstMatch(line);
      if (m != null) {
        final text = (m.group(4) ?? '').trim();
        if (text.isNotEmpty) lineOptions.add(text);
      } else if (lineOptions.isEmpty) {
        if (line.trim().isNotEmpty) promptLines.add(line.trim());
      }
    }

    if (lineOptions.length >= 2) {
      return ParsedEmbeddedOptions(
        prompt: promptLines.join('\n').trim(),
        options: lineOptions,
      );
    }

    // 2) Inline parse (no newlines between A./B./C./D.)
    final inline = RegExp(
      r'(?<![A-Za-z0-9])([A-Da-d])\s*[.、．:：)）]\s*',
    );
    final matches = inline.allMatches(front).toList();
    if (matches.length < 2) return null;

    var start = 0;
    for (var i = 0; i < matches.length; i++) {
      if (matches[i].group(1)!.toUpperCase() == 'A') {
        start = i;
        break;
      }
    }
    final run = matches.sublist(start);
    if (run.length < 2) return null;

    if (run.first.group(1)!.toUpperCase() != 'A') return null;

    final labels = [
      for (final m in run) m.group(1)!.toUpperCase().codeUnitAt(0) - 65,
    ];
    if (labels.first != 0) return null;

    final options = <String>[];
    for (var i = 0; i < run.length; i++) {
      final from = run[i].end;
      final to = i + 1 < run.length ? run[i + 1].start : front.length;
      final text = front.substring(from, to).trim();
      if (text.isEmpty) continue;
      options.add(text);
    }
    if (options.length < 2) return null;

    final prompt = front.substring(0, run.first.start).trim();
    return ParsedEmbeddedOptions(prompt: prompt, options: options);
  }

  /// Parse correct option indices from an answer field.
  static List<int> parseCorrectIndices(String answerRaw, List<String> options) {
    var answer = answerRaw.trim();
    answer = answer
        .replaceFirst(
          RegExp(
            r'^(答案|正确答案|正确选项|正解|Answer|Ans)\s*[:：]?\s*',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
    if (answer.isEmpty || options.isEmpty) return const [];

    final indices = <int>{};

    void addIfValid(int i) {
      if (i >= 0 && i < options.length) indices.add(i);
    }

    // Exact full-string match first
    final exact = options.indexWhere(
      (o) => o == answer || o.toLowerCase() == answer.toLowerCase(),
    );
    if (exact >= 0) return [exact];

    final compactLetters = answer.replaceAll(RegExp(r'[,;、|/＋+\s]+'), '');
    if (RegExp(r'^[A-Fa-f]+$').hasMatch(compactLetters)) {
      for (final c in compactLetters.toUpperCase().codeUnits) {
        addIfValid(c - 65);
      }
    } else {
      final numberParts = answer
          .split(RegExp(r'[,;、|/＋+\s]+'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (numberParts.isNotEmpty &&
          numberParts.every((part) => RegExp(r'^\d+$').hasMatch(part))) {
        for (final part in numberParts) {
          final n = int.parse(part);
          if (n >= 1 && n <= options.length) {
            addIfValid(n - 1);
          }
        }
      }
    }

    final sorted = indices.toList()..sort();
    return sorted;
  }

  /// Whether a lowercased field name looks like an option column.
  static bool isOptionFieldName(String lower) {
    final s = lower.trim();
    if (s.isEmpty) return false;
    if (isAnswerFieldName(s)) return false;
    if (RegExp(r'^(option|choice|opt|选项|备选)\s*[_-]?\s*[a-f0-9]?$')
        .hasMatch(s)) {
      return true;
    }
    if (RegExp(r'^q[_-]?\s*[a-f1-9]$').hasMatch(s)) return true;
    if (RegExp(r'^[a-f]$').hasMatch(s)) return true;
    if (RegExp(r'^[甲乙丙丁戊己]$').hasMatch(s)) return true;
    if (RegExp(r'^选项\s*[a-f甲乙丙丁1-9]$').hasMatch(s)) return true;
    if (RegExp(r'^选项[一二三四五六]$').hasMatch(s)) return true;
    if (RegExp(r'^(option|choice)\s*[a-f1-9]$').hasMatch(s)) return true;
    if (RegExp(r'^(option|choice|opt)[_-][a-f1-9]$').hasMatch(s)) return true;
    return false;
  }

  /// Whether a lowercased field name looks like an answer key column.
  static bool isAnswerFieldName(String lower) {
    final s = lower.trim();
    return s == 'answer' ||
        s == 'answers' ||
        s == 'correct' ||
        s == 'key' ||
        s.contains('correct answer') ||
        s == '答案' ||
        s == '正确答案' ||
        s == '正确选项' ||
        s == '正解' ||
        s == '参考答案' ||
        s.contains('right answer');
  }

  static bool nameLooksLikeMcq(String nameLower) {
    return nameLower.contains('multiple choice') ||
        nameLower.contains('multiplechoice') ||
        nameLower.contains('mcq') ||
        nameLower.contains('单选') ||
        nameLower.contains('选择题') ||
        nameLower.contains('题库') ||
        nameLower.contains('真题') ||
        nameLower.contains('试题') ||
        (nameLower.contains('quiz') && !nameLower.contains('cloze')) ||
        (nameLower.contains('choice') && !nameLower.contains('multi'));
  }

  static bool nameLooksLikeMultiSelect(String nameLower) {
    return nameLower.contains('multi select') ||
        nameLower.contains('multiselect') ||
        nameLower.contains('multi-choice') ||
        nameLower.contains('multiple answer') ||
        nameLower.contains('多选') ||
        nameLower.contains('多选题');
  }

  /// Check choice cardinality from question prompt and notetype name.
  static PracticeChoiceCardinality choiceCardinality({
    String notetypeName = '',
    required String prompt,
  }) {
    final normalizedPrompt = prompt.toLowerCase();
    final promptSaysMulti = RegExp(
      r'多项选择题|多选题|不定项选择题|可多选|请选择所有|选择所有|'
      r'有多项.{0,8}正确|select\s+all|choose\s+all|multiple\s+answers?',
    ).hasMatch(normalizedPrompt);
    final promptSaysSingle = RegExp(
      r'单项选择题|单选题|只有一项.{0,8}正确|唯一正确|'
      r'single[-\s]?choice|select\s+one|choose\s+one',
    ).hasMatch(normalizedPrompt);
    if (promptSaysMulti && promptSaysSingle) {
      return PracticeChoiceCardinality.conflict;
    }
    if (promptSaysMulti) {
      return PracticeChoiceCardinality.multi;
    }
    if (promptSaysSingle) {
      return PracticeChoiceCardinality.single;
    }

    final name = notetypeName.toLowerCase();
    final nameSaysMulti = name.contains('multi select') ||
        name.contains('multiselect') ||
        name.contains('multi-choice') ||
        name.contains('multiple answer') ||
        name.contains('多选') ||
        name.contains('多选题');
    final nameSaysSingle = RegExp(r'single[-\s]?choice|单选').hasMatch(name);
    if (nameSaysMulti && nameSaysSingle) return PracticeChoiceCardinality.unknown;
    if (nameSaysMulti) return PracticeChoiceCardinality.multi;
    if (nameSaysSingle) return PracticeChoiceCardinality.single;

    return PracticeChoiceCardinality.unknown;
  }

  /// Detect choice layout from field names and notetype name.
  static PracticeChoiceFieldLayout? detectChoiceLayout({
    required List<String> fieldNames,
    String notetypeName = '',
  }) {
    if (fieldNames.length < 3) return null;
    final lower = fieldNames.map((f) => f.toLowerCase().trim()).toList();

    final optionIndices = <int>[];
    for (var i = 0; i < lower.length; i++) {
      if (isOptionFieldName(lower[i])) optionIndices.add(i);
    }
    if (optionIndices.length < 2) return null;

    final optionSet = optionIndices.toSet();
    final promptIndex = _findFieldIndex(lower, [
          'question',
          'prompt',
          'title',
          'stem',
          'text',
          '问题',
          '题目',
          '题干',
          '题面',
          'front',
        ]) ??
        (() {
          for (var i = 0; i < lower.length; i++) {
            if (!optionSet.contains(i) && !isAnswerFieldName(lower[i])) {
              return i;
            }
          }
          return 0;
        })();

    var answerIndex = _findFieldIndex(lower, [
      'answers',
      'answer',
      'correct',
      'correct answer',
      'correct answers',
      'key',
      '答案',
      '正确答案',
      '正确选项',
      '正解',
      '参考答案',
    ]);
    if (answerIndex != null && optionSet.contains(answerIndex)) {
      answerIndex = null;
      for (var i = 0; i < lower.length; i++) {
        if (!optionSet.contains(i) && isAnswerFieldName(lower[i])) {
          answerIndex = i;
          break;
        }
      }
    }
    answerIndex ??= (() {
      for (var i = lower.length - 1; i >= 0; i--) {
        if (!optionSet.contains(i) && i != promptIndex) return i;
      }
      return optionIndices.last;
    })();

    final nameLower = notetypeName.toLowerCase();
    final multi = nameLower.contains('multi select') ||
        nameLower.contains('multiselect') ||
        nameLower.contains('multi-choice') ||
        nameLower.contains('multiple answer') ||
        nameLower.contains('多选') ||
        lower.any((f) =>
            f.contains('answers') ||
            f.contains('correct answers') ||
            f.contains('多选'));

    return PracticeChoiceFieldLayout(
      promptIndex: promptIndex,
      answerIndex: answerIndex,
      optionIndices: List.unmodifiable(optionIndices),
      multi: multi,
    );
  }

  static int? _findFieldIndex(List<String> lowerFields, List<String> patterns) {
    for (var i = 0; i < lowerFields.length; i++) {
      for (final pattern in patterns) {
        if (lowerFields[i] == pattern || lowerFields[i].contains(pattern)) {
          return i;
        }
      }
    }
    return null;
  }
}
