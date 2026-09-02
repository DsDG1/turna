// Dart imports:
import 'dart:async';
import 'dart:math';

// Package imports:
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/application/anki_official/anki_import_cleanup_service.dart';
import 'package:turna/application/anki_official/introduction/card_introduction_eligibility.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine.dart';
import 'package:turna/application/anki_official/migration/official_anki_migration_dao.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_lifecycle_models.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_uninstall_saga.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/application/anki_official/v2/official_anki_v2_retire_service.dart';
import 'package:turna/application/audio_controller.dart';
import 'package:turna/application/mistake_provider.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/application/anki_official/official_anki_ids.dart';
import 'package:turna/data/anki_import_dao.dart';
import 'package:turna/data/anki_note_dao.dart';
import 'package:turna/data/anki_owner_authority_dao.dart';
import 'package:turna/data/anki_unification_dao.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/data/review_history_dao.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/audio/anki_audio_resolver.dart';
import 'package:turna/domain/repositories/i_course_repository.dart';
import 'package:turna/service/locator.dart';

/// Centralized Anki deck management: uninstall, incremental update detection,
/// review limits, and SRS key partitioning.
///
/// Phase 3 features:
/// - Deck uninstall (by tag batch delete + media cleanup)
/// - Incremental update detection (source_hash comparison)
/// - Review limits (daily new/review caps)
/// - SRS state partitioning (per-import prefs keys)
@lazySingleton
class AnkiDeckManager {
  final ICourseRepository _repo;
  final SrsProvider _srsProvider;
  final AnkiImportDao _importDao;
  final AnkiNoteDao _noteDao;
  final AnkiAudioResolver _audioResolver;
  final AnkiUnificationDao? _unificationDao;
  final AppPrefs _appPrefs;
  final MistakeProvider? _mistakeProvider;
  final ReviewHistoryDao? _reviewHistoryDao;

  AnkiDeckManager({
    required ICourseRepository repo,
    required SrsProvider srsProvider,
    required AnkiImportDao importDao,
    required AnkiNoteDao noteDao,
    required AppPrefs appPrefs,
    AnkiAudioResolver? audioResolver,
    AnkiUnificationDao? unificationDao,
    MistakeProvider? mistakeProvider,
    ReviewHistoryDao? reviewHistoryDao,
  })  : _repo = repo,
        _srsProvider = srsProvider,
        _importDao = importDao,
        _noteDao = noteDao,
        _appPrefs = appPrefs,
        _audioResolver = audioResolver ?? AnkiAudioResolver(),
        _unificationDao = unificationDao,
        _mistakeProvider = mistakeProvider,
        _reviewHistoryDao = reviewHistoryDao;

  // ─── Review Limits ──────────────────────────────────────────────────

  /// Default daily new card limit.
  static const int defaultDailyNewLimit = 20;

  /// Default daily review card limit.
  static const int defaultDailyReviewLimit = 200;

  static const String _dailyNewLimitKey = 'anki.dailyNewLimit';
  static const String _dailyReviewLimitKey = 'anki.dailyReviewLimit';

  int get dailyNewLimit {
    return _appPrefs.preferences
        .getInt(_dailyNewLimitKey, defaultValue: defaultDailyNewLimit)
        .getValue();
  }

  int get dailyReviewLimit {
    return _appPrefs.preferences
        .getInt(_dailyReviewLimitKey, defaultValue: defaultDailyReviewLimit)
        .getValue();
  }

  Future<void> setDailyNewLimit(int limit) async {
    await _appPrefs.preferences.setInt(_dailyNewLimitKey, limit);
  }

  Future<void> setDailyReviewLimit(int limit) async {
    await _appPrefs.preferences.setInt(_dailyReviewLimitKey, limit);
  }

  // ─── Daily Challenge Toggle ─────────────────────────────────────────

  static const String _dailyChallengeAnkiKey =
      'anki.dailyChallengeIncludesAnki';

  /// Whether Anki-imported cards may appear in the daily challenge pool.
  /// Defaults to `true`; the settings page exposes a toggle to turn this off.
  bool get dailyChallengeIncludesAnki {
    return _appPrefs.preferences
        .getBool(_dailyChallengeAnkiKey, defaultValue: true)
        .getValue();
  }

  Future<void> setDailyChallengeIncludesAnki(bool value) async {
    await _appPrefs.preferences.setBool(_dailyChallengeAnkiKey, value);
  }

