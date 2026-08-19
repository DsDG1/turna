import 'dart:io';
import 'dart:math';

import 'package:sqlite3/sqlite3.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/migration/official_anki_engine_kind.dart';
import 'package:turna/application/anki_official/migration/official_anki_fixture_pilot_saga.dart';
import 'package:turna/application/anki_official/migration/official_anki_migration_dao.dart';
import 'package:turna/application/anki_official/migration/official_anki_migration_state.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';

/// Device A §5.4: same fixture source, mutation=0 and mutation>0.
/// Does not wipe Collection, does not touch production routes.
class OfficialAnkiFixtureRollbackPathResult {
  const OfficialAnkiFixtureRollbackPathResult({
    required this.migrationId,
    required this.legacyImportId,
    required this.delta,
    required this.state,
    required this.recordedKind,
  });

  final String migrationId;
  final String legacyImportId;
  final int delta;
  final LegacyAnkiMigrationState state;
  final String? recordedKind;
}

class OfficialAnkiFixtureRollbackDrillReport {
  const OfficialAnkiFixtureRollbackDrillReport({
    this.mutationGt0,
    this.mutationEq0,
    this.userCardCount,
    this.collectionPresent = true,
    this.detail = '',
  });

  final OfficialAnkiFixtureRollbackPathResult? mutationGt0;
  final OfficialAnkiFixtureRollbackPathResult? mutationEq0;
  final int? userCardCount;
  final bool collectionPresent;
  final String detail;

  bool get bothPassed =>
      mutationGt0?.state ==
          LegacyAnkiMigrationState.noLegacyScheduleRollback &&
      mutationGt0?.recordedKind == 'official' &&
      mutationEq0?.state == LegacyAnkiMigrationState.rollbackEligible &&
      mutationEq0?.recordedKind == 'legacy';
}

class OfficialAnkiFixtureRollbackDrill {
  const OfficialAnkiFixtureRollbackDrill();

  static const zeroImportId = 'p5c-fixture-rb0';
  static const zeroMigrationId = 'mig-p5c-fixture-rb0';

  static int postCutoverDelta({
    required int storedAtCutover,
    required int currentSourceRevlog,
  }) {
    return max(0, currentSourceRevlog - storedAtCutover);
  }

  static int countRevlogForCards({
    required File collectionFile,
    required Iterable<int> cardIds,
  }) {
    final ids = cardIds.toList();
    if (!collectionFile.existsSync() || ids.isEmpty) return 0;
    final db = sqlite3.open(collectionFile.path, mode: OpenMode.readOnly);
    try {
      final placeholders = List.filled(ids.length, '?').join(',');
      final row = db.select(
        'SELECT COUNT(*) AS n FROM revlog WHERE cid IN ($placeholders)',
        ids,
      );
      return (row.first['n'] as num).toInt();
    } finally {
      db.dispose();
    }
  }

