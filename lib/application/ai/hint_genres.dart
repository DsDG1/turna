// Dart imports:
import 'dart:convert';

/// Typed results for the depth-learning tutor genres. Each is produced by
/// `AiHintProvider`'s genre methods (`explainGrammarPoint`, `compareSynonyms`,
/// `decomposeSentence`, `explainWhyWrong`), which ask the model for a small
/// JSON object and parse it client-side via the `fromJson` factories here.
///
/// The factories are tolerant: missing keys or wrong-typed values collapse to
/// empty strings / empty lists rather than throwing, so a slightly-off model
/// reply still renders something useful in the tutor sheet.

List<String> _stringList(dynamic value) {
  if (value is! List) return const [];
  return [for (final e in value) e?.toString() ?? ''];
}

List<Map<String, dynamic>> _objectList(dynamic value) {
  if (value is! List) return const [];
  return [
    for (final e in value)
      if (e is Map<String, dynamic>) e
  ];
}

/// Deep explanation of a single grammar point.
class GrammarExplanation {
  const GrammarExplanation({
    required this.explanation,
    this.relatedExamples = const [],
    this.contrastWith = const [],
  });

  final String explanation;
  final List<String> relatedExamples;
  final List<String> contrastWith;

  static GrammarExplanation fromJson(Map<String, dynamic> m) =>
      GrammarExplanation(
        explanation: (m['explanation'] ?? '').toString(),
        relatedExamples: _stringList(m['relatedExamples']),
        contrastWith: _stringList(m['contrastWith']),
      );
}

/// One side-by-side comparison of two near-synonymous words.
class SynonymPair {
  const SynonymPair({
    required this.a,
    required this.b,
    required this.nuance,
    required this.whenToUseA,
    required this.whenToUseB,
    this.examples = const [],
  });

  final String a;
  final String b;
  final String nuance;
  final String whenToUseA;
  final String whenToUseB;
  final List<String> examples;

  static SynonymPair fromJson(Map<String, dynamic> m) => SynonymPair(
        a: (m['a'] ?? '').toString(),
        b: (m['b'] ?? '').toString(),
        nuance: (m['nuance'] ?? '').toString(),
        whenToUseA: (m['whenToUseA'] ?? '').toString(),
        whenToUseB: (m['whenToUseB'] ?? '').toString(),
        examples: _stringList(m['examples']),
      );
}

/// Result of comparing a set of near-synonyms.
class SynonymComparison {
  const SynonymComparison({this.pairs = const []});

  final List<SynonymPair> pairs;

  static SynonymComparison fromJson(Map<String, dynamic> m) =>
      SynonymComparison(
        pairs: _objectList(m['pairs']).map(SynonymPair.fromJson).toList(),
      );
}

/// A single token in a decomposed sentence.
class SentenceToken {
  const SentenceToken({
    required this.surface,
    this.lemma,
    required this.gloss,
    required this.role,
  });

  final String surface;
  final String? lemma;
  final String gloss;
  final String role;

  static SentenceToken fromJson(Map<String, dynamic> m) => SentenceToken(
        surface: (m['surface'] ?? '').toString(),
        lemma: m['lemma']?.toString(),
        gloss: (m['gloss'] ?? '').toString(),
        role: (m['role'] ?? '').toString(),
      );
}

/// Token-by-token decomposition of a sentence plus a structure summary.
class SentenceBreakdown {
  const SentenceBreakdown({
    this.tokens = const [],
    this.structure = '',
  });

  final List<SentenceToken> tokens;
  final String structure;

  static SentenceBreakdown fromJson(Map<String, dynamic> m) =>
      SentenceBreakdown(
        tokens: _objectList(m['tokens']).map(SentenceToken.fromJson).toList(),
        structure: (m['structure'] ?? '').toString(),
      );
}

/// Explanation of why a learner's answer was wrong and how to avoid it.
class WhyWrongExplanation {
  const WhyWrongExplanation({
    required this.whyWrong,
    required this.whatYouProbablyThought,
    required this.howToRemember,
  });

  final String whyWrong;
  final String whatYouProbablyThought;
  final String howToRemember;

  static WhyWrongExplanation fromJson(Map<String, dynamic> m) =>
      WhyWrongExplanation(
        whyWrong: (m['whyWrong'] ?? '').toString(),
        whatYouProbablyThought: (m['whatYouProbablyThought'] ?? '').toString(),
        howToRemember: (m['howToRemember'] ?? '').toString(),
      );
}

/// Strip a leading ```lang fence and trailing ``` so a model reply that
/// ignored the "no fences" instruction still decodes.
String stripCodeFences(String s) {
  var cleaned = s.trim();
  if (cleaned.startsWith('```')) {
    cleaned = cleaned
        .replaceAll(RegExp(r'^```\w*\n?'), '')
        .replaceAll(RegExp(r'\n?```$'), '')
        .trim();
  }
  return cleaned;
}

/// Decode a model reply into a JSON object, stripping code fences first.
/// Throws a [FormatException] (via [jsonDecode]) when the reply is not JSON.
Map<String, dynamic> decodeJsonObject(String reply) =>
    jsonDecode(stripCodeFences(reply)) as Map<String, dynamic>;
