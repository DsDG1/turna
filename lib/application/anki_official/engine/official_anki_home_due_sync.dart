import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_session.dart';
import 'package:turna/application/anki_official/engine/official_formal_due_repository.dart';
import 'package:turna/application/anki_official/engine/official_formal_due_snapshot_builder.dart';
import 'package:turna/application/anki_official/engine/official_formal_due_update.dart';
import 'package:turna/application/anki_official/introduction/card_introduction_store.dart';
import 'package:turna/application/anki_official/migration/official_anki_engine_kind.dart';
import 'package:turna/application/anki_official/migration/official_anki_migration_dao.dart';
import 'package:turna/application/anki_official/migration/official_anki_production_router.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/courses/course_loader.dart';
import 'package:turna/data/anki_import_dao.dart';

/// Refreshes official-routed import ids and the six formal-due sets per
/// source into [OfficialFormalDueRepository] (maintainability plan Wave 1).
///
/// One refresh = ONE atomic commit: everything is collected first, then a
/// single [OfficialFormalDueUpdate] lands with one generation bump. A failed
/// refresh marks the snapshot unavailable while the last good six sets stay
/// visible; a late result detects staleness by generation and is dropped
/// instead of overwriting newer data. Safe to call from Play Hub, Profile,
/// and the Anki review hub.
class OfficialAnkiHomeDueSync {
  const OfficialAnkiHomeDueSync();

  static Future<void>? _inFlight;

  Future<void> refresh() async {
    final existing = _inFlight;
    if (existing != null) {
      await existing;
      return;
    }
    final run = _refreshOnce();
    _inFlight = run;
    try {
      await run;
    } finally {
      if (identical(_inFlight, run)) _inFlight = null;
    }
  }

