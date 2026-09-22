import 'dart:io';

import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine.dart';
import 'package:turna/application/anki_official/import/official_anki_import_state.dart';
import 'package:turna/application/anki_official/import/official_anki_source_hasher.dart';
import 'package:turna/application/anki_official/import/official_anki_staging_manager.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_lifecycle_models.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/official_anki_ids.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/storage/official_anki_import_attempt_dao.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/application/anki_official/v2/official_anki_v2_unowned_card_reclaimer.dart';
import 'package:turna/core/logger.dart';

/// Staging-first import control plane (doc 42 P1): start + cancel only.
class OfficialAnkiImportSaga {
  OfficialAnkiImportSaga({
    required this.sources,
    required this.attempts,
    required this.paths,
    OfficialAnkiStagingManager? manager,
    this.hasher = const OfficialAnkiSourceHasher(),
    this.nowMillis,
    this.liveEngine,
  }) : manager = manager ?? OfficialAnkiStagingManager(livePaths: paths);

  final OfficialAnkiSourceDao sources;
  final OfficialAnkiImportAttemptDao attempts;
  final OfficialAnkiPaths paths;
  final OfficialAnkiStagingManager manager;
  final OfficialAnkiSourceHasher hasher;
  final int Function()? nowMillis;
  final OfficialAnkiEngine? liveEngine;

  int get _now => nowMillis?.call() ?? DateTime.now().millisecondsSinceEpoch;