  OfficialAnkiFixtureRollbackPathResult rollbackObserving({
    required OfficialAnkiFixturePilotSaga saga,
    required OfficialAnkiMigrationDao dao,
    required String migrationId,
    required int currentSourceRevlog,
    int? nowMillis,
  }) {
    final row = dao.findById(migrationId);
    if (row == null) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.invalidState,
        messageKey: 'official_anki.migration_missing',
      );
    }
    if (!isFixturePilotSource(importId: row.legacyImportId)) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.invalidArgument,
        messageKey: 'official_anki.non_allowlist_source',
      );
    }
    final delta = postCutoverDelta(
      storedAtCutover: row.officialMutationCountAtCutover,
      currentSourceRevlog: currentSourceRevlog,
    );
    saga.rollback(
      migrationId: migrationId,
      currentState: row.state,
      officialMutationDelta: delta,
      nowMillis: nowMillis,
    );
    final after = dao.findById(migrationId)!;
    return OfficialAnkiFixtureRollbackPathResult(
      migrationId: after.migrationId,
      legacyImportId: after.legacyImportId,
      delta: delta,
      state: after.state,
      recordedKind: after.recordedKind,
    );
  }

  Future<OfficialAnkiFixtureRollbackDrillReport> runBothPaths({
    required OfficialAnkiFixturePilotSaga saga,
    required OfficialAnkiMigrationDao dao,
    required OfficialAnkiPaths paths,
    required String profileId,
    int? userCardCount,
    int? nowMillis,
    int? currentSourceRevlogOverride,
  }) async {
    final now = nowMillis ?? DateTime.now().millisecondsSinceEpoch;
    final fixtures = dao.listFixtureMigrations(profileId: profileId);
    var gt0 = _existing(
      fixtures,
      LegacyAnkiMigrationState.noLegacyScheduleRollback,
    );
    var eq0 = _existing(
      fixtures,
      LegacyAnkiMigrationState.rollbackEligible,
    );

    final observing = dao.findObservingFixture(profileId: profileId);
    final template = observing ??
        fixtures.cast<LegacyAnkiMigrationRow?>().firstWhere(
              (row) => row!.officialSourceId != null,
              orElse: () => null,
            );
    if (template == null) {
      return OfficialAnkiFixtureRollbackDrillReport(
        mutationGt0: gt0,
        mutationEq0: eq0,
        userCardCount: userCardCount,
        collectionPresent: paths.collectionFile.existsSync(),
        detail: 'no_fixture_migration',
      );
    }

    final cardIds = dao
        .listCardMap(template.migrationId)
        .map((row) => row.officialCardId)
        .whereType<int>();
    final currentRevlog = currentSourceRevlogOverride ??
        countRevlogForCards(
          collectionFile: paths.collectionFile,
          cardIds: cardIds,
        );

    if (gt0 == null &&
        observing != null &&
        postCutoverDelta(
              storedAtCutover: observing.officialMutationCountAtCutover,
              currentSourceRevlog: currentRevlog,
            ) >
            0) {
      gt0 = rollbackObserving(
        saga: saga,
        dao: dao,
        migrationId: observing.migrationId,
        currentSourceRevlog: currentRevlog,
        nowMillis: now,
      );
    }

    if (eq0 == null) {
      final liveObserving = dao.findObservingFixture(profileId: profileId);
      if (liveObserving != null &&
          postCutoverDelta(
                storedAtCutover: liveObserving.officialMutationCountAtCutover,
                currentSourceRevlog: currentRevlog,
              ) ==
              0) {
        eq0 = rollbackObserving(
          saga: saga,
          dao: dao,
          migrationId: liveObserving.migrationId,
          currentSourceRevlog: currentRevlog,
          nowMillis: now,
        );
      } else {
        eq0 = await _cutoverSiblingAtCurrentRevlogAndRollback(
          saga: saga,
          dao: dao,
          template: dao.findById(template.migrationId)!,
          currentSourceRevlog: currentRevlog,
          nowMillis: now,
        );
      }
    }

    return OfficialAnkiFixtureRollbackDrillReport(
      mutationGt0: gt0,
      mutationEq0: eq0,
      userCardCount: userCardCount,
      collectionPresent: paths.collectionFile.existsSync(),
      detail: gt0 == null
          ? 'mutation_gt0_needs_post_cutover_rating'
          : 'ok',
    );
  }

  OfficialAnkiFixtureRollbackPathResult? _existing(
    List<LegacyAnkiMigrationRow> rows,
    LegacyAnkiMigrationState state,
  ) {
    for (final row in rows) {
      if (row.state != state) continue;
      return OfficialAnkiFixtureRollbackPathResult(
        migrationId: row.migrationId,
        legacyImportId: row.legacyImportId,
        delta: state == LegacyAnkiMigrationState.noLegacyScheduleRollback
            ? 1
            : 0,
        state: row.state,
        recordedKind: row.recordedKind,
      );
    }
    return null;
  }

  Future<OfficialAnkiFixtureRollbackPathResult>
      _cutoverSiblingAtCurrentRevlogAndRollback({
    required OfficialAnkiFixturePilotSaga saga,
    required OfficialAnkiMigrationDao dao,
    required LegacyAnkiMigrationRow template,
    required int currentSourceRevlog,
    required int nowMillis,
  }) async {
    final existing = dao.findByLegacyImport(
      profileId: template.profileId,
      legacyImportId: zeroImportId,
    );
    final migrationId = existing?.migrationId ?? zeroMigrationId;
    if (existing == null) {
      dao.insertDetected(
        migrationId: migrationId,
        profileId: template.profileId,
        legacyImportId: zeroImportId,
        policy: template.schedulingPolicy,
        nowMillis: nowMillis,
        sourceHash: template.sourceHash,
        legacyCardCount: template.legacyCardCount,
      );
    }
    var row = dao.findById(migrationId)!;
    if (row.state != LegacyAnkiMigrationState.observing &&
        row.state != LegacyAnkiMigrationState.cutover &&
        row.state != LegacyAnkiMigrationState.rollbackEligible) {
      _walkToVerifying(
        dao,
        row,
        nowMillis,
        officialSourceId: template.officialSourceId,
      );
      final map = dao.listCardMap(template.migrationId);
      if (map.isNotEmpty) {
        dao.upsertCardMapRows(migrationId: migrationId, rows: map);
      }
      final matched = map
          .where((item) => item.matchState == LegacyAnkiMatchState.matched)
          .length;
      final official =
          map.where((item) => item.officialCardId != null).length;
      final count = map.isEmpty ? 1 : map.length;
      final ok = await saga.verifyAndCutover(
        migrationId: migrationId,
        legacyCardCount:
            template.legacyCardCount == 0 ? count : template.legacyCardCount,
        officialCardCount: official == 0 ? count : official,
        matchedCount: matched == 0 ? count : matched,
        projectionItemCount: matched == 0 ? count : matched,
        officialMutationCountAtCutover: currentSourceRevlog,
        nowMillis: nowMillis,
      );
      if (!ok) {
        throw const OfficialAnkiException(
          code: OfficialAnkiErrorCode.invalidState,
          messageKey: 'official_anki.verify_count_mismatch',
        );
      }
    }
    row = dao.findById(migrationId)!;
    if (row.state == LegacyAnkiMigrationState.rollbackEligible) {
      return OfficialAnkiFixtureRollbackPathResult(
        migrationId: row.migrationId,
        legacyImportId: row.legacyImportId,
        delta: 0,
        state: row.state,
        recordedKind: row.recordedKind,
      );
    }
    return rollbackObserving(
      saga: saga,
      dao: dao,
      migrationId: migrationId,
      currentSourceRevlog: currentSourceRevlog,
      nowMillis: nowMillis,
    );
  }

  void _walkToVerifying(
    OfficialAnkiMigrationDao dao,
    LegacyAnkiMigrationRow start,
    int nowMillis, {
    String? officialSourceId,
  }) {
    const chain = <LegacyAnkiMigrationState>[
      LegacyAnkiMigrationState.detected,
      LegacyAnkiMigrationState.awaitingPackage,
      LegacyAnkiMigrationState.validatingSource,
      LegacyAnkiMigrationState.backingUp,
      LegacyAnkiMigrationState.importingOfficial,
      LegacyAnkiMigrationState.indexingOfficial,
      LegacyAnkiMigrationState.mappingCards,
      LegacyAnkiMigrationState.projectingCourse,
      LegacyAnkiMigrationState.verifying,
    ];
    var current = start.state;
    final id = start.migrationId;
    for (var i = 0; i < chain.length - 1; i++) {
      if (current == chain[i]) {
        dao.transition(
          migrationId: id,
          expected: chain[i],
          next: chain[i + 1],
          nowMillis: nowMillis,
          officialSourceId: officialSourceId ?? start.officialSourceId,
        );
        current = chain[i + 1];
      }
    }
    if (current != LegacyAnkiMigrationState.verifying) {
      throw OfficialAnkiException(
        code: OfficialAnkiErrorCode.invalidState,
        messageKey: 'official_anki.illegal_migration_transition',
        debugDetails: 'sibling stuck at ${current.name}',
      );
    }
  }
}
