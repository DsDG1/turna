import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine.dart';
import 'package:turna/application/anki_official/import/official_anki_import_saga.dart';
import 'package:turna/application/anki_official/import/official_anki_import_state.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_checkpoint_dao.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_lifecycle_models.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_source_metadata_dao.dart';
import 'package:turna/application/anki_official/storage/official_anki_import_attempt_dao.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:flutter/foundation.dart' show debugPrint;

typedef OfficialAnkiClock = int Function();

/// Catalog recovery / indexing for leftover attempts. New imports use
/// [OfficialAnkiImportSaga]; this type no longer writes live Collection
/// during preview (doc 42 P4).
class OfficialAnkiImportOrchestrator {
  OfficialAnkiImportOrchestrator({
    required this.engine,
    required this.sources,
    required this.attempts,
    required this.paths,
    this.nowMillis,
    this.fault,
    this.batchSize = 200,
  });

  final OfficialAnkiEngine engine;
  final OfficialAnkiSourceDao sources;
  final OfficialAnkiImportAttemptDao attempts;
  final OfficialAnkiPaths paths;
  final OfficialAnkiClock? nowMillis;
  final OfficialAnkiFaultPoint? fault;
  final int batchSize;

  int get _now => nowMillis?.call() ?? DateTime.now().millisecondsSinceEpoch;

  void _trip(OfficialAnkiFaultPoint point) {
    if (fault == point) {
      throw OfficialAnkiException(
        code: OfficialAnkiErrorCode.internalError,
        messageKey: 'official_anki.fault_injected',
        debugDetails: point.name,
      );
    }
  }

  Future<OfficialAnkiImportResult> recoverAttempt(
    OfficialAnkiAttemptRow attempt,
  ) async {
    final phase = attempt.phase;
    if (phase == OfficialAnkiAttemptPhase.previewReady) {
      return OfficialAnkiImportResult(
        sourceId: attempt.sourceId,
        attemptId: attempt.attemptId,
        state: OfficialAnkiSourceState.previewReady,
        cardCount: sources.cardCount(attempt.sourceId),
        noteCount: attempt.importedNoteCount,
      );
    }
    // K2：v2 live import 中途强杀停在 committing。checkpoint 已废，
    // 续跑会叠幽灵卡；放弃账本 + 回收 collection 里无主卡。
    if (phase == OfficialAnkiAttemptPhase.committing) {
      final source = sources.findById(attempt.sourceId);
      if (source != null && source.isV2) {
        await OfficialAnkiImportSaga(
          sources: sources,
          attempts: attempts,
          paths: paths,
          liveEngine: engine,
        ).cancelSource(attempt.sourceId);
        return OfficialAnkiImportResult(
          sourceId: attempt.sourceId,
          attemptId: attempt.attemptId,
          state: OfficialAnkiSourceState.cancelled,
          cardCount: 0,
          noteCount: 0,
        );
      }
    }
    if (OfficialAnkiAttemptPhase.stagingCancellable.contains(phase)) {
      await OfficialAnkiImportSaga(
        sources: sources,
        attempts: attempts,
        paths: paths,
      ).cancelSource(attempt.sourceId);
      return OfficialAnkiImportResult(
        sourceId: attempt.sourceId,
        attemptId: attempt.attemptId,
        state: OfficialAnkiSourceState.cancelled,
        cardCount: 0,
        noteCount: 0,
      );
    }

    final decision = decideOfficialAnkiRecovery(attempt);
    switch (decision.action) {
      case OfficialAnkiRecoveryAction.resume:
        return resumeIndexing(attempt);
      case OfficialAnkiRecoveryAction.retry:
        return markFailedBeforeImport(attempt);
      case OfficialAnkiRecoveryAction.reconcile:
        return markNeedsReconciliation(attempt);
      case OfficialAnkiRecoveryAction.rollback:
        return rollbackAttempt(attempt);
      case OfficialAnkiRecoveryAction.quarantine:
        return _markTerminal(attempt, OfficialAnkiSourceState.quarantined);
      case OfficialAnkiRecoveryAction.leave:
        return OfficialAnkiImportResult(
          sourceId: attempt.sourceId,
          attemptId: attempt.attemptId,
          state: decision.state,
          cardCount: sources.cardCount(attempt.sourceId),
          noteCount: attempt.importedNoteCount,
        );
    }
  }

  Future<OfficialAnkiImportResult> rollbackAttempt(
    OfficialAnkiAttemptRow attempt,
  ) async {
    final checkpointId = attempt.checkpointId;
    if (checkpointId == null || checkpointId.isEmpty) {
      return _markTerminal(attempt, OfficialAnkiSourceState.quarantined);
    }
    try {
      await engine.restoreBackup(checkpointId);
    } catch (suppressed) {
      debugPrint('[OfficialAnkiImportOrchestrator] restore: $suppressed');
      return _markTerminal(attempt, OfficialAnkiSourceState.quarantined);
    }
    try {
      await OfficialAnkiCheckpointDao(sources.database).releaseFile(
        paths: paths,
        checkpointId: checkpointId,
        nowMillis: _now,
      );
    } catch (suppressed) {
      debugPrint('[OfficialAnkiImportOrchestrator] ckpt release: $suppressed');
    }
    return _markTerminal(attempt, OfficialAnkiSourceState.rolledBack);
  }

  Future<OfficialAnkiImportResult> resumeIndexing(
      OfficialAnkiAttemptRow attempt) {
    if (!attempt.hasImportedNotes) {
      return markNeedsReconciliation(attempt);
    }
    return _indexCards(
      sourceId: attempt.sourceId,
      attemptId: attempt.attemptId,
      expectedState: attempt.state,
      startOffset: attempt.nextOffset,
      incrementRecovery: true,
    );
  }

