import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:turna/application/anki_official/engine/official_anki_lock_reconciler.dart';
import 'package:turna/application/anki_official/import/unified_anki_import_orchestrator.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/import/anki_import_execution_plan.dart';
import 'package:turna/application/anki_official/import/anki_import_facade.dart';
import 'package:turna/application/anki_official/import/official_anki_import_state.dart';
import 'package:turna/application/anki_official/migration/official_anki_migration_dao.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/official_anki_ids.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/projection/official_anki_course_entry.dart';
import 'package:turna/application/anki_official/projection/official_anki_mapping_suggestion.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_service.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_source_metadata_dao.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/import/official_anki_import_saga.dart';
import 'package:turna/application/anki_official/storage/official_anki_import_attempt_dao.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/data/course_database.dart';

/// Projection-preview snapshot after Official-first saga + migration link.
class OfficialAnkiOfficialFirstPreview {
  const OfficialAnkiOfficialFirstPreview({
    required this.sourceId,
    required this.sourceHash,
    required this.cardCount,
    required this.noteCount,
    required this.decks,
    required this.schemas,
    required this.suggestions,
    required this.service,
  });

  final String sourceId;
  final String sourceHash;
  final int cardCount;
  final int noteCount;
  final List<OfficialAnkiDeckNode> decks;
  final List<OfficialAnkiProjectionSchema> schemas;
  final Map<int, OfficialAnkiMappingSuggestion> suggestions;
  final OfficialAnkiCourseProjectionService service;
}

/// Application-side Official-first import (doc 34 W4-02 / G-C C3).
///
/// The wizard UI confirms mappings and updates course scope; this type owns
/// saga, migration-link, projection preview, and publish so those stages
/// share one [AnkiImportExecutionPlan].
class OfficialAnkiOfficialFirstService {
  const OfficialAnkiOfficialFirstService();

  Future<OfficialAnkiImportResult?> importPackage({
    required String filePath,
    required AnkiImportExecutionPlan plan,
    OfficialAnkiFeatureFlags? flags,
  }) async {
    if (!plan.isOfficialFirst) return null;
    final resolvedFlags = flags ?? OfficialAnkiFeatureFlags.current;
    OfficialAnkiImporter? officialImporter =
        OfficialAnkiCompositionRoot.session;
    if (officialImporter == null) {
      final support = await getApplicationSupportDirectory();
      officialImporter = await OfficialAnkiCompositionRoot.requireImporter(
        supportDir: support,
      );
    }
    final facade = AnkiImportFacade.resolve(
      flags: resolvedFlags,
      officialImporter: officialImporter,
      plan: plan,
    );
    if (!facade.isOfficial) return null;
    return facade.importOfficialOrNull(
      packagePath: filePath,
      displayName: filePath.split(RegExp(r'[/\\]')).last,
    );
  }


