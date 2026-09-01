import 'dart:convert';
import 'dart:math';

import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine.dart';
import 'package:turna/application/anki_official/introduction/card_introduction_eligibility.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_checkpoint_dao.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_file_log.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_lifecycle_models.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_maintenance.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_source_metadata_dao.dart';
import 'package:turna/application/anki_official/official_anki_ids.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';

class OfficialAnkiUninstallSaga {
  OfficialAnkiUninstallSaga({
    required this.catalog,
    required this.engine,
    this.paths,
    this.deleteProjection,
    this.deleteAppRows,
  });

  final OfficialAnkiDatabase catalog;
  final OfficialAnkiEngine engine;
  final OfficialAnkiPaths? paths;
  final Future<void> Function(String sourceId)? deleteProjection;
  final Future<void> Function(String sourceId, Set<int> cardIds)? deleteAppRows;

  Future<OfficialAnkiUninstallResult> run(String sourceId) async {
    final dao = OfficialAnkiSourceDao(catalog);
    final now = DateTime.now().millisecondsSinceEpoch;
    dao.markPendingCleanup(sourceId: sourceId, nowMillis: now);

    final cards = dao.listCards(sourceId);
    if (cards.isEmpty) {
      return _retireEmpty(sourceId, dao);
    }
    final exclusive = cards
        .map((c) => c.cardId)
        .toSet()
        .difference(dao.retainingSharedCardIds(sourceId))
        .toList()
      ..sort();
    final receiptId = newOfficialAnkiId('cln');
    catalog.handle.execute(
      '''
INSERT OR REPLACE INTO anki_cleanup_receipts (
  receipt_id, source_id, phase, ownership_json,
  collection_cards_requested, created_at_millis, updated_at_millis
) VALUES (?, ?, ?, ?, ?, ?, ?)
''',
      [
        receiptId,
        sourceId,
        'd2_snapshot',
        jsonEncode({
          'cardIds': [for (final c in cards) c.cardId],
          'exclusive': exclusive,
          'noteIds': [for (final c in cards) c.noteId],
          'notetypeIds': [
            for (final c in cards)
              if (c.notetypeId != null) c.notetypeId,
          ],
          'deckIds': [for (final c in cards) c.deckId],
        }),
        exclusive.length,
        now,
        now,
      ],
    );

    var removed = 0;
    Set<int> remaining;
    try {
      removed = await _deleteExclusiveWithRetry(exclusive);
      remaining = await _existingCardIdsWithRetry(exclusive);
    } on OfficialAnkiException catch (error) {
      officialAnkiFileLog(
        'OfficialAnkiUninstall',
        'cleanup $sourceId stopped: ${error.code.name} ${error.messageKey}',
        warning: true,
        error: error,
      );
      dao.markPendingCleanup(
        sourceId: sourceId,
        nowMillis: DateTime.now().millisecondsSinceEpoch,
        errorCode: error.code.name,
      );
      return OfficialAnkiUninstallResult(
        sourceId: sourceId,
        phase: 'd5_verify',
        logicalDeleteComplete: false,
        collectionCardsRequested: exclusive.length,
        collectionCardsRemoved: removed,
        collectionCardsRemaining: exclusive.length,
        retryable: true,
        errorCode: error.code.name,
        mediaGcPending: true,
        compactPending: true,
      );
    }
    if (remaining.isNotEmpty) {
      dao.markPendingCleanup(
        sourceId: sourceId,
        nowMillis: DateTime.now().millisecondsSinceEpoch,
        errorCode: 'collection_cards_remain',
      );
      return OfficialAnkiUninstallResult(
        sourceId: sourceId,
        phase: 'd5_verify',
        logicalDeleteComplete: false,
        collectionCardsRequested: exclusive.length,
        collectionCardsRemoved: removed,
        collectionCardsRemaining: remaining.length,
        retryable: true,
        errorCode: 'collection_cards_remain',
        mediaGcPending: true,
        compactPending: true,
      );
    }

    await deleteProjection?.call(sourceId);
    await deleteAppRows?.call(
      sourceId,
      cards.map((c) => c.cardId).toSet(),
    );

    final profileId = dao.findById(sourceId)?.profileId ??
        CardIntroductionEligibility.defaultProfileId;
    final metadata = OfficialAnkiSourceMetadataDao(catalog);

    final jobs = OfficialAnkiMaintenanceJobDao(catalog);
    final jobNow = DateTime.now().millisecondsSinceEpoch;
    jobs.enqueue(
      profileId: profileId,
      kind: OfficialAnkiMaintenanceKind.mediaGc,
      sourceId: sourceId,
      nowMillis: jobNow,
    );
    jobs.enqueue(
      profileId: profileId,
      kind: OfficialAnkiMaintenanceKind.metadataPrune,
      sourceId: sourceId,
      nowMillis: jobNow,
    );
    jobs.enqueue(
      profileId: profileId,
      kind: OfficialAnkiMaintenanceKind.checkpointRelease,
      sourceId: sourceId,
      nowMillis: jobNow,
    );
    jobs.enqueue(
      profileId: profileId,
      kind: OfficialAnkiMaintenanceKind.compactCollection,
      nowMillis: jobNow,
    );
    jobs.enqueue(
      profileId: profileId,
      kind: OfficialAnkiMaintenanceKind.compactCatalog,
      nowMillis: jobNow,
    );
    jobs.enqueue(
      profileId: profileId,
      kind: OfficialAnkiMaintenanceKind.compactCourse,
      nowMillis: jobNow,
    );

    final ckpt = OfficialAnkiCheckpointDao(catalog);
    final paths = this.paths;
    if (paths != null) {
      for (final row in ckpt.listReady(sourceId)) {
        await ckpt.releaseFile(
          paths: paths,
          checkpointId: row.checkpointId,
          nowMillis: jobNow,
        );
      }
    }

    dao.deleteSource(profileId: profileId, sourceId: sourceId);
    metadata.pruneOrphanMappings(
      profileId: profileId,
      collectionUseCount: (notetypeId) => metadata.mappingRefCount(
        profileId: profileId,
        notetypeId: notetypeId,
      ),
    );

    catalog.handle.execute(
      'UPDATE anki_cleanup_receipts SET phase = ?, logical_complete = 1, '
      'collection_cards_removed = ?, collection_cards_remaining = 0, '
      'updated_at_millis = ? WHERE receipt_id = ?',
      ['logical_complete', removed, jobNow, receiptId],
    );

    return OfficialAnkiUninstallResult(
      sourceId: sourceId,
      phase: 'logical_complete',
      logicalDeleteComplete: true,
      collectionCardsRequested: exclusive.length,
      collectionCardsRemoved: removed,
      collectionCardsRemaining: 0,
      mediaGcPending: true,
      compactPending: true,
    );
  }

