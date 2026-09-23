import 'package:turna/application/anki_official/browser/official_anki_source_aware_browser.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine.dart';
import 'package:turna/application/anki_official/import/official_anki_import_saga.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_lifecycle_models.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_maintenance.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_pending_imports.dart';
import 'package:turna/application/anki_official/migration/official_anki_engine_kind.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/review/official_anki_routed_source.dart';
import 'package:turna/application/anki_official/stats/official_anki_source_aware_stats.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_import_attempt_dao.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/core/logger.dart';
import 'package:turna/domain/repositories/i_anki_note_store.dart';

// Views consume the row shape through this facade; they never import
// *_dao.dart files or instantiate DAOs (enforced by layering_guard_test).
export 'package:turna/application/anki_official/storage/official_anki_source_dao.dart'
    show OfficialAnkiSourceRow;

/// One repair-center catalog snapshot: pending imports plus the
/// profile-scoped source/job rows the page renders in sections.
class OfficialAnkiCatalogSnapshot {
  const OfficialAnkiCatalogSnapshot({
    this.pendingImports = const [],
    this.sources = const [],
    this.pendingJobs = const [],
    this.failedJobs = const [],
  });

  final List<OfficialAnkiPendingImport> pendingImports;
  final List<OfficialAnkiSourceRow> sources;
  final List<Map<String, Object?>> pendingJobs;
  final List<Map<String, Object?>> failedJobs;
}

/// Result of [OfficialAnkiCatalogService.resolveReviewRoute]: which engine
/// owns the section and — when official — the review target to open.
class OfficialAnkiReviewRoute {
  const OfficialAnkiReviewRoute({required this.routedEngine, this.target});

  final AnkiEngineKind routedEngine;
  final OfficialAnkiRoutedSource? target;
}

/// View-facing facade over the Official Anki catalog store.
///
/// Every DAO access the anki/anki_official screens used to perform inline
/// lives here so views never construct DAOs or import `*_dao.dart`
/// (enforced by layering_guard_test). Catalog/paths/engine default to the
/// composition root's shared handles; tests inject them per parameter —
/// same seam the widgets used to expose directly.
class OfficialAnkiCatalogService {
  const OfficialAnkiCatalogService();

  /// States excluded from the storage delete UI: an import/control-plane
  /// row mid-flight must be cancelled, not deleted underneath the saga.
  static const inProgressSourceStates = {
    'staging',
    'selected',
    'preparing',
    'backing_up',
    'importing_official',
    'indexing_notes',
    'indexing_cards',
    'preview_ready',
    'cancelled',
    'failed_before_import',
    'cancel_requested',
    'rollback_pending',
    'rolled_back',
  };

  OfficialAnkiDatabase? _catalog(OfficialAnkiDatabase? catalog) =>
      catalog ?? OfficialAnkiCompositionRoot.readOnlyCatalog;

  /// Interrupted imports awaiting discard (banner + repair center).
  List<OfficialAnkiPendingImport> pendingImports({
    OfficialAnkiDatabase? catalog,
  }) {
    final db = _catalog(catalog);
    if (db == null) return const [];
    return const OfficialAnkiPendingImportStore().list(db);
  }

  /// Whether [sourceId] resolves to a source row in the catalog.
  bool isOfficialSource(String sourceId, {OfficialAnkiDatabase? catalog}) {
    final db = _catalog(catalog);
    if (db == null) return false;
    return OfficialAnkiSourceDao(db).findById(sourceId) != null;
  }

  /// Owned card descriptors for a source (deck-option derivation etc.).
  List<OfficialAnkiCardDescriptor> cardsForSource(
    String sourceId, {
    OfficialAnkiDatabase? catalog,
  }) {
    final db = _catalog(catalog);
    if (db == null) return const [];
    return OfficialAnkiSourceDao(db).listCards(sourceId);
  }

  /// Repair-center snapshot: pending imports + source/job rows for
  /// [profileId] (jobs stay empty when no profile is resolved).
  OfficialAnkiCatalogSnapshot repairSnapshot({
    OfficialAnkiDatabase? catalog,
    String? profileId,
  }) {
    final db = _catalog(catalog);
    if (db == null) return const OfficialAnkiCatalogSnapshot();
    final pending = const OfficialAnkiPendingImportStore().list(db);
    if (profileId == null) {
      return OfficialAnkiCatalogSnapshot(pendingImports: pending);
    }
    final jobs = OfficialAnkiMaintenanceJobDao(db);
    return OfficialAnkiCatalogSnapshot(
      pendingImports: pending,
      sources: OfficialAnkiSourceDao(db).listSources(profileId),
      pendingJobs: jobs.pending(profileId: profileId),
      failedJobs: jobs.recentFailed(profileId: profileId),
    );
  }

  /// Sources the storage drill-down may offer for deletion — in-progress
  /// import states excluded (see [inProgressSourceStates]).
  List<OfficialAnkiSourceRow> deletableSources(
    String profileId, {
    OfficialAnkiDatabase? catalog,
  }) {
    final db = _catalog(catalog);
    if (db == null) return const [];
    return [
      for (final source in OfficialAnkiSourceDao(db).listSources(profileId))
        if (!inProgressSourceStates.contains(source.state)) source,
    ];
  }

