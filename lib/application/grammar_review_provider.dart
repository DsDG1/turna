// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:varnamala/application/srs_queue_provider.dart';
import 'package:varnamala/core/sm2.dart';
import 'package:varnamala/domain/course/lesson_word_link.dart';
import 'package:varnamala/domain/course/srs_word.dart';
import 'package:varnamala/service/locator.dart';

/// Parallel SRS queue for grammar points ([LocalStateKeys.grammarReviewState]).
@lazySingleton
class GrammarReviewProvider extends SrsQueueProvider {
  GrammarReviewProvider(super.appPrefs, super.linkStore);

  @override
  String get statePrefsKey => LocalStateKeys.grammarReviewState;

  @override
  String get logTag => 'GrammarReviewProvider';

  void registerGrammarPoint(String id) => registerItem(id);

  /// Force [id] into the due queue immediately (mistake → grammar cross-route).
  Future<void> markDueNow(String id) async {
    final current = state;
    final existing = current[id];
    if (existing == null) {
      current[id] = SrsWord.fresh(id);
    } else {
      current[id] = existing.copyWith(dueAt: DateTime.now());
    }
    await persist(current);
  }

  void registerAll(Iterable<String> ids) => registerAllItems(ids);

  Future<void> recordLessonLinks({
    required Iterable<String> ids,
    required String lessonId,
    required String lessonName,
  }) =>
      recordLinks(
        ids: ids,
        lessonId: lessonId,
        lessonName: lessonName,
        type: LinkType.grammarPoint,
      );

  String? getLessonNameForGrammarPoint(String id) =>
      linkStore.lessonNameFor(id);

  Future<SrsWord?> reviewGrammarPoint(String id, int quality) =>
      reviewItem(id, quality);

  Future<SrsWord?> reviewWithQuality(String id, ReviewGrade grade) =>
      reviewGrammarPoint(id, grade.sm2);

  List<SrsWord> getDueGrammarPoints([DateTime? now]) => getDueItems(now: now);

  int get dueCount => primaryDueCount;
  int get totalSeen => state.values.where((w) => w.reps >= 1).length;
  int get totalRegistered => state.length;
}
