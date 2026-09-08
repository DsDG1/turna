// Dart imports:
import 'dart:convert';

// Package imports:
import 'package:crypto/crypto.dart';
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/application/achievements/achievement_service.dart';
import 'package:turna/application/cosmetic_provider.dart';
import 'package:turna/application/game_provider.dart';
import 'package:turna/application/gems_provider.dart';
import 'package:turna/application/grammar_review_provider.dart';
import 'package:turna/application/lesson_link_store.dart';
import 'package:turna/application/lesson_progress_provider.dart';
import 'package:turna/application/mistake_provider.dart';
import 'package:turna/application/restore_normalization_service.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/application/study_stats_provider.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/data/srs_state_dao.dart';
import 'package:turna/data/study_log_repository.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/service/locator.dart';

class FunLabSnapshotMeta {
  final DateTime createdAt;
  final int srsItemCount;

  const FunLabSnapshotMeta({
    required this.createdAt,
    required this.srsItemCount,
  });
}

class FunLabSnapshotContentChanged implements Exception {
  const FunLabSnapshotContentChanged();
}

enum _SnapshotPrefType { bool_, int_, string, stringList }

class _SnapshotPref {
  final String key;
  final _SnapshotPrefType type;

  const _SnapshotPref(this.key, this.type);
}

/// Persistent, single-slot checkpoint storage for the Fun Lab.
///
/// Course content itself is deliberately excluded. A fingerprint prevents a
/// snapshot from being restored after the built-in content or Anki import set
/// changes, which would otherwise leave progress referring to different rows.
@lazySingleton
class FunLabSnapshotService {
  final AppPrefs _prefs;
  final CourseDatabase _db;
  final SrsStateDao _srsStateDao;
  final SrsProvider _srsProvider;
  final GrammarReviewProvider _grammarProvider;
  final LessonProgressProvider _lessonProgress;
  final MistakeProvider _mistakeProvider;
  final LessonLinkStore _linkStore;
  final StudyLogRepository _studyLogRepository;
  final StudyStatsProvider _studyStatsProvider;
  final GemsProvider _gemsProvider;
  final GameProvider _gameProvider;
  final AchievementService _achievementService;

  FunLabSnapshotService(
    this._prefs,
    this._db,
    this._srsStateDao,
    this._srsProvider,
    this._grammarProvider,
    this._lessonProgress,
    this._mistakeProvider,
    this._linkStore,
    this._studyLogRepository,
    this._studyStatsProvider,
    this._gemsProvider,
    this._gameProvider,
    this._achievementService,
  );

