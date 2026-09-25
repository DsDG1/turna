// Project imports:
import 'package:turna/application/grammar_review_provider.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/domain/course/srs_word.dart';

/// The lesson SRS undo log (plan P4 extraction from LessonViewModel).
///
/// One entry per queue an interaction touched (word / expression / grammar
/// point), captured AFTER `register*` so a never-before-seen item's
/// `previous` reflects the fresh state the register just inserted — undo
/// then restores the "never seen" condition the user expected.
///
/// [rollbackAll] drains in LIFO order; an entry blocked by an in-flight
/// grade gate is pushed back and reported so the UI keeps the undo affordance.
class LessonSrsUndoLog {
  LessonSrsUndoLog({
    required SrsProvider srs,
    required GrammarReviewProvider grammar,
  })  : _srs = srs,
        _grammar = grammar;

  final SrsProvider _srs;
  final GrammarReviewProvider _grammar;
  final List<_SrsUndoEntry> _entries = [];

  bool get isEmpty => _entries.isEmpty;

  void captureWord(String id, SrsWord? previous) =>
      _entries.add(_SrsUndoEntry(id, previous));

  void captureExpression(String id, SrsWord? previous) =>
      _entries.add(_SrsUndoEntry(id, previous, isExpression: true));

  void captureGrammarPoint(String id, SrsWord? previous) => _entries
      .add(_SrsUndoEntry(id, previous, isGrammarPoint: true));

  /// Rolls every captured entry back in LIFO order. Returns false (and
  /// keeps the blocked entry at the top) when a rollback gate is held.
  Future<bool> rollbackAll() async {
    while (_entries.isNotEmpty) {
      final entry = _entries.removeLast();
      final ok = entry.isGrammarPoint
          ? await _grammar.rollbackGrammarPoint(entry.id, entry.previous)
          : entry.isExpression
              ? await _srs.rollbackExpression(entry.id, entry.previous)
              : await _srs.rollbackWord(entry.id, entry.previous);
      if (!ok) {
        _entries.add(entry);
        return false;
      }
    }
    return true;
  }

  void clear() => _entries.clear();
}

class _SrsUndoEntry {
  final String id;
  final SrsWord? previous;
  final bool isExpression;
  final bool isGrammarPoint;

  const _SrsUndoEntry(
    this.id,
    this.previous, {
    this.isExpression = false,
    this.isGrammarPoint = false,
  });
}
