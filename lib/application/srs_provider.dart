// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:varnamala/application/srs_queue_provider.dart';
import 'package:varnamala/core/sm2.dart';
import 'package:varnamala/domain/course/lesson_word_link.dart';
import 'package:varnamala/domain/course/srs_word.dart';
import 'package:varnamala/service/locator.dart';

/// Manages word + expression SRS state in one prefs blob ([LocalStateKeys.srsState]).
@lazySingleton
class SrsProvider extends SrsQueueProvider {
  SrsProvider(super.appPrefs, super.linkStore);

  List<SrsWord>? _cachedDueExpressions;
  DateTime? _cachedExpressionDueAt;
  int? _cachedExpressionDueCount;

  @override
  String get statePrefsKey => LocalStateKeys.srsState;

  @override
  String get logTag => 'SrsProvider';

  /// Register a new word as fresh (due immediately) if not yet seen.
  void registerWord(String wordId) =>
      registerItem(wordId, type: SrsItemType.word);

  /// Register multiple new words.
  void registerAll(Iterable<String> wordIds) =>
      registerAllItems(wordIds, type: SrsItemType.word);

  /// Register a new expression as fresh if not yet seen.
  void registerExpression(String expressionId) =>
      registerItem(expressionId, type: SrsItemType.expression);

  /// Register multiple new expressions.
  void registerAllExpressions(Iterable<String> expressionIds) =>
      registerAllItems(expressionIds, type: SrsItemType.expression);

  /// Persist first-seen lesson links for words/expressions.
  Future<void> recordLessonLinks({
    required Iterable<String> wordIds,
    required String lessonId,
    required String lessonName,
    LinkType type = LinkType.word,
  }) =>
      recordLinks(
        ids: wordIds,
        lessonId: lessonId,
        lessonName: lessonName,
        type: type,
      );

  String? getLessonNameForWord(String wordId) => linkStore.lessonNameFor(wordId);

  String? getLessonNameForExpression(String expressionId) =>
      linkStore.lessonNameFor(expressionId);

  Future<SrsWord?> reviewWord(String wordId, int quality) =>
      reviewItem(wordId, quality);

  Future<SrsWord?> reviewWithQuality(String wordId, ReviewQuality quality) =>
      reviewWord(wordId, quality.sm2);

  Future<SrsWord?> reviewExpression(String expressionId, int quality) =>
      reviewItem(expressionId, quality);

  Future<SrsWord?> reviewExpressionWithQuality(
    String expressionId,
    ReviewQuality quality,
  ) =>
      reviewExpression(expressionId, quality.sm2);

  /// Words whose `dueAt` is in the past or now (primary due cache).
  List<SrsWord> getDueWords([DateTime? now]) => getDueItems(
        typeFilter: SrsItemType.word,
        now: now,
        usePrimaryCache: true,
      );

  /// Expressions whose `dueAt` is in the past or now (secondary cache).
  List<SrsWord> getDueExpressions([DateTime? now]) {
    final cutoff = now ?? DateTime.now();
    if (_cachedDueExpressions != null &&
        _cachedExpressionDueAt != null &&
        !_cachedExpressionDueAt!.isAfter(cutoff)) {
      return _cachedDueExpressions!;
    }
    final result = getDueItems(
      typeFilter: SrsItemType.expression,
      now: cutoff,
      usePrimaryCache: false,
    );
    _cachedDueExpressions = result;
    _cachedExpressionDueAt = cutoff;
    _cachedExpressionDueCount = result.length;
    return result;
  }

  List<SrsWord> getMixedWords(int n) {
    final seen = state.values
        .where((w) => w.type == SrsItemType.word && w.reps >= 1)
        .toList();
    seen.shuffle();
    return seen.take(n).toList();
  }

  List<SrsWord> getMixedExpressions(int n) {
    final seen = state.values
        .where((w) => w.type == SrsItemType.expression && w.reps >= 1)
        .toList();
    seen.shuffle();
    return seen.take(n).toList();
  }

  List<SrsWord> getLapseWords() {
    return state.values
        .where((w) => w.type == SrsItemType.word && w.lapses > 0)
        .toList()
      ..sort((a, b) => b.lapses.compareTo(a.lapses));
  }

  List<SrsWord> getLapseExpressions() {
    return state.values
        .where((w) => w.type == SrsItemType.expression && w.lapses > 0)
        .toList()
      ..sort((a, b) => b.lapses.compareTo(a.lapses));
  }

  int get dueCount => primaryCachedDueCount ?? getDueWords().length;
  int get totalSeen =>
      state.values.where((w) => w.type == SrsItemType.word && w.reps >= 1).length;
  int get totalRegistered =>
      state.values.where((w) => w.type == SrsItemType.word).length;

  int get expressionDueCount =>
      _cachedExpressionDueCount ?? getDueExpressions().length;
  int get expressionTotalSeen => state.values
      .where((w) => w.type == SrsItemType.expression && w.reps >= 1)
      .length;
  int get expressionTotalRegistered =>
      state.values.where((w) => w.type == SrsItemType.expression).length;

  @override
  void invalidateDueCaches() {
    super.invalidateDueCaches();
    _cachedDueExpressions = null;
    _cachedExpressionDueAt = null;
    _cachedExpressionDueCount = null;
  }
}