  Future<void> _refreshOnce() async {
    final repo = OfficialFormalDueRepository.instance;
    // Cold-start hydration: rebuild the in-memory introduced set from the
    // ledger before the builder reads it, so due badges are correct after
    // a restart (01-due-state.md). Idempotent; swallows its own errors.
    await CardIntroductionStore.resolve().hydrateFromLedger();
    if (!LegacyAnkiMigrationFlags.cutoverEnabled) {
      // Owner routing still needs recorded Official ids (doc 34 W0-06).
      // Due numbers stay unavailable while cutover is paused.
      _commitOrDrop(
        repo,
        const OfficialFormalDueSnapshotBuilder().build(
          sources: const [],
          unavailable: true,
          error: 'cutover_disabled',
        ),
      );
      return;
    }
    try {
      final support = await getApplicationSupportDirectory();
      const router = OfficialAnkiProductionRouter();
      final paths = router.pathsForDefaultProfile(support);
      if (!paths.catalogFile.existsSync()) {
        _commitOrDrop(
          repo,
          const OfficialFormalDueSnapshotBuilder().build(sources: const []),
        );
        return;
      }
      final catalog = OfficialAnkiDatabase.file(paths.catalogFile.path);
      try {
        final dao = OfficialAnkiMigrationDao(catalog);
        final sources = OfficialAnkiSourceDao(catalog);
        await _adoptCourseImports(router, dao, sources);
        if (!OfficialAnkiFeatureFlags.current.allowsOfficialScheduler) {
          _commitOrDrop(
            repo,
            const OfficialFormalDueSnapshotBuilder().build(
              sources: [
                for (final importId in router.officialImportIds(dao: dao))
                  OfficialFormalDueSourceInput(
                    importId: importId,
                    schedulerDueCardIds: const {},
                    schedulerDueSynced: false,
                  ),
              ],
            ),
          );
          return;
        }
        await OfficialAnkiCompositionRoot.requireImporter(supportDir: support);
        final session = OfficialAnkiCompositionRoot.session;
        if (session is! OfficialAnkiSession) {
          repo.markUnavailable(StateError('official session unavailable'));
          return;
        }
        var opened = false;
        OfficialAnkiException? lastOpenError;
        for (var attempt = 0; attempt < 6; attempt++) {
          try {
            await session.ensureCollectionOpen();
            opened = true;
            break;
          } on OfficialAnkiException catch (error) {
            lastOpenError = error;
            if (error.code == OfficialAnkiErrorCode.collectionAlreadyOpen) {
              opened = true;
              break;
            }
            if (error.code != OfficialAnkiErrorCode.collectionLocked) {
              rethrow;
            }
            await Future<void>.delayed(
              Duration(milliseconds: 80 * (attempt + 1)),
            );
          }
        }
        if (!opened) {
          if (lastOpenError != null) throw lastOpenError;
          repo.markUnavailable(StateError('collection open retry exhausted'));
          return;
        }

        Future<Set<int>> fetchByQuery(String query) async {
          final ids = <int>{};
          String? pageToken;
          while (true) {
            final page = await session.searchCardsPage(
              search: query,
              pageSize: 500,
              pageToken: pageToken,
            );
            ids.addAll(page.cardIds);
            if (page.nextPageToken == null ||
                page.nextPageToken!.isEmpty ||
                page.cardIds.isEmpty) {
              break;
            }
            pageToken = page.nextPageToken;
          }
          return ids;
        }

        Future<Set<int>> fetchSuspendedCardIds({int? deckId}) => fetchByQuery(
            deckId == null ? 'is:suspended' : 'deck:$deckId is:suspended');

        Future<Set<int>> fetchBuriedCardIds({int? deckId}) => fetchByQuery(
            deckId == null ? 'is:buried' : 'deck:$deckId is:buried');

        // R3-2: retired evidence must stay consistent with the projection
        // state. A retired (uninstalled/tombstoned) card is one whose
        // course placement row was deactivated — hard deletes simply leave
        // the set empty, and the router intersects whatever we return with
        // the source's placements.
        Future<Set<int>> fetchRetiredCardIds({int? deckId}) async {
          try {
            final course = CourseLoader.databaseOrNull();
            if (course == null) return const <int>{};
            final rows = await course
                .customSelect(
                  'SELECT card_id FROM anki_course_card_placements '
                  'WHERE active = 0',
                )
                .get();
            return {for (final row in rows) row.read<int>('card_id')};
          } catch (_) {
            return const <int>{};
          }
        }

        // Exact card-id formal due (doc 34 W5 / plan 34 R3): all six sets
        // per source, never count approximation. The router is pure — it
        // only collects.
        final baseGeneration = repo.generation;
        final collected = await router.collectFormalDueCardIds(
          dao: dao,
          sources: sources,
          setCurrentDeck: session.setCurrentDeck,
          getReviewQueue: ({int fetchLimit = 500}) =>
              session.getReviewQueue(fetchLimit: fetchLimit),
          getSuspendedCardIds: fetchSuspendedCardIds,
          getBuriedCardIds: fetchBuriedCardIds,
          getRetiredCardIds: fetchRetiredCardIds,
        );
        if (repo.isStale(baseGeneration)) {
          // A mutation or concurrent refresh landed while we were
          // collecting; re-collect once so the newest state is not
          // clobbered by older data (bounded retry, never an overwrite).
          debugPrint(
            '[OfficialAnkiHomeDueSync] generation moved during collect; '
            'retrying once',
          );
          final retryBase = repo.generation;
          final retried = await router.collectFormalDueCardIds(
            dao: dao,
            sources: sources,
            setCurrentDeck: session.setCurrentDeck,
            getReviewQueue: ({int fetchLimit = 500}) =>
                session.getReviewQueue(fetchLimit: fetchLimit),
            getSuspendedCardIds: fetchSuspendedCardIds,
            getBuriedCardIds: fetchBuriedCardIds,
            getRetiredCardIds: fetchRetiredCardIds,
          );
          final result = repo.commit(
            const OfficialFormalDueSnapshotBuilder().build(
              sources: retried.inputs,
              rawDueBySource: retried.rawDueByImport,
            ),
            basedOnGeneration: retryBase,
          );
          if (result != OfficialFormalDueCommitResult.committed) {
            debugPrint(
              '[OfficialAnkiHomeDueSync] retry still stale; dropping result',
            );
          }
          return;
        }
        _commitOrDrop(
          repo,
          const OfficialFormalDueSnapshotBuilder().build(
            sources: collected.inputs,
            rawDueBySource: collected.rawDueByImport,
          ),
          basedOnGeneration: baseGeneration,
        );
      } finally {
        catalog.close();
      }
    } catch (error) {
      // Failed refresh: keep the last good six sets and mark unavailable —
      // never zero, never a partial guess (plan 34 R3-3). The repository
      // was never touched mid-collect, so there is nothing to roll back.
      repo.markUnavailable(error);
    }
  }

  void _commitOrDrop(
    OfficialFormalDueRepository repo,
    OfficialFormalDueUpdate update, {
    int? basedOnGeneration,
  }) {
    final result = repo.commit(
      update,
      basedOnGeneration: basedOnGeneration ?? repo.generation,
    );
    if (result != OfficialFormalDueCommitResult.committed) {
      debugPrint(
        '[OfficialAnkiHomeDueSync] stale generation; dropping refresh result',
      );
    }
  }

  Future<void> _adoptCourseImports(
    OfficialAnkiProductionRouter router,
    OfficialAnkiMigrationDao dao,
    OfficialAnkiSourceDao sources,
  ) async {
    try {
      final course = CourseLoader.databaseOrNull();
      if (course == null) return;
      for (final row in await AnkiImportDao(course).getAll()) {
        router.adoptExistingIfCatalogMatches(
          dao: dao,
          sources: sources,
          importId: row.importId,
          sourceHash: row.sourceHash,
        );
      }
    } catch (_) {}
  }
}
