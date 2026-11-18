import 'package:turna/domain/anki/official_anki_v2_view_models.dart';

/// Persistence contract for the derived `anki_course_tree_view` table
/// (ADR 0043). Implemented in `lib/data/official_anki_v2_view_store.dart`.
abstract class IOfficialAnkiV2ViewStore {
  Future<void> replaceAll({
    required List<OfficialAnkiV2ViewRow> rows,
    required int rebuiltAtMillis,
  });

  Future<void> replaceScoped({
    required Set<String> liveSourceIds,
    required Map<String, List<OfficialAnkiV2ViewRow>> rowsBySource,
    required int rebuiltAtMillis,
    void Function(int inserted, int total)? onInserted,
  });

  Future<int> distinctSectionCount();

  Future<int> splitSectionCount();

  Future<int> distinctLessonCount();

  Future<bool> get isAvailable;

  Future<int> cardCountForSource(String sourceId);

  Future<List<OfficialAnkiV2ViewSectionSummary>> sectionSummaries();

  Future<List<OfficialAnkiV2ViewRow>> rowsForLesson(String lessonId);

  Future<List<OfficialAnkiV2ViewRow>> treeRows();

  Future<Set<String>> lessonIds();

  Future<Map<String, String>> lessonKeysById();

  Future<List<int>> cardIdsForSource(String sourceId);

  Future<void> deleteBySource(String sourceId);

  Future<void> clear();
}
