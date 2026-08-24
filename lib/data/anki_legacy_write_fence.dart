import 'package:turna/data/anki_owner_authority_dao.dart';
import 'package:turna/data/course_database.dart';

/// Why a Legacy writer is touching anki data (plan 34 §R4-1).
enum LegacyWriteIntent {
  /// Ordinary product write (review answer, import, projection rebuild).
  /// Denied once the source's write fence is frozen or officialOnly.
  normalLegacyWrite,

  /// Migration read paths never mutate; declaring this intent on a
  /// mutator is a programming error and always denied.
  migrationRead,

  /// One-shot cleanup owned by the migration saga (deleteByImport during
  /// cutover). Allowed only while the saga holds an unconsumed cleanup
  /// token for the source.
  migrationCleanup,

  /// Restoring Legacy state during a verified rollback. Allowed only
  /// while the source's transition is in rollbackPending.
  rollbackRestore,
}

/// Thrown when a Legacy mutator hits a write fence (plan 34 §R4-1: freeze
/// is a behavior, not a comment).
class LegacyWriteDenied implements Exception {
  const LegacyWriteDenied({
    required this.importId,
    required this.operation,
    required this.fence,
    required this.intent,
  });

  final String importId;
  final String operation;
  final AnkiWriteFence fence;
  final LegacyWriteIntent intent;

  @override
  String toString() => 'LegacyWriteDenied(import=$importId, op=$operation, '
      'fence=${fence.name}, intent=${intent.name})';
}

/// One-time token authorizing migration cleanup for a single source.
class LegacyMigrationCleanupToken {
  LegacyMigrationCleanupToken({required this.courseId, required this.token});

  final String courseId;
  final String token;
  bool consumed = false;
}

/// In-memory projection of `anki_course_sources.write_fence` for sync
/// enforcement inside Legacy DAO mutators.
///
/// The authority lives in CourseDatabase (async drift); Legacy mutators
/// are synchronous, so this registry is loaded at startup (before any
/// writer runs) and updated by the owner-authority transitions in the
/// same flow that commits them. A crash between the DB write and the
/// registry update is healed by the next app start's [loadFrom].
class LegacyWriteFence {
  LegacyWriteFence._();

  static final LegacyWriteFence instance = LegacyWriteFence._();

  final Map<String, AnkiWriteFence> _fenceByImportId = {};
  final Map<String, AnkiWriteFence> _fenceByCourseId = {};
  final Map<String, String> _sourceByLegacyImportId = {};
  final Map<String, LegacyMigrationCleanupToken> _cleanupTokensByCourse = {};
  final Set<String> _rollbackPendingCourses = {};

  /// Loads every source's fence from the authority table. Idempotent.
  /// Legacy import ids linked by a transition inherit their source's
  /// fence, so pre-cutover writers are fenced through the id they know.
  Future<void> loadFrom(CourseDatabase db) async {
    final dao = AnkiOwnerAuthorityDao(db);
    final rows = await dao.listSources('profile-default-01');
    _fenceByImportId.clear();
    _fenceByCourseId.clear();
    for (final row in rows) {
      _fenceByImportId[row.sourceId] = row.writeFence;
      _fenceByCourseId[row.courseId] = row.writeFence;
    }
    _sourceByLegacyImportId.clear();
    final transitions = await db
        .customSelect(
          'SELECT legacy_import_id, official_source_id FROM '
          'anki_owner_transitions WHERE legacy_import_id IS NOT NULL',
        )
        .get();
    for (final row in transitions) {
      final legacyId = row.read<String>('legacy_import_id');
      final sourceId = row.read<String>('official_source_id');
      final fence = _fenceByImportId[sourceId];
      if (fence != null && legacyId.isNotEmpty) {
        _fenceByImportId[legacyId] = fence;
        _sourceByLegacyImportId[legacyId] = sourceId;
      }
    }
  }

  /// Called by the owner-authority DAO whenever a fence transitions.
  void updateFence({
    required String courseId,
    required String sourceId,
    required AnkiWriteFence fence,
  }) {
    _fenceByImportId[sourceId] = fence;
    _fenceByCourseId[courseId] = fence;
    // Linked legacy import ids follow their source's fence.
    _sourceByLegacyImportId.forEach((legacyId, linkedSource) {
      if (linkedSource == sourceId) {
        _fenceByImportId[legacyId] = fence;
      }
    });
  }

