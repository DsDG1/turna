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

  Future<Set<CanonicalCardKey>> introducedKeys({
    required String courseId,
    required AnkiBackendKind backend,
    required String profileId,
  }) async {
    final rows = await _db.customSelect(
      '''
      SELECT source_id, card_id
      FROM anki_card_introduction_states
      WHERE course_id = ? AND status = 'introduced'
      ''',
      variables: [Variable.withString(courseId)],
    ).get();
    return {
      for (final row in rows)
        CanonicalCardKey(
          backend: backend,
          profileId: profileId,
          sourceId: row.read<String>('source_id'),
          cardId: row.read<int>('card_id'),
        ),
    };
  }

  /// Every introduction row as a flat (source, card, status) ref.
  ///
  /// The cold-start read for [CardIntroductionStore.hydrateFromLedger]:
  /// status is returned raw so the caller decides which states it folds
  /// into memory.
  Future<List<({String sourceId, int cardId, CardIntroductionStatus status})>>
      allIntroductionRefs() async {
    final rows = await _db.customSelect(
      '''
      SELECT source_id, card_id, status
      FROM anki_card_introduction_states
      ''',
    ).get();
    return [
      for (final row in rows)
        (
          sourceId: row.read<String>('source_id'),
          cardId: row.read<int>('card_id'),
          status: CardIntroductionStatus.values
              .byName(row.read<String>('status')),
        ),
    ];
  }

  Future<int> countByStatus({
    required String courseId,
    required CardIntroductionStatus status,
  }) async {
    final rows = await _db.customSelect(
      '''
      SELECT COUNT(*) AS n
      FROM anki_card_introduction_states
      WHERE course_id = ? AND status = ?
      ''',
      variables: [
        Variable.withString(courseId),
        Variable.withString(status.name),
      ],
    ).get();
    if (rows.isEmpty) return 0;
    return rows.single.read<int>('n');
  }

  Future<int> countIntroducedForSource({
    required String courseId,
    required String sourceId,
  }) async {
    final rows = await _db.customSelect(
      '''
      SELECT COUNT(*) AS n
      FROM anki_card_introduction_states
      WHERE course_id = ? AND source_id = ? AND status = 'introduced'
      ''',
      variables: [
        Variable.withString(courseId),
        Variable.withString(sourceId),
      ],
    ).get();
    if (rows.isEmpty) return 0;
    return rows.single.read<int>('n');
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

  Future<void> insertActivePlacement({
    required String placementId,
    required String courseId,
    required String profileId,
    required CanonicalCardKey key,
    required String sectionId,
    required String unitId,
    required String lessonId,
    required int order,
    required String sourceFingerprint,
  }) async {
    await _db.customStatement(
      '''
      INSERT INTO anki_course_card_placements (
        placement_id, course_id, profile_id, source_id, card_id,
        section_id, unit_id, lesson_id, display_order, active,
        projection_version, source_fingerprint, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 1, 1, ?, ?, ?)
      ''',
      [
        placementId,
        courseId,
        profileId,
        key.sourceId,
        key.cardId,
        sectionId,
        unitId,
        lessonId,
        order,
        sourceFingerprint,
        DateTime.now().millisecondsSinceEpoch,
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
  }

  Future<void> insertActivePresentation({
    required String courseId,
    required CanonicalCardKey key,
    required String kind,
    required String payloadJson,
    required String sourceFingerprint,
  }) async {
    await _db.customStatement(
      '''
      INSERT INTO anki_card_presentations (
        course_id, source_id, card_id, presentation_kind, payload_json,
        status, mapping_version, classifier_version, source_fingerprint,
        user_confirmed, updated_at
      ) VALUES (?, ?, ?, ?, ?, 'active', 1, 1, ?, 0, ?)
      ''',
      [
        courseId,
        key.sourceId,
        key.cardId,
        kind,
        payloadJson,
        sourceFingerprint,
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
  }

  /// Remove only the rebuildable placement/presentation rows for a course.
  /// Re-import uses this inside its enclosing transaction before inserting
  /// the new source fingerprint. Introduction state and product events are
  /// retained so replacing a package never erases learning history.
  Future<void> deleteProjectionIdentityByCourseId(String courseId) async {
    for (final table in const [
      'anki_course_card_placements',
      'anki_card_presentations',
    ]) {
      await _db.customStatement(
        'DELETE FROM $table WHERE course_id = ?',
        [courseId],
      );
    }
  }

  /// P5F-31: drop every unification row owned by [courseId] (official source
  /// uninstall). These tables have no inbound foreign keys, so plain deletes
  /// in any order are safe inside the caller's flow.
  Future<void> deleteByCourseId(String courseId) async {
    for (final table in const [
      'anki_course_card_placements',
      'anki_card_presentations',
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