  static const _snapshotPrefs = <_SnapshotPref>[
    _SnapshotPref(LocalStateKeys.initialized, _SnapshotPrefType.bool_),
    _SnapshotPref(LocalStateKeys.score, _SnapshotPrefType.int_),
    _SnapshotPref(LocalStateKeys.streak, _SnapshotPrefType.int_),
    _SnapshotPref(LocalStateKeys.lastStreakDate, _SnapshotPrefType.string),
    _SnapshotPref(LocalStateKeys.lessonsCompleted, _SnapshotPrefType.int_),
    _SnapshotPref(LocalStateKeys.perfectLessons, _SnapshotPrefType.int_),
    _SnapshotPref(
      LocalStateKeys.completedLessonIds,
      _SnapshotPrefType.stringList,
    ),
    _SnapshotPref(
      LocalStateKeys.perfectLessonIds,
      _SnapshotPrefType.stringList,
    ),
    _SnapshotPref(LocalStateKeys.streakWasBroken, _SnapshotPrefType.bool_),
    _SnapshotPref(
      LocalStateKeys.streakProtectedDays,
      _SnapshotPrefType.stringList,
    ),
    _SnapshotPref(
      LocalStateKeys.streakAutoUseVoucher,
      _SnapshotPrefType.bool_,
    ),
    _SnapshotPref(LocalStateKeys.wordsLearned, _SnapshotPrefType.int_),
    _SnapshotPref(LocalStateKeys.gems, _SnapshotPrefType.int_),
    _SnapshotPref(
      LocalStateKeys.cosmeticsUnlocked,
      _SnapshotPrefType.stringList,
    ),
    _SnapshotPref(
      LocalStateKeys.cosmeticsEquippedRing,
      _SnapshotPrefType.string,
    ),
    _SnapshotPref(
      LocalStateKeys.cosmeticsEquippedAvatarRing,
      _SnapshotPrefType.string,
    ),
    _SnapshotPref(
      LocalStateKeys.cosmeticsEquippedProfileTheme,
      _SnapshotPrefType.string,
    ),
    _SnapshotPref(
      LocalStateKeys.cosmeticsEquippedCompletionEffect,
      _SnapshotPrefType.string,
    ),
    // v1 achievement list (legacy) + achievements v2 state/projection/marker.
    _SnapshotPref(LocalStateKeys.achievements, _SnapshotPrefType.stringList),
    _SnapshotPref(LocalStateKeys.achievementsStateV2, _SnapshotPrefType.string),
    _SnapshotPref(
      LocalStateKeys.achievementsProjectionV1,
      _SnapshotPrefType.string,
    ),
    _SnapshotPref(
      LocalStateKeys.achievementsMigrationVersion,
      _SnapshotPrefType.int_,
    ),
    _SnapshotPref(LocalStateKeys.lessonWordLinks, _SnapshotPrefType.string),
    _SnapshotPref(LocalStateKeys.mistakeLog, _SnapshotPrefType.string),
    _SnapshotPref(
      LocalStateKeys.mistakeDailyCounts,
      _SnapshotPrefType.string,
    ),
    _SnapshotPref(
      LocalStateKeys.mistakeMasteredTotal,
      _SnapshotPrefType.int_,
    ),
    _SnapshotPref('study.logs', _SnapshotPrefType.string),
    _SnapshotPref('study.logs.recent', _SnapshotPrefType.string),
    _SnapshotPref('study.dailyStats', _SnapshotPrefType.string),
    _SnapshotPref('anki.newDoneToday', _SnapshotPrefType.int_),
    _SnapshotPref('anki.reviewDoneToday', _SnapshotPrefType.int_),
    _SnapshotPref('anki.limitsDate', _SnapshotPrefType.string),
    _SnapshotPref(
      LocalStateKeys.funAllAchievementsUnlocked,
      _SnapshotPrefType.bool_,
    ),
  ];

  static const _srsColumns =
      'language_code, word_id, queue, due_at, interval_days, ease, reps, lapses, '
      'is_leech, is_suspended, is_buried, type, last_reviewed_at, '
      'stability, difficulty, fsrs_state, learning_step, source_kind, '
      'source_id, owner_id';

  static const _reviewColumns =
      'id, card_id, language_code, queue, reviewed_at, quality, prev_interval_days, '
      'next_interval_days, prev_ease, next_ease, reps, lapses, type, '
      'source_key, source_kind, source_id, owner_id';

