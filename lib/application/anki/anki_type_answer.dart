/// Pure Anki type-answer normalization and comparison helpers.
class AnkiTypeAnswerResult {
  final String expected;
  final String actual;
  final String normalizedExpected;
  final String normalizedActual;
  final int commonPrefixLength;
  final int commonSuffixLength;

  const AnkiTypeAnswerResult({
    required this.expected,
    required this.actual,
    required this.normalizedExpected,
    required this.normalizedActual,
    required this.commonPrefixLength,
    required this.commonSuffixLength,
  });

  bool get correct => normalizedExpected == normalizedActual;
  String get expectedMiddle => normalizedExpected.substring(
        commonPrefixLength,
        normalizedExpected.length - commonSuffixLength,
      );
  String get actualMiddle => normalizedActual.substring(
        commonPrefixLength,
        normalizedActual.length - commonSuffixLength,
      );
}

class AnkiTypeAnswerMatcher {
  const AnkiTypeAnswerMatcher._();

  static AnkiTypeAnswerResult compare(String expected, String actual) {
    final normalizedExpected = normalize(expected);
    final normalizedActual = normalize(actual);
    var prefix = 0;
    final prefixLimit = normalizedExpected.length < normalizedActual.length
        ? normalizedExpected.length
        : normalizedActual.length;
    while (prefix < prefixLimit &&
        normalizedExpected[prefix] == normalizedActual[prefix]) {
      prefix++;
    }
    var suffix = 0;
    final suffixLimit =
        normalizedExpected.length - prefix < normalizedActual.length - prefix
            ? normalizedExpected.length - prefix
            : normalizedActual.length - prefix;
    while (suffix < suffixLimit &&
        normalizedExpected[normalizedExpected.length - suffix - 1] ==
            normalizedActual[normalizedActual.length - suffix - 1]) {
      suffix++;
    }
    return AnkiTypeAnswerResult(
      expected: expected,
      actual: actual,
      normalizedExpected: normalizedExpected,
      normalizedActual: normalizedActual,
      commonPrefixLength: prefix,
      commonSuffixLength: suffix,
    );
  }

  static String normalize(String value) =>
      value.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
}
