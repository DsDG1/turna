import 'dart:io';

import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine.dart';
import 'package:turna/application/anki_official/import/official_anki_import_state.dart';
import 'package:turna/application/anki_official/import/official_anki_source_hasher.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/storage/official_anki_import_attempt_dao.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';

typedef OfficialAnkiClock = int Function();

/// Official import saga. Never calls [AnkiImporter] or [AnkiImportService].
class OfficialAnkiImportOrchestrator {
  OfficialAnkiImportOrchestrator({
    required this.engine,
    required this.sources,
    required this.attempts,
    required this.paths,
    this.hasher = const OfficialAnkiSourceHasher(),
    this.nowMillis,
    this.fault,
    this.batchSize = 200,
  });

  final OfficialAnkiEngine engine;
  final OfficialAnkiSourceDao sources;
  final OfficialAnkiImportAttemptDao attempts;
  final OfficialAnkiPaths paths;
  final OfficialAnkiSourceHasher hasher;
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

  Future<OfficialAnkiImportResult> importFile({
    required String packagePath,
    required String displayName,
    String? requestId,
    bool cancel = false,
  }) async {
    final package = File(packagePath);
    if (!package.existsSync() || !packagePath.toLowerCase().endsWith('.apkg')) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.packageInvalid,
        messageKey: 'official_anki.package_invalid',
      );
    }

    _trip(OfficialAnkiFaultPoint.beforeHash);
    final digest = await hasher.hashFile(packagePath);
    final existing = sources.findByHash(paths.profileId, digest.sha256);
    if (existing != null && existing.state == OfficialAnkiSourceState.active.wire) {
      return OfficialAnkiImportResult(
        sourceId: existing.sourceId,
        attemptId: existing.sourceId,
        state: OfficialAnkiSourceState.active,
        cardCount: sources.cardCount(existing.sourceId),
        noteCount: 0,
        alreadyImported: true,
      );
    }
    if (existing != null &&
        existing.state != OfficialAnkiSourceState.active.wire &&
        existing.state != OfficialAnkiSourceState.cancelled.wire &&
        existing.state != OfficialAnkiSourceState.failedBeforeImport.wire) {
      final unfinished = attempts
          .unfinished()
          .where((row) => row.sourceId == existing.sourceId);
      if (unfinished.isNotEmpty) {
        return recoverAttempt(unfinished.first);
      }
    }

    final sourceId = existing?.sourceId ?? 'src-${digest.sha256.substring(0, 16)}';
    final attemptId = 'att-${_now.toRadixString(16)}-${digest.sha256.substring(0, 8)}';
    final rid = requestId ?? 'req-$attemptId';

    sources.upsertSource(
      sourceId: sourceId,
      profileId: paths.profileId,
      sourceHash: digest.sha256,
      sourceSize: digest.bytes,
      displayName: displayName,
      state: OfficialAnkiSourceState.selected.wire,
      backendCommit: 'pending',
      nowMillis: _now,
      activeAttemptId: attemptId,
    );
    attempts.insert(
      attemptId: attemptId,
      sourceId: sourceId,
      requestId: rid,
      state: OfficialAnkiSourceState.preparing.wire,
      nowMillis: _now,
    );
    _trip(OfficialAnkiFaultPoint.afterSourceBeforeCheckpoint);

    await engine.openProfile(paths);
    await engine.checkCollection();
    attempts.transition(
      attemptId: attemptId,
      expectedState: OfficialAnkiSourceState.preparing.wire,
      nextState: OfficialAnkiSourceState.backingUp.wire,
      nowMillis: _now,
    );
    final checkpoint = await engine.createBackup();
    attempts.transition(
      attemptId: attemptId,
      expectedState: OfficialAnkiSourceState.backingUp.wire,
      nextState: OfficialAnkiSourceState.importingOfficial.wire,
      nowMillis: _now,
      checkpointId: checkpoint,
    );
    _trip(OfficialAnkiFaultPoint.afterCheckpointBeforeImport);

    if (cancel || fault == OfficialAnkiFaultPoint.duringImportCancel) {
      await engine.cancel();
      try {
        await engine.importPackage(packagePath: packagePath);
      } on OfficialAnkiException catch (error) {
        if (error.code != OfficialAnkiErrorCode.importCancelled) rethrow;
      }
      await engine.checkCollection();
      attempts.transition(
        attemptId: attemptId,
        expectedState: OfficialAnkiSourceState.importingOfficial.wire,
        nextState: OfficialAnkiSourceState.cancelled.wire,
        nowMillis: _now,
      );
      sources.transitionSource(
        sourceId: sourceId,
        expectedState: OfficialAnkiSourceState.selected.wire,
        nextState: OfficialAnkiSourceState.cancelled.wire,
        nowMillis: _now,
      );
      return OfficialAnkiImportResult(
        sourceId: sourceId,
        attemptId: attemptId,
        state: OfficialAnkiSourceState.cancelled,
        cardCount: 0,
        noteCount: 0,
      );
    }

    final imported = await engine.importPackage(packagePath: packagePath);
    _trip(OfficialAnkiFaultPoint.afterImportBeforeNoteIds);
    attempts.transition(
      attemptId: attemptId,
      expectedState: OfficialAnkiSourceState.importingOfficial.wire,
      nextState: OfficialAnkiSourceState.indexingNotes.wire,
      nowMillis: _now,
      nativeImportToken: imported.nativeImportToken,
      importedNoteIds: imported.associatedNoteIds,
    );
    _trip(OfficialAnkiFaultPoint.afterNoteIdsBeforeCards);
    return _indexCards(
      sourceId: sourceId,
      attemptId: attemptId,
      noteIds: imported.associatedNoteIds,
      expectedState: OfficialAnkiSourceState.indexingNotes.wire,
    );
  }

  Future<OfficialAnkiImportResult> recoverAttempt(
    OfficialAnkiAttemptRow attempt,
  ) {
    final decision = decideOfficialAnkiRecovery(attempt);
    switch (decision.action) {
      case OfficialAnkiRecoveryAction.resume:
        return resumeIndexing(attempt);
      case OfficialAnkiRecoveryAction.retry:
        return markFailedBeforeImport(attempt);
      case OfficialAnkiRecoveryAction.reconcile:
        return markNeedsReconciliation(attempt);
      case OfficialAnkiRecoveryAction.leave:
        return Future.value(
          OfficialAnkiImportResult(
            sourceId: attempt.sourceId,
            attemptId: attempt.attemptId,
            state: decision.state,
            cardCount: sources.cardCount(attempt.sourceId),
            noteCount: attempt.importedNoteIds.length,
          ),
        );
    }
  }

  Future<OfficialAnkiImportResult> resumeIndexing(OfficialAnkiAttemptRow attempt) {
    if (attempt.importedNoteIds.isEmpty) {
      return markNeedsReconciliation(attempt);
    }
    return _indexCards(
      sourceId: attempt.sourceId,
      attemptId: attempt.attemptId,
      noteIds: attempt.importedNoteIds,
      expectedState: attempt.state,
      incrementRecovery: true,
    );
  }

  Future<OfficialAnkiImportResult> markFailedBeforeImport(
    OfficialAnkiAttemptRow attempt,
  ) async {
    attempts.transition(
      attemptId: attempt.attemptId,
      expectedState: attempt.state,
      nextState: OfficialAnkiSourceState.failedBeforeImport.wire,
      nowMillis: _now,
      incrementRecovery: true,
    );
    final source = sources.findById(attempt.sourceId);
    if (source != null && source.state != OfficialAnkiSourceState.active.wire) {
      sources.transitionSource(
        sourceId: attempt.sourceId,
        expectedState: source.state,
        nextState: OfficialAnkiSourceState.failedBeforeImport.wire,
        nowMillis: _now,
      );
    }
    return OfficialAnkiImportResult(
      sourceId: attempt.sourceId,
      attemptId: attempt.attemptId,
      state: OfficialAnkiSourceState.failedBeforeImport,
      cardCount: 0,
      noteCount: 0,
    );
  }

  Future<OfficialAnkiImportResult> markNeedsReconciliation(
    OfficialAnkiAttemptRow attempt,
  ) async {
    attempts.transition(
      attemptId: attempt.attemptId,
      expectedState: attempt.state,
      nextState: OfficialAnkiSourceState.needsReconciliation.wire,
      nowMillis: _now,
      incrementRecovery: true,
    );
    final source = sources.findById(attempt.sourceId);
    if (source != null && source.state != OfficialAnkiSourceState.active.wire) {
      sources.transitionSource(
        sourceId: attempt.sourceId,
        expectedState: source.state,
        nextState: OfficialAnkiSourceState.needsReconciliation.wire,
        nowMillis: _now,
      );
    }
    return OfficialAnkiImportResult(
      sourceId: attempt.sourceId,
      attemptId: attempt.attemptId,
      state: OfficialAnkiSourceState.needsReconciliation,
      cardCount: sources.cardCount(attempt.sourceId),
      noteCount: attempt.importedNoteIds.length,
    );
  }

  Future<OfficialAnkiImportResult> _indexCards({
    required String sourceId,
    required String attemptId,
    required List<int> noteIds,
    required String expectedState,
    bool incrementRecovery = false,
  }) async {
    if (noteIds.isEmpty) {
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
    final descriptors = <OfficialAnkiCardDescriptor>[];
    for (var offset = 0; offset < noteIds.length; offset += batchSize) {
      final batch = noteIds.sublist(
        offset,
        offset + batchSize > noteIds.length ? noteIds.length : offset + batchSize,
      );
      final noteCards = await engine.getNoteCardsBatch(batch);
      final cardIds = noteCards.values.expand((ids) => ids).toList();
      if (cardIds.isNotEmpty) {
        descriptors.addAll(await engine.getCardDescriptorsBatch(cardIds));
      }
      sources.upsertCardBatch(sourceId: sourceId, cards: descriptors);
      attempts.transition(
        attemptId: attemptId,
        expectedState: OfficialAnkiSourceState.indexingCards.wire,
        nextState: OfficialAnkiSourceState.indexingCards.wire,
        nowMillis: _now,
        cursorJson: '{"offset":$offset}',
      );
      if (offset == 0) {
        _trip(OfficialAnkiFaultPoint.afterMidBatchCursor);
      }
    }
    _trip(OfficialAnkiFaultPoint.afterCardsBeforeActive);
    await engine.checkCollection();
    attempts.transition(
      attemptId: attemptId,
      expectedState: OfficialAnkiSourceState.indexingCards.wire,
      nextState: OfficialAnkiSourceState.active.wire,
      nowMillis: _now,
    );
    sources.transitionSource(
      sourceId: sourceId,
      expectedState: OfficialAnkiSourceState.selected.wire,
      nextState: OfficialAnkiSourceState.active.wire,
      nowMillis: _now,
      importedAtMillis: _now,
    );
    _trip(OfficialAnkiFaultPoint.afterActiveRestart);
    final uniqueNotes = descriptors.map((card) => card.noteId).toSet().length;
    return OfficialAnkiImportResult(
      sourceId: sourceId,
      attemptId: attemptId,
      state: OfficialAnkiSourceState.active,
      cardCount: sources.cardCount(sourceId),
      noteCount: uniqueNotes,
    );
  }
}