  Future<OfficialAnkiImportResult> markFailedBeforeImport(
    OfficialAnkiAttemptRow attempt,
  ) {
    return _markTerminal(attempt, OfficialAnkiSourceState.failedBeforeImport);
  }

  Future<OfficialAnkiImportResult> markNeedsReconciliation(
    OfficialAnkiAttemptRow attempt,
  ) {
    return _markTerminal(attempt, OfficialAnkiSourceState.needsReconciliation);
  }

  /// Shared tail of the two terminal mark paths: attempt transition with
  /// recovery increment, best-effort source transition (skipped while the
  /// source is active — that race belongs to the coordinator), then result.
  /// Before import nothing was written, so counts are zeroed; reconciliation
  /// reports what survived.
  Future<OfficialAnkiImportResult> _markTerminal(
    OfficialAnkiAttemptRow attempt,
    OfficialAnkiSourceState terminal,
  ) async {
    attempts.transition(
      attemptId: attempt.attemptId,
      expectedState: attempt.state,
      nextState: terminal.wire,
      nowMillis: _now,
      incrementRecovery: true,
    );
    final source = sources.findById(attempt.sourceId);
    if (source != null && source.state != OfficialAnkiSourceState.active.wire) {
      sources.transitionSource(
        sourceId: attempt.sourceId,
        expectedState: source.state,
        nextState: terminal.wire,
        nowMillis: _now,
      );
    }
    final beforeImport = terminal == OfficialAnkiSourceState.failedBeforeImport;
    return OfficialAnkiImportResult(
      sourceId: attempt.sourceId,
      attemptId: attempt.attemptId,
      state: terminal,
      cardCount: beforeImport ? 0 : sources.cardCount(attempt.sourceId),
      noteCount: beforeImport ? 0 : attempt.importedNoteCount,
    );
  }

  Future<OfficialAnkiImportResult> _indexCards({
    required String sourceId,
    required String attemptId,
    required String expectedState,
    required int startOffset,
    bool incrementRecovery = false,
    int? collectionNoteCount,
    int? collectionCardCount,
  }) async {
    if (attempts.noteIdCount(attemptId) == 0) {
      final attempt = attempts.find(attemptId);
      if (attempt != null) {
        return markNeedsReconciliation(attempt);
      }
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.needsReconciliation,
        messageKey: 'official_anki.needs_reconciliation',
      );
    }
    attempts.transition(
      attemptId: attemptId,
      expectedState: expectedState,
      nextState: OfficialAnkiSourceState.indexingCards.wire,
      nowMillis: _now,
      incrementRecovery: incrementRecovery,
    );
    var offset = startOffset;
    var firstBatchDone = false;
    while (true) {
      final batch = attempts.noteIdPage(attemptId, offset, batchSize);
      if (batch.isEmpty) break;
      final noteCards = await engine.getNoteCardsBatch(batch);
      final cardIds = noteCards.values.expand((ids) => ids).toList();
      final descriptors = cardIds.isEmpty
          ? const <OfficialAnkiCardDescriptor>[]
          : await engine.getCardDescriptorsBatch(cardIds);
      final nextOffset = offset + batch.length;
      attempts.commitIndexBatch(
        attemptId: attemptId,
        sourceId: sourceId,
        cards: descriptors,
        nextOffset: nextOffset,
        nowMillis: _now,
      );
      offset = nextOffset;
      if (!firstBatchDone) {
        firstBatchDone = true;
        _trip(OfficialAnkiFaultPoint.afterMidBatchCursor);
      }
    }
    _trip(OfficialAnkiFaultPoint.afterCardsBeforeActive);
    await engine.checkCollection();
    final cards = sources.listCards(sourceId);
    OfficialAnkiSourceMetadataDao(sources.database).replaceAssociations(
      sourceId: sourceId,
      cards: cards,
    );
    attempts.transition(
      attemptId: attemptId,
      expectedState: OfficialAnkiSourceState.indexingCards.wire,
      nextState: OfficialAnkiSourceState.previewReady.wire,
      nowMillis: _now,
    );
    final source = sources.findById(sourceId);
    if (source != null &&
        source.state != OfficialAnkiSourceState.staging.wire &&
        source.state != OfficialAnkiSourceState.active.wire) {
      sources.transitionSource(
        sourceId: sourceId,
        expectedState: source.state,
        nextState: OfficialAnkiSourceState.staging.wire,
        nowMillis: _now,
      );
    }
    _trip(OfficialAnkiFaultPoint.afterPreviewReady);
    _trip(OfficialAnkiFaultPoint.afterActiveRestart);
    return OfficialAnkiImportResult(
      sourceId: sourceId,
      attemptId: attemptId,
      state: OfficialAnkiSourceState.previewReady,
      cardCount: sources.cardCount(sourceId),
      noteCount: attempts.noteIdCount(attemptId),
      collectionNoteCount: collectionNoteCount,
      collectionCardCount: collectionCardCount,
    );
  }

  Future<void> markSourceActive(String sourceId) async {
    final source = sources.findById(sourceId);
    if (source == null) return;
    if (source.state == OfficialAnkiSourceState.active.wire) return;
    sources.transitionSource(
      sourceId: sourceId,
      expectedState: source.state,
      nextState: OfficialAnkiSourceState.active.wire,
      nowMillis: _now,
      importedAtMillis: _now,
    );
  }
}