  /// Restore Anki learning prefs to factory defaults (new/review limits +
  /// daily-challenge inclusion). Does not uninstall decks or clear SRS.
  Future<void> resetLearningDefaults() async {
    await setDailyNewLimit(defaultDailyNewLimit);
    await setDailyReviewLimit(defaultDailyReviewLimit);
    await setDailyChallengeIncludesAnki(true);
  }

  // ─── Deck Uninstall ─────────────────────────────────────────────────

  /// Route an uninstall through the resolved owner. CourseDatabase authority
  /// identifies Official ids, `legacy_anki_migrations` translates mirrored
  /// Legacy ids, and the course-tree prefix is only a recovery hint. A
  /// mirrored import is cleaned on both sides — official collection/catalog
  /// first, then the legacy rows. Returns false when Official cleanup is
  /// safely deferred for a later retry.
  Future<bool> uninstall(String importId) async {
    final owner = await _resolveDeletionOwner(importId);
    final officialSourceId = owner.officialSourceId;
    if (officialSourceId != null) {
      // v2 分叉（step4.md B5/D6）：chain='v2' 的 source 走 retiring 序列
      // （账本单事务即刻移除 + job 驱动引擎删除/终删/视图重建/GC），
      // 不进 v1 的跨库 uninstall saga。任一段强杀由 job 表续跑收敛。
      if (await _isV2Source(officialSourceId)) {
        return _uninstallV2Source(officialSourceId);
      }
      final completed = await uninstallOfficialSource(officialSourceId);
      if (!completed) return false;
    }
    if (officialSourceId == null || await _hasLegacyArtifacts(importId)) {
      await uninstallDeck(importId);
    }
    return true;
  }

  Future<bool> _isV2Source(String sourceId) async {
    try {
      await OfficialAnkiCompositionRoot.initializeReadOnlyLocator();
      final catalog = OfficialAnkiCompositionRoot.readOnlyCatalog;
      if (catalog == null) return false;
      return OfficialAnkiSourceDao(catalog).findById(sourceId)?.isV2 ?? false;
    } catch (_) {
      return false;
    }
  }

  CourseDatabase? _courseDatabase() {
    try {
      return getIt.isRegistered<CourseDatabase>()
          ? getIt<CourseDatabase>()
          : null;
    } catch (_) {
      return null;
    }
  }

  /// v2 retiring 序列入口（B5）：①账本单事务即刻移除（含视图定向删行）
  /// → ②③④同步推进一遍（引擎在场时一次走完）；引擎缺席时 job 留队，
  /// 下次启动 `runPending` 续跑——两种情况都返回 true（用户视角已移除，
  /// 与 v1「deferred 返回 false」的差别在于 v2 的收敛由 job 表保证）。
  Future<bool> _uninstallV2Source(String sourceId) async {
    await OfficialAnkiCompositionRoot.initializeReadOnlyLocator();
    final catalog = OfficialAnkiCompositionRoot.readOnlyCatalog;
    final paths = OfficialAnkiCompositionRoot.locatorPaths;
    if (catalog == null || paths == null) {
      return false;
    }
    // B5 契约：引擎缺席（含解析抛错）不得阻塞 ①账本单事务（job 留队
    // 续跑）。用户可见的「移除失败」只剩两处来源：locator 未就绪的
    // 早退 return false，或 beginRetire 自身抛错（unknown source / DB）。
    OfficialAnkiEngine? engine;
    try {
      engine = await _resolveOfficialEngine();
    } catch (error) {
      debugPrint('[AnkiDeckManager] v2 retire engine absent: $error');
    }
    final service = OfficialAnkiV2RetireService(
      catalog: catalog,
      paths: paths,
      course: _courseDatabase(),
      engine: engine,
    );
    await service.beginRetire(sourceId: sourceId);
    Future<void> enginePass() async {
      try {
        await service.runRetireJob(sourceId: sourceId);
      } catch (error) {
        debugPrint('[AnkiDeckManager] v2 retire deferred: $error');
      }
    }

    // 小源：同步走完引擎删除（F4 测试与日常小包）。大源（含 10 万卡
    // 夹具）：beginRetire 已让课程树即刻不可见，引擎分批删卡不挡 UI，
    // 否则确认删除会卡死，表现就是「删不掉」。
    final owned = OfficialAnkiSourceDao(catalog).cardCount(sourceId);
    if (owned <= OfficialAnkiV2RetireService.defaultDeleteChunk) {
      await enginePass();
    } else {
      debugPrint(
        '[AnkiDeckManager] v2 retire engine pass detached: '
        '$sourceId ($owned cards)',
      );
      unawaited(enginePass());
    }
    return true;
  }

