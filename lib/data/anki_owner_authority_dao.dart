import 'package:drift/drift.dart';
import 'package:turna/data/anki_legacy_write_fence.dart';
import 'package:turna/data/course_database.dart';

/// Write fence states for an anki course source (plan 34 §6.1).
///
/// - [open]: the Legacy writer still owns mutations.
/// - [frozen]: every ordinary Legacy mutation is rejected; only the
///   migration saga (holding the cleanup token) may proceed.
/// - [officialOnly]: only the Official engine may write. Legacy writes are
///   rejected even for migration cleanup except an explicit rollback token.
enum AnkiWriteFence {
  open,
  frozen,
  officialOnly;

  String get wireName => name;

  static AnkiWriteFence parse(String raw) => switch (raw) {
        'open' => AnkiWriteFence.open,
        'frozen' => AnkiWriteFence.frozen,
        'officialOnly' => AnkiWriteFence.officialOnly,
        _ => throw ArgumentError.value(raw, 'raw', 'unknown write fence'),
      };
}

/// Visibility states for an anki course source. `state` is the single
/// visibility column (plan 34 §6.1 item 1); no second visibility flag may
/// be introduced.
enum AnkiSourceVisibility {
  staging,
  active,
  repairing,
  pendingCleanup,
  retired,
  quarantined;

  String get wireName => name;

  static AnkiSourceVisibility parse(String raw) =>
      AnkiSourceVisibility.values.firstWhere(
        (value) => value.wireName == raw,
        orElse: () => throw ArgumentError.value(raw, 'raw', 'unknown state'),
      );
}

/// Lifecycle of a single Legacy→Official owner cutover (plan 34 §6.2).
enum OwnerTransitionPhase {
  discovered,
  awaitingUserPolicy,
  backingUp,
  importingOfficial,
  verifyingIdentity,
  projectionStaging,
  cutoverReady,
  frozen,
  committing,
  observing,
  complete,
  rollbackPending,
  recoveringForward,
  rolledBackLegacy,
  rollbackEligible,
  noLegacyScheduleRollback;

  String get wireName => name;

  static OwnerTransitionPhase parse(String raw) =>
      OwnerTransitionPhase.values.firstWhere(
        (value) => value.wireName == raw,
        orElse: () => throw ArgumentError.value(raw, 'raw', 'unknown phase'),
      );

  /// Terminal phases excluded from the in-flight unique index.
  bool get isTerminal => switch (this) {
        OwnerTransitionPhase.complete ||
        OwnerTransitionPhase.rolledBackLegacy ||
        OwnerTransitionPhase.rollbackEligible ||
        OwnerTransitionPhase.noLegacyScheduleRollback =>
          true,
        _ => false,
      };
}

/// A row of `anki_course_sources` — the production owner authority (D3).
class AnkiCourseSourceAuthorityRow {
  const AnkiCourseSourceAuthorityRow({
    required this.courseId,
    required this.profileId,
    required this.sourceId,
    required this.backendKind,
    required this.displayName,
    required this.state,
    required this.ownerGeneration,
    required this.writeFence,
    this.activeProjectionGeneration,
    this.lastTransitionId,
  });

  final String courseId;
  final String profileId;
  final String sourceId;
  final String backendKind;
  final String displayName;
  final AnkiSourceVisibility state;
  final int ownerGeneration;
  final AnkiWriteFence writeFence;
  final String? activeProjectionGeneration;
  final String? lastTransitionId;

  bool get isOfficialBackend => backendKind == 'official';
}

/// A row of `anki_owner_transitions`.
class OwnerTransitionRow {
  const OwnerTransitionRow({
    required this.transitionId,
    required this.profileId,
    required this.legacyImportId,
    required this.officialSourceId,
    required this.courseId,
    required this.fromBackend,
    required this.toBackend,
    required this.phase,
    required this.generation,
    required this.policy,
    required this.createdAt,
    required this.updatedAt,
    this.lastErrorCode,
  });

