import 'text_metrics.dart';

/// Result of parsing embedded options from card text.
class ParsedEmbeddedOptions {
  final String prompt;
  final List<String> options;

  /// True when the options came from the unlabeled line-pool fallback
  /// (strategy 3) rather than labeled A./①/1. markers. Callers gate
  /// loose rows on answer alignment before trusting them — a paragraph
  /// split by `<br>` must not masquerade as an option pool.
  final bool loose;

  /// Correct indices when the parse itself carried an explicit answer
  /// marker (back-face layouts); empty otherwise.
  final List<int> correctIndices;

  const ParsedEmbeddedOptions({
    required this.prompt,
    required this.options,
    this.loose = false,
    this.correctIndices = const <int>[],
  });
}

/// Parsed cardinality for choice questions.
enum PracticeChoiceCardinality { single, multi, unknown, conflict }

/// Utilities for detecting, parsing, and grading embedded options
/// (A/B/C/D) in Anki cards (absorbs the old `anki_practice/embedded_
/// options.dart`). Pure structure, zero topic words.
class EmbeddedOptionsParser {
  static final RegExp _blockTagRegex = RegExp(
    r'<br\s*/?>|</p>|</div>|</li>|</tr>|</h[1-6]>',
    caseSensitive: false,
  );

  static final RegExp _anyTagRegex = RegExp(r'<[^>]+>');

  /// Convert block-level HTML to newlines, strip formatting tags (keeping
  /// media tags like `<img>`/`<audio>`), fold full-width Latin to ASCII,
  /// and decode common entities so option scanning sees the same text the
  /// user does (Anki fields routinely use `<br>`/`<div>` instead of `\n`
  /// and `Ａ．` instead of `A.`).
  static String normalizeForOptionScan(String raw) {
    return _foldFullWidth(raw)
        .replaceAll(_blockTagRegex, '\n')
        .replaceAllMapped(_anyTagRegex, (m) {
          final tag = m.group(0)!.toLowerCase();
          return tag.startsWith('<img') ||
                  tag.startsWith('<audio') ||
                  tag.startsWith('<video') ||
                  tag.startsWith('<source')
              ? m.group(0)!
              : '';
        })
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'");
  }

  /// Whether [text] looks like it contains lettered options (A./B. …),
  /// circled numbers (①/②), or bracketed options ((A)/(B), （A）/（B）),
  /// even when they are jammed into one paragraph without newlines.
  static bool looksLikeEmbeddedOptions(String raw) {
    final text = normalizeForOptionScan(raw);
    final letterHits = RegExp(
      r'(?<![A-Za-z0-9])([A-Ha-h])\s*[.、．:：)）\]】。]',
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
      r'(?<![A-Za-z0-9])([1-8])\s*[.、．:：)）\]】。]',
    ).allMatches(text).length;
    if (numHits >= 2) return true;
    // Sequential label runs (`A 选项` then `B 选项` with only whitespace
    // as the separator) — prose rarely walks the alphabet or the digits
    // in order.
    return _hasSequentialLabels(text);
  }

  /// Sequential-label signal for space-only separators: standalone letter
  /// labels anywhere, digit labels only at line starts (digits appear in
  /// prose too often to trust mid-line).
  static bool _hasSequentialLabels(String text) {
    final letters = RegExp(
      r'(?<![A-Za-z0-9])([A-Ha-h])(?![A-Za-z0-9])',
    )
        .allMatches(text)
        .map((m) => m.group(1)!.toUpperCase())
        .toList();
    for (var i = 1; i < letters.length; i++) {
      if (letters[i].codeUnitAt(0) == letters[i - 1].codeUnitAt(0) + 1) {
        return true;
      }
    }
    final lineStartDigits = RegExp(
      r'^\s*([1-8])(?![0-9])',
      multiLine: true,
    )
        .allMatches(text)
        .map((m) => m.group(1)!)
        .toList();
    for (var i = 1; i < lineStartDigits.length; i++) {
      if (lineStartDigits[i].codeUnitAt(0) ==
          lineStartDigits[i - 1].codeUnitAt(0) + 1) {
        return true;
      }
    }
    return false;
  }