  /// Issues a one-time cleanup token for a frozen source (migration saga).
  LegacyMigrationCleanupToken issueCleanupToken(String courseId) {
    final token = LegacyMigrationCleanupToken(
      courseId: courseId,
      token: 'cleanup-$courseId-${DateTime.now().microsecondsSinceEpoch}',
    );
    _cleanupTokensByCourse[courseId] = token;
    return token;
  }

  /// Marks a course as actively rolling back (enables rollbackRestore).
  void beginRollback(String courseId) {
    _rollbackPendingCourses.add(courseId);
  }

  void endRollback(String courseId) {
    _rollbackPendingCourses.remove(courseId);
  }

  AnkiWriteFence fenceFor(String importId) =>
      _fenceByImportId[importId] ?? AnkiWriteFence.open;

  /// Sync fence check for Legacy mutators. [importId] is the import or
  /// source id the mutation targets; global mutators pass null and are
  /// only denied when EVERY known source is fenced (conservative: a
  /// global write touching fenced data is the saga's cleanup problem).
  void assertAllowed({
    required String? importId,
    required String operation,
    LegacyWriteIntent intent = LegacyWriteIntent.normalLegacyWrite,
    LegacyMigrationCleanupToken? cleanupToken,
    String? courseId,
  }) {
    if (intent == LegacyWriteIntent.migrationRead) {
      throw StateError(
        'migrationRead declared on mutating operation "$operation"',
      );
    }
    final fence = courseId != null
        ? (_fenceByCourseId[courseId] ?? AnkiWriteFence.open)
        : (importId != null && importId.isNotEmpty
            ? fenceFor(importId)
            : _aggregateFence());
    switch (fence) {
      case AnkiWriteFence.open:
        return;
      case AnkiWriteFence.frozen:
        if (intent == LegacyWriteIntent.normalLegacyWrite) {
          throw LegacyWriteDenied(
            importId: importId ?? '(global)',
            operation: operation,
            fence: fence,
            intent: intent,
          );
        }
        if (intent == LegacyWriteIntent.rollbackRestore) {
          // Rollback restore is a Legacy write by design; it is gated by
          // the rollback-pending marker, not the fence alone.
          final course = courseId ?? '';
          if (course.isEmpty || !_rollbackPendingCourses.contains(course)) {
            throw LegacyWriteDenied(
              importId: importId ?? '(global)',
              operation: operation,
              fence: fence,
              intent: intent,
            );
          }
          return;
        }
        // migrationCleanup: require an unconsumed token for the course.
        _requireCleanupToken(
            cleanupToken, courseId, importId, operation, fence, intent);
      case AnkiWriteFence.officialOnly:
        if (intent == LegacyWriteIntent.normalLegacyWrite) {
          throw LegacyWriteDenied(
            importId: importId ?? '(global)',
            operation: operation,
            fence: fence,
            intent: intent,
          );
        }
        _requireCleanupToken(
            cleanupToken, courseId, importId, operation, fence, intent);
    }
  }

  void _requireCleanupToken(
    LegacyMigrationCleanupToken? token,
    String? courseId,
    String? importId,
    String operation,
    AnkiWriteFence fence,
    LegacyWriteIntent intent,
  ) {
    final effectiveCourse = courseId ?? '';
    final valid = token != null &&
        !token.consumed &&
        token.courseId == effectiveCourse &&
        _cleanupTokensByCourse[effectiveCourse] == token;
    if (!valid) {
      throw LegacyWriteDenied(
        importId: importId ?? '(global)',
        operation: operation,
        fence: fence,
        intent: intent,
      );
    }
  }

  AnkiWriteFence _aggregateFence() {
    var sawFrozen = false;
    var sawOfficialOnly = false;
    for (final fence in _fenceByImportId.values) {
      if (fence == AnkiWriteFence.officialOnly) sawOfficialOnly = true;
      if (fence == AnkiWriteFence.frozen) sawFrozen = true;
    }
    if (sawOfficialOnly) return AnkiWriteFence.officialOnly;
    if (sawFrozen) return AnkiWriteFence.frozen;
    return AnkiWriteFence.open;
  }

  /// Test seam.
  void debugReset() {
    _fenceByImportId.clear();
    _fenceByCourseId.clear();
    _sourceByLegacyImportId.clear();
    _cleanupTokensByCourse.clear();
    _rollbackPendingCourses.clear();
  }
}
