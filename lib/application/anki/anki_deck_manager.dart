// Dart imports:
import 'dart:async';
import 'dart:math';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/application/anki/anki_models.dart';
import 'package:turna/application/anki/anki_review_assembler.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/data/anki_import_dao.dart';
import 'package:turna/data/anki_note_dao.dart';
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
  final AppPrefs _appPrefs;

  AnkiDeckManager({
    required ICourseRepository repo,
    required SrsProvider srsProvider,
    required AnkiImportDao importDao,
    required AnkiNoteDao noteDao,
    required AppPrefs appPrefs,
    AnkiAudioResolver? audioResolver,
  })  : _repo = repo,
        _srsProvider = srsProvider,
        _importDao = importDao,
        _noteDao = noteDao,
        _appPrefs = appPrefs,
        _audioResolver = audioResolver ?? AnkiAudioResolver();

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
    final useDeck = importId != null &&
        (wasNewCard
            ? await dailyNewLimitFor(importId) != null
            : await dailyReviewLimitFor(importId) != null);
    final key = useDeck
        ? _deckDoneKey(importId!, isNew: wasNewCard)
        : (wasNewCard ? _newDoneTodayKey : _reviewDoneTodayKey);
    final current =
        _appPrefs.preferences.getInt(key, defaultValue: 0).getValue();
    await _appPrefs.preferences.setInt(key, max(0, current - 1));
  }

  // ─── Deck Uninstall ─────────────────────────────────────────────────

  /// Completely uninstall an imported Anki deck:
  /// 1. Delete vocabulary entries by tag
  /// 2. Delete section tree
  /// 3. Remove SRS entries
  /// 4. Clean up media files
  /// 5. Delete NoteStore (notetypes/notes/cards_meta)
  /// 6. Delete import metadata
  Future<void> uninstallDeck(String importId) async {
    // 1. Delete vocabulary by tag
    final tag = 'anki:$importId';
    await _repo.deleteByTag(tag);

    // 2. Delete sections with this import id prefix
    final sections = await _repo.sectionShells();
    for (final section in sections) {
      if (section.id.contains('anki-$importId')) {
        await _repo.deleteSection(section.id);
      }
    }

    // 3. Remove SRS entries for this import
    _removeSrsEntries(importId);

    // 4. Clean up media files
    await _audioResolver.deleteImportMedia(importId);

    // 5. Delete NoteStore (notetypes/notes/cards_meta for this import).
    await _noteDao.deleteByImport(importId);
    // Also drop the "智能去解密" pre-rendered HTML cache for this import.
    await _noteDao.deletePrerenderedByPrefix('anki-$importId-');

    // 6. Delete import metadata
    await _importDao.delete(importId);
  }

  void _removeSrsEntries(String importId) {
    final prefix = 'anki-$importId-';
    _srsProvider.removeByPrefix(prefix);
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
