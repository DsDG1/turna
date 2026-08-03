// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/application/srs_queue_provider.dart';
import 'package:turna/core/sm2.dart';
import 'package:turna/domain/course/lesson_word_link.dart';
import 'package:turna/domain/course/srs_word.dart';
import 'package:turna/service/locator.dart';

/// Manages word + expression SRS state in the `srs_states` SQLite table
/// (queue `'srs'`; migrated from [LocalStateKeys.srsState] in schema v7).
@lazySingleton
class SrsProvider extends SrsQueueProvider {
  SrsProvider(super.appPrefs, super.linkStore, super.srsDao);

  List<SrsWord>? _cachedDueExpressions;
  DateTime? _cachedExpressionDueAt;
  int? _cachedExpressionDueCount;
  Set<String>? _cachedDueWordIdSet;

  @override
  String get statePrefsKey => LocalStateKeys.srsState;

  @override
  String get queueId => 'srs';

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

  /// Bulk-import externally-migrated SRS states (Anki deck import). Existing
  /// ids are skipped so re-imports are idempotent.
  Future<void> bulkImportStates(Map<String, SrsWord> states) =>
      importStates(states);

  /// Remove all entries whose id starts with [prefix] (Anki deck uninstall).
  Future<void> removeByPrefix(String prefix) => removeItemsByPrefix(prefix);

  /// Remove only ids created by a failed import transaction.
  Future<void> rollbackImportedIds(Iterable<String> ids) =>
      removeImportedItems(ids);

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

  String? getLessonNameForWord(String wordId) =>
      linkStore.lessonNameFor(wordId);

  String? getLessonNameForExpression(String expressionId) =>
      linkStore.lessonNameFor(expressionId);

  Future<SrsWord?> reviewWord(String wordId, int quality) =>
      reviewItem(wordId, quality);

  Future<SrsWord?> reviewWithQuality(String wordId, ReviewGrade grade) =>
      reviewWithOutcome(wordId, grade.outcome);

  /// Binary pass/fail for a word (记住·做对 / 没记住·做错).
  Future<SrsWord?> reviewWordOutcome(String wordId, ReviewOutcome outcome) =>
      reviewWithOutcome(wordId, outcome);

  Future<bool> undoWordReview(String wordId, SrsWord previous) =>
      undoReview(wordId, previous);

  Future<void> setWordFlags(
    String wordId, {
    bool? suspended,
    bool? buried,
  }) =>
      setItemFlags(wordId, suspended: suspended, buried: buried);

  Future<SrsWord?> reviewExpression(String expressionId, int quality) =>
      reviewItem(expressionId, quality);

  Future<SrsWord?> reviewExpressionWithQuality(
    String expressionId,
    ReviewGrade grade,
  ) =>
      reviewWithOutcome(expressionId, grade.outcome);

  Future<SrsWord?> reviewExpressionOutcome(
    String expressionId,
    ReviewOutcome outcome,
  ) =>
      reviewWithOutcome(expressionId, outcome);

  /// Public surface for [LessonViewModel.undoLastInteraction] to roll back
  /// a word grade captured before the most recent submission. Delegates to
  /// the base class' gate-protected [SrsQueueProvider.undoReview] so an
  /// in-flight grade can't overwrite the restored state. [previous] is the
  /// snapshot taken in [LessonViewModel._applySrsOutcome]; when it is null
  /// (e.g. the grade was for a freshly registered word the lesson never
  /// saw before), we restore the in-memory fresh state, not a freshly
  /// re-registered one — otherwise the undo would silently re-register the
  /// id with a different timestamp.
  Future<bool> rollbackWord(String wordId, SrsWord? previous) =>
      undoReview(wordId, previous ?? state[wordId] ?? SrsWord.fresh(wordId));

  /// Same as [rollbackWord] but for the expression queue.
  Future<bool> rollbackExpression(String expressionId, SrsWord? previous) =>
      undoReview(expressionId, previous ?? state[expressionId] ?? SrsWord.fresh(expressionId));

  /// Words whose `dueAt` is in the past or now (primary due cache).
  List<SrsWord> getDueWords([DateTime? now]) => getDueItems(
        typeFilter: SrsItemType.word,
        now: now,
        usePrimaryCache: true,
      );

  /// Stable identity set of due word ids — cached alongside the primary due
  /// cache so `context.select` equality holds across notifies that don't
  /// change the due set. Avoids rebuilding CourseTree on every SRS notify.
  Set<String> get dueWordIdSet {
    if (_cachedDueWordIdSet != null) return _cachedDueWordIdSet!;
    _cachedDueWordIdSet = getDueWords().map((w) => w.wordId).toSet();
    return _cachedDueWordIdSet!;
  }

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
  int get totalSeen => state.values
      .where((w) => w.type == SrsItemType.word && w.reps >= 1)
      .length;
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
    _cachedDueWordIdSet = null;
  }
}