  /// Resolve which persisted owner an uninstall id belongs to. The production
  /// authority handles official source ids, the migration link translates a
  /// Legacy id for mirrored imports, and the tree prefix is a pre-authority
  /// recovery fallback.
  Future<AnkiDeletionOwner> _resolveDeletionOwner(String importId) async {
    // The CourseDatabase authority survives projection/catalog cleanup and is
    // therefore the only reliable way to route a retry for a half-finished
    // (or formerly ghosted) official uninstall.
    final authority = _locateAuthorityDao();
    if (authority != null) {
      try {
        final row = await authority.findBySource(
          profileId: CardIntroductionEligibility.defaultProfileId,
          sourceId: importId,
        );
        if (row?.isOfficialBackend == true) {
          return AnkiDeletionOwner(
            importId: importId,
            officialSourceId: importId,
          );
        }
      } catch (e) {
        debugPrint(
          '[AnkiDeckManager] owner authority lookup failed for $importId: $e',
        );
      }
    }
    try {
      await OfficialAnkiCompositionRoot.initializeReadOnlyLocator();
      final catalog = OfficialAnkiCompositionRoot.readOnlyCatalog;
      if (catalog != null) {
        final migration = OfficialAnkiMigrationDao(catalog).findByLegacyImport(
          profileId: CardIntroductionEligibility.defaultProfileId,
          legacyImportId: importId,
        );
        final sourceId = migration?.officialSourceId;
        if (sourceId != null && sourceId.isNotEmpty) {
          return AnkiDeletionOwner(
            importId: importId,
            officialSourceId: sourceId,
          );
        }
      }
    } catch (e) {
      debugPrint(
        '[AnkiDeckManager] migration link lookup failed for $importId: $e',
      );
    }
    // v2 chain（step4.md B5，真机 F4）：原生 v2 源按零写入纪律不落 v1
    // authority 表、不落 course.db sections——账本是两代共享的唯一事实源。
    // 没有这条直查，v2 分叉永远不可达，uninstall 空转返回 true（「已移除」
    // 假阳性，source 原封不动）。authority/迁移链仍在前，v1 路由不变。
    try {
      await OfficialAnkiCompositionRoot.initializeReadOnlyLocator();
      final ledgerCatalog = OfficialAnkiCompositionRoot.readOnlyCatalog;
      if (ledgerCatalog != null &&
          OfficialAnkiSourceDao(ledgerCatalog).findById(importId) != null) {
        return AnkiDeletionOwner(
          importId: importId,
          officialSourceId: importId,
        );
      }
    } catch (e) {
      debugPrint(
        '[AnkiDeckManager] ledger owner lookup failed for $importId: $e',
      );
    }
    if (await _isOfficialSource(importId)) {
      return AnkiDeletionOwner(importId: importId, officialSourceId: importId);
    }
    return AnkiDeletionOwner(importId: importId);
  }

  /// Whether legacy rows (import record or `anki-<importId>-…` sections)
  /// still exist for this id. Mirrored imports own both sides; pure
  /// official-first sources own none.
  Future<bool> _hasLegacyArtifacts(String importId) async {
    if (await _importDao.getById(importId) != null) return true;
    final prefix = 'anki-$importId-';
    final sections = await _repo.sectionShells();
    return sections.any((section) => section.id.startsWith(prefix));
  }

  /// Official sources own `official-anki-<sourceId>-…` tree ids.
  Future<bool> _isOfficialSource(String importId) async {
    final prefix = 'official-anki-$importId-';
    final sections = await _repo.sectionShells();
    return sections.any((section) => section.id.startsWith(prefix));
  }

