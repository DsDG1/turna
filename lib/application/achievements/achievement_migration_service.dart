// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/application/achievements/achievement_metric_projector.dart';
import 'package:turna/application/achievements/achievement_state_repository.dart';
import 'package:turna/core/logger.dart';
import 'package:turna/domain/achievements/achievement_catalog.dart';
import 'package:turna/domain/achievements/achievement_state.dart';
import 'package:turna/service/locator.dart';

/// Result of a migration pass (first run or a no-op re-run).
class AchievementMigrationReport {
  final bool ran;
  final int backfilledTiers;
  final List<String> unknownIds;
  final bool hadLegacyStreak100;
  final List<String> countConflicts;

  const AchievementMigrationReport({
    required this.ran,
    this.backfilledTiers = 0,
    this.unknownIds = const [],
    this.hadLegacyStreak100 = false,
    this.countConflicts = const [],
  });
}

/// One-shot v1 -> v2 migration (plan §6). Reads the legacy
/// `achievements.unlocked` id list plus current authoritative metrics and
/// backfills every reached tier as `origin=migration, rewardGranted=true,
/// seen=true` — no per-tier gem back-pay. The v1 list itself is never
/// modified.
///
/// Idempotent: guarded by `achievements.migration.version` and, even without
/// the marker, re-running changes nothing (set semantics on tier ids).
@lazySingleton
class AchievementMigrationService {
  static const int currentMigrationVersion = 1;

  final AppPrefs _prefs;
  final AchievementStateRepository _stateRepository;
  final AchievementMetricProjector _projector;

  AchievementMigrationService(
    this._prefs,
    this._stateRepository,
    this._projector,
  );

  /// v1 ids with precise "already rewarded" semantics: these unlock their
  /// mapped tier even if the live metric has since dropped (e.g. streak).
  static const Map<String, String> _exactTierTargets = {
    'xp_1000': 'xp_journey_003',
    'xp_10000': 'xp_journey_005',
    'xp_50000': 'xp_journey_006',
    'streak_3': 'streak_journey_001',
    'streak_7': 'streak_journey_002',
    'streak_30': 'streak_journey_004',
    'streak_365': 'streak_journey_008',
  };

  Future<AchievementMigrationReport> runIfNeeded() async {
    final version = _prefs.preferences
        .getInt(LocalStateKeys.achievementsMigrationVersion, defaultValue: 0)
        .getValue();
    if (version >= currentMigrationVersion) {
      return const AchievementMigrationReport(ran: false);
    }

    final v1Ids = _prefs.preferences
        .getStringList(LocalStateKeys.achievements, defaultValue: const [])
        .getValue()
        .toSet();

    final snapshot = await _projector.buildSnapshot();
    final diagnostics = <String>[];
    var hadLegacyStreak100 = false;
    final unknownIds = <String>[];
    final countConflicts = <String>[];

    _recordCountConflicts(countConflicts);

    final unlocked = <String, AchievementTierState>{};

    // 1) Precise v1 id mapping — preserved regardless of current metrics.
    for (final id in v1Ids) {
      final tierId = _exactTierTargets[id];
      if (tierId != null) {
        final tier = AchievementCatalog.tierById(tierId);
        if (tier != null) {
          unlocked[tierId] = _migrationTierState(tierId);
        }
        continue;
      }
      switch (id) {
        case 'champion':
        case 'sharpshooter':
        case 'scholar':
        case 'sage':
        case 'wildfire':
        case 'winner':
          // Recomputed from authoritative metrics below (plan §6.2).
          break;
        case 'streak_100':
          // New ladder has no 100-day tier (75 -> 125). Record as legacy
          // commemorative state; never map onto the 125-day tier.
          hadLegacyStreak100 = true;
          diagnostics.add('legacy:streak_100');
          break;
        default:
          unknownIds.add(id);
          diagnostics.add('unknown:$id');
      }
    }

    // 2) Authoritative backfill: every published tier already reached.
    var backfilled = 0;
    for (final series in AchievementCatalog.publishedSeries) {
      final value = snapshot.metricValue(series.metric);
      for (final tier in series.tiers) {
        if (value < tier.target) break;
        if (unlocked.containsKey(tier.id)) continue;
        unlocked[tier.id] = _migrationTierState(tier.id);
        backfilled++;
      }
    }

    // Unpublished series (vocabulary) are never backfilled — no trustworthy
    // historical source exists for them.

    await _stateRepository.mutate((current) {
      final merged = Map<String, AchievementTierState>.of(current.unlockedTiers)
        ..addAll(unlocked);
      return current.copyWith(
        unlockedTiers: merged,
        updatedAt: DateTime.now(),
        migrationDiagnostics: {
          ...current.migrationDiagnostics,
          ...diagnostics,
        }.toList(growable: false),
      );
    });

    await _prefs.preferences.setInt(
      LocalStateKeys.achievementsMigrationVersion,
      currentMigrationVersion,
    );

    logger.i(
      'Achievement v1->v2 migration: $backfilled backfilled, '
      '${unknownIds.length} unknown ids, streak100=$hadLegacyStreak100',
    );

    return AchievementMigrationReport(
      ran: true,
      backfilledTiers: backfilled,
      unknownIds: unknownIds,
      hadLegacyStreak100: hadLegacyStreak100,
      countConflicts: countConflicts,
    );
  }

  AchievementTierState _migrationTierState(String tierId) =>
      AchievementTierState(
        tierId: tierId,
        unlockedAt: DateTime.now(),
        rewardGranted: true,
        rewardGrantedAt: DateTime.now(),
        seen: true,
        seenAt: DateTime.now(),
        origin: AchievementUnlockOrigin.migration,
      );

  /// Plan §6.4: legacy integer counters larger than the deduped id sets are
  /// diagnostic only — the id sets stay authoritative.
  void _recordCountConflicts(List<String> conflicts) {
    final legacyCompleted = _prefs.preferences
        .getInt(LocalStateKeys.lessonsCompleted, defaultValue: 0)
        .getValue();
    final legacyPerfect = _prefs.preferences
        .getInt(LocalStateKeys.perfectLessons, defaultValue: 0)
        .getValue();
    final idCompleted = _prefs.preferences
        .getStringList(
          LocalStateKeys.completedLessonIds,
          defaultValue: const [],
        )
        .getValue()
        .toSet()
        .length;
    final idPerfect = _prefs.preferences
        .getStringList(
          LocalStateKeys.perfectLessonIds,
          defaultValue: const [],
        )
        .getValue()
        .toSet()
        .length;
    if (legacyCompleted > idCompleted) {
      conflicts.add(
        'lessonsCompleted:$legacyCompleted>${idCompleted}byId — id set wins',
      );
    }
    if (legacyPerfect > idPerfect) {
      conflicts.add(
        'perfectLessons:$legacyPerfect>${idPerfect}byId — id set wins',
      );
    }
  }
}
