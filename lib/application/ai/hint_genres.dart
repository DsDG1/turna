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

  String toPlainText() {
    final buf = StringBuffer()
      ..writeln('错在哪：$whyWrong')
      ..writeln('你可能以为：$whatYouProbablyThought')
      ..writeln('如何记住：$howToRemember');
    return buf.toString().trimRight();
  }
}

/// Dictionary AI enrichment (examples + mnemonic; optional synonyms/gloss).
class DictionaryEnrichment {
  const DictionaryEnrichment({
    required this.term,
    this.expandedGloss = '',
    this.examples = const [],
    this.pairs = const [],
    this.mnemonic = '',
  });

  final String term;
  final String expandedGloss;
  final List<String> examples;
  final List<SynonymPair> pairs;
  final String mnemonic;

  static DictionaryEnrichment fromJson(
    Map<String, dynamic> m, {
    String term = '',
  }) =>
      DictionaryEnrichment(
        term: term.isNotEmpty ? term : (m['term'] ?? '').toString(),
        expandedGloss: (m['expandedGloss'] ?? '').toString(),
        examples: _stringList(m['examples']),
        pairs: _objectList(m['pairs']).map(SynonymPair.fromJson).toList(),
        mnemonic: (m['mnemonic'] ?? '').toString(),
      );

  String toPlainText() {
    final buf = StringBuffer();
    if (term.isNotEmpty) buf.writeln(term);
    if (expandedGloss.isNotEmpty) buf.writeln(expandedGloss);
    if (examples.isNotEmpty) {
      buf.writeln('例句：');
      for (final e in examples) {
        buf.writeln('- $e');
      }
    }
    if (mnemonic.isNotEmpty) buf.writeln('记忆钩：$mnemonic');
    if (pairs.isNotEmpty) {
      buf.writeln('近义：');
      for (final p in pairs) {
        buf.writeln('- ${p.a} / ${p.b}: ${p.nuance}');
      }
    }
    return buf.toString().trimRight();
  }
}

/// One weak area inside a diagnosis report.
class DiagnosisWeakArea {
  const DiagnosisWeakArea({
    required this.title,
    this.severity = 'medium',
    this.evidence = const [],
  });

  final String title;
  final String severity;
  final List<String> evidence;

  static DiagnosisWeakArea fromJson(Map<String, dynamic> m) =>
      DiagnosisWeakArea(
        title: (m['title'] ?? '').toString(),
        severity: (m['severity'] ?? 'medium').toString(),
        evidence: _stringList(m['evidence']),
      );
}

/// Text-only learning diagnosis (not a course tree).
class DiagnosisReport {
  DiagnosisReport({
    this.weakAreas = const [],
    this.priorityTips = const [],
    this.exampleDrillIdeas = const [],
    DateTime? generatedAt,
  }) : generatedAt = generatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  final List<DiagnosisWeakArea> weakAreas;
  final List<String> priorityTips;
  final List<String> exampleDrillIdeas;
  final DateTime generatedAt;

  static DiagnosisReport fromJson(Map<String, dynamic> m) => DiagnosisReport(
        weakAreas: _objectList(m['weakAreas'])
            .map(DiagnosisWeakArea.fromJson)
            .toList(),
        priorityTips: _stringList(m['priorityTips']),
        exampleDrillIdeas: _stringList(m['exampleDrillIdeas']),
        generatedAt: DateTime.now(),
      );

  String toPlainText() {
    final buf = StringBuffer();
    if (weakAreas.isNotEmpty) {
      buf.writeln('薄弱点：');
      for (final a in weakAreas) {
        buf.writeln('- [${a.severity}] ${a.title}');
        for (final e in a.evidence) {
          buf.writeln('  · $e');
        }
      }
    }
    if (priorityTips.isNotEmpty) {
      buf.writeln('优先建议：');
      for (final t in priorityTips) {
        buf.writeln('- $t');
      }
    }
    if (exampleDrillIdeas.isNotEmpty) {
      buf.writeln('可练想法：');
      for (final t in exampleDrillIdeas) {
        buf.writeln('- $t');
      }
    }
    return buf.toString().trimRight();
  }
}

// Extension methods for existing genres' plain-text export.
extension GrammarExplanationPlainText on GrammarExplanation {
  String toPlainText() {
    final buf = StringBuffer()..writeln(explanation);
    if (relatedExamples.isNotEmpty) {
      buf.writeln('相关例句：');
      for (final e in relatedExamples) {
        buf.writeln('- $e');
      }
    }
    if (contrastWith.isNotEmpty) {
      buf.writeln('易混淆：');
      for (final c in contrastWith) {
        buf.writeln('- $c');
      }
    }
    return buf.toString().trimRight();
  }
}

extension SynonymComparisonPlainText on SynonymComparison {
  String toPlainText() {
    final buf = StringBuffer();
    for (final p in pairs) {
      buf
        ..writeln('${p.a} vs ${p.b}')
        ..writeln('差异：${p.nuance}')
        ..writeln('用 A：${p.whenToUseA}')
        ..writeln('用 B：${p.whenToUseB}');
      if (p.examples.isNotEmpty) {
        for (final e in p.examples) {
          buf.writeln('- $e');
        }
      }
      buf.writeln();
    }
    return buf.toString().trimRight();
  }
}

extension SentenceBreakdownPlainText on SentenceBreakdown {
  String toPlainText() {
    final buf = StringBuffer();
    if (structure.isNotEmpty) buf.writeln('句型：$structure');
    for (final t in tokens) {
      final lemma = t.lemma == null || t.lemma!.isEmpty ? '' : ' (${t.lemma})';
      buf.writeln('${t.surface}$lemma — ${t.gloss} [${t.role}]');
    }
    return buf.toString().trimRight();
  }
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
