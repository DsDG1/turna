import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_lock_reconciler.dart';
import 'package:turna/application/anki_official/engine/official_anki_session.dart';
import 'package:turna/application/anki_official/engine/official_formal_due_repository.dart';
import 'package:turna/application/anki_official/engine/official_formal_due_snapshot_builder.dart';
import 'package:turna/application/anki_official/engine/official_formal_due_update.dart';
import 'package:turna/application/anki_official/introduction/imported_history_introducer.dart';
import 'package:turna/application/anki_official/migration/official_anki_engine_kind.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';

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

  /// Test seam: replaces the refresh body wholesale (Play Hub / review hub
  /// widget tests stub due refreshes without an engine or collection).
  static Future<void> Function()? debugRefreshOverride;

  Future<void> refresh() async {
    final override = debugRefreshOverride;
    if (override != null) {
      await override();
      return;
    }
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

  /// Doc 38 P2: mutating scheduler ops bump the engine's page generation,
  /// so a background answer during pagination can stale our page token
  /// (PAGE_TOKEN_STALE, recoverable). One bounded restart with a fresh
  /// token; a second stale within the same refresh falls through to
  /// markUnavailable like any other failure.
  Future<void> _refreshOnce() async {
    try {
      await _collectAndCommit();
    } on OfficialAnkiException catch (error) {
      if (marksUnavailableWithoutRethrow(error)) {
        OfficialFormalDueRepository.instance.markUnavailable(error);
        return;
      }
      if (error.code != OfficialAnkiErrorCode.pageTokenStale) rethrow;
      try {
        await _collectAndCommit();
      } on OfficialAnkiException catch (retryError) {
        if (marksUnavailableWithoutRethrow(retryError) ||
            retryError.code == OfficialAnkiErrorCode.pageTokenStale) {
          OfficialFormalDueRepository.instance.markUnavailable(retryError);
          return;
        }
        rethrow;
      }
    }
  }

  /// Maintenance/engine-state failures must not escape as uncaught platform
  /// errors (step1 pending_cleanup / compact invalid_state).
  static bool marksUnavailableWithoutRethrow(OfficialAnkiException error) {
    switch (error.code) {
      case OfficialAnkiErrorCode.invalidState:
      case OfficialAnkiErrorCode.schedulerBusy:
      case OfficialAnkiErrorCode.collectionLocked:
        return true;
      default:
        return false;
    }
  }

  Future<void> _collectAndCommit() async {
    final repo = OfficialFormalDueRepository.instance;
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
      final paths = OfficialAnkiPaths.defaultProfile(support);
      if (!paths.catalogFile.existsSync()) {
        _commitOrDrop(
          repo,
          const OfficialFormalDueSnapshotBuilder().build(sources: const []),
        );
        return;
      }
      // Doc 38 P4-C: reuse the shared main-isolate locator handle instead
      // of open/close per refresh; WAL + busy_timeout (database open)
      // covers concurrent worker-isolate access.
      await OfficialAnkiCompositionRoot.initializeReadOnlyLocator(
        supportDir: support,
      );
      final catalog = OfficialAnkiCompositionRoot.readOnlyCatalog!;
      try {
        final sources = OfficialAnkiSourceDao(catalog);
        if (!OfficialAnkiFeatureFlags.current.allowsOfficialScheduler) {
          final activeSources = sources
              .listSources('profile-default-01')
              .where((s) => s.state == 'active');
          _commitOrDrop(
            repo,
            const OfficialFormalDueSnapshotBuilder().build(
              sources: [
                for (final s in activeSources)
                  OfficialFormalDueSourceInput(
                    importId: s.sourceId,
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
            if (error.code != OfficialAnkiErrorCode.collectionLocked &&
                error.code != OfficialAnkiErrorCode.invalidState &&
                error.code != OfficialAnkiErrorCode.schedulerBusy) {
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

        // Imported-history adopt (01-due-state.md): upgrade ledger rows that
        // were seeded `unintroduced` although the collection proves the card
        // was already studied (reps>=1). Runs BEFORE the collect so the
        // committed snapshot already sees the adopted ids; the repository's
        // generation guard absorbs the racing change events. Failures never
        // fail the refresh — the next pass retries.
        await _adoptImportedHistory(session);

        // P1 lock reconcile: unintroduced cards of every projected source
        // stay suspended in the scheduler, so the due/learn/new searches
        // below already exclude them. Also self-heals anything that slipped
        // past the publish hook (imports pre-dating P1, a failed unlock).
        // Failures never fail the refresh — the next pass retries.
        await _reconcileLocks();

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



        // Exact card-id formal due (doc 34 W5 / plan 34 R3): all six sets
        // per source, never count approximation. The router is pure — it
        // only collects. `is:new`/`is:learn` match on card type, so the
        // due search must negate suspended/buried explicitly (the formula
        // subtracts the same sets as defense in depth); the un-negated
        // search keeps the raw counts that feed the "unintroduced new"
        // hint.
        Future<Set<int>> searchSchedulerDue({required int deckId}) =>
            fetchByQuery(
              'did:$deckId (is:due OR is:learn OR is:new) '
              '-is:suspended -is:buried',
            );
        Future<Set<int>> searchUnfilteredDue({required int deckId}) =>
            fetchByQuery(
              'did:$deckId (is:due OR is:learn OR is:new)',
            );
        final baseGeneration = repo.generation;
        final collected = await _collectFormalDueCardIds(
          sources: sources,
          searchSchedulerDueCardIds: searchSchedulerDue,
          searchUnfilteredDueCardIds: searchUnfilteredDue,
          getSuspendedCardIds: fetchSuspendedCardIds,
          getBuriedCardIds: fetchBuriedCardIds,
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
          final retried = await _collectFormalDueCardIds(
            sources: sources,
            searchSchedulerDueCardIds: searchSchedulerDue,
            searchUnfilteredDueCardIds: searchUnfilteredDue,
            getSuspendedCardIds: fetchSuspendedCardIds,
            getBuriedCardIds: fetchBuriedCardIds,
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
        // Shared locator handle: intentionally not closed here.
      }
    } on OfficialAnkiException catch (error) {
      if (error.code == OfficialAnkiErrorCode.pageTokenStale) rethrow;
      // Failed refresh: keep the last good six sets and mark unavailable —
      // never zero, never a partial guess (plan 34 R3-3). The repository
      // was never touched mid-collect, so there is nothing to roll back.
      repo.markUnavailable(error);
    } catch (error) {
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

  Future<void> _reconcileLocks() async {
    try {
      final catalog = OfficialAnkiCompositionRoot.readOnlyCatalog;
      if (catalog == null) return;
      final sources = OfficialAnkiSourceDao(catalog).listSources('profile-default-01');
      if (sources.isEmpty) return;
      final reconciler = OfficialAnkiLockReconciler.resolve();
      for (final s in sources) {
        if (s.state == 'active') {
          await reconciler.reconcileSource(sourceId: s.sourceId);
        }
      }
    } catch (error) {
      debugPrint('[OfficialAnkiHomeDueSync] lock reconcile failed: $error');
    }
  }

  Future<void> _adoptImportedHistory(OfficialAnkiSession session) async {
    try {
      final catalog = OfficialAnkiCompositionRoot.readOnlyCatalog;
      if (catalog == null) return;
      final rows = catalog.handle.select(
        'SELECT DISTINCT source_id, card_id FROM anki_source_cards',
      );
      if (rows.isEmpty) return;
      final cardIdsBySource = <String, Set<int>>{};
      for (final row in rows) {
        cardIdsBySource
            .putIfAbsent(row['source_id'] as String, () => <int>{})
            .add(row['card_id'] as int);
      }
      await const ImportedHistoryIntroducer().adopt(
        searchPage: session.searchCardsPage,
        cardIdsBySource: cardIdsBySource,
      );
    } catch (error) {
      debugPrint(
        '[OfficialAnkiHomeDueSync] imported-history adopt failed: $error',
      );
    }
  }

  static Future<_CollectedFormalDue> _collectFormalDueCardIds({
    required OfficialAnkiSourceDao sources,
    required Future<Set<int>> Function({required int deckId}) searchSchedulerDueCardIds,
    required Future<Set<int>> Function({required int deckId}) searchUnfilteredDueCardIds,
    required Future<Set<int>> Function({int? deckId}) getSuspendedCardIds,
    required Future<Set<int>> Function({int? deckId}) getBuriedCardIds,
    String profileId = 'profile-default-01',
  }) async {
    final activeSources = sources
        .listSources(profileId)
        .where((s) => s.state == 'active')
        .toList();
    final allSuspended = await getSuspendedCardIds();
    final allBuried = await getBuriedCardIds();
    final inputs = <OfficialFormalDueSourceInput>[];
    final rawDueByImport = <String, int>{};

    for (final source in activeSources) {
      final cards = sources.listCards(source.sourceId);
      if (cards.isEmpty) {
        inputs.add(
          OfficialFormalDueSourceInput(
            importId: source.sourceId,
            schedulerDueCardIds: const {},
            schedulerDueSynced: true,
          ),
        );
        rawDueByImport[source.sourceId] = 0;
        continue;
      }
      final deckId = cards.first.deckId;
      final cardIds = {for (final c in cards) c.cardId};
      final queueIds = await searchSchedulerDueCardIds(deckId: deckId);
      final dueIds = queueIds.intersection(cardIds);
      final unfiltered = await searchUnfilteredDueCardIds(deckId: deckId);
      final rawIds = unfiltered.intersection(cardIds);

      rawDueByImport[source.sourceId] = rawIds.length;
      inputs.add(
        OfficialFormalDueSourceInput(
          importId: source.sourceId,
          schedulerDueCardIds: dueIds,
          schedulerDueSynced: true,
          activePlacementCardIds: cardIds,
          suspendedCardIds: allSuspended.intersection(cardIds),
          buriedCardIds: allBuried.intersection(cardIds),
        ),
      );
    }
    return _CollectedFormalDue(
      inputs: inputs,
      rawDueByImport: rawDueByImport,
    );
  }
}

class _CollectedFormalDue {
  const _CollectedFormalDue({
    required this.inputs,
    required this.rawDueByImport,
  });

  final List<OfficialFormalDueSourceInput> inputs;
  final Map<String, int> rawDueByImport;
}