  /// Hard-uninstall an official source. Unlike the historical soft uninstall,
  /// the official Anki collection also loses the source's notes and cards —
  /// deleting a deck deletes everything. The projection, vocabulary rows
  /// (P5F-33 channel), unification bookkeeping, catalog rows, review history,
  /// and mistake-log entries are dropped in the same pass.
  ///
  /// The collection delete is a structured step, not best-effort: when the
  /// engine is unavailable or `deleteNotes` fails, the source is marked
  /// `pending_cleanup`, its catalog/migration rows are kept (they are the
  /// only way to find those notes again), and `false` is returned so the
  /// caller knows the removal is deferred. Retrying [uninstall] — or
  /// [retryPendingOfficialCleanups] on the next start — resumes the saga.
  Future<bool> uninstallOfficialSource(String sourceId) async {
    // Hide the source from selectable-course surfaces before destructive
    // work begins. If the engine is temporarily unavailable, both catalogs
    // retain enough ownership metadata for the startup retry.
    await _setAuthorityState(
      sourceId,
      AnkiSourceVisibility.pendingCleanup,
    );
    await _markOfficialSourcePendingCleanup(sourceId);

    final _OfficialSourceContentIds contentIds;
    try {
      contentIds = await _officialSourceContentIds(sourceId);
    } catch (suppressed) {
      debugPrint('[AnkiDeckManager] suppressed error: $suppressed');
      // Without the ownership metadata the saga must stop: deleting the
      // projection/catalog first would orphan the collection notes.
      await _markOfficialSourcePendingCleanup(sourceId);
      return false;
    }
    OfficialAnkiEngine? engine = OfficialAnkiCompositionRoot.engine;
    if (engine == null) {
      try {
        engine = await _resolveOfficialEngine();
      } catch (e) {
        debugPrint('[AnkiDeckManager] official engine resolve failed: $e');
      }
    }
    final catalog = OfficialAnkiCompositionRoot.readOnlyCatalog;
    if (engine != null && catalog != null) {
      final saga = OfficialAnkiUninstallSaga(
        catalog: catalog,
        engine: engine,
        paths: OfficialAnkiCompositionRoot.locatorPaths,
        deleteProjection: (id) async {
          await _repo.deleteOfficialProjection(id);
          await _repo.deleteByTag('official:$id');
        },
        deleteAppRows: (id, cardIds) async {
          final unification = _unificationDao;
          if (unification != null) {
            await unification.deleteByCourseId(
              CardIntroductionEligibility.courseIdForOfficialSource(id),
            );
          }
          await _reviewHistoryDao?.deleteByCardPrefix('official-anki-$id-');
          await _mistakeProvider?.removeForAnkiDeletion(
            idPrefixes: ['official-anki-$id-'],
            cardIds: cardIds,
          );
        },
      );
      OfficialAnkiUninstallResult result;
      try {
        result = await saga.run(sourceId);
      } catch (e) {
        debugPrint('[AnkiDeckManager] uninstall saga failed for $sourceId: $e');
        await _markOfficialSourcePendingCleanup(sourceId);
        return false;
      }
      if (!result.logicalDeleteComplete) {
        await _markOfficialSourcePendingCleanup(sourceId);
        return false;
      }
      await _setAuthorityState(sourceId, AnkiSourceVisibility.retired);
      return true;
    }

    final collectionDeleted =
        await _deleteOfficialSourceCards(contentIds.exclusiveCardIds);
    if (!collectionDeleted) {
      await _markOfficialSourcePendingCleanup(sourceId);
      return false;
    }

    await _repo.deleteOfficialProjection(sourceId);
    await _repo.deleteByTag('official:$sourceId');
    final unification = _unificationDao;
    if (unification != null) {
      await unification.deleteByCourseId(
        CardIntroductionEligibility.courseIdForOfficialSource(sourceId),
      );
    }
    await _setAuthorityState(sourceId, AnkiSourceVisibility.retired);
    if (catalog != null) {
      OfficialAnkiSourceDao(catalog).deleteSource(
        profileId: CardIntroductionEligibility.defaultProfileId,
        sourceId: sourceId,
      );
    }
    await _reviewHistoryDao?.deleteByCardPrefix('official-anki-$sourceId-');
    await _mistakeProvider?.removeForAnkiDeletion(
      idPrefixes: ['official-anki-$sourceId-'],
      cardIds: contentIds.cardIds,
    );
    return true;
  }