  /// Extract `A. option` / `1) option` / `（A） option` / `① option` from a front-face string.
  static ParsedEmbeddedOptions? extractEmbeddedOptions(String rawFront) {
    final front = normalizeForOptionScan(rawFront);
    // 1) Line-oriented parse
    final lines = front.split(RegExp(r'\r?\n'));
    final lineOptions = <String>[];
    final promptLines = <String>[];
    final optionLine = RegExp(
      r'^\s*(?:'
      r'([A-Ha-h])\s*[.、．:：)）\]】。]\s*'
      r'|[（(【\[]\s*([A-Ha-h1-8])\s*[）)】\]]\s*'
      r'|([①-⑧])\s*'
      r'|([1-8])\s*[.、．:：)）\]】。]\s*'
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
      r'(?:(?<![A-Za-z0-9])([A-Ha-h])\s*[.、．:：)）\]】。]\s*'
      r'|[（(【\[]\s*([A-Ha-h1-8])\s*[）)】\]]\s*'
      r'|([①-⑧])\s*'
      r'|(?<![A-Za-z0-9])([1-8])\s*[.、．:：)）\]】。]\s*)',
    );
    final matches = inline.allMatches(front).toList();
    if (matches.length >= 2) {
      String labelOf(int i) => (matches[i].group(1) ??
              matches[i].group(2) ??
              matches[i].group(3) ??
              matches[i].group(4) ??
              '')
          .toUpperCase();

      var start = -1;
      for (var i = 0; i < matches.length; i++) {
        final rawLabel = labelOf(i);
        if (rawLabel == 'A' || rawLabel == '①' || rawLabel == '1') {
          start = i;
          break;
        }
      }
      if (start >= 0) {
        final run = matches.sublist(start);
        if (run.length >= 2) {
          final options = <String>[];
          for (var i = 0; i < run.length; i++) {
            final from = run[i].end;
            final to = i + 1 < run.length ? run[i + 1].start : front.length;
            final text = front.substring(from, to).trim();
            if (text.isEmpty) continue;
            options.add(text);
          }
          if (options.length >= 2) {
            final prompt = front.substring(0, run.first.start).trim();
            return ParsedEmbeddedOptions(prompt: prompt, options: options);
          }
        }
      }
    }

    // 3) Unlabeled line pool: no labels anywhere, but the text is a
    // handful of short standalone lines. The answer is expected to be a
    // bare label — callers gate loose rows on alignment before trusting
    // them.
    return _extractUnlabeledLinePool(front);
  }

  static const int _unlabeledOptionMinLines = 3;
  static const int _unlabeledOptionMaxLines = 8;
  static const int _unlabeledOptionLineMaxChars = 80;

  /// A whole line that is nothing but an explicit answer marker
  /// (`答案：B` / `Answer: C`) — excluded from unlabeled pools.
  static final RegExp _answerMarkerLine = RegExp(
    r'^\s*(?:答案|正确答案|正确选项|正解|参考答案|Answer|Ans|选)\s*[为是:：]?\s*'
    r'(?:[A-Ha-h]{1,4}|[①-⑧]{1,4}|[1-9])\s*[.、．:：)）\]】。]?\s*$',
    caseSensitive: false,
  );

  static ParsedEmbeddedOptions? _extractUnlabeledLinePool(String front) {
    final lines = front
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final pool = <String>[
      for (final line in lines)
        if (!_answerMarkerLine.hasMatch(line)) line,
    ];
    if (pool.length < _unlabeledOptionMinLines ||
        pool.length > _unlabeledOptionMaxLines) {
      return null;
    }
    final labeledLine = RegExp(
      r'^\s*(?:'
      r'[（(【\[]\s*[A-Ha-h1-8]\s*[）)】\]]'
      r'|[①-⑧]'
      r'|[A-Ha-h]\s*[.、．:：)）\]】。]'
      r'|[1-8]\s*[.、．:：)）\]】。]'
      r')',
    );
    for (final line in pool) {
      if (line.length > _unlabeledOptionLineMaxChars) return null;
      if (labeledLine.hasMatch(line)) return null;
    }
    return ParsedEmbeddedOptions(prompt: '', options: pool, loose: true);
  }

