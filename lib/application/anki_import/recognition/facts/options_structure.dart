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
  /// circled numbers (①/②), or bracketed options ((A)/(B), （A）/（B）),
  /// even when they are jammed into one paragraph without newlines.
  static bool looksLikeEmbeddedOptions(String text) {
    final letterHits = RegExp(
      r'(?<![A-Za-z0-9])([A-Ha-h])\s*[.、．:：)）\]】]',
    ).allMatches(text).length;
    if (letterHits >= 2) return true;
    final circledHits = RegExp(
      r'[①-⑧]',
    ).allMatches(text).length;
    if (circledHits >= 2) return true;
    final bracketHits = RegExp(
      r'[（(【\[]\s*([A-Ha-h1-8])\s*[）)】\]]',
    ).allMatches(text).length;
    if (bracketHits >= 2) return true;
    final numHits = RegExp(
      r'(?<![A-Za-z0-9])([1-8])\s*[.、．:：)）\]】]',
    ).allMatches(text).length;
    return numHits >= 2;
  }

  /// Extract `A. option` / `1) option` / `（A） option` / `① option` from a front-face string.
  static ParsedEmbeddedOptions? extractEmbeddedOptions(String front) {
    // 1) Line-oriented parse
    final lines = front.split(RegExp(r'\r?\n'));
    final lineOptions = <String>[];
    final promptLines = <String>[];
    final optionLine = RegExp(
      r'^\s*(?:'
      r'([A-Ha-h])\s*[.、．:：)）\]】]\s*'
      r'|[（(【\[]\s*([A-Ha-h1-8])\s*[）)】\]]\s*'
      r'|([①-⑧])\s*'
      r'|([1-8])\s*[.、．:：)）\]】]\s*'
      r')(.+)$',
    );

    for (final line in lines) {
      final m = optionLine.firstMatch(line);
      if (m != null) {
        final text = (m.group(5) ?? '').trim();
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

    // 2) Inline parse (no newlines between A./B./C./D. or (A)/(B))
    final inline = RegExp(
      r'(?:(?<![A-Za-z0-9])([A-Ha-h])\s*[.、．:：)）\]】]\s*'
      r'|[（(【\[]\s*([A-Ha-h])\s*[）)】\]]\s*'
      r'|([①-⑧])\s*)',
    );
    final matches = inline.allMatches(front).toList();
    if (matches.length < 2) return null;

    var start = 0;
    for (var i = 0; i < matches.length; i++) {
      final rawLabel = (matches[i].group(1) ??
              matches[i].group(2) ??
              matches[i].group(3) ??
              '')
          .toUpperCase();
      if (rawLabel == 'A' || rawLabel == '①') {
        start = i;
        break;
      }
    }
    final run = matches.sublist(start);
    if (run.length < 2) return null;

    final firstLabel = (run.first.group(1) ??
            run.first.group(2) ??
            run.first.group(3) ??
            '')
        .toUpperCase();
    if (firstLabel != 'A' && firstLabel != '①') return null;

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
    if (RegExp(r'^[A-Ha-h]+$').hasMatch(compactLetters)) {
      for (final c in compactLetters.toUpperCase().codeUnits) {
        addIfValid(c - 65);
      }
    } else if (RegExp(r'^[①-⑧]+$').hasMatch(compactLetters)) {
      for (final c in compactLetters.runes) {
        addIfValid(c - 0x2460);
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
    if (RegExp(r'^(option|choice|opt|选项|备选)\s*[_-]?\s*[a-h0-9]?$')
        .hasMatch(s)) {
      return true;
    }
    if (RegExp(r'^q[_-]?\s*[a-h1-9]$').hasMatch(s)) return true;
    if (RegExp(r'^[a-h]$').hasMatch(s)) return true;
    if (RegExp(r'^[甲乙丙丁戊己庚辛]$').hasMatch(s)) return true;
    if (RegExp(r'^选项\s*[a-h甲乙丙丁1-9]$').hasMatch(s)) return true;
    if (RegExp(r'^选项[一二三四五六七八]$').hasMatch(s)) return true;
    if (RegExp(r'^(option|choice)\s*[a-h1-9]$').hasMatch(s)) return true;
    if (RegExp(r'^(option|choice|opt)[_-][a-h1-9]$').hasMatch(s)) return true;
    return false;
  }

  /// Extract option pool from separate fields (OptionA..D, A..D, Q_1..Q_10, etc.)
  static List<String>? extractMultiFieldOptions(
    List<String> fieldNames,
    List<String> fieldValues,
  ) {
    final pairs = <(int index, String name, String val)>[];
    for (var i = 0; i < fieldNames.length; i++) {
      final name = fieldNames[i].toLowerCase();
      if (isOptionFieldName(name) && i < fieldValues.length) {
        final val = fieldValues[i].trim();
        if (val.isNotEmpty) {
          pairs.add((i, name, val));
        }
      }
    }
    if (pairs.length >= 2) {
      return pairs.map((p) => p.$3).toList();
    }
    return null;
  }

  /// Split an option-pool field value (`A|B|C` / newline / `;` / `||` lists).
  static List<String> parseOptionPool(
    String raw, {
    int maxOptions = 8,
    int maxChars = 80,
  }) {
    final parts = raw
        .split(RegExp(r'\|\||###|[\r\n|;,]+'))
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
