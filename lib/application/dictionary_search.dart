// Project imports:
import 'package:turna/courses/languages/language_content_store.dart';
import 'package:turna/domain/course/language_codes.dart';
import 'package:turna/domain/course/expression.dart';
import 'package:turna/domain/course/grammar_point.dart';
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
    this.speakAsWordId,
    this.speakText,
  });

  final DictionaryHitKind kind;
  final String id;
  final String title;
  final String subtitle;
  final String? pronunciation;

  /// Prefer [AudioController.speakWord] when set.
  final String? speakAsWordId;

  /// Fallback TTS text when no word id.
  final String? speakText;
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
      hits.add(DictionaryHit(
        kind: DictionaryHitKind.vocab,
        id: entry.id,
        title: entry.term,
        subtitle: entry.translation,
        pronunciation: entry.pronunciation,
        speakAsWordId: entry.id,
        speakText: entry.term,
      ));
      if (hits.length >= limit) return hits;
    }
  }

  for (final exp in expressionsById.values) {
    if (_matchesExpression(exp, q)) {
      hits.add(DictionaryHit(
        kind: DictionaryHitKind.expression,
        id: exp.id,
        title: exp.term,
        subtitle: exp.translation,
        pronunciation: exp.pronunciation,
        speakText: exp.term,
      ));
      if (hits.length >= limit) return hits;
    }
  }

  for (final gp in grammarPointById.values) {
    if (_matchesGrammar(gp, q)) {
      hits.add(DictionaryHit(
        kind: DictionaryHitKind.grammar,
        id: gp.id,
        title: gp.title,
        subtitle: gp.explanation,
        speakText: gp.title,
      ));
      if (hits.length >= limit) return hits;
    }
  }

  return hits;
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