  /// Clause that explains rather than answers. An answer field often
  /// carries `B。解析：…`; the head before this clause is the answer.
  static final RegExp _explanationClause = RegExp(
    r'(?:解析|解释|说明|提示|分析|rationale|explanation|because|since|why)',
    caseSensitive: false,
  );

  /// CJK-only explanation words — strong enough to cut at a sentence
  /// boundary even when the head is prose (`北京。解析：…`).
  static final RegExp _cjkExplanationClause = RegExp(
    r'(?:解析|解释|说明|提示|分析)',
  );

  /// An answer head that is nothing but labels and separators (`B。`,
  /// `AC`, `2、3`) — safe to cut an explanation clause after it.
  static final RegExp _labelIshHead = RegExp(
    r'^[A-Ha-h①-⑧0-9\s.、．:：)）\]】。,，;；/|+＋]+$',
  );

  /// Whitespace/trailing-punctuation-insensitive comparison key for the
  /// exact-match branch (`选项 一` vs `选项一`, `选项二。` vs `选项二`).
  static String _comparable(String s) => s
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll(RegExp(r'[。．.;；,，、]+$'), '')
      .toLowerCase();

  /// Parse correct option indices from an answer field.
  static List<int> parseCorrectIndices(
    String answerRaw,
    List<String> options,
  ) {
    if (options.isEmpty) return const [];
    var answerWithLabel = answerRaw.trim();
    if (answerWithLabel.isEmpty) return const [];

    // `B。解析：…` keeps only its head. A clause at position zero means
    // the whole value is an explanation — keep the original text.
    final explanation = _explanationClause.firstMatch(answerWithLabel);
    if (explanation != null && explanation.start > 0) {
      final head = answerWithLabel.substring(0, explanation.start).trim();
      final isCjkClause = _cjkExplanationClause.hasMatch(explanation.group(0)!);
      final boundaryBefore = answerWithLabel.substring(
        explanation.start - 1,
        explanation.start,
      );
      final strongBoundary = '。；;\n'.contains(boundaryBefore);
      if (head.isNotEmpty &&
          (_labelIshHead.hasMatch(head) || (isCjkClause && strongBoundary))) {
        answerWithLabel = head;
      }
    }

    // Answer-word prefix (`答案：B`, `Answer: B`, `选B`). `选` must not
    // eat the first character of answers that repeat an option text
    // starting with `选项…`/`选题…`.
    answerWithLabel = answerWithLabel
        .replaceFirst(
          RegExp(
            r'^(?:答案|正确答案|正确选项|正解|参考答案|Answer|Ans|选(?![题项]))\s*[为是:：]?\s*',
            caseSensitive: false,
          ),
          '',
        )
        .trim();

    // Trailing sentence punctuation (`B。` / `AC，`).
    answerWithLabel = answerWithLabel
        .replaceFirst(RegExp(r'[。．.;；,，、\s]+$'), '')
        .trim();
    if (answerWithLabel.isEmpty) return const [];

    // Answers often repeat the option label: `A. 选项文本` / `（B）文本`.
    // Strip that prefix so the exact-match branch below can align it.
    final labelStripped = answerWithLabel
        .replaceFirst(
          RegExp(
            r'^(?:'
            r'[A-Ha-h]\s*[.、．:：)）\]】。]'
            r'|[（(【\[]\s*[A-Ha-h1-8]\s*[）)】\]]'
            r'|[①-⑧]'
            r'|[1-9]\s*[.、．:：)）\]】。]'
            r')\s*',
          ),
          '',
        )
        .trim();

    final indices = <int>{};

    void addIfValid(int i) {
      if (i >= 0 && i < options.length) indices.add(i);
    }

    // Exact full-string match first (label-stripped, then raw).
    for (final candidate in [labelStripped, answerWithLabel]) {
      if (candidate.isEmpty) continue;
      final exact = options.indexWhere(
        (o) => _comparable(o) == _comparable(candidate),
      );
      if (exact >= 0) return [exact];
    }

    final compact = RegExp(r'[,;、|/＋+\s。．.]+');
    final compactLetters = answerWithLabel.replaceAll(compact, '');
    if (RegExp(r'^[A-Ha-h]+$').hasMatch(compactLetters)) {
      for (final c in compactLetters.toUpperCase().codeUnits) {
        addIfValid(c - 65);
      }
    } else if (RegExp(r'^[①-⑧]+$').hasMatch(compactLetters)) {
      for (final c in compactLetters.runes) {
        addIfValid(c - 0x2460);
      }
    } else {
      final numberParts = answerWithLabel
          .split(compact)
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
  /// Separators are normalized first so `CorrectAnswer` (no space)
  /// matches the composite checks.
  static bool isAnswerFieldName(String lower) {
    final s = lower.trim().replaceAll(RegExp(r'[_\-\s]+'), '');
    return s == 'answer' ||
        s == 'answers' ||
        s == 'ans' ||
        s == 'key' ||
        s == 'answerkey' ||
        s == 'correct' ||
        s == '解答' ||
        s == '答案' ||
        s == '正确答案' ||
        s == '正确选项' ||
        s == '正解' ||
        s == '参考答案' ||
        s.contains('correctanswer') ||
        s.contains('rightanswer') ||
        s.contains('answer');
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

  /// Fold full-width Latin letters/digits (Ａ-Ｚａ-ｚ０-９) to ASCII so
  /// option scanning sees `Ａ．` and `A.` alike.
  static String _foldFullWidth(String text) {
    return text.replaceAllMapped(
      RegExp(r'[Ａ-Ｚａ-ｚ０-９]'),
      (m) => String.fromCharCode(m.group(0)!.runes.first - 0xFEE0),
    );
  }

  /// Whether the value is nothing but an option label (`B` / `②` / `3` /
  /// `B。`) — the answer shape an unlabeled line pool pairs with.
  static bool isBareLabelAnswer(String raw) {
    return RegExp(
      r'^\s*(?:[A-Ha-h]|[①-⑧]|[1-9])\s*[.、．:：)）\]】。]?\s*$',
    ).hasMatch(raw);
  }

  /// Whether the value is a handful of short standalone lines — the
  /// unlabeled option-pool shape (labels live in the answer field).
  static bool hasUnlabeledOptionLines(String raw) {
    final parsed = _extractUnlabeledLinePool(normalizeForOptionScan(raw));
    return parsed != null;
  }

  static int _labelToIndex(String label) {
    final rune = label.runes.first;
    if (rune >= 0x41 && rune <= 0x48) return rune - 0x41;
    if (rune >= 0x61 && rune <= 0x68) return rune - 0x61;
    if (rune >= 0x2460 && rune <= 0x2467) return rune - 0x2460;
    final digit = int.tryParse(label);
    return digit == null ? -1 : digit - 1;
  }

  /// Parse a back-face value that carries both the options and the
  /// explicit answer (`A. x<br>B. y<br>答案：B`). Null unless an explicit
  /// answer marker aligns to one of the extracted options.
  static ParsedEmbeddedOptions? extractBackFaceChoice(String rawBack) {
    final normalized = normalizeForOptionScan(rawBack);
    final cleaned = normalized
        .split(RegExp(r'\r?\n'))
        .where((line) => !_answerMarkerLine.hasMatch(line))
        .join('\n');
    final embedded = extractEmbeddedOptions(cleaned);
    if (embedded == null) return null;
    final marker = RegExp(
      r'(?:答案|正确答案|正确选项|正解|参考答案|Answer|Ans|选)\s*[为是:：]?\s*'
      r'([A-Ha-h]{1,4}|[①-⑧]{1,4}|[1-9])(?![A-Za-z0-9])',
      caseSensitive: false,
    ).firstMatch(normalized);
    if (marker == null) return null;
    final indices = <int>{};
    for (final rune in marker.group(1)!.runes) {
      final label = String.fromCharCode(rune);
      final index = _labelToIndex(label);
      if (index >= 0 && index < embedded.options.length) indices.add(index);
    }
    if (indices.isEmpty) return null;
    final sorted = indices.toList()..sort();
    return ParsedEmbeddedOptions(
      prompt: embedded.prompt,
      options: embedded.options,
      correctIndices: sorted,
    );
  }
}
