import 'package:path_provider/path_provider.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_session.dart';
import 'package:turna/application/anki_official/engine/official_formal_due_repository.dart';
import 'package:turna/application/anki_official/migration/official_anki_engine_kind.dart';
import 'package:turna/application/anki_official/migration/official_anki_migration_dao.dart';
import 'package:turna/application/anki_official/migration/official_anki_production_router.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/courses/course_loader.dart';
import 'package:turna/data/anki_import_dao.dart';

/// Refreshes official-routed import ids (exclusion) and the six formal-due
/// sets per source. Safe to call from Play Hub, Profile, and the Anki
/// review hub.
///
/// All state lands in [OfficialFormalDueRepository] (plan 34 D6): a failed
/// refresh marks the snapshot unavailable while the last good six sets
/// stay visible; a late result can detect staleness by generation.
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
    repo.saveForRollback();
    if (!LegacyAnkiMigrationFlags.cutoverEnabled) {
      // Owner routing still needs recorded Official ids (doc 34 W0-06).
      // Due numbers stay unavailable while cutover is paused.
      repo.apply(byImport: {}, unavailable: true);
      return;
    }
    try {
      final support = await getApplicationSupportDirectory();
      const router = OfficialAnkiProductionRouter();
      final paths = router.pathsForDefaultProfile(support);
      if (!paths.catalogFile.existsSync()) {
        repo.apply(byImport: {});
        return;
      }
      final catalog = OfficialAnkiDatabase.file(paths.catalogFile.path);
      try {
        final dao = OfficialAnkiMigrationDao(catalog);
        final sources = OfficialAnkiSourceDao(catalog);
        await _adoptCourseImports(router, dao, sources);
        if (!OfficialAnkiFeatureFlags.current.allowsOfficialScheduler) {
          repo.apply(
            byImport: {
              for (final importId in router.officialImportIds(dao: dao))
                importId: buildFormalDuePerSource(
                  importId: importId,
                  schedulerDueCardIds: const {},
                  schedulerDueSynced: false,
                  activePlacementCardIds: const {},
                  suspendedCardIds: const {},
                  buriedCardIds: const {},
                  retiredCardIds: const {},
                ),
            },
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
        await router.refreshHomeDueFromDeckTree(
          dao: dao,
          sources: sources,
          getDeckTree: session.listDeckTree,
        );

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
        // per source, never count approximation.
        await router.refreshFormalDueCardIds(
          dao: dao,
          sources: sources,
          setCurrentDeck: session.setCurrentDeck,
          getReviewQueue: ({int fetchLimit = 500}) =>
              session.getReviewQueue(fetchLimit: fetchLimit),
          getSuspendedCardIds: fetchSuspendedCardIds,
          getBuriedCardIds: fetchBuriedCardIds,
          getRetiredCardIds: fetchRetiredCardIds,
        );
      } finally {
        catalog.close();
      }
    } catch (error) {
      // Failed refresh: restore the last good six sets and mark
      // unavailable — never zero, never a partial guess (plan 34 R3-3).
      repo.rollback();
      repo.markUnavailable(error);
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