  final String transitionId;
  final String profileId;
  final String? legacyImportId;
  final String officialSourceId;
  final String courseId;
  final String fromBackend;
  final String toBackend;
  final OwnerTransitionPhase phase;
  final int generation;
  final String policy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? lastErrorCode;
}

/// Thrown when a CAS-style update sees an unexpected prior value. Callers
/// must treat this as "another writer moved first", never retry blindly.
class OwnerAuthorityConflict implements Exception {
  const OwnerAuthorityConflict(this.message);

  final String message;

  @override
  String toString() => 'OwnerAuthorityConflict: $message';
}

/// CourseDatabase-side authority for anki course sources, write fences and
/// owner transitions (plan 34 D3). The Official catalog's
/// `legacy_anki_migrations` table is only a replayable journal mirror —
/// production routing must read [AnkiOwnerAuthorityDao] exclusively.
class AnkiOwnerAuthorityDao {
  AnkiOwnerAuthorityDao(this._db);

  final CourseDatabase _db;

  Future<T> transaction<T>(Future<T> Function() action) =>
      _db.transaction(action);

  /// Pushes one source's fence into the sync enforcement registry (the
  /// registry is the in-memory projection Legacy mutators check).
  Future<void> _publishFence(String courseId) async {
    final row = await findByCourseId(courseId);
    if (row != null) {
      LegacyWriteFence.instance.updateFence(
        courseId: row.courseId,
        sourceId: row.sourceId,
        fence: row.writeFence,
      );
    }
  }

  // ---------------------------------------------------------------------
  // Course source catalog
  // ---------------------------------------------------------------------