  /// Retry every `pending_cleanup` source whose collection delete failed
  /// earlier. The candidate set is the union of the Official catalog and the
  /// CourseDatabase authority: either side may be the only surviving journal
  /// after an interrupted uninstall. Intended to run on app start so users do
  /// not have to keep pressing delete after a transient engine failure.
  Future<int> retryPendingOfficialCleanups() async {
    final pendingSourceIds = <String>{};
    try {
      await OfficialAnkiCompositionRoot.initializeReadOnlyLocator();
      final catalog = OfficialAnkiCompositionRoot.readOnlyCatalog;
      if (catalog != null) {
        pendingSourceIds.addAll(
          OfficialAnkiSourceDao(catalog)
              .listSources(CardIntroductionEligibility.defaultProfileId)
              .where((source) => source.state == 'pending_cleanup')
              .map((source) => source.sourceId),
        );
      }
    } catch (e) {
      debugPrint('[AnkiDeckManager] pending catalog lookup failed: $e');
    }

    try {
      final authority = _locateAuthorityDao();
      if (authority != null) {
        pendingSourceIds.addAll(
          (await authority.listSources(
            CardIntroductionEligibility.defaultProfileId,
          ))
              .where(
                (source) =>
                    source.isOfficialBackend &&
                    source.state == AnkiSourceVisibility.pendingCleanup,
              )
              .map((source) => source.sourceId),
        );
      }
    } catch (e) {
      debugPrint('[AnkiDeckManager] pending authority lookup failed: $e');
    }

    var resumed = 0;
    for (final sourceId in pendingSourceIds) {
      try {
        if (await uninstallOfficialSource(sourceId)) {
          resumed++;
        }
      } catch (e) {
        debugPrint(
          '[AnkiDeckManager] pending cleanup retry failed for $sourceId: $e',
        );
      }
    }
    return resumed;
  }

  /// The source's exact card ids and the subset that no sibling source owns.
  /// Read before the catalog rows are deleted. A read failure
  /// yields an empty id set and blocks the saga: proceeding would drop the
  /// ownership metadata while leaving the collection notes behind.
  Future<_OfficialSourceContentIds> _officialSourceContentIds(
    String sourceId,
  ) async {
    try {
      await OfficialAnkiCompositionRoot.initializeReadOnlyLocator();
      final catalog = OfficialAnkiCompositionRoot.readOnlyCatalog;
      if (catalog == null) {
        throw StateError('official catalog unavailable');
      }
      final dao = OfficialAnkiSourceDao(catalog);
      final cards = dao.listCards(sourceId);
      final cardIds = cards.map((card) => card.cardId).toSet();
      final sharedCardIds = dao.sharedCardIds(sourceId);
      return _OfficialSourceContentIds(
        cardIds: cardIds,
        exclusiveCardIds: cardIds.difference(sharedCardIds).toList()..sort(),
      );
    } catch (e) {
      debugPrint(
        '[AnkiDeckManager] read official source cards failed '
        'for $sourceId: $e',
      );
      rethrow;
    }
  }

  /// Remove only cards owned exclusively by this source. The native engine
  /// deletes a note only when its final card is removed. Batched to stay
  /// under the DELETE_CARDS id cap.
  /// Returns false when the collection could not be cleaned — the caller
  /// must then keep the catalog rows and mark the source pending cleanup.
  Future<bool> _deleteOfficialSourceCards(List<int> cardIds) async {
    if (cardIds.isEmpty) return true;
    try {
      final engine = await _resolveOfficialEngine();
      if (engine == null) {
        debugPrint(
          '[AnkiDeckManager] official engine unavailable; '
          '${cardIds.length} collection cards kept',
        );
        return false;
      }
      const batchLimit = 5000;
      for (var start = 0; start < cardIds.length; start += batchLimit) {
        final end = min(start + batchLimit, cardIds.length);
        await engine.deleteCards(cardIds.sublist(start, end));
      }
      return true;
    } catch (e) {
      debugPrint(
        '[AnkiDeckManager] official collection deleteCards failed: $e',
      );
      return false;
    }
  }

  Future<void> _markOfficialSourcePendingCleanup(String sourceId) async {
    try {
      final catalog = OfficialAnkiCompositionRoot.readOnlyCatalog;
      if (catalog == null) return;
      OfficialAnkiSourceDao(catalog).markPendingCleanup(
        sourceId: sourceId,
        nowMillis: DateTime.now().millisecondsSinceEpoch,
      );
    } catch (e) {
      debugPrint(
        '[AnkiDeckManager] mark pending_cleanup failed for $sourceId: $e',
      );
    }
  }