  Future<FunLabSnapshotMeta?> loadMeta() async {
    final rows = await _db
        .customSelect(
          'SELECT created_at, srs_item_count FROM fun_lab_snapshot_meta '
          'WHERE id = 1',
        )
        .get();
    if (rows.isEmpty) return null;
    return FunLabSnapshotMeta(
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        rows.single.read<int>('created_at'),
      ),
      srsItemCount: rows.single.read<int>('srs_item_count'),
    );
  }

  Future<FunLabSnapshotMeta> createSnapshot() async {
    final createdAt = DateTime.now();
    final prefsJson = jsonEncode(_capturePrefs());
    final fingerprint = await _contentFingerprint();
    final countRow = await _db
        .customSelect(
          'SELECT COUNT(*) AS total FROM srs_states',
        )
        .getSingle();
    final itemCount = countRow.read<int>('total');

    await _db.transaction(() async {
      await _clearSnapshotTables();
      await _db.customStatement(
        'INSERT INTO fun_lab_snapshot_srs ($_srsColumns) '
        'SELECT $_srsColumns FROM srs_states',
      );
      await _db.customStatement(
        'INSERT INTO fun_lab_snapshot_review_events ($_reviewColumns) '
        'SELECT $_reviewColumns FROM review_events',
      );
      await _db.customStatement('''
        INSERT INTO fun_lab_snapshot_anki_state
          (import_id, card_id, suspended, buried_until, marked, flag)
        SELECT import_id, card_id, suspended, buried_until, marked, flag
        FROM anki_cards_meta
      ''');
      await _db.customStatement(
        'INSERT INTO fun_lab_snapshot_meta '
        '(id, created_at, content_fingerprint, prefs_json, srs_item_count) '
        'VALUES (1, ?, ?, ?, ?)',
        [
          createdAt.millisecondsSinceEpoch,
          fingerprint,
          prefsJson,
          itemCount,
        ],
      );
    });

    return FunLabSnapshotMeta(createdAt: createdAt, srsItemCount: itemCount);
  }

  Future<void> restoreSnapshot() async {
    final rows = await _db
        .customSelect(
          'SELECT content_fingerprint, prefs_json FROM fun_lab_snapshot_meta '
          'WHERE id = 1',
        )
        .get();
    if (rows.isEmpty) throw StateError('No Fun Lab snapshot');
    final row = rows.single;
    if (row.read<String>('content_fingerprint') !=
        await _contentFingerprint()) {
      throw const FunLabSnapshotContentChanged();
    }

    final decoded = jsonDecode(row.read<String>('prefs_json'));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid Fun Lab preference snapshot');
    }

    await _db.transaction(() async {
      await _db.customStatement('DELETE FROM srs_states');
      await _db.customStatement(
        'INSERT INTO srs_states ($_srsColumns) '
        'SELECT $_srsColumns FROM fun_lab_snapshot_srs',
      );
      await _db.customStatement('DELETE FROM review_events');
      await _db.customStatement(
        'INSERT INTO review_events ($_reviewColumns) '
        'SELECT $_reviewColumns FROM fun_lab_snapshot_review_events',
      );
      await _db.customStatement('''
        UPDATE anki_cards_meta
        SET suspended = (
              SELECT s.suspended FROM fun_lab_snapshot_anki_state s
              WHERE s.import_id = anki_cards_meta.import_id
                AND s.card_id = anki_cards_meta.card_id
            ),
            buried_until = (
              SELECT s.buried_until FROM fun_lab_snapshot_anki_state s
              WHERE s.import_id = anki_cards_meta.import_id
                AND s.card_id = anki_cards_meta.card_id
            ),
            marked = (
              SELECT s.marked FROM fun_lab_snapshot_anki_state s
              WHERE s.import_id = anki_cards_meta.import_id
                AND s.card_id = anki_cards_meta.card_id
            ),
            flag = (
              SELECT s.flag FROM fun_lab_snapshot_anki_state s
              WHERE s.import_id = anki_cards_meta.import_id
                AND s.card_id = anki_cards_meta.card_id
            )
        WHERE EXISTS (
          SELECT 1 FROM fun_lab_snapshot_anki_state s
          WHERE s.import_id = anki_cards_meta.import_id
            AND s.card_id = anki_cards_meta.card_id
        )
      ''');
    });

    await _restorePrefs(decoded);
    await _refreshProviders();
  }

  Future<void> deleteSnapshot() => _db.transaction(_clearSnapshotTables);

  Future<int> countPostponableReviews() async {
    return _srsStateDao.countPostponable();
  }

  Future<int> postponeAllActiveReviews(Duration duration) async {
    final affected = await _srsStateDao.postponeActiveBy(duration);
    await Future.wait([
      _srsProvider.reloadFromStorage(),
      _grammarProvider.reloadFromStorage(),
    ]);
    return affected;
  }

  Future<void> _clearSnapshotTables() async {
    await _db.customStatement('DELETE FROM fun_lab_snapshot_anki_state');
    await _db.customStatement('DELETE FROM fun_lab_snapshot_review_events');
    await _db.customStatement('DELETE FROM fun_lab_snapshot_srs');
    await _db.customStatement('DELETE FROM fun_lab_snapshot_meta');
  }

  Map<String, dynamic> _capturePrefs() {
    final store = _prefs.preferences;
    final existing = store.getKeys().getValue();
    final values = <String, dynamic>{};
    for (final pref in _snapshotPrefs) {
      if (!existing.contains(pref.key)) continue;
      values[pref.key] = _readPref(pref);
    }
    for (final key in existing.where(_isDeckCounterKey)) {
      values[key] = {
        'type': _SnapshotPrefType.int_.name,
        'value': store.getInt(key, defaultValue: 0).getValue(),
      };
    }
    return values;
  }

  Map<String, dynamic> _readPref(_SnapshotPref pref) {
    final store = _prefs.preferences;
    final Object value;
    switch (pref.type) {
      case _SnapshotPrefType.bool_:
        value = store.getBool(pref.key, defaultValue: false).getValue();
      case _SnapshotPrefType.int_:
        value = store.getInt(pref.key, defaultValue: 0).getValue();
      case _SnapshotPrefType.string:
        value = store.getString(pref.key, defaultValue: '').getValue();
      case _SnapshotPrefType.stringList:
        value = store
            .getStringList(pref.key, defaultValue: const <String>[]).getValue();
    }
    return {'type': pref.type.name, 'value': value};
  }

  Future<void> _restorePrefs(Map<String, dynamic> values) async {
    final store = _prefs.preferences;
    final currentKeys = store.getKeys().getValue();
    final staticKeys = _snapshotPrefs.map((e) => e.key).toSet();
    for (final key in currentKeys) {
      if ((staticKeys.contains(key) || _isDeckCounterKey(key)) &&
          !values.containsKey(key)) {
        await store.remove(key);
      }
    }

    for (final entry in values.entries) {
      final encoded = entry.value;
      if (encoded is! Map) continue;
      final type = encoded['type']?.toString();
      final value = encoded['value'];
      switch (type) {
        case 'bool_':
          if (value is bool) await store.setBool(entry.key, value);
        case 'int_':
          if (value is int) await store.setInt(entry.key, value);
        case 'string':
          if (value is String) await store.setString(entry.key, value);
        case 'stringList':
          if (value is List) {
            await store.setStringList(
              entry.key,
              value.map((e) => e.toString()).toList(growable: false),
            );
          }
      }
    }
  }

  Future<void> _refreshProviders() async {
    await Future.wait([
      _srsProvider.reloadFromStorage(),
      _grammarProvider.reloadFromStorage(),
    ]);
    _lessonProgress.reloadFromPrefs();
    _mistakeProvider.reloadFromPrefs();
    await _linkStore.reloadFromPrefs();
    await _studyLogRepository.reloadFromPrefs();
    if (getIt.isRegistered<RestoreNormalizationService>()) {
      await getIt<RestoreNormalizationService>().normalize();
    } else {
      await _gemsProvider.reconcileAfterRestore();
      if (getIt.isRegistered<CosmeticProvider>()) {
        await getIt<CosmeticProvider>().ensureInitialized();
      }
      await _prefs.preferences.setBool(LocalStateKeys.funAutoAnswer, false);
    }
    _gameProvider.refreshFromPrefs();
    await _studyStatsProvider.refreshFromPrefs();
    await _achievementService.reloadFromPrefs();
  }

  Future<String> _contentFingerprint() async {
    final meta = await _db
        .customSelect(
          'SELECT key, value FROM course_meta ORDER BY key',
        )
        .get();
    final imports = await _db
        .customSelect(
          'SELECT import_id, source_hash, version FROM anki_imports '
          'ORDER BY import_id',
        )
        .get();
    final payload = jsonEncode({
      'course': [
        for (final row in meta)
          [row.read<String>('key'), row.read<String>('value')],
      ],
      'imports': [
        for (final row in imports)
          [
            row.read<String>('import_id'),
            row.read<String>('source_hash'),
            row.read<int>('version'),
          ],
      ],
    });
    return sha256.convert(utf8.encode(payload)).toString();
  }

  static bool _isDeckCounterKey(String key) =>
      key.startsWith('anki.deck.') && key.contains('Done.');
}
