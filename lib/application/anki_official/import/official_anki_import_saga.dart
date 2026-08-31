import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine.dart';
import 'package:turna/application/anki_official/import/official_anki_import_state.dart';
import 'package:turna/application/anki_official/import/official_anki_source_hasher.dart';
import 'package:turna/application/anki_official/import/official_anki_staging_manager.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_lifecycle_models.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_source_metadata_dao.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/official_anki_ids.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/projection/official_anki_mapping_suggestion.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_service.dart';
import 'package:turna/application/anki_official/storage/official_anki_import_attempt_dao.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';

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
  }) async {
    final package = File(packagePath);
    if (!package.existsSync() || !packagePath.toLowerCase().endsWith('.apkg')) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.packageInvalid,
        messageKey: 'official_anki.package_invalid',
      );
    }
    final digest = await hasher.hashFile(packagePath);
    if (_discarded) {
      throw _cancelled();
    }
    final sourceId = newOfficialAnkiId('src');
    final attemptId = newOfficialAnkiId('att');
    final stagingPaths = manager.pathsFor(attemptId);
    await stagingPaths.ensureLayout();
    sources.upsertSource(
      sourceId: sourceId,
      profileId: paths.profileId,
      sourceHash: digest.sha256,
      sourceSize: digest.bytes,
      displayName: displayName,
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
    try {
      if (_discarded) {
        await _abandon(
          sourceId: sourceId,
          attemptId: attemptId,
          stagingRoot: stagingPaths.profileRoot,
        );
        throw _cancelled();
      }
      final engine = await manager.acquire(stagingPaths);
      attempts.setPhase(
        attemptId: attemptId,
        phase: OfficialAnkiAttemptPhase.stagingImporting,
        nowMillis: _now,
      );
      if (_discarded) {
        await _abandon(
          sourceId: sourceId,
          attemptId: attemptId,
          stagingRoot: stagingPaths.profileRoot,
        );
        throw _cancelled();
      }
      final imported = await engine.importPackage(
        packagePath: packagePath,
        withScheduling: false,
      );
      if (_discarded) {
        await _abandon(
          sourceId: sourceId,
          attemptId: attemptId,
          stagingRoot: stagingPaths.profileRoot,
        );
        throw _cancelled();
      }
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
      );
    } catch (error) {
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

  Future<OfficialAnkiImportResult> commitLive({
    required String sourceId,
    required String packagePath,
    OfficialAnkiCourseProjectionService? projection,
    Map<int, OfficialAnkiMappingSuggestion> suggestions = const {},
    Set<int> confirmedNotetypes = const {},
    Set<int> skippedNotetypes = const {},
  }) async {
    final digest = await hasher.hashFile(packagePath);
    final existing = sources.findByHash(paths.profileId, digest.sha256);
    if (existing != null &&
        existing.state == OfficialAnkiSourceState.active.wire &&
        existing.sourceId != sourceId) {
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
        existing.state == OfficialAnkiSourceState.active.wire &&
        existing.sourceId == sourceId) {
      return OfficialAnkiImportResult(
        sourceId: sourceId,
        attemptId: sourceId,
        state: OfficialAnkiSourceState.active,
        cardCount: sources.cardCount(sourceId),
        noteCount: 0,
        alreadyImported: true,
      );
    }

    OfficialAnkiAttemptRow? attempt;
    for (final row in attempts.unfinished()) {
      if (row.sourceId == sourceId) {
        attempt = row;
        break;
      }
    }
    if (attempt == null) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.invalidState,
        messageKey: 'official_anki.invalid_state',
        debugDetails: 'commit_without_preview',
      );
    }
    final engine = liveEngine ?? OfficialAnkiCompositionRoot.engine;
    if (engine == null) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.capabilityMissing,
        messageKey: 'official_anki.importer_not_ready',
      );
    }

    attempts.setPhase(
      attemptId: attempt.attemptId,
      phase: OfficialAnkiAttemptPhase.committing,
      nowMillis: _now,
    );
    if (_discarded) {
      attempts.setPhase(
        attemptId: attempt.attemptId,
        phase: OfficialAnkiAttemptPhase.quarantined,
        nowMillis: _now,
      );
      throw _cancelled();
    }

    OfficialAnkiImportLog imported;
    try {
      imported = await engine.importPackage(
        packagePath: packagePath,
        withScheduling: true,
      );
    } catch (error) {
      attempts.setPhase(
        attemptId: attempt.attemptId,
        phase: OfficialAnkiAttemptPhase.quarantined,
        nowMillis: _now,
      );
      rethrow;
    }

    attempts.replaceNoteIds(
      attemptId: attempt.attemptId,
      noteIds: imported.associatedNoteIds,
    );
    final descriptors = <OfficialAnkiCardDescriptor>[];
    var offset = 0;
    const batchSize = 200;
    while (true) {
      final batch = attempts.noteIdPage(attempt.attemptId, offset, batchSize);
      if (batch.isEmpty) break;
      final noteCards = await engine.getNoteCardsBatch(batch);
      final cardIds = noteCards.values.expand((ids) => ids).toList();
      if (cardIds.isNotEmpty) {
        descriptors.addAll(await engine.getCardDescriptorsBatch(cardIds));
      }
      offset += batch.length;
    }
    attempts.commitIndexBatch(
      attemptId: attempt.attemptId,
      sourceId: sourceId,
      cards: descriptors,
      nextOffset: offset,
      nowMillis: _now,
    );
    OfficialAnkiSourceMetadataDao(sources.database).replaceAssociations(
      sourceId: sourceId,
      cards: descriptors,
    );
    attempts.setPhase(
      attemptId: attempt.attemptId,
      phase: OfficialAnkiAttemptPhase.receiptCommitted,
      nowMillis: _now,
    );

    _promoteMappings(
      projection: projection,
      sourceId: sourceId,
      stagingPath: attempt.stagingPath,
      suggestions: suggestions,
      confirmedNotetypes: confirmedNotetypes,
      skippedNotetypes: skippedNotetypes,
    );

    attempts.setPhase(
      attemptId: attempt.attemptId,
      phase: OfficialAnkiAttemptPhase.projecting,
      nowMillis: _now,
    );
    return OfficialAnkiImportResult(
      sourceId: sourceId,
      attemptId: attempt.attemptId,
      state: OfficialAnkiSourceState.staging,
      cardCount: imported.cardCount,
      noteCount: imported.noteCount,
      collectionCardCount: imported.cardCount,
      collectionNoteCount: imported.noteCount,
    );
  }

  Future<void> finishCommit({
    required String sourceId,
    required String attemptId,
    required bool published,
  }) async {
    final attempt = attempts.find(attemptId);
    final stagingRoot = attempt?.stagingPath == null
        ? null
        : Directory(attempt!.stagingPath!);
    await manager.kill();
    if (stagingRoot != null) {
      await OfficialAnkiStagingManager.deleteDirectory(stagingRoot);
    }
    if (!published) return;
    attempts.setPhase(
      attemptId: attemptId,
      phase: OfficialAnkiAttemptPhase.completed,
      nowMillis: _now,
    );
    try {
      attempts.transition(
        attemptId: attemptId,
        expectedState: attempt?.state ?? OfficialAnkiSourceState.staging.wire,
        nextState: OfficialAnkiSourceState.completed.wire,
        nowMillis: _now,
      );
    } catch (suppressed) {
      debugPrint('[OfficialAnkiImportSaga] complete attempt: $suppressed');
    }
    final source = sources.findById(sourceId);
    if (source != null && source.state != OfficialAnkiSourceState.active.wire) {
      sources.transitionSource(
        sourceId: sourceId,
        expectedState: source.state,
        nextState: OfficialAnkiSourceState.active.wire,
        nowMillis: _now,
      );
    }
  }

  void _promoteMappings({
    required OfficialAnkiCourseProjectionService? projection,
    required String sourceId,
    required String? stagingPath,
    required Map<int, OfficialAnkiMappingSuggestion> suggestions,
    required Set<int> confirmedNotetypes,
    required Set<int> skippedNotetypes,
  }) {
    if (projection == null) return;
    var merged = Map<int, OfficialAnkiMappingSuggestion>.from(suggestions);
    var confirmed = {...confirmedNotetypes};
    var skipped = {...skippedNotetypes};
    if (stagingPath != null) {
      final file = File('$stagingPath/mapping.json');
      if (file.existsSync()) {
        try {
          final raw = jsonDecode(file.readAsStringSync());
          if (raw is Map) {
            final map = Map<String, Object?>.from(raw);
            final stored = map['suggestions'];
            if (stored is Map) {
              for (final entry in stored.entries) {
                final id = int.tryParse('${entry.key}');
                if (id == null || entry.value is! Map) continue;
                merged[id] = OfficialAnkiMappingSuggestion.fromJson(
                  Map<String, Object?>.from(entry.value as Map),
                );
              }
            }
            final c = map['confirmed'];
            if (c is List) {
              confirmed.addAll(
                c.map((e) => (e as num).toInt()),
              );
            }
            final s = map['skipped'];
            if (s is List) {
              skipped.addAll(
                s.map((e) => (e as num).toInt()),
              );
            }
          }
        } catch (suppressed) {
          debugPrint('[OfficialAnkiImportSaga] mapping.json: $suppressed');
        }
      }
    }
    OfficialAnkiProjectionSchema schemaFor(int id) {
      final suggestion = merged[id];
      return OfficialAnkiProjectionSchema(
        notetypeId: id,
        name: 'nt-$id',
        kind: 'normal',
        fieldNames: const ['Front', 'Back'],
        templateNames: const ['Card 1'],
        schemaFingerprint: suggestion?.schemaFingerprint ?? '',
      );
    }

    for (final id in skipped) {
      projection.skipNotetype(schema: schemaFor(id));
    }
    for (final id in confirmed) {
      final suggestion = merged[id];
      if (suggestion == null) continue;
      projection.confirmMapping(schema: schemaFor(id), suggestion: suggestion);
    }
  }

  Future<void> cancelActive() async {
    OfficialAnkiCompositionRoot.stagingDiscardRequested = true;
    final rows = attempts.unfinished().where((row) {
      if (OfficialAnkiAttemptPhase.stagingCancellable.contains(row.phase)) {
        return true;
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
        stagingRoot: row.stagingPath == null
            ? null
            : Directory(row.stagingPath!),
      );
    }
  }

  Future<void> cancelSource(String sourceId) async {
    OfficialAnkiAttemptRow? row;
    for (final candidate in attempts.unfinished()) {
      if (candidate.sourceId == sourceId) {
        row = candidate;
        break;
      }
    }
    if (row == null) return;
    await _abandon(
      sourceId: row.sourceId,
      attemptId: row.attemptId,
      stagingRoot: row.stagingPath == null ? null : Directory(row.stagingPath!),
    );
  }

  bool get _discarded =>
      OfficialAnkiCompositionRoot.stagingDiscardRequested;

  OfficialAnkiException _cancelled() => const OfficialAnkiException(
        code: OfficialAnkiErrorCode.importCancelled,
        messageKey: 'official_anki.import_cancelled',
        recoverable: true,
      );

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
      debugPrint('[OfficialAnkiImportSaga] intent: $suppressed');
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
      debugPrint('[OfficialAnkiImportSaga] phase: $suppressed');
    }
    try {
      sources.deleteSource(profileId: paths.profileId, sourceId: sourceId);
    } catch (suppressed) {
      debugPrint('[OfficialAnkiImportSaga] deleteSource: $suppressed');
    }
  }
}