  /// Review-gate routing rule (extracted from AnkiOfficialReviewGate):
  /// catalog presence + source state → routed engine; the owned card set
  /// → review target. A legacy-routed section never gets a target.
  OfficialAnkiReviewRoute resolveReviewRoute({
    required OfficialAnkiDatabase catalog,
    required String importId,
  }) {
    final sources = OfficialAnkiSourceDao(catalog);
    final source = sources.findById(importId);
    final isOfficial = source != null && source.state == 'active';
    if (!isOfficial) {
      return const OfficialAnkiReviewRoute(routedEngine: AnkiEngineKind.legacy);
    }
    final cards = sources.listCards(source.sourceId);
    return OfficialAnkiReviewRoute(
      routedEngine: AnkiEngineKind.official,
      target: cards.isEmpty
          ? null
          : OfficialAnkiRoutedSource(
              importId: importId,
              sourceId: source.sourceId,
              deckId: cards.first.deckId,
              cardIds: {for (final card in cards) card.cardId},
            ),
    );
  }

  /// Exact-source stats future; null when [sourceId] is not an official
  /// source — the caller then renders the legacy stats path instead.
  Future<OfficialAnkiSourceAwareStatsSnapshot>? statsForSource(
    String sourceId, {
    OfficialAnkiDatabase? catalog,
    OfficialAnkiEngine? engine,
  }) {
    final db = _catalog(catalog);
    if (db == null) return null;
    final sources = OfficialAnkiSourceDao(db);
    if (sources.findById(sourceId) == null) return null;
    return OfficialAnkiSourceAwareStats(
      sources: sources,
      engine: engine ?? OfficialAnkiCompositionRoot.engine,
    ).forOfficialSource(sourceId);
  }

  /// Long-lived browser for the card browser page (doc 38 P4-A). Null when
  /// no catalog is available — the page falls back to the legacy path.
  OfficialAnkiSourceAwareBrowser? browser({
    required IAnkiNoteStore legacyNotes,
    OfficialAnkiDatabase? catalog,
    OfficialAnkiEngine? engine,
    OfficialAnkiPreviewCache? previewCache,
  }) {
    final db = _catalog(catalog);
    if (db == null) return null;
    return OfficialAnkiSourceAwareBrowser(
      sources: OfficialAnkiSourceDao(db),
      legacyNotes: legacyNotes,
      engine: engine ?? OfficialAnkiCompositionRoot.engine,
      previewCache: previewCache,
    );
  }

  /// PRAGMA integrity_check on the catalog; null when no catalog.
  String? catalogIntegrityCheck({OfficialAnkiDatabase? catalog}) {
    final db = _catalog(catalog);
    if (db == null) return null;
    return db.handle
        .select('PRAGMA integrity_check')
        .first
        .values
        .first
        .toString();
  }

  /// Discard an interrupted import through the saga. False when catalog or
  /// paths are unavailable — same fail-quiet contract the callers had.
  Future<bool> discardPendingImport(
    String sourceId, {
    OfficialAnkiDatabase? catalog,
    OfficialAnkiPaths? paths,
  }) async {
    final db = _catalog(catalog);
    final resolvedPaths = paths ?? OfficialAnkiCompositionRoot.locatorPaths;
    if (db == null || resolvedPaths == null) return false;
    await OfficialAnkiImportSaga(
      sources: OfficialAnkiSourceDao(db),
      attempts: OfficialAnkiImportAttemptDao(db),
      paths: resolvedPaths,
    ).cancelSource(sourceId);
    return true;
  }

  /// Mark [jobId] pending again and drain the maintenance queue. The
  /// engine is resolved lazily (import probe) because several job kinds
  /// cannot run without it; jobs they leave behind stay in retry_wait.
  Future<bool> retryAndRunMaintenanceJob(
    String jobId, {
    OfficialAnkiDatabase? catalog,
    OfficialAnkiPaths? paths,
    OfficialAnkiEngine? engine,
  }) async {
    final db = _catalog(catalog);
    final resolvedPaths = paths ?? OfficialAnkiCompositionRoot.locatorPaths;
    if (db == null || resolvedPaths == null) return false;
    OfficialAnkiMaintenanceJobDao(db).retryJob(
      jobId: jobId,
      nowMillis: DateTime.now().millisecondsSinceEpoch,
    );
    var resolved = engine ?? OfficialAnkiCompositionRoot.engine;
    if (resolved == null) {
      try {
        await OfficialAnkiCompositionRoot.requireImporter();
        resolved = OfficialAnkiCompositionRoot.engine;
      } catch (e) {
        // Availability probe: the engine may be legitimately absent.
        logger.d('OfficialAnkiCatalogService: engine probe failed: $e');
      }
    }
    await OfficialAnkiMaintenanceRunner(
      catalog: db,
      paths: resolvedPaths,
      engine: resolved,
    ).runPending(profileId: resolvedPaths.profileId);
    return true;
  }

  void deleteMaintenanceJob(
    String jobId, {
    OfficialAnkiDatabase? catalog,
  }) {
    final db = _catalog(catalog);
    if (db == null) return;
    OfficialAnkiMaintenanceJobDao(db).deleteJob(jobId: jobId);
  }

  /// Clears failed maintenance rows for [profileId]; returns the count.
  int clearFailedMaintenanceJobs(
    String profileId, {
    OfficialAnkiDatabase? catalog,
  }) {
    final db = _catalog(catalog);
    if (db == null) return 0;
    return OfficialAnkiMaintenanceJobDao(db).clearFailed(profileId: profileId);
  }
}
