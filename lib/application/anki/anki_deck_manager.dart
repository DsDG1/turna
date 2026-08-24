// Dart imports:
import 'dart:async';
import 'dart:math';

// Package imports:
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/application/anki/anki_models.dart';
import 'package:turna/application/anki/anki_import_cleanup_service.dart';
import 'package:turna/application/anki/anki_review_assembler.dart';
import 'package:turna/application/anki/card_introduction_eligibility.dart';
import 'package:turna/application/anki/unified_anki_import_orchestrator.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine.dart';
import 'package:turna/application/anki_official/migration/official_anki_migration_dao.dart';
import 'package:turna/application/anki_official/migration/official_anki_write_owner.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/application/mistake_provider.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/data/anki_import_dao.dart';
import 'package:turna/data/anki_note_dao.dart';
import 'package:turna/data/anki_unification_dao.dart';
import 'package:turna/data/review_history_dao.dart';
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

  // ─── Daily Counters ─────────────────────────────────────────────────

  static const String _newDoneTodayKey = 'anki.newDoneToday';
  static const String _reviewDoneTodayKey = 'anki.reviewDoneToday';
  static const String _limitsDateKey = 'anki.limitsDate';

  static String _deckDoneKey(String importId, {required bool isNew}) =>
      'anki.deck.$importId.${isNew ? 'new' : 'review'}Done.${_todayStamp()}';

  static String _todayStamp() {
    final now = DateTime.now();
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '${now.year}-$m-$d';
  }

  /// Reset the daily counters when the calendar day has rolled over.
  /// Fire-and-forget writes — reads below always go through this first, so
  /// the values are consistent within the session even before the writes
  /// land.
  void _resetCountersIfNewDay() {
    final today = _todayStamp();
    final stored = _appPrefs.preferences
        .getString(_limitsDateKey, defaultValue: '')
        .getValue();
    if (stored == today) return;
    unawaited(_appPrefs.preferences.setString(_limitsDateKey, today));
    unawaited(_appPrefs.preferences.setInt(_newDoneTodayKey, 0));
    unawaited(_appPrefs.preferences.setInt(_reviewDoneTodayKey, 0));
  }

  /// New cards (reps == 0 at review time) already studied today.
  int get newDoneToday {
    _resetCountersIfNewDay();
    return _appPrefs.preferences
        .getInt(_newDoneTodayKey, defaultValue: 0)
        .getValue();
  }

  /// Review cards already studied today.
  int get reviewDoneToday {
    _resetCountersIfNewDay();
    return _appPrefs.preferences
        .getInt(_reviewDoneTodayKey, defaultValue: 0)
        .getValue();
  }

  /// How many new cards may still be introduced today.
  int get newRemainingToday => max(0, dailyNewLimit - newDoneToday);

  /// How many review cards may still be studied today.
  int get reviewRemainingToday => max(0, dailyReviewLimit - reviewDoneToday);

  Future<int?> dailyNewLimitFor(String importId) =>
      _importDao.dailyNewLimitFor(importId);

  Future<int?> dailyReviewLimitFor(String importId) =>
      _importDao.dailyReviewLimitFor(importId);

  Future<int> remainingForImport(String importId, {required bool isNew}) async {
    final limit = isNew
        ? await dailyNewLimitFor(importId)
        : await dailyReviewLimitFor(importId);
    if (limit == null) return isNew ? newRemainingToday : reviewRemainingToday;
    _resetCountersIfNewDay();
    final key = _deckDoneKey(importId, isNew: isNew);
    final done = _appPrefs.preferences.getInt(key, defaultValue: 0).getValue();
    return max(0, limit - done);
  }

  /// Record one reviewed card against today's counters. [isNewCard] should
  /// reflect the card's state *before* the review (reps == 0).
  Future<void> recordCardReviewed({
    required bool isNewCard,
    String? importId,
  }) async {
    assertLegacySrsAnswerAllowed(importId: importId);
    _resetCountersIfNewDay();
    if (importId != null) {
      final limit = isNewCard
          ? await dailyNewLimitFor(importId)
          : await dailyReviewLimitFor(importId);
      if (limit != null) {
        final key = _deckDoneKey(importId, isNew: isNewCard);
        final current =
            _appPrefs.preferences.getInt(key, defaultValue: 0).getValue();
        await _appPrefs.preferences.setInt(key, min(limit, current + 1));
        return;
      }
    }
    final key = isNewCard ? _newDoneTodayKey : _reviewDoneTodayKey;
    final current =
        _appPrefs.preferences.getInt(key, defaultValue: 0).getValue();
    await _appPrefs.preferences.setInt(key, current + 1);
  }

  Future<void> recordCardUnreviewed({
    required bool wasNewCard,
    String? importId,
  }) async {
    _resetCountersIfNewDay();
    if (importId != null) {
      final limit = wasNewCard
          ? await dailyNewLimitFor(importId)
          : await dailyReviewLimitFor(importId);
      if (limit != null) {
        await _decrementDone(_deckDoneKey(importId, isNew: wasNewCard));
        return;
      }
    }
    await _decrementDone(
      wasNewCard ? _newDoneTodayKey : _reviewDoneTodayKey,
    );
  }

  Future<void> _decrementDone(String key) async {
    final current =
        _appPrefs.preferences.getInt(key, defaultValue: 0).getValue();
    await _appPrefs.preferences.setInt(key, max(0, current - 1));
  }

  // ─── Deck Uninstall ─────────────────────────────────────────────────

  /// Route an uninstall through the resolved owner. The
  /// `legacy_anki_migrations` link table decides whether the id maps to an
  /// official source (mirrored and official-first imports); the course-tree
  /// prefix is only a recovery hint. A mirrored import is cleaned on both
  /// sides — official collection/catalog first, then the legacy rows.
  Future<void> uninstall(String importId) async {
    final owner = await _resolveDeletionOwner(importId);
    final officialSourceId = owner.officialSourceId;
    if (officialSourceId != null) {
      await uninstallOfficialSource(officialSourceId);
    }
    if (officialSourceId == null || await _hasLegacyArtifacts(importId)) {
      await uninstallDeck(importId);
    }
  }

  /// Resolve which persisted owner an uninstall id belongs to. The migration
  /// link is authoritative; the `official-anki-<id>-…` tree prefix only
  /// recovers official-first sources whose catalog rows are missing.
  Future<AnkiDeletionOwner> _resolveDeletionOwner(String importId) async {
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
    final _OfficialSourceContentIds contentIds;
    try {
      contentIds = await _officialSourceContentIds(sourceId);
    } catch (_) {
      // Without the ownership metadata the saga must stop: deleting the
      // projection/catalog first would orphan the collection notes.
      await _markOfficialSourcePendingCleanup(sourceId);
      return false;
    }
    final collectionDeleted =
        await _deleteOfficialSourceNotes(contentIds.noteIds);
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
    final catalog = OfficialAnkiCompositionRoot.readOnlyCatalog;
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
    UnifiedAnkiImportOrchestrator.instance.invalidate(importId: sourceId);
    return true;
  }

  /// Retry every `pending_cleanup` source whose collection delete failed
  /// earlier. Intended to run on app start so users do not have to keep
  /// pressing delete after a transient engine failure.
  Future<int> retryPendingOfficialCleanups() async {
    try {
      await OfficialAnkiCompositionRoot.initializeReadOnlyLocator();
      final catalog = OfficialAnkiCompositionRoot.readOnlyCatalog;
      if (catalog == null) return 0;
      final pending = OfficialAnkiSourceDao(catalog)
          .listSources(CardIntroductionEligibility.defaultProfileId)
          .where((source) => source.state == 'pending_cleanup')
          .toList();
      var resumed = 0;
      for (final source in pending) {
        if (await uninstallOfficialSource(source.sourceId)) {
          resumed++;
        }
      }
      return resumed;
    } catch (e) {
      debugPrint('[AnkiDeckManager] pending cleanup retry failed: $e');
      return 0;
    }
  }

  /// The source's note ids (for collection deletion) and card ids (for
  /// mistake-log matching — official card word ids do not carry the
  /// sourceId). Read before the catalog rows are deleted. A read failure
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
      final cards = OfficialAnkiSourceDao(catalog).listCards(sourceId);
      final noteIds = cards.map((card) => card.noteId).toSet().toList()..sort();
      return _OfficialSourceContentIds(
        noteIds,
        cards.map((card) => card.cardId).toSet(),
      );
    } catch (e) {
      debugPrint(
        '[AnkiDeckManager] read official source cards failed '
        'for $sourceId: $e',
      );
      rethrow;
    }
  }

  /// Remove the source's notes (and every card that uses them) from the
  /// official collection. Batched to stay under the DELETE_NOTES id cap.
  /// Returns false when the collection could not be cleaned — the caller
  /// must then keep the catalog rows and mark the source pending cleanup.
  Future<bool> _deleteOfficialSourceNotes(List<int> noteIds) async {
    if (noteIds.isEmpty) return true;
    try {
      final engine = await _resolveOfficialEngine();
      if (engine == null) {
        debugPrint(
          '[AnkiDeckManager] official engine unavailable; '
          '${noteIds.length} collection notes kept',
        );
        return false;
      }
      const batchLimit = 5000;
      for (var start = 0; start < noteIds.length; start += batchLimit) {
        final end = min(start + batchLimit, noteIds.length);
        await engine.deleteNotes(noteIds.sublist(start, end));
      }
      return true;
    } catch (e) {
      debugPrint(
        '[AnkiDeckManager] official collection deleteNotes failed: $e',
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
    ).deleteAll(importId);
  }

  // ─── Incremental Update Detection ──────────────────────────────────

  /// Check if a file has already been imported (by hash).
  /// Returns the existing import record if found.
  Future<AnkiImportRecord?> checkExistingImport(String sourceHash) async {
    return _importDao.findByHash(sourceHash);
  }

  /// Note ids from [newCollection] that are not yet imported (i.e. absent
  /// from the SRS queue under [importId]). Used by the import wizard's
  /// skip-existing strategy and collision preview.
  List<int> detectNewNotes({
    required AnkiCollection newCollection,
    required String importId,
  }) {
    final srsIds = _srsProvider.state.keys;
    // Card-level wordIds (decision 2): a note counts as already imported if
    // any of its cards is in the SRS queue.
    final existingNids = <int>{
      for (final card in newCollection.cards)
        if (srsIds.contains('anki-$importId-c${card.id}')) card.nid,
    };
    return [
      for (final note in newCollection.notes)
        if (!existingNids.contains(note.id)) note.id,
    ];
  }

  // ─── SRS Partitioning (Phase 3.5) ──────────────────────────────────

  /// Get the prefs key for an import's SRS state partition.
  static String srsPartitionKey(String importId) => 'anki_srs_state_$importId';

  /// Count of Anki cards in the SRS queue.
  int get ankiSrsCount {
    return _srsProvider.state.values
        .where((w) => w.wordId.startsWith(AnkiReviewAssembler.ankiPrefix))
        .length;
  }

  /// Whether the SRS queue has exceeded the recommended threshold
  /// for prefs-based storage (suggest SQLite migration above this).
  bool get shouldMigrateToSqlite => ankiSrsCount > 5000;
}

/// Note/card ids owned by one official source, read from the catalog right
/// before the source rows are deleted.
class _OfficialSourceContentIds {
  const _OfficialSourceContentIds(this.noteIds, this.cardIds);

  final List<int> noteIds;
  final Set<int> cardIds;
}

/// The persisted owner(s) an uninstall id resolves to. Mirrored imports
/// (legacy main write + official mirror) carry both sides; [officialSourceId]
/// is null for pure legacy decks.
class AnkiDeletionOwner {
  const AnkiDeletionOwner({required this.importId, this.officialSourceId});

  final String importId;
  final String? officialSourceId;
}
