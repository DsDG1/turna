import 'dart:convert';

import 'package:turna/application/anki/anki_card_adapter.dart';
import 'package:turna/application/anki/anki_deck_assembler.dart';
import 'package:turna/application/anki/anki_import_cleanup_service.dart';
import 'package:turna/application/anki/anki_importer.dart';
import 'package:turna/application/anki/anki_models.dart';
import 'package:turna/application/anki/anki_srs_migrator.dart';
import 'package:turna/application/anki/card_introduction_eligibility.dart';
import 'package:turna/application/anki/unified_anki_import_orchestrator.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/import/anki_import_execution_plan.dart';
import 'package:turna/application/anki_official/import/official_anki_official_first_service.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/audio_controller.dart';
import 'package:turna/application/mistake_provider.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/data/anki_import_dao.dart';
import 'package:turna/data/anki_note_dao.dart';
import 'package:turna/data/anki_unification_dao.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/data/course_repository.dart';
import 'package:turna/data/review_history_dao.dart';
import 'package:turna/domain/audio/anki_audio_resolver.dart';

enum ImportStrategy { merge, skipExisting, forceReplace, appendAsNew }

enum LegacyAnkiImportStage {
  copyingMedia,
  assemblingCourse,
  migratingSrs,
  savingMetadata,
}

class LegacyAnkiImportInspector {
  const LegacyAnkiImportInspector(this.database);

  final CourseDatabase database;

  Future<AnkiImportRecord?> findExistingByHash(String sourceHash) =>
      AnkiImportDao(database).findByHash(sourceHash);
}

typedef LegacyAnkiImportProgress = void Function(
  LegacyAnkiImportStage stage,
  double progress,
  String detail,
);

class LegacyAnkiImportRequest {
  const LegacyAnkiImportRequest({
    required this.collection,
    required this.filePath,
    required this.sourceHash,
    required this.plan,
    required this.strategy,
    required this.mappingOverrides,
    required this.smartGrouping,
    required this.sectionBetaGrouping,
    required this.liteThreshold,
    required this.importLearningProgress,
    required this.dailyNewLimit,
    required this.isSample,
    this.previous,
    this.isCancelled,
    this.onProgress,
  });

  final AnkiCollection collection;
  final String filePath;
  final String sourceHash;
  final AnkiImportExecutionPlan plan;
  final ImportStrategy strategy;
  final Map<int, NotetypeMapping> mappingOverrides;
  final bool smartGrouping;
  final bool sectionBetaGrouping;
  final int liteThreshold;
  final bool importLearningProgress;
  final int dailyNewLimit;
  final bool isSample;
  final AnkiImportRecord? previous;
  final bool Function()? isCancelled;
  final LegacyAnkiImportProgress? onProgress;
}

class LegacyAnkiImportExecutionResult {
  const LegacyAnkiImportExecutionResult({
    required this.importId,
    required this.summary,
    required this.mediaReport,
    this.noOp = false,
  });

  final String importId;
  final AnkiImportSummary summary;
  final AnkiMediaCopyReport mediaReport;
  final bool noOp;
}

/// Owns the complete Legacy import transaction and its recovery policy.
///
/// UI callers supply only an immutable, user-confirmed request and progress
/// callbacks. DAO construction, visibility/owner decisions, rollback,
/// force-replace ordering, and media cleanup stay in this application layer.
class LegacyAnkiImportExecutor {
  LegacyAnkiImportExecutor({
    required this.database,
    required this.srsProvider,
    required this.reviewHistoryDao,
    required this.mistakeProvider,
    required this.audioController,
    AnkiAudioResolver? audioResolver,
    UnifiedAnkiImportOrchestrator? unified,
    OfficialAnkiOfficialFirstService? officialFirst,
  })  : audioResolver = audioResolver ?? AnkiAudioResolver(),
        unified = unified ?? UnifiedAnkiImportOrchestrator.instance,
        officialFirst =
            officialFirst ?? const OfficialAnkiOfficialFirstService();

  final CourseDatabase database;
  final SrsProvider srsProvider;
  final ReviewHistoryDao reviewHistoryDao;
  final MistakeProvider mistakeProvider;
  final AudioController audioController;
  final AnkiAudioResolver audioResolver;
  final UnifiedAnkiImportOrchestrator unified;
  final OfficialAnkiOfficialFirstService officialFirst;

