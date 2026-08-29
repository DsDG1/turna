import 'text_metrics.dart';

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

/// Utilities for detecting, parsing, and grading embedded options
/// (A/B/C/D) in Anki cards (absorbs the old `anki_practice/embedded_
/// options.dart`). Pure structure, zero topic words.
class EmbeddedOptionsParser {
  /// Whether [text] looks like it contains lettered options (A./B. …),
  /// even when they are jammed into one paragraph without newlines.
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
  static List<int> parseCorrectIndices(
    String answerRaw,
    List<String> options,
  ) {
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

  /// Split an option-pool field value (`A|B|C` / newline / `;` lists).
  static List<String> parseOptionPool(
    String raw, {
    int maxOptions = 8,
    int maxChars = 80,
  }) {
    final parts = raw
        .split(RegExp(r'[\n|;,]+'))
        .map(CardText.shortText)
        .where((part) => part.isNotEmpty)
        .toList();
    final unique = <String>[];
    final seen = <String>{};
    for (final part in parts) {
      final clipped =
          part.length > maxChars ? part.substring(0, maxChars) : part;
      if (seen.add(clipped.toLowerCase())) {
        unique.add(clipped);
      }
      if (unique.length >= maxOptions) break;
    }
    return unique;
  }
}
