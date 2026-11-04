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
///
/// Matching runs against a memoized pre-normalized index (see [_SearchIndex]):
/// fold/lowercase happens once per content generation instead of once per
/// query, so each query is allocation-free scanning over plain strings. The
/// matchers below are field-for-field equivalent to the naive scan this
/// replaced — same fields, same contains semantics, same vocab → expression →
/// grammar ordering and limit truncation.
List<DictionaryHit> searchDictionary(String query, {int limit = 50}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];
  final index = _loadSearchIndex();
  // Target-side matching uses the same language-aware fold as the
  // vocabularyByTerm index (Turkish İ/I handling). The index applies the
  // same fold at build time; a language switch republishes the globals and
  // bumps the generation, so build and query sides always agree.
  final qTarget =
      LanguageCodes.lookupFoldKey(query, LanguageContentStore.activeCode);

  final hits = <DictionaryHit>[];

  for (final keys in index.vocab) {
    if (_matchesVocabKeys(keys, q, qTarget)) {
      hits.add(_vocabHit(keys.entry));
      if (hits.length >= limit) return hits;
    }
  }

  for (final keys in index.expressions) {
    if (_matchesExpressionKeys(keys, q)) {
      hits.add(_expressionHit(keys.entry));
      if (hits.length >= limit) return hits;
    }
  }

  for (final keys in index.grammar) {
    if (_matchesGrammarKeys(keys, q)) {
      hits.add(_grammarHit(keys.entry));
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

bool _matchesVocabKeys(_VocabKeys keys, String q, String qTarget) {
  if (keys.foldedTerm.contains(qTarget)) return true;
  if (keys.lowerTranslation.contains(q)) return true;
  if (keys.lowerPronunciation?.contains(q) == true) return true;
  for (final t in keys.lowerTags) {
    if (t.contains(q)) return true;
  }
  return false;
}

bool _matchesExpressionKeys(_ExpressionKeys keys, String q) {
  if (keys.lowerTerm.contains(q)) return true;
  if (keys.lowerTranslation.contains(q)) return true;
  if (keys.lowerPronunciation?.contains(q) == true) return true;
  for (final t in keys.lowerTags) {
    if (t.contains(q)) return true;
  }
  return false;
}

bool _matchesGrammarKeys(_GrammarKeys keys, String q) {
  if (keys.lowerTitle.contains(q)) return true;
  if (keys.lowerExplanation.contains(q)) return true;
  return false;
}

/// Normalized search keys for one vocab entry, computed once per index build.
final class _VocabKeys {
  const _VocabKeys(
    this.entry,
    this.foldedTerm,
    this.lowerTranslation,
    this.lowerPronunciation,
    this.lowerTags,
  );

  final WordEntry entry;
  final String foldedTerm;
  final String lowerTranslation;
  final String? lowerPronunciation;
  final List<String> lowerTags;
}

final class _ExpressionKeys {
  const _ExpressionKeys(
    this.entry,
    this.lowerTerm,
    this.lowerTranslation,
    this.lowerPronunciation,
    this.lowerTags,
  );

  final Expression entry;
  final String lowerTerm;
  final String lowerTranslation;
  final String? lowerPronunciation;
  final List<String> lowerTags;
}

final class _GrammarKeys {
  const _GrammarKeys(this.entry, this.lowerTitle, this.lowerExplanation);

  final GrammarPoint entry;
  final String lowerTitle;
  final String lowerExplanation;
}

/// Memoized pre-normalized view of the global content maps, in store order
/// (vocab → expressions → grammar) so hit ordering matches the naive scan.
final class _SearchIndex {
  _SearchIndex(this.key, this.vocab, this.expressions, this.grammar);

  /// Staleness fingerprint of the globals this index was built from:
  /// - generation — [LanguageContentStore.globalsGeneration]; bumps on
  ///   language switch / drop / reset, which also covers the language-aware
  ///   term fold having to be recomputed for the new active language.
  /// - the three map lengths — the globals are refilled in place (identity
  ///   never changes), and in-place insertions/removals (tests seed the maps
  ///   directly) change a length without touching the generation.
  final (int, int, int, int) key;

  final List<_VocabKeys> vocab;
  final List<_ExpressionKeys> expressions;
  final List<_GrammarKeys> grammar;
}

_SearchIndex? _searchIndexMemo;

_SearchIndex _loadSearchIndex() {
  final key = (
    LanguageContentStore.globalsGeneration,
    vocabById.length,
    expressionsById.length,
    grammarPointById.length,
  );
  final memo = _searchIndexMemo;
  if (memo != null && memo.key == key) return memo;
  final index = _buildSearchIndex(key);
  return _searchIndexMemo = index;
}

_SearchIndex _buildSearchIndex((int, int, int, int) key) {
  final code = LanguageContentStore.activeCode;
  return _SearchIndex(
    key,
    [
      for (final entry in vocabById.values)
        _VocabKeys(
          entry,
          LanguageCodes.lookupFoldKey(entry.term, code),
          entry.translation.toLowerCase(),
          entry.pronunciation?.toLowerCase(),
          [for (final t in entry.tags) t.toLowerCase()],
        ),
    ],
    [
      for (final exp in expressionsById.values)
        _ExpressionKeys(
          exp,
          exp.term.toLowerCase(),
          exp.translation.toLowerCase(),
          exp.pronunciation?.toLowerCase(),
          [for (final t in exp.tags) t.toLowerCase()],
        ),
    ],
    [
      for (final gp in grammarPointById.values)
        _GrammarKeys(
          gp,
          gp.title.toLowerCase(),
          gp.explanation.toLowerCase(),
        ),
    ],
  );
}
