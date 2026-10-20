// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/application/grammar_review_provider.dart';
import 'package:turna/application/mistake_provider.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/application/weak_word_quiz_assembler.dart';
import 'package:turna/courses/languages/vocab.dart';
import 'package:turna/domain/ai/ai_course.dart';
import 'package:turna/domain/course/mistake_entry.dart';
import 'package:turna/domain/repositories/i_course_repository.dart';

/// Formats the learner's recent evidence into a bounded prompt block.
///
/// This is the single place where mistakes / weak words / difficult points are
/// turned into model input. Keeping it out of the queue makes the wording
/// testable and keeps the retry path deterministic: the formatted block is
/// stored in the request snapshot, so a retry sees the same evidence even if
/// the learner answered more questions in between.
@lazySingleton
class AiPracticeSourceContextBuilder {
  AiPracticeSourceContextBuilder(
    this._mistakes,
    this._srs,
    this._grammar,
    this._courseRepository,
  );

  final MistakeProvider _mistakes;
  final SrsProvider _srs;
  final GrammarReviewProvider _grammar;
  final ICourseRepository _courseRepository;

  static const int maxMistakes = 20;
  static const int maxWeakWords = 20;
  static const int maxDifficultPoints = 12;

  Future<String> build(AiPracticeSource kind) async {
    switch (kind) {
      case AiPracticeSource.mistakes:
        return _mistakesBlock();
      case AiPracticeSource.weakWords:
        return _weakWordsBlock();
      case AiPracticeSource.difficult:
        return _difficultBlock();
      case AiPracticeSource.custom:
        return '';
    }
  }

  String _mistakesBlock() {
    final entries = _mistakes.recentMistakes(max: maxMistakes);
    if (entries.isEmpty) return 'No recorded mistakes yet.';
    final buf = StringBuffer('Recent mistakes (newest last):');
    for (final entry in entries) {
      final id = entry.wordId ??
          entry.expressionId ??
          entry.grammarPointId ??
          entry.id;
      buf
        ..writeln()
        ..write('- [$id] user="${entry.userAnswer}" '
            'correct="${entry.correctAnswer}"');
      if (entry.grammarPointId != null) buf.write(' grammar');
      if (entry.wordId != null) {
        final vocab = vocabById[entry.wordId!];
        if (vocab != null) {
          buf.write(' ${vocab.term} = ${vocab.translation}');
        }
      }
    }
    return buf.toString();
  }

  String _weakWordsBlock() {
    final weak = WeakWordQuizAssembler.aggregateWeakWords(
      _mistakes.entries,
      limit: maxWeakWords,
    );
    if (weak.isEmpty) return 'No aggregated weak words yet.';
    final buf = StringBuffer('Weak words (repeated mistakes):');
    for (final word in weak) {
      buf
        ..writeln()
        ..write('- [${word.wordId}] "${word.displayText}"')
        ..write(word.translation == null ? '' : ' = ${word.translation}')
        ..write(' (${word.mistakeCount}x)');
    }
    return buf.toString();
  }

  Future<String> _difficultBlock() async {
    final buf = StringBuffer();
    final seenGrammar = <String>{};

    final grammarMistakes = _mistakes.entries
        .where((e) => (e.grammarPointId ?? '').isNotEmpty)
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    for (final entry in grammarMistakes.take(maxDifficultPoints)) {
      final id = entry.grammarPointId!;
      if (!seenGrammar.add(id)) continue;
      var title = id;
      try {
        final point = await _courseRepository.grammarPointById(id);
        title = point?.title ?? id;
      } catch (_) {
        // Best effort: the id alone still gives the model a target.
      }
      buf.writeln('- grammar [$id] $title '
          '(mistakes: ${_countGrammar(id)})');
    }

    final lapses = [
      ..._srs.getLapseWords().map((w) => (word: w, kind: 'word')),
      ..._srs.getLapseExpressions().map((w) => (word: w, kind: 'expression')),
    ]..sort((a, b) => b.word.lapses.compareTo(a.word.lapses));
    for (final item in lapses.take(maxDifficultPoints)) {
      final id = item.word.wordId;
      if (!seenGrammar.add(id)) continue;
      final vocab = vocabById[id];
      buf.writeln('- lapsed ${item.kind} [$id] '
          '${vocab?.term ?? ''}${vocab == null ? '' : ' = ${vocab.translation}'}'
          ' (lapses: ${item.word.lapses})');
    }

    final dueGrammar = _grammar.getDueGrammarPoints().take(8);
    for (final item in dueGrammar) {
      if (!seenGrammar.add(item.wordId)) continue;
      var title = item.wordId;
      try {
        final point = await _courseRepository.grammarPointById(item.wordId);
        title = point?.title ?? item.wordId;
      } catch (_) {
        // Same best-effort fallback as above.
      }
      buf.writeln('- due grammar [${item.wordId}] $title '
          '(lapses: ${item.lapses})');
    }

    if (buf.isEmpty) return 'No difficult points recorded yet.';
    return 'Difficult points (grammar / lapsed items):\n$buf';
  }

  int _countGrammar(String grammarPointId) => _mistakes.entries
      .where((MistakeEntry e) => e.grammarPointId == grammarPointId)
      .length;
}
