// Project imports:
import 'package:turna/courses/languages/language_content_store.dart';
import 'package:turna/domain/course/language_codes.dart';
import 'package:turna/domain/course/expression.dart';
import 'package:turna/domain/course/grammar_point.dart';
import 'package:turna/domain/course/pos_tag.dart';
import 'package:turna/domain/course/word_entry.dart';

/// Kind of dictionary hit.
enum DictionaryHitKind { vocab, expression, grammar }

/// A single search result for the dictionary page.
class DictionaryHit {
  const DictionaryHit({
    required this.kind,
    required this.id,
    required this.title,
    required this.subtitle,
    this.pronunciation,
    this.posLabel,
    this.speakAsWordId,
    this.speakText,
    this.examples = const <(String, String)>[],
  });

  final DictionaryHitKind kind;
  final String id;
  final String title;
  final String subtitle;
  final String? pronunciation;

  /// Chinese POS label. Null when the word has no closed tag.
  final String? posLabel;

  /// Prefer [AudioController.speakWord] when set.
  final String? speakAsWordId;

  /// Fallback TTS text when no word id.
  final String? speakText;

  /// Linked example expressions as `(term, gloss)` pairs. Only grammar hits
  /// carry examples today — resolved from the same in-memory expression map
  /// the search scans, so no new data source is involved.
  final List<(String, String)> examples;
}

/// Case-insensitive search over vocab / expressions / grammar points.
///
/// Pure function over the in-memory maps populated at startup — no I/O.
List<DictionaryHit> searchDictionary(String query, {int limit = 50}) {
  final q = query.trim().toLowerCase();
  // Target-side matching uses the same language-aware fold as the
  // vocabularyByTerm index (Turkish İ/I handling).
  final qTarget =
      LanguageCodes.lookupFoldKey(query, LanguageContentStore.activeCode);
  if (q.isEmpty) return const [];

  final hits = <DictionaryHit>[];

  for (final entry in vocabById.values) {
    if (_matchesVocab(entry, q, qTarget)) {
      hits.add(_vocabHit(entry));
      if (hits.length >= limit) return hits;
    }
  }

  for (final exp in expressionsById.values) {
    if (_matchesExpression(exp, q)) {
      hits.add(_expressionHit(exp));
      if (hits.length >= limit) return hits;
    }
  }

  for (final gp in grammarPointById.values) {
    if (_matchesGrammar(gp, q)) {
      hits.add(_grammarHit(gp));
      if (hits.length >= limit) return hits;
    }
  }

  return hits;
}

/// Full entry directory in stable store order (vocab → expressions →
/// grammar) — the dictionary landing list before any query.
///
/// Same data source [searchDictionary] scans, just unfiltered; vocabulary and
/// grammar indexes are bounded by the loaded course, so the whole list is
/// cheap to build and rendered lazily by the page.
List<DictionaryHit> listDictionaryEntries() {
  return [
    for (final entry in vocabById.values) _vocabHit(entry),
    for (final exp in expressionsById.values) _expressionHit(exp),
    for (final gp in grammarPointById.values) _grammarHit(gp),
  ];
}

DictionaryHit _vocabHit(WordEntry entry) {
  return DictionaryHit(
    kind: DictionaryHitKind.vocab,
    id: entry.id,
    title: entry.term,
    subtitle: entry.translation,
    pronunciation: entry.pronunciation,
    posLabel: _posLabel(entry.pos),
    speakAsWordId: entry.id,
    speakText: entry.term,
  );
}

DictionaryHit _expressionHit(Expression exp) {
  return DictionaryHit(
    kind: DictionaryHitKind.expression,
    id: exp.id,
    title: exp.term,
    subtitle: exp.translation,
    pronunciation: exp.pronunciation,
    speakText: exp.term,
  );
}

DictionaryHit _grammarHit(GrammarPoint gp) {
  return DictionaryHit(
    kind: DictionaryHitKind.grammar,
    id: gp.id,
    title: gp.title,
    subtitle: gp.explanation,
    speakText: gp.title,
    examples: [
      for (final id in gp.exampleExpressionIds)
        if (expressionsById[id] case final exp?)
          (exp.term, exp.translation),
    ],
  );
}

String? _posLabel(String? raw) {
  final label = posTagLabel(PosTag.parse(raw));
  return label.isEmpty ? null : label;
}

bool _matchesVocab(WordEntry e, String q, String qTarget) {
  if (LanguageCodes.lookupFoldKey(e.term, LanguageContentStore.activeCode)
      .contains(qTarget)) {
    return true;
  }
  if (e.translation.toLowerCase().contains(q)) return true;
  if (e.pronunciation?.toLowerCase().contains(q) == true) return true;
  for (final t in e.tags) {
    if (t.toLowerCase().contains(q)) return true;
  }
  return false;
}

bool _matchesExpression(Expression e, String q) {
  if (e.term.toLowerCase().contains(q)) return true;
  if (e.translation.toLowerCase().contains(q)) return true;
  if (e.pronunciation?.toLowerCase().contains(q) == true) return true;
  for (final t in e.tags) {
    if (t.toLowerCase().contains(q)) return true;
  }
  return false;
}

bool _matchesGrammar(GrammarPoint g, String q) {
  if (g.title.toLowerCase().contains(q)) return true;
  if (g.explanation.toLowerCase().contains(q)) return true;
  return false;
}
