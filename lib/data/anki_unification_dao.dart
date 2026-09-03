import 'package:drift/drift.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/domain/anki/canonical_card_key.dart';
import 'package:turna/domain/anki/card_introduction_state.dart';

/// Persistence for course placement / presentation / introduction tables
/// added in schema v18. Scheduling remains in the source-owned ledger.
class AnkiUnificationDao {
  AnkiUnificationDao(this._db);

  final CourseDatabase _db;

  /// Runs [action] inside a single database transaction so multi-row
  /// identity writes are all-or-nothing (a thrown error rolls back every
  /// insert in the batch).
  Future<T> transaction<T>(Future<T> Function() action) =>
      _db.transaction(action);

  Future<void> upsertIntroduction({
    required String courseId,
    required CanonicalCardKey key,
    required CardIntroductionStatus status,
    CardIntroducedBy? introducedBy,
    DateTime? introducedAt,
    String? firstLessonId,
    DateTime? lastStudiedAt,
  }) async {
    await _db.customStatement(
      '''
      INSERT INTO anki_card_introduction_states (
        course_id, source_id, card_id, status, introduced_by,
        introduced_at, first_lesson_id, last_studied_at, version
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1)
      ON CONFLICT(course_id, source_id, card_id) DO UPDATE SET
        status = excluded.status,
        introduced_by = COALESCE(anki_card_introduction_states.introduced_by, excluded.introduced_by),
        introduced_at = COALESCE(anki_card_introduction_states.introduced_at, excluded.introduced_at),
        first_lesson_id = COALESCE(anki_card_introduction_states.first_lesson_id, excluded.first_lesson_id),
        last_studied_at = excluded.last_studied_at,
        version = anki_card_introduction_states.version + 1
      ''',
      [
        courseId,
        key.sourceId,
        key.cardId,
        status.name,
        introducedBy?.name,
        introducedAt?.millisecondsSinceEpoch,
        firstLessonId,
        lastStudiedAt?.millisecondsSinceEpoch,
      ],
    );
  }

  Future<CardIntroductionState> introductionState({
    required String courseId,
    required CanonicalCardKey key,
  }) async {
    final rows = await _db.customSelect(
      '''
      SELECT status, introduced_by, introduced_at, first_lesson_id,
             last_studied_at, version
      FROM anki_card_introduction_states
      WHERE course_id = ? AND source_id = ? AND card_id = ?
      ''',
      variables: [
        Variable.withString(courseId),
        Variable.withString(key.sourceId),
        Variable.withInt(key.cardId),
      ],
    ).get();
    if (rows.isEmpty) {
      return CardIntroductionState(
        courseId: courseId,
        cardKey: key,
        status: CardIntroductionStatus.unintroduced,
      );
    }
    final row = rows.single;
    DateTime? millis(String column) {
      final value = row.data[column];
      if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
      return null;
    }

    CardIntroductionStatus status;
    final rawStatus = row.read<String>('status');
    status = CardIntroductionStatus.values.firstWhere(
      (value) => value.name == rawStatus,
      orElse: () => CardIntroductionStatus.unintroduced,
    );
    final rawBy = row.data['introduced_by'] as String?;
    final by = rawBy == null
        ? null
        : CardIntroducedBy.values.firstWhere(
            (value) => value.name == rawBy,
            orElse: () => CardIntroducedBy.migration,
          );
    return CardIntroductionState(
      courseId: courseId,
      cardKey: key,
      status: status,
      introducedBy: by,
      introducedAt: millis('introduced_at'),
      firstLessonId: row.data['first_lesson_id'] as String?,
      lastStudiedAt: millis('last_studied_at'),
      version: row.read<int>('version'),
    );
  }

  /// Introduced card ids of one source, straight from the ledger. P1: this
  /// is the authoritative read for the scheduler lock (what may never be
  /// suspended) and for completion unlocking — neither depends on any
  /// in-memory mirror.
  Future<Set<int>> introducedCardIdsForSource({
    required String sourceId,
  }) async {
    final rows = await _db.customSelect(
      '''
      SELECT card_id
      FROM anki_card_introduction_states
      WHERE source_id = ? AND status = 'introduced'
      ''',
      variables: [Variable.withString(sourceId)],
    ).get();
    return {for (final row in rows) row.read<int>('card_id')};
  }

  /// Insert an initial row without clobbering a later introduced/retired state.
  Future<void> ensureInitial({
    required String courseId,
    required CanonicalCardKey key,
    required CardIntroductionStatus status,
    CardIntroducedBy? introducedBy,
    DateTime? introducedAt,
    String? firstLessonId,
  }) async {
    await _db.customStatement(
      '''
      INSERT INTO anki_card_introduction_states (
        course_id, source_id, card_id, status, introduced_by,
        introduced_at, first_lesson_id, last_studied_at, version
      ) VALUES (?, ?, ?, ?, ?, ?, ?, NULL, 1)
      ON CONFLICT(course_id, source_id, card_id) DO NOTHING
      ''',
      [
        courseId,
        key.sourceId,
        key.cardId,
        status.name,
        introducedBy?.name,
        introducedAt?.millisecondsSinceEpoch,
        firstLessonId,
      ],
    );
  }

  /// Upgrades one card's introduction row to introduced because imported
  /// history (reps>=1) proves it was already studied. Returns whether the
  /// row was inserted or upgraded; rows already introduced or retired are
  /// left untouched — a backfill must never rewrite the course-taught or
  /// retired lifecycle.
  Future<bool> adoptImportedHistory({
    required String courseId,
    required CanonicalCardKey key,
    required DateTime adoptedAt,
  }) async {
    final affected = await _db.customUpdate(
      '''
      INSERT INTO anki_card_introduction_states (
        course_id, source_id, card_id, status, introduced_by,
        introduced_at, first_lesson_id, last_studied_at, version
      ) VALUES (?, ?, ?, 'introduced', 'importedHistory', ?, NULL, ?, 1)
      ON CONFLICT(course_id, source_id, card_id) DO UPDATE SET
        status = 'introduced',
        introduced_by = COALESCE(
          anki_card_introduction_states.introduced_by, 'importedHistory'),
        introduced_at = COALESCE(
          anki_card_introduction_states.introduced_at, excluded.introduced_at),
        last_studied_at = excluded.last_studied_at,
        version = anki_card_introduction_states.version + 1
      WHERE anki_card_introduction_states.status = 'unintroduced'
      ''',
      variables: [
        Variable.withString(courseId),
        Variable.withString(key.sourceId),
        Variable.withInt(key.cardId),
        Variable.withInt(adoptedAt.millisecondsSinceEpoch),
        Variable.withInt(adoptedAt.millisecondsSinceEpoch),
      ],
    );
    return affected > 0;
  }

  /// P5F-31: drop every unification row owned by [courseId] (official source
  /// uninstall). These tables have no inbound foreign keys, so plain deletes
  /// in any order are safe inside the caller's flow.
  Future<void> deleteByCourseId(String courseId) async {
    for (final table in const [
      'anki_card_introduction_states',
      'study_product_events',
    ]) {
      await _db.customStatement(
        'DELETE FROM $table WHERE course_id = ?',
        [courseId],
      );
    }
  }
}
