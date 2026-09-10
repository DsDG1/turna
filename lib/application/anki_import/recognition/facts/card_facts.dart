import 'options_structure.dart';
import 'text_metrics.dart';

/// Row-paired choice measurement: how many sample rows parse as choice
/// and how many of those align an answer. Rates, not a single lucky
/// sample — a mixed deck must be measured honestly (doc 37 §3.4).
class ChoiceRowStats {
  const ChoiceRowStats({
    required this.totalRows,
    required this.parseRows,
    required this.alignedRows,
  });

  /// Rows with a non-empty front value.
  final int totalRows;

  /// Rows whose front parsed as ≥2 options (loose rows only count once
  /// their answer aligned).
  final int parseRows;

  /// Rows whose front parsed AND whose paired answer aligned.
  final int alignedRows;

  double get parseRate => totalRows == 0 ? 0 : parseRows / totalRows;
  double get alignRate => parseRows == 0 ? 0 : alignedRows / parseRows;
}

/// Measure choice rows across paired (front, answer) values. Unlabeled
/// line pools ([ParsedEmbeddedOptions.loose]) count as parsed only when
/// their answer aligns — a paragraph split by `<br>` must not
/// masquerade as an option pool.
ChoiceRowStats measureChoiceRows(List<(String, String)> rows) {
  var total = 0;
  var parsed = 0;
  var aligned = 0;
  for (final (front, answer) in rows) {
    if (front.trim().isEmpty) continue;
    total++;
    final embedded = EmbeddedOptionsParser.extractEmbeddedOptions(front);
    if (embedded == null) continue;
    final hit = EmbeddedOptionsParser.parseCorrectIndices(
      answer,
      embedded.options,
    ).isNotEmpty;
    if (embedded.loose) {
      if (hit) {
        parsed++;
        aligned++;
      }
      continue;
    }
    parsed++;
    if (hit) aligned++;
  }
  return ChoiceRowStats(
    totalRows: total,
    parseRows: parsed,
    alignedRows: aligned,
  );
}

/// L0 content probes over one field's sample values (or one card's field
/// values at projection time). Pure measurement — the archetype rules
/// decide what the measurements mean.
class CardFacts {
  CardFacts._(this.values);

  final List<String> values;

  factory CardFacts.of(List<String> values) => CardFacts._(values);

  int get nonEmptyCount =>
      values.where((v) => v.trim().isNotEmpty).length;

  bool get isEmpty => nonEmptyCount == 0;

  /// Fraction of non-empty values satisfying [probe].
  double rateOf(bool Function(String value) probe) {
    var hit = 0;
    var total = 0;
    for (final value in values) {
      if (value.trim().isEmpty) continue;
      total++;
      if (probe(value)) hit++;
    }
    return total == 0 ? 0 : hit / total;
  }

  bool get anyContainsSound =>
      values.any((v) => v.contains('[sound:') || v.contains('[anki:play:'));

  bool get anyContainsImage =>
      values.any((v) => v.contains('<img') || v.contains('[image:'));

  bool get anyContainsClozeMarker =>
      values.any((v) => RegExp(r'\{\{c\d+::').hasMatch(v));

  double get clozeMarkerRate =>
      rateOf((v) => RegExp(r'\{\{c\d+::').hasMatch(v));

  double get plainShortRate => rateOf(
        (v) => CardText.isPlainTextSample(v) && CardText.isShortAnswer(v),
      );

  double get shortRate => rateOf((v) => CardText.isShortAnswer(v));

  double get sentenceRate => rateOf((v) => CardText.isSentence(v));

  double get looksLikeOptionsRate =>
      rateOf((v) => EmbeddedOptionsParser.looksLikeEmbeddedOptions(v));

  bool get anyContainsScript => values.any(
        (v) =>
            v.toLowerCase().contains('<script') ||
            v.toLowerCase().contains('javascript:') ||
            RegExp(r'on[a-z]+\s*=', caseSensitive: false).hasMatch(v),
      );

  bool get anyContainsComplexHtml => values.any(
        (v) => RegExp(
          r'<(table|svg|audio|video|iframe|canvas|object|embed|form|input|button)\b',
          caseSensitive: false,
        ).hasMatch(v),
      );

  /// Parse the first non-empty value as an option pool.
  List<String> parseOptionPool() {
    for (final value in values) {
      if (value.trim().isEmpty) continue;
      final options = EmbeddedOptionsParser.parseOptionPool(value);
      if (options.length >= 2) return options;
    }
    return const <String>[];
  }

  /// Extract embedded options from the first value that has them.
  ParsedEmbeddedOptions? extractEmbeddedOptions() {
    for (final value in values) {
      if (value.trim().isEmpty) continue;
      final parsed = EmbeddedOptionsParser.extractEmbeddedOptions(value);
      if (parsed != null && parsed.options.length >= 2) return parsed;
    }
    return null;
  }

  /// Parse correct indices of [options] against these values.
  List<int> parseCorrectIndices(List<String> options) {
    for (final value in values) {
      if (value.trim().isEmpty) continue;
      final indices = EmbeddedOptionsParser.parseCorrectIndices(value, options);
      if (indices.isNotEmpty) return indices;
    }
    return const <int>[];
  }
}