  Future<void> upsertSource({
    required String courseId,
    required String profileId,
    required String sourceId,
    required String backendKind,
    required String displayName,
    required String sourceHash,
    required String sourceFingerprint,
    required AnkiSourceVisibility state,
  }) async {
    await _db.customStatement(
      '''
      INSERT INTO anki_course_sources (
        course_id, profile_id, source_id, backend_kind, display_name,
        source_hash, source_fingerprint, state, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(course_id) DO UPDATE SET
        profile_id = excluded.profile_id,
        source_id = excluded.source_id,
        backend_kind = excluded.backend_kind,
        display_name = excluded.display_name,
        source_hash = excluded.source_hash,
        source_fingerprint = excluded.source_fingerprint,
        state = excluded.state,
        updated_at = excluded.updated_at
      ''',
      [
        courseId,
        profileId,
        sourceId,
        backendKind,
        displayName,
        sourceHash,
        sourceFingerprint,
        state.wireName,
        DateTime.now().millisecondsSinceEpoch,
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
    await _publishFence(courseId);
  }

  Future<List<AnkiCourseSourceAuthorityRow>> listSources(String profileId,
      {bool activeOnly = false}) async {
    final rows = await _db.customSelect(
      activeOnly
          ? 'SELECT * FROM anki_course_sources WHERE profile_id = ? '
              "AND state = 'active' ORDER BY created_at"
          : 'SELECT * FROM anki_course_sources WHERE profile_id = ? '
              'ORDER BY created_at',
      variables: [Variable.withString(profileId)],
    ).get();
    return [for (final row in rows) _mapSource(row.data)];
  }

  Future<AnkiCourseSourceAuthorityRow?> findBySource({
    required String profileId,
    required String sourceId,
  }) async {
    final rows = await _db.customSelect(
      'SELECT * FROM anki_course_sources WHERE profile_id = ? AND source_id = ?',
      variables: [
        Variable.withString(profileId),
        Variable.withString(sourceId),
      ],
    ).get();
    if (rows.isEmpty) return null;
    return _mapSource(rows.single.data);
  }

  Future<AnkiCourseSourceAuthorityRow?> findByCourseId(String courseId) async {
    final rows = await _db.customSelect(
      'SELECT * FROM anki_course_sources WHERE course_id = ?',
      variables: [Variable.withString(courseId)],
    ).get();
    if (rows.isEmpty) return null;
    return _mapSource(rows.single.data);
  }

  /// Visibility commit — the last step of the import saga (D7). Fails when
  /// the row is missing rather than silently creating one: visibility must
  /// never run ahead of the staging row.
  Future<void> commitVisibility({
    required String courseId,
    required AnkiSourceVisibility state,
    String? activeProjectionGeneration,
  }) async {
    final updated = await _db.customUpdate(
      'UPDATE anki_course_sources SET state = ?, '
      'active_projection_generation = COALESCE(?, '
      'active_projection_generation), updated_at = ? '
      'WHERE course_id = ?',
      variables: [
        Variable.withString(state.wireName),
        Variable<String>(activeProjectionGeneration),
        Variable.withInt(DateTime.now().millisecondsSinceEpoch),
        Variable.withString(courseId),
      ],
    );
    if (updated != 1) {
      throw OwnerAuthorityConflict(
        'visibility commit for $courseId matched no source row',
      );
    }
  }

  // ---------------------------------------------------------------------
  // Write fence
  // ---------------------------------------------------------------------


  /// Fence transition with compare-and-swap semantics. Legal moves:
  /// open→frozen (migration freeze), frozen→officialOnly (owner commit),
  /// frozen→open (rollback receipt). `officialOnly` never regresses to
  /// `open` — that would re-enable the Legacy writer after Official
  /// mutations exist (plan 34 §6.2 forbidden moves).
  Future<void> compareAndSetWriteFence({
    required String courseId,
    required AnkiWriteFence expected,
    required AnkiWriteFence next,
  }) async {
    if (next == AnkiWriteFence.open &&
        expected == AnkiWriteFence.officialOnly) {
      throw OwnerAuthorityConflict(
        'write fence may not regress officialOnly → open',
      );
    }
    final updated = await _db.customUpdate(
      'UPDATE anki_course_sources SET write_fence = ?, updated_at = ? '
      'WHERE course_id = ? AND write_fence = ?',
      variables: [
        Variable.withString(next.wireName),
        Variable.withInt(DateTime.now().millisecondsSinceEpoch),
        Variable.withString(courseId),
        Variable.withString(expected.wireName),
      ],
    );
    if (updated != 1) {
      throw OwnerAuthorityConflict(
        'write fence CAS failed for $courseId '
        '(expected ${expected.wireName})',
      );
    }
    await _publishFence(courseId);
  }

  // ---------------------------------------------------------------------
  // Owner transitions
  // ---------------------------------------------------------------------

  /// Starts a transition. The partial unique index rejects a second
  /// in-flight transition for the same course_id.
  Future<OwnerTransitionRow> beginTransition({
    required String transitionId,
    required String profileId,
    String? legacyImportId,
    required String officialSourceId,
    required String courseId,
    required String fromBackend,
    required String toBackend,
    required String policy,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.customStatement(
      '''
      INSERT INTO anki_owner_transitions (
        transition_id, profile_id, legacy_import_id, official_source_id,
        course_id, from_backend, to_backend, phase, generation, policy,
        created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, 'discovered', 0, ?, ?, ?)
      ''',
      [
        transitionId,
        profileId,
        legacyImportId,
        officialSourceId,
        courseId,
        fromBackend,
        toBackend,
        policy,
        now,
        now,
      ],
    );
    final row = await transitionById(transitionId);
    if (row == null) {
      throw StateError('transition $transitionId vanished after insert');
    }
    if (legacyImportId != null) {
      LegacyWriteFence.instance.linkLegacyImport(
        legacyImportId: legacyImportId,
        officialSourceId: officialSourceId,
      );
    }
    return row;
  }

  Future<OwnerTransitionRow?> transitionById(String transitionId) async {
    final rows = await _db.customSelect(
      'SELECT * FROM anki_owner_transitions WHERE transition_id = ?',
      variables: [Variable.withString(transitionId)],
    ).get();
    if (rows.isEmpty) return null;
    return _mapTransition(rows.single.data);
  }

  Future<OwnerTransitionRow?> inFlightTransition(String courseId) async {
    final rows = await _db.customSelect(
      "SELECT * FROM anki_owner_transitions WHERE course_id = ? "
      "AND phase NOT IN ('complete', 'rolledBackLegacy', 'rollbackEligible', "
      "'noLegacyScheduleRollback') ORDER BY created_at DESC LIMIT 1",
      variables: [Variable.withString(courseId)],
    ).get();
    if (rows.isEmpty) return null;
    return _mapTransition(rows.single.data);
  }

  /// Advances the transition phase with CAS on the expected prior phase.
  Future<void> advancePhase({
    required String transitionId,
    required OwnerTransitionPhase from,
    required OwnerTransitionPhase to,
    String? errorCode,
  }) async {
    final updated = await _db.customUpdate(
      'UPDATE anki_owner_transitions SET phase = ?, updated_at = ?, '
      'last_error_code = ? WHERE transition_id = ? AND phase = ?',
      variables: [
        Variable.withString(to.wireName),
        Variable.withInt(DateTime.now().millisecondsSinceEpoch),
        Variable<String>(errorCode),
        Variable.withString(transitionId),
        Variable.withString(from.wireName),
      ],
    );
    if (updated != 1) {
      throw OwnerAuthorityConflict(
        'phase CAS failed for $transitionId '
        '(expected ${from.wireName} → ${to.wireName})',
      );
    }
  }

  /// The single authoritative owner switch. Runs inside one CourseDatabase
  /// transaction: backend_kind, owner generation, write fence and the
  /// transition phase commit together or not at all. The catalog mirror is
  /// updated after this succeeds and may be replayed on failure.
  Future<void> commitOwnership({
    required String transitionId,
    required String courseId,
    String? legacyCourseId,
  }) async {
    await _db.transaction(() async {
      final rows = await _db.customSelect(
        'SELECT owner_generation FROM anki_course_sources WHERE course_id = ?',
        variables: [Variable.withString(courseId)],
      ).get();
      if (rows.isEmpty) {
        throw OwnerAuthorityConflict(
          'owner commit for $courseId matched no source row',
        );
      }
      final generation = rows.single.read<int>('owner_generation');
      await _db.customStatement(
        'UPDATE anki_course_sources SET backend_kind = \'official\', '
        'owner_generation = ?, write_fence = \'officialOnly\', '
        'last_transition_id = ?, updated_at = ? WHERE course_id = ?',
        [
          generation + 1,
          transitionId,
          DateTime.now().millisecondsSinceEpoch,
          courseId,
        ],
      );
      if (legacyCourseId != null && legacyCourseId != courseId) {
        await _db.customStatement(
          "UPDATE anki_course_sources SET state = 'retired', "
          "write_fence = 'officialOnly', owner_generation = "
          "owner_generation + 1, last_transition_id = ?, updated_at = ? "
          "WHERE course_id = ?",
          [
            transitionId,
            DateTime.now().millisecondsSinceEpoch,
            legacyCourseId,
          ],
        );
      }
      final updated = await _db.customUpdate(
        'UPDATE anki_owner_transitions SET phase = \'observing\', '
        'generation = ?, updated_at = ? '
        'WHERE transition_id = ? AND phase = \'committing\'',
        variables: [
          Variable.withInt(generation + 1),
          Variable.withInt(DateTime.now().millisecondsSinceEpoch),
          Variable.withString(transitionId),
        ],
      );
      if (updated != 1) {
        throw OwnerAuthorityConflict(
          'owner commit CAS failed: transition $transitionId '
          'not in committing phase',
        );
      }
      await _publishFence(courseId);
      if (legacyCourseId != null && legacyCourseId != courseId) {
        await _publishFence(legacyCourseId);
      }
    });
  }

  /// Rollback before the owner commit: restores the Legacy writer and ends
  /// the transition. After `commitOwnership` this must never be called —
  /// post-commit failures take the forward-recovery path instead.
  Future<void> rollbackToLegacy({
    required String transitionId,
    required String courseId,
  }) async {
    await _db.transaction(() async {
      final rows = await _db.customSelect(
        'SELECT backend_kind FROM anki_course_sources WHERE course_id = ?',
        variables: [Variable.withString(courseId)],
      ).get();
      if (rows.isEmpty) {
        throw OwnerAuthorityConflict(
          'rollback for $courseId matched no source row',
        );
      }
      if (rows.single.read<String>('backend_kind') == 'official') {
        throw OwnerAuthorityConflict(
          'cannot roll back $courseId: ownership already committed; '
          'use forward recovery',
        );
      }
      await _db.customStatement(
        "UPDATE anki_course_sources SET write_fence = 'open', "
        'last_transition_id = ?, updated_at = ? WHERE course_id = ?',
        [
          transitionId,
          DateTime.now().millisecondsSinceEpoch,
          courseId,
        ],
      );
      final updated = await _db.customUpdate(
        'UPDATE anki_owner_transitions SET phase = \'rolledBackLegacy\', '
        'updated_at = ? WHERE transition_id = ? AND phase = ?',
        variables: [
          Variable.withInt(DateTime.now().millisecondsSinceEpoch),
          Variable.withString(transitionId),
          Variable.withString(OwnerTransitionPhase.rollbackPending.wireName),
        ],
      );
      if (updated != 1) {
        throw OwnerAuthorityConflict(
          'rollback CAS failed for $transitionId: not in rollbackPending',
        );
      }
      await _publishFence(courseId);
    });
  }

  // ---------------------------------------------------------------------
  // Course scope repair journal
  // ---------------------------------------------------------------------

  Future<void> recordScopeRepair({
    required String newCourseScope,
    required String newCourseOrder,
    String? oldCourseScope,
    String? oldCourseOrder,
    required String reason,
  }) async {
    await _db.customStatement(
      '''
      INSERT INTO course_scope_repair_journal (
        repaired_at, old_course_scope, new_course_scope, old_course_order,
        new_course_order, reason
      ) VALUES (?, ?, ?, ?, ?, ?)
      ''',
      [
        DateTime.now().millisecondsSinceEpoch,
        oldCourseScope,
        newCourseScope,
        oldCourseOrder,
        newCourseOrder,
        reason,
      ],
    );
  }

  Future<void> setScopeCodecVersion(int version) async {
    await _db.customStatement(
      'INSERT INTO course_meta_v21_codec (key, value) '
      "VALUES ('course_scope_codec_version', ?) "
      'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
      [version.toString()],
    );
  }

  Future<int?> scopeCodecVersion() async {
    final rows = await _db
        .customSelect(
          "SELECT value FROM course_meta_v21_codec "
          "WHERE key = 'course_scope_codec_version'",
        )
        .get();
    if (rows.isEmpty) return null;
    return int.tryParse(rows.single.read<String>('value'));
  }

  // ---------------------------------------------------------------------
  // Row mapping
  // ---------------------------------------------------------------------

  AnkiCourseSourceAuthorityRow _mapSource(Map<String, Object?> data) {
    return AnkiCourseSourceAuthorityRow(
      courseId: data['course_id']! as String,
      profileId: data['profile_id']! as String,
      sourceId: data['source_id']! as String,
      backendKind: data['backend_kind']! as String,
      displayName: data['display_name']! as String,
      state: AnkiSourceVisibility.parse(data['state']! as String),
      ownerGeneration: data['owner_generation']! as int,
      writeFence: AnkiWriteFence.parse(data['write_fence']! as String),
      activeProjectionGeneration:
          data['active_projection_generation'] as String?,
      lastTransitionId: data['last_transition_id'] as String?,
    );
  }

  OwnerTransitionRow _mapTransition(Map<String, Object?> data) {
    return OwnerTransitionRow(
      transitionId: data['transition_id']! as String,
      profileId: data['profile_id']! as String,
      legacyImportId: data['legacy_import_id'] as String?,
      officialSourceId: data['official_source_id']! as String,
      courseId: data['course_id']! as String,
      fromBackend: data['from_backend']! as String,
      toBackend: data['to_backend']! as String,
      phase: OwnerTransitionPhase.parse(data['phase']! as String),
      generation: data['generation']! as int,
      policy: data['policy']! as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        data['created_at']! as int,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        data['updated_at']! as int,
      ),
      lastErrorCode: data['last_error_code'] as String?,
    );
  }
}