  Future<LegacyAnkiImportExecutionResult> execute(
    LegacyAnkiImportRequest request,
  ) async {
    _validatePlan(request.plan);
    final dao = AnkiImportDao(database);
    final noteDao = AnkiNoteDao(database);
    final repo = CourseRepository(database);
    final unificationDao = AnkiUnificationDao(database);
    final cleanup = _cleanup(repo, dao, noteDao, unificationDao);
    final srsIdsBefore = srsProvider.state.keys.toSet();
    final previous = request.previous;
    var importId = previous?.importId ?? _newImportId();
    if (request.strategy == ImportStrategy.appendAsNew ||
        (request.strategy == ImportStrategy.forceReplace && previous != null)) {
      importId = _newImportId();
    }
    final rollbackNewImport = previous == null ||
        request.strategy == ImportStrategy.appendAsNew ||
        request.strategy == ImportStrategy.forceReplace;
    final replacingInPlace = previous != null && importId == previous.importId;
    final mediaImportId = replacingInPlace
        ? AnkiAudioResolver.stagingImportId(importId)
        : importId;
    AnkiMediaSwapReceipt? mediaSwap;
    final unifiedRequest = UnifiedAnkiImportRequest(
      importId: importId,
      sourceHash: request.sourceHash,
      canonicalCardIds: [for (final card in request.collection.cards) card.id],
      persistedOwnerIsOfficial: request.plan.persistedOwnerIsOfficial,
      reuseExistingIdentity: request.strategy != ImportStrategy.appendAsNew &&
          request.strategy != ImportStrategy.forceReplace,
    );

    try {
      final begin = await unified.begin(unifiedRequest);
      if (begin.noOp) {
        return LegacyAnkiImportExecutionResult(
          importId: importId,
          noOp: true,
          mediaReport: const AnkiMediaCopyReport(),
          summary: AnkiImportSummary(
            importId: importId,
            sectionCount: 0,
            unitCount: 0,
            lessonCount: 0,
            cardCount: begin.canonicalCardCount,
            wordEntryCount: begin.canonicalCardCount,
            sourceCardCount: begin.canonicalCardCount,
          ),
        );
      }

      request.onProgress?.call(
        LegacyAnkiImportStage.copyingMedia,
        0,
        '',
      );
      final media = await audioResolver.copyMedia(
        sourceDir: request.collection.mediaDir,
        importId: mediaImportId,
        mediaMapping: request.collection.media,
      );

      late AnkiImportSummary summary;
      await database.transaction(() async {
        await dao.upsert(_record(
          request: request,
          importId: importId,
          indexedCardCount: 0,
        ));
        if (previous != null && importId == previous.importId) {
          await _clearDerivedImportData(importId, repo, noteDao);
        }

        request.onProgress?.call(
          LegacyAnkiImportStage.assemblingCourse,
          0,
          '',
        );
        summary = await AnkiDeckAssembler().assemble(
          collection: request.collection,
          importId: importId,
          repo: repo,
          noteDao: noteDao,
          mappingOverrides: request.mappingOverrides,
          smartGrouping: request.smartGrouping,
          sectionBetaGrouping: request.sectionBetaGrouping,
          liteThreshold: request.liteThreshold,
          onProgress: (progress, detail) => request.onProgress?.call(
            LegacyAnkiImportStage.assemblingCourse,
            progress,
            detail,
          ),
          isCancelled: request.isCancelled,
        );
        if (request.isCancelled?.call() ?? false) {
          throw const AnkiImportCancelled();
        }

        request.onProgress?.call(
          LegacyAnkiImportStage.migratingSrs,
          0,
          '',
        );
        if (begin.wroteTurnaSrs) {
          await AnkiSrsMigrator().migrate(
            cards: request.collection.cards,
            importId: importId,
            srsProvider: srsProvider,
            revlog: request.collection.revlog,
            reviewHistoryDao: reviewHistoryDao,
            newCardsPerDay: request.dailyNewLimit,
            collectionCreationTime: request.collection.collectionCreationTime,
            importScheduling: request.importLearningProgress,
          );
        }

        request.onProgress?.call(
          LegacyAnkiImportStage.savingMetadata,
          0,
          '',
        );
        await dao.upsert(_record(
          request: request,
          importId: importId,
          mediaCount: media.availableCount,
          indexedCardCount: summary.cardCount,
        ));
        await dao.markComplete(
          importId,
          sourceCardCount: request.collection.cards.length,
          indexedCardCount: summary.cardCount,
          importedScheduling: request.importLearningProgress,
        );
        if (replacingInPlace) {
          mediaSwap = await audioResolver.swapStagedMedia(
            stagingImportId: mediaImportId,
            targetImportId: importId,
            sourceHash: request.sourceHash,
          );
          await unificationDao.deleteProjectionIdentityByCourseId(
            CardIntroductionEligibility.courseIdForLegacyImport(importId),
          );
        }
        // Identity rows and the visible import metadata are one CourseDB
        // commit. Any identity failure rolls back the assembled course too.
        await unified.finalize(
          unifiedRequest,
          unificationDao: unificationDao,
        );
      });
      final committedMediaSwap = mediaSwap;
      if (committedMediaSwap != null) {
        await audioResolver.finalizeMediaSwap(committedMediaSwap);
      }

      if (request.strategy == ImportStrategy.forceReplace && previous != null) {
        try {
          await _cleanup(
            repo,
            dao,
            noteDao,
            unificationDao,
          ).deleteAll(previous.importId);
        } catch (_) {
          // Both complete copies are recoverable; deleting the newly committed
          // replacement after a cleanup-only failure would lose more data.
        }
      }

      if (request.plan.isLegacyOnly &&
          OfficialAnkiFeatureFlags.current.legacyMirror &&
          !request.isSample) {
        try {
          await officialFirst.importAndRecord(
            filePath: request.filePath,
            plan: request.plan,
            importId: importId,
            hash: request.sourceHash,
            cardCount: summary.cardCount,
          );
        } catch (_) {
          // Development-only mirror remains best-effort and never changes the
          // already committed Legacy owner.
        }
      }

      return LegacyAnkiImportExecutionResult(
        importId: importId,
        summary: summary.copyWith(
          missingMediaCount: media.missingCount,
          failedMediaCount: media.failedCount,
        ),
        mediaReport: media,
      );
    } catch (error) {
      unified.invalidate(importId: importId, sourceHash: request.sourceHash);
      final failedMediaSwap = mediaSwap;
      if (failedMediaSwap != null) {
        try {
          await audioResolver.rollbackMediaSwap(failedMediaSwap);
        } catch (_) {}
      } else if (replacingInPlace) {
        try {
          await audioResolver.deleteImportMedia(mediaImportId);
        } catch (_) {}
      }
      final addedSrsIds = srsProvider.state.keys
          .where((id) =>
              id.startsWith('anki-$importId-') && !srsIdsBefore.contains(id))
          .toList();
      await srsProvider.rollbackImportedIds(addedSrsIds);
      if (rollbackNewImport) {
        try {
          await cleanup.deleteAll(importId);
        } catch (_) {}
      }
      if (!replacingInPlace) {
        try {
          await dao.markFailed(
            importId,
            reason:
                error is AnkiImportCancelled ? 'cancelled' : error.toString(),
          );
        } catch (_) {}
      }
      rethrow;
    } finally {
      AnkiImporter.cleanupExtractedDir(request.collection.mediaDir);
    }
  }