  Future<OfficialAnkiUninstallResult> _retireEmpty(
    String sourceId,
    OfficialAnkiSourceDao dao,
  ) async {
    final profileId = dao.findById(sourceId)?.profileId ??
        CardIntroductionEligibility.defaultProfileId;
    dao.deleteSource(profileId: profileId, sourceId: sourceId);
    return OfficialAnkiUninstallResult(
      sourceId: sourceId,
      phase: 'logical_complete',
      logicalDeleteComplete: true,
    );
  }

  Future<int> _deleteExclusiveWithRetry(List<int> exclusive) async {
    return _withOpenRetry(() async {
      var removed = 0;
      const batchLimit = 5000;
      for (var start = 0; start < exclusive.length; start += batchLimit) {
        final end = min(start + batchLimit, exclusive.length);
        removed += await engine.deleteCards(exclusive.sublist(start, end));
      }
      return removed;
    });
  }

  Future<Set<int>> _existingCardIdsWithRetry(List<int> cardIds) {
    return _withOpenRetry(() => _existingCardIds(cardIds));
  }

  Future<T> _withOpenRetry<T>(Future<T> Function() work) async {
    await _ensureCollectionOpen();
    try {
      return await work();
    } on OfficialAnkiException catch (error) {
      if (error.code != OfficialAnkiErrorCode.invalidState) rethrow;
      officialAnkiFileLog(
        'OfficialAnkiUninstall',
        'invalid_state, retrying after openProfile: $error',
        warning: true,
        error: error,
      );
      await _ensureCollectionOpen();
      return await work();
    }
  }

  Future<void> _ensureCollectionOpen() async {
    final paths = this.paths;
    if (paths == null) return;
    try {
      await engine.openProfile(paths);
    } on OfficialAnkiException catch (error) {
      if (error.code == OfficialAnkiErrorCode.collectionAlreadyOpen) {
        return;
      }
      rethrow;
    }
  }

  Future<Set<int>> _existingCardIds(List<int> cardIds) async {
    if (cardIds.isEmpty) return const <int>{};
    final found = <int>{};
    const chunk = 50;
    for (var i = 0; i < cardIds.length; i += chunk) {
      final slice = cardIds.sublist(i, min(i + chunk, cardIds.length));
      final query = 'cid:${slice.join(',')}';
      final page = await engine.searchCardsPage(
        search: query,
        pageSize: slice.length,
      );
      found.addAll(page.cardIds);
    }
    return found;
  }
}