  /// Official-first pick path: saga → migration link → projection preview.
  Future<OfficialAnkiOfficialFirstPreview> importThenPreview({
    required String filePath,
    required AnkiImportExecutionPlan plan,
    required CourseDatabase course,
    OfficialAnkiFeatureFlags? flags,
  }) async {
    if (!plan.isOfficialFirst) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.invalidState,
        messageKey: 'official_anki.flag_fail_closed',
        debugDetails: 'import_plan_missing',
      );
    }
    final catalog = OfficialAnkiCompositionRoot.readOnlyCatalog;
    final livePaths = OfficialAnkiCompositionRoot.locatorPaths;
    if (catalog == null || livePaths == null) {
      final official = await importPackage(
        filePath: filePath,
        plan: plan,
        flags: flags,
      );
      final state = official?.state;
      if (official == null || !(state?.allowsPreview ?? false)) {
        throw OfficialAnkiException(
          code: OfficialAnkiErrorCode.invalidState,
          messageKey: 'official_anki.import_not_active',
          debugDetails:
              'official-first import ended in state ${state?.name ?? 'none'}',
        );
      }
      final sourceHash =
          readSourceHash(official.sourceId) ?? 'official-unknown';
      await recordMigration(
        importId: official.sourceId,
        official: official,
        hash: sourceHash,
        cardCount: official.cardCount,
      );
      return preparePreview(
        official: official,
        sourceHash: sourceHash,
        course: course,
        flags: flags,
      );
    }
    OfficialAnkiCompositionRoot.stagingDiscardRequested = false;
    final official = await OfficialAnkiImportSaga(
      sources: OfficialAnkiSourceDao(catalog),
      attempts: OfficialAnkiImportAttemptDao(catalog),
      paths: livePaths,
    ).startStaging(
      packagePath: filePath,
      displayName: filePath.split(RegExp(r'[/\\]')).last,
    );
    final state = official.state;
    if (!state.allowsPreview) {
      throw OfficialAnkiException(
        code: OfficialAnkiErrorCode.invalidState,
        messageKey: 'official_anki.import_not_active',
        debugDetails: 'official-first import ended in state ${state.name}',
      );
    }
    final sourceHash = readSourceHash(official.sourceId) ?? 'official-unknown';
    await recordMigration(
      importId: official.sourceId,
      official: official,
      hash: sourceHash,
      cardCount: official.cardCount,
    );
    return preparePreview(
      official: official,
      sourceHash: sourceHash,
      course: course,
      flags: flags,
    );
  }

  Future<void> recordMigration({
    required String importId,
    required OfficialAnkiImportResult official,
    required String hash,
    required int cardCount,
  }) async {
    final support = await getApplicationSupportDirectory();
    final paths = OfficialAnkiPaths(
      profileId: 'profile-default-01',
      profileRoot: Directory('${support.path}/official_anki/default'),
    );
    final catalog = OfficialAnkiCompositionRoot.readOnlyCatalog ??
        OfficialAnkiDatabase.file(paths.catalogFile.path);
    try {
      final migrationDao = OfficialAnkiMigrationDao(catalog);
      final now = DateTime.now().millisecondsSinceEpoch;
      final existing = migrationDao.findByLegacyImport(
        profileId: paths.profileId,
        legacyImportId: importId,
      );
      if (existing == null) {
        migrationDao.insertObservingOfficial(
          migrationId: newOfficialAnkiId('mig'),
          profileId: paths.profileId,
          legacyImportId: importId,
          officialSourceId: official.sourceId,
          sourceHash: hash,
          nowMillis: now,
          cardCount: cardCount,
        );
      } else if (existing.recordedKind != 'official' ||
          existing.officialSourceId != official.sourceId) {
        migrationDao.setOfficialSourceAndRecordedKind(
          migrationId: existing.migrationId,
          officialSourceId: official.sourceId,
          recordedKind: 'official',
          nowMillis: now,
        );
      }
    } finally {
      if (OfficialAnkiCompositionRoot.readOnlyCatalog == null) {
        catalog.close();
      }
    }
  }

  String? readSourceHash(String sourceId) {
    final catalog = OfficialAnkiCompositionRoot.readOnlyCatalog ??
        OfficialAnkiCourseEntry.catalogOf?.call();
    if (catalog == null) return null;
    return OfficialAnkiSourceDao(catalog).findById(sourceId)?.sourceHash;
  }

  Future<OfficialAnkiOfficialFirstPreview> preparePreview({
    required OfficialAnkiImportResult official,
    required String sourceHash,
    required CourseDatabase course,
    OfficialAnkiFeatureFlags? flags,
  }) async {
    final engine = OfficialAnkiCompositionRoot.stagingEngineFromSession() ??
        OfficialAnkiCompositionRoot.projectionEngineFromSession();
    if (engine == null) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.capabilityMissing,
        messageKey: 'official_anki.importer_not_ready',
      );
    }
    final catalog = OfficialAnkiCompositionRoot.readOnlyCatalog ??
        OfficialAnkiCourseEntry.catalogOf?.call();
    if (catalog == null) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.capabilityMissing,
        messageKey: 'official_anki.catalog_missing',
      );
    }
    final service = OfficialAnkiCompositionRoot.createProjectionService(
      engine: engine,
      catalog: catalog,
      course: course,
      sourceId: official.sourceId,
      profileId: OfficialAnkiCompositionRoot.locatorPaths?.profileId ??
          'profile-default-01',
      flags: flags ?? OfficialAnkiFeatureFlags.current,
    );
    final metadata = OfficialAnkiSourceMetadataDao(catalog);
    var notetypeIds = metadata.notetypeIds(official.sourceId);
    var sourceDeckIds = metadata.deckIds(official.sourceId).toSet();
    if (notetypeIds.isEmpty || sourceDeckIds.isEmpty) {
      final cards = OfficialAnkiSourceDao(catalog).listCards(official.sourceId);
      if (notetypeIds.isEmpty) {
        final ids = <int>{};
        for (final card in cards) {
          final id = card.notetypeId;
          if (id != null) ids.add(id);
        }
        notetypeIds = ids.toList();
      }
      if (sourceDeckIds.isEmpty) {
        sourceDeckIds = {for (final card in cards) card.deckId};
      }
      metadata.replaceAssociations(sourceId: official.sourceId, cards: cards);
    }
    final schemas = await engine.getProjectionSchemas(
      notetypeIds: notetypeIds,
      includeSamples: true,
      sampleLimit: 30,
    );
    final allDecks = await engine.listDeckTree();
    final decks = _scopeDecks(allDecks, sourceDeckIds);
    return OfficialAnkiOfficialFirstPreview(
      sourceId: official.sourceId,
      sourceHash: sourceHash,
      cardCount: official.cardCount,
      noteCount: official.noteCount,
      decks: decks,
      schemas: schemas,
      suggestions: {
        for (final schema in schemas)
          schema.notetypeId: service.suggestFor(schema),
      },
      service: service,
    );
  }

  Future<OfficialAnkiProjectionPublishResult> projectAndPublish({
    required OfficialAnkiCourseProjectionService service,
    required String sourceId,
    required String sourceHash,
  }) async {
    final result = await service.projectSource();
    if (result.needsMapping || result.failed || result.cancelled) {
      return result;
    }
    await UnifiedAnkiImportOrchestrator.instance.publishFromProjection(
      sourceId: sourceId,
      sourceHash: sourceHash,
    );
    final catalog = OfficialAnkiCompositionRoot.readOnlyCatalog;
    if (catalog != null) {
      final dao = OfficialAnkiSourceDao(catalog);
      final source = dao.findById(sourceId);
      if (source != null && source.state != OfficialAnkiSourceState.active.wire) {
        dao.transitionSource(
          sourceId: sourceId,
          expectedState: source.state,
          nextState: OfficialAnkiSourceState.active.wire,
          nowMillis: DateTime.now().millisecondsSinceEpoch,
          importedAtMillis: DateTime.now().millisecondsSinceEpoch,
        );
      }
    }
    // P1: seed the scheduler lock right after publish — every card the
    // ledger did not introduce (fresh imports minus imported history)
    // stays suspended until its lesson completes. Fail-closed: the home
    // due sync re-runs the reconcile idempotently if this pass fails.
    await OfficialAnkiLockReconciler.resolve().reconcileSource(
          sourceId: sourceId,
        );
    return result;
  }
}

List<OfficialAnkiDeckNode> _scopeDecks(
  List<OfficialAnkiDeckNode> all,
  Set<int> sourceDeckIds,
) {
  if (sourceDeckIds.isEmpty) return all;
  final names = {
    for (final deck in all)
      if (sourceDeckIds.contains(deck.deckId)) deck.name,
  };
  return [
    for (final deck in all)
      if (sourceDeckIds.contains(deck.deckId) ||
          names.any(
            (name) =>
                name == deck.name ||
                name.startsWith('${deck.name}::'),
          ))
        deck,
  ];
}