  static void _validatePlan(AnkiImportExecutionPlan plan) {
    if (plan.kind == AnkiImportExecutionKind.failClosed ||
        plan.kind == AnkiImportExecutionKind.unsupported) {
      throw OfficialAnkiException(
        code: OfficialAnkiErrorCode.capabilityMissing,
        messageKey: 'official_anki.flag_fail_closed',
        debugDetails: plan.reason,
      );
    }
    if (!plan.isLegacyOnly) {
      throw OfficialAnkiException(
        code: OfficialAnkiErrorCode.invalidState,
        messageKey: 'official_anki.flag_fail_closed',
        debugDetails: plan.isOfficialFirst
            ? 'official_first_must_not_write_legacy_notestore'
            : plan.reason,
      );
    }
  }

  AnkiImportRecord _record({
    required LegacyAnkiImportRequest request,
    required String importId,
    required int indexedCardCount,
    int mediaCount = 0,
  }) {
    return AnkiImportRecord(
      importId: importId,
      sourcePath: request.filePath,
      sourceHash: request.sourceHash,
      importedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      deckCount: request.collection.decks.length,
      noteCount: request.collection.notes.length,
      cardCount: request.collection.cards.length,
      mediaCount: mediaCount,
      notetypesJson: jsonEncode(
        request.mappingOverrides.map(
          (key, value) => MapEntry(key.toString(), value.toJson()),
        ),
      ),
      sourceCardCount: request.collection.cards.length,
      storedCardCount: request.collection.cards.length,
      indexedCardCount: indexedCardCount,
      importedScheduling: request.importLearningProgress,
    );
  }

  AnkiImportCleanupService _cleanup(
    CourseRepository repo,
    AnkiImportDao dao,
    AnkiNoteDao noteDao,
    AnkiUnificationDao unificationDao,
  ) {
    return AnkiImportCleanupService(
      repository: repo,
      srsProvider: srsProvider,
      importDao: dao,
      noteDao: noteDao,
      reviewHistoryDao: reviewHistoryDao,
      audioResolver: audioResolver,
      unificationDao: unificationDao,
      mistakeProvider: mistakeProvider,
      audioController: audioController,
    );
  }

  static Future<void> _clearDerivedImportData(
    String importId,
    CourseRepository repo,
    AnkiNoteDao noteDao,
  ) async {
    await repo.deleteByTag('anki:$importId');
    final sections = await repo.sectionShells();
    for (final section in sections) {
      if (section.id.startsWith('anki-$importId-')) {
        await repo.deleteSection(section.id);
      }
    }
    await noteDao.deleteByImport(importId);
    await noteDao.deletePrerenderedByPrefix('anki-$importId-');
  }

  static String _newImportId() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(36);
}