  /// CourseDatabase is the production source authority. It is registered
  /// manually during startup (after injectable configuration), so resolve it
  /// lazily instead of adding it to this generated constructor graph.
  AnkiOwnerAuthorityDao? _locateAuthorityDao() {
    try {
      return getIt.isRegistered<AnkiOwnerAuthorityDao>()
          ? getIt<AnkiOwnerAuthorityDao>()
          : null;
    } catch (suppressed) {
      debugPrint('[AnkiDeckManager] suppressed error: $suppressed');
      return null;
    }
  }

  /// Move an existing authority row through the uninstall lifecycle. Older
  /// pre-authority imports legitimately have no row, in which case the
  /// Official catalog/projection fallback remains sufficient.
  Future<void> _setAuthorityState(
    String sourceId,
    AnkiSourceVisibility state,
  ) async {
    final authority = _locateAuthorityDao();
    if (authority == null) return;
    final row = await authority.findBySource(
      profileId: CardIntroductionEligibility.defaultProfileId,
      sourceId: sourceId,
    );
    if (row == null || row.state == state) return;
    await authority.commitVisibility(
      courseId: row.courseId,
      state: state,
    );
  }

  /// Engine for collection writes: the live session's engine when one is
  /// open, otherwise open (or fall back to) the shared importer session.
  /// Null when official anki is unavailable (flags off / worker failed).
  Future<OfficialAnkiEngine?> _resolveOfficialEngine() async {
    final existing = OfficialAnkiCompositionRoot.engine;
    if (existing != null) return existing;
    await OfficialAnkiCompositionRoot.requireImporter();
    return OfficialAnkiCompositionRoot.engine;
  }

  /// Completely uninstall an imported Anki deck.
  ///
  /// Delegates to [AnkiImportCleanupService.deleteAll] — the single uninstall
  /// saga (also used by the import wizard's rollback) — so the two paths can
  /// never drift apart again. Steps: vocabulary by tag, section tree by exact
  /// prefix, SRS entries (awaited), review history, unification bookkeeping,
  /// media files, NoteStore + derived tables, import metadata, mistake log,
  /// orchestrator caches.
  Future<void> uninstallDeck(String importId) async {
    await AnkiImportCleanupService(
      repository: _repo,
      srsProvider: _srsProvider,
      importDao: _importDao,
      noteDao: _noteDao,
      reviewHistoryDao: _reviewHistoryDao,
      audioResolver: _audioResolver,
      unificationDao: _unificationDao,
      mistakeProvider: _mistakeProvider,
      audioController: _locateAudioController(),
    ).deleteAll(importId);
  }

  /// The cleanup service releases the media player's file handles before
  /// deleting deck media. Resolved lazily so tests that never register an
  /// [AudioController] can still construct and run this manager.
  AudioController? _locateAudioController() {
    try {
      return getIt.isRegistered<AudioController>()
          ? getIt<AudioController>()
          : null;
    } catch (suppressed) {
      debugPrint('[AnkiDeckManager] suppressed error: $suppressed');
      return null;
    }
  }

  // ─── Incremental Update Detection ──────────────────────────────────

  /// Check if a file has already been imported (by hash).
  /// Returns the existing import record if found.
  Future<AnkiImportRecord?> checkExistingImport(String sourceHash) async {
    return _importDao.findByHash(sourceHash);
  }

  // ─── SRS Partitioning (Phase 3.5) ──────────────────────────────────

  /// Get the prefs key for an import's SRS state partition.
  static String srsPartitionKey(String importId) => 'anki_srs_state_$importId';

  /// Count of Anki cards in the SRS queue.
  int get ankiSrsCount {
    return _srsProvider.state.values
        .where((w) => w.wordId.startsWith(LegacyAnkiIdentifiers.ankiPrefix))
        .length;
  }

  /// Whether the SRS queue has exceeded the recommended threshold
  /// for prefs-based storage (suggest SQLite migration above this).
  bool get shouldMigrateToSqlite => ankiSrsCount > 5000;
}

/// Note/card ids owned by one official source, read from the catalog right
/// before the source rows are deleted.
class _OfficialSourceContentIds {
  const _OfficialSourceContentIds({
    required this.cardIds,
    required this.exclusiveCardIds,
  });

  final Set<int> cardIds;
  final List<int> exclusiveCardIds;
}

/// The persisted owner(s) an uninstall id resolves to. Mirrored imports
/// (legacy main write + official mirror) carry both sides; [officialSourceId]
/// is null for pure legacy decks.
class AnkiDeletionOwner {
  const AnkiDeletionOwner({required this.importId, this.officialSourceId});

  final String importId;
  final String? officialSourceId;
}
