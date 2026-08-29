import 'options_structure.dart';
import 'text_metrics.dart';

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