  Future<OfficialAnkiImportResult> startStaging({
    required String packagePath,
    required String displayName,
    OfficialAnkiSourceDigest? digest,
    bool withMedia = true,
  }) async {
    final package = File(packagePath);
    if (!package.existsSync() || !packagePath.toLowerCase().endsWith('.apkg')) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.packageInvalid,
        messageKey: 'official_anki.package_invalid',
      );
    }
    final sourceId = newOfficialAnkiId('src');
    final attemptId = newOfficialAnkiId('att');
    final stagingPaths = manager.pathsFor(attemptId);
    // 整文件哈希与 worker spawn/openProfile 互不依赖——先拉起 acquire，
    // hash 计算填满 spawn 的空档。acquire 内部已 ensureLayout（C1/C5）。
    final engineFuture = manager.acquire(stagingPaths);
    try {
      final resolvedDigest = digest ?? await hasher.hashFile(packagePath);
      sources.upsertSource(
        sourceId: sourceId,
        profileId: paths.profileId,
        sourceHash: resolvedDigest.sha256,
        sourceSize: resolvedDigest.bytes,
        displayName: displayName,
        originalUri: packagePath,
        state: OfficialAnkiSourceState.staging.wire,
        backendCommit: 'pending',
        nowMillis: _now,
        activeAttemptId: attemptId,
      );
      attempts.insert(
        attemptId: attemptId,
        sourceId: sourceId,
        requestId: 'req-$attemptId',
        state: OfficialAnkiSourceState.staging.wire,
        nowMillis: _now,
        phase: OfficialAnkiAttemptPhase.created,
        stagingPath: stagingPaths.profileRoot.path,
      );
      await _guardDiscard(
        sourceId: sourceId,
        attemptId: attemptId,
        stagingRoot: stagingPaths.profileRoot,
      );
      final engine = await engineFuture;
      attempts.setPhase(
        attemptId: attemptId,
        phase: OfficialAnkiAttemptPhase.stagingImporting,
        nowMillis: _now,
      );
      await _guardDiscard(
        sourceId: sourceId,
        attemptId: attemptId,
        stagingRoot: stagingPaths.profileRoot,
      );
      final imported = await engine.importPackage(
        packagePath: packagePath,
        withScheduling: true,
        withMedia: withMedia,
      );
      await _guardDiscard(
        sourceId: sourceId,
        attemptId: attemptId,
        stagingRoot: stagingPaths.profileRoot,
      );
      attempts.setPhase(
        attemptId: attemptId,
        phase: OfficialAnkiAttemptPhase.previewReady,
        nowMillis: _now,
      );
      attempts.transition(
        attemptId: attemptId,
        expectedState: OfficialAnkiSourceState.staging.wire,
        nextState: OfficialAnkiSourceState.previewReady.wire,
        nowMillis: _now,
      );
      return OfficialAnkiImportResult(
        sourceId: sourceId,
        attemptId: attemptId,
        state: OfficialAnkiSourceState.previewReady,
        cardCount: imported.cardCount,
        noteCount: imported.noteCount,
        sourceHash: resolvedDigest.sha256,
        associatedNoteIds: imported.associatedNoteIds,
      );
    } catch (error) {
      // 先等 spawn 落定——否则 _abandon 的 kill() 可能看不到尚未挂到
      // CompositionRoot 的 session，worker isolate 会泄漏。
      try {
        await engineFuture;
      } catch (suppressed) {
        logger.w('[OfficialAnkiImportSaga] acquire settle: $suppressed');
      }
      if (error is OfficialAnkiException &&
          error.code == OfficialAnkiErrorCode.importCancelled) {
        await _abandon(
          sourceId: sourceId,
          attemptId: attemptId,
          stagingRoot: stagingPaths.profileRoot,
        );
        throw _cancelled();
      }
      await _abandon(
        sourceId: sourceId,
        attemptId: attemptId,
        stagingRoot: stagingPaths.profileRoot,
      );
      rethrow;
    }
  }

  Future<void> cancelActive() async {
    OfficialAnkiCompositionRoot.stagingDiscardRequested = true;
    final rows = attempts.unfinished().where((row) {
      if (OfficialAnkiAttemptPhase.stagingCancellable.contains(row.phase)) {
        return true;
      }
      // stagingPath 自 insert 写入后永不清空，兜底条件会命中已进入
      // live 写的 attempt——committing/receipt_committed 期间 abandon
      // 会删掉正在提交的台账（A2）。这两个 phase 不在 staging 取消范围。
      if (row.phase == OfficialAnkiAttemptPhase.committing ||
          row.phase == OfficialAnkiAttemptPhase.receiptCommitted) {
        return false;
      }
      return row.stagingPath != null && row.stagingPath!.isNotEmpty;
    }).toList();
    if (rows.isEmpty) {
      await manager.kill();
      return;
    }
    for (final row in rows) {
      await _abandon(
        sourceId: row.sourceId,
        attemptId: row.attemptId,
        stagingRoot:
            row.stagingPath == null ? null : Directory(row.stagingPath!),
      );
    }
  }

  Future<void> cancelSource(String sourceId) async {
    final row = attempts.unfinishedBySource(sourceId);
    if (row == null) return;
    final wasV2 = sources.findById(sourceId)?.isV2 ?? false;
    await _abandon(
      sourceId: row.sourceId,
      attemptId: row.attemptId,
      stagingRoot: row.stagingPath == null ? null : Directory(row.stagingPath!),
    );
    if (wasV2) {
      await OfficialAnkiV2UnownedCardReclaimer(
        catalog: sources.database,
        paths: paths,
        engine: liveEngine ?? OfficialAnkiCompositionRoot.engine,
      ).purge();
    }
  }

  bool get _discarded => OfficialAnkiCompositionRoot.stagingDiscardRequested;

  OfficialAnkiException _cancelled() => const OfficialAnkiException(
        code: OfficialAnkiErrorCode.importCancelled,
        messageKey: 'official_anki.import_cancelled',
        recoverable: true,
      );

  /// Abandons the attempt and throws the canonical cancelled error once
  /// a discard was requested; a no-op otherwise.
  Future<void> _guardDiscard({
    required String sourceId,
    required String attemptId,
    required Directory? stagingRoot,
  }) async {
    if (!_discarded) return;
    await _abandon(
      sourceId: sourceId,
      attemptId: attemptId,
      stagingRoot: stagingRoot,
    );
    throw _cancelled();
  }

  Future<void> _abandon({
    required String sourceId,
    required String attemptId,
    Directory? stagingRoot,
  }) async {
    try {
      attempts.setUserIntent(
        attemptId: attemptId,
        intent: OfficialAnkiUserIntent.discard,
        nowMillis: _now,
      );
      attempts.setPhase(
        attemptId: attemptId,
        phase: OfficialAnkiAttemptPhase.cancelRequested,
        nowMillis: _now,
      );
    } catch (suppressed) {
      logger.w('[OfficialAnkiImportSaga] intent: $suppressed');
    }
    await manager.kill();
    if (stagingRoot != null) {
      await OfficialAnkiStagingManager.deleteDirectory(stagingRoot);
    }
    try {
      attempts.setPhase(
        attemptId: attemptId,
        phase: OfficialAnkiAttemptPhase.cancelled,
        nowMillis: _now,
      );
      final current = attempts.find(attemptId);
      if (current != null &&
          current.state != OfficialAnkiSourceState.cancelled.wire) {
        attempts.transition(
          attemptId: attemptId,
          expectedState: current.state,
          nextState: OfficialAnkiSourceState.cancelled.wire,
          nowMillis: _now,
        );
      }
    } catch (suppressed) {
      logger.w('[OfficialAnkiImportSaga] phase: $suppressed');
    }
    try {
      sources.deleteSource(profileId: paths.profileId, sourceId: sourceId);
    } catch (suppressed) {
      logger.w('[OfficialAnkiImportSaga] deleteSource: $suppressed');
    }
  }
}
