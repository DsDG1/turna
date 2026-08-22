// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/application/achievements/achievement_evaluator.dart';
import 'package:turna/application/achievements/achievement_metric_projector.dart';
import 'package:turna/application/achievements/achievement_migration_service.dart';
import 'package:turna/application/achievements/achievement_state_repository.dart';
import 'package:turna/application/gems_provider.dart';
import 'package:turna/core/logger.dart';
import 'package:turna/domain/achievements/achievement_catalog.dart';
import 'package:turna/domain/achievements/achievement_definition.dart';
import 'package:turna/domain/achievements/achievement_state.dart';
import 'package:turna/domain/achievements/achievement_unlock_result.dart';

/// Single writer for the unified achievement system (plan §5.1). Every
/// unlock path — lesson completion, review completion, startup reconcile —
/// funnels through [evaluateAndReward], which serializes:
///
/// ```text
/// evaluate -> persist unlock (rewardGranted=false)
///          -> grant gems through GemsProvider
///          -> persist rewardGranted=true
///          -> notify listeners (feedback queue derives from seen=false)
/// ```
///
/// A crash between persist and grant is healed by [recoverPendingRewards] on
/// the next startup, so gems are paid exactly once.
@lazySingleton
class AchievementService extends ChangeNotifier {
  final AchievementStateRepository _stateRepository;
  final AchievementMetricProjector _projector;
  final AchievementMigrationService _migrationService;
  final GemsProvider _gemsProvider;

  /// Serializes whole evaluate/recover cycles (outer lock on top of the
  /// repository's own write chain).
  Future<void> _evaluateChain = Future.value();

  AchievementMetricSnapshot _lastSnapshot = AchievementMetricSnapshot();

  AchievementService(
    this._stateRepository,
    this._projector,
    this._migrationService,
    this._gemsProvider,
  );

  // ── Read API (UI) ─────────────────────────────────────────────────

  /// Persisted state; empty until first [initialize]/[readState].
  AchievementStateDocument get state => _stateRepository.current;

  /// Most recent metric snapshot (refreshed by [initialize] and every
  /// evaluation). UI progress views read this, never raw prefs.
  AchievementMetricSnapshot get lastSnapshot => _lastSnapshot;

  bool get hasUnseenUnlocks => unseenLiveUnlocks.isNotEmpty;

  /// Feedback queue: persisted live unlocks the user has not seen yet.
  List<AchievementTierState> get unseenLiveUnlocks => state.unlockedTiers.values
      .where((t) =>
          !t.seen &&
          t.origin == AchievementUnlockOrigin.live &&
          AchievementCatalog.tierById(t.tierId) != null)
      .toList(growable: false);

  /// Unlocked badge count across published series.
  int get unlockedBadgeCount => state.unlockedTiers.keys
      .where(_isPublishedTier)
      .length;

  /// Most recent unlock across published series (null for fresh accounts).
  AchievementTierState? get latestUnlock {
    AchievementTierState? latest;
    for (final t in state.unlockedTiers.values) {
      if (!_isPublishedTier(t.tierId)) continue;
      if (latest == null || t.unlockedAt.isAfter(latest.unlockedAt)) {
        latest = t;
      }
    }
    return latest;
  }

  bool _isPublishedTier(String tierId) {
    final tier = AchievementCatalog.tierById(tierId);
    if (tier == null) return false;
    final series = AchievementCatalog.allSeries
        .where((s) => s.tiers.contains(tier))
        .firstOrNull;
    return series?.published ?? false;
  }

  /// Progress views for every published series, in catalog order.
  List<AchievementSeriesProgress> progressViews([AchievementMetricSnapshot? snapshot]) {
    final snap = snapshot ?? _lastSnapshot;
    final doc = state;
    return [
      for (final series in AchievementCatalog.publishedSeries)
        _progressFor(series, snap, doc),
    ];
  }

  AchievementSeriesProgress progressFor(String seriesId) {
    final series = AchievementCatalog.seriesById(seriesId);
    if (series == null || !series.published) {
      return AchievementSeriesProgress(
        seriesId: seriesId,
        currentProgress: 0,
        completedTierCount: 0,
        totalTierCount: 0,
        nextTier: null,
        hasUnseenUnlock: false,
      );
    }
    return _progressFor(series, _lastSnapshot, state);
  }

  AchievementSeriesProgress _progressFor(
    AchievementSeriesDefinition series,
    AchievementMetricSnapshot snapshot,
    AchievementStateDocument doc,
  ) {
    final value = snapshot.metricValue(series.metric);
    var persistedCount = 0;
    var hasUnseen = false;
    for (final tier in series.tiers) {
      final tierState = doc.tierState(tier.id);
      if (tierState != null) {
        persistedCount++;
        if (!tierState.seen) hasUnseen = true;
      }
    }
    // Unlocked count cannot exceed tiers reached per the persisted ledger;
    // metrics may have dropped since unlock (streak), so persistedCount is
    // authoritative for completion display.
    return AchievementSeriesProgress(
      seriesId: series.id,
      currentProgress: value,
      completedTierCount: persistedCount,
      totalTierCount: series.tiers.length,
      nextTier: series.nextTierAfter(value),
      hasUnseenUnlock: hasUnseen,
    );
  }

  /// Resolved unlock info for feedback surfaces (banner / detail sheet).
  AchievementUnlockResult? unlockInfoFor(String tierId) {
    final tier = AchievementCatalog.tierById(tierId);
    final tierState = state.tierState(tierId);
    if (tier == null || tierState == null) return null;
    final series = AchievementCatalog.allSeries
        .where((s) => s.tiers.contains(tier))
        .firstOrNull;
    if (series == null) return null;
    return AchievementUnlockResult(
      seriesId: series.id,
      tierId: tierId,
      target: tier.target,
      gemReward: tier.gemReward,
      cosmeticRewardId: tier.cosmeticRewardId,
      unlockedAt: tierState.unlockedAt,
      origin: tierState.origin,
    );
  }

  // ── Lifecycle ──────────────────────────────────────────────────────

  /// Startup sequence: one-shot v1 migration -> reward recovery -> a light
  /// reconcile. Never throws into the caller; failures defer to next start.
  Future<void> initialize() async {
    try {
      await _migrationService.runIfNeeded();
    } catch (e) {
      logger.w('Achievement migration failed (will retry next start): $e');
    }
    await refreshSnapshot();
    await recoverPendingRewards();
    await evaluateAndReward();
  }

  /// Rebuild the metric snapshot from authoritative sources.
  Future<void> refreshSnapshot() async {
    _lastSnapshot = await _projector.buildSnapshot();
  }

  // ── Write API (single writer) ─────────────────────────────────────

  /// Evaluate every published series and persist + reward new unlocks.
  /// Returns the unlocks produced by this call (empty when idempotent).
  Future<List<AchievementUnlockResult>> evaluateAndReward() async {
    final results = <AchievementUnlockResult>[];
    await _enqueue((_) async {
      final snapshot = await _projector.buildSnapshot();
      _lastSnapshot = snapshot;
      final doc = await _stateRepository.read();
      final fresh = AchievementEvaluator.evaluate(
        seriesList: AchievementCatalog.publishedSeries,
        state: doc,
        snapshot: snapshot,
        origin: AchievementUnlockOrigin.live,
      );
      if (fresh.isEmpty) return;

      // Phase 1: persist unlocks with rewardGranted=false.
      final now = DateTime.now();
      final newStates = <String, AchievementTierState>{};
      for (final r in fresh) {
        newStates[r.tierId] = AchievementTierState(
          tierId: r.tierId,
          unlockedAt: now,
          rewardGranted: false,
          seen: false,
          origin: AchievementUnlockOrigin.live,
        );
      }
      await _stateRepository.mutate(
        (current) => current.copyWith(
          unlockedTiers: {...current.unlockedTiers, ...newStates},
          updatedAt: now,
        ),
      );

      // Phase 2: grant gems (single GemsProvider write), then mark granted.
      final gemTotal = fresh.fold<int>(0, (sum, r) => sum + r.gemReward);
      if (gemTotal > 0) {
        await _gemsProvider.addGems(gemTotal);
      }
      await _stateRepository.mutate(
        (current) => current.copyWith(
          unlockedTiers: {
            for (final e in current.unlockedTiers.entries)
              e.key: newStates.containsKey(e.key) && !e.value.rewardGranted
                  ? e.value.copyWith(
                      rewardGranted: true,
                      rewardGrantedAt: now,
                    )
                  : e.value,
          },
          updatedAt: now,
        ),
      );

      results.addAll(fresh);
      if (results.isNotEmpty) {
        logger.i('Achievement unlocked ${results.length} tier(s): '
            '${results.map((r) => r.tierId).join(', ')}');
      }
    });
    if (results.isNotEmpty) notifyListeners();
    return results;
  }

  /// Record a formal review session (per-card answers) then evaluate.
  Future<List<AchievementUnlockResult>> recordReviewSession({
    required int cardsAnswered,
  }) async {
    await _projector.applyReviewSessionDelta(cardsAnswered: cardsAnswered);
    return evaluateAndReward();
  }

  /// Fold studied word ids into the projection (vocabulary series data).
  Future<void> recordStudiedWords(Iterable<String> wordIds) =>
      _projector.applyStudiedWords(wordIds);

  /// Re-pay any unlock whose gem grant never landed (crash between the two
  /// phases). Idempotent: safe on every startup.
  Future<void> recoverPendingRewards() async {
    await _enqueue((_) async {
      final doc = await _stateRepository.read();
      final pending = doc.unlockedTiers.values
          .where((t) =>
              !t.rewardGranted &&
              t.origin == AchievementUnlockOrigin.live &&
              AchievementCatalog.tierById(t.tierId) != null)
          .toList(growable: false);
      if (pending.isEmpty) return;

      var gemTotal = 0;
      for (final t in pending) {
        gemTotal += AchievementCatalog.tierById(t.tierId)?.gemReward ?? 0;
      }
      if (gemTotal > 0) {
        await _gemsProvider.addGems(gemTotal);
      }
      final now = DateTime.now();
      await _stateRepository.mutate(
        (current) => current.copyWith(
          unlockedTiers: {
            for (final e in current.unlockedTiers.entries)
              e.key: !e.value.rewardGranted
                  ? e.value.copyWith(rewardGranted: true, rewardGrantedAt: now)
                  : e.value,
          },
          updatedAt: now,
        ),
      );
      logger.i('Achievement reward recovery paid $gemTotal gems for '
          '${pending.length} tier(s)');
    });
  }

  /// Consume the feedback queue for a completion-page banner: returns the
  /// unseen live unlocks and marks them seen. Loss-safe — seen is persisted
  /// per tier id.
  Future<List<AchievementUnlockResult>> takeFeedbackBatch({int max = 4}) async {
    final batch = unseenLiveUnlocks.take(max).toList(growable: false);
    if (batch.isEmpty) return const [];
    await markSeen(batch.map((t) => t.tierId).toSet());
    return [
      for (final t in batch)
        if (unlockInfoFor(t.tierId) != null) unlockInfoFor(t.tierId)!,
    ];
  }

  /// Mark tiers as seen (achievements page visit / banner shown).
  Future<void> markSeen(Set<String> tierIds) async {
    if (tierIds.isEmpty) return;
    final now = DateTime.now();
    await _stateRepository.mutate(
      (current) => current.copyWith(
        unlockedTiers: {
          for (final e in current.unlockedTiers.entries)
            e.key: tierIds.contains(e.key) && !e.value.seen
                ? e.value.copyWith(seen: true, seenAt: now)
                : e.value,
        },
        updatedAt: now,
      ),
    );
    notifyListeners();
  }

  /// Account reset: clear v2 state, projection, and the migration marker so
  /// a future migration would start clean. The v1 list is cleared by
  /// `GameProvider.resetAccountGameState`.
  Future<void> resetAll() async {
    await _stateRepository.clear();
    await _projector.reset();
    await _evaluateChain;
    _lastSnapshot = AchievementMetricSnapshot();
    notifyListeners();
  }

  /// Reload persisted state after an external restore (import / Fun Lab).
  Future<void> reloadFromPrefs() async {
    await _stateRepository.reloadFromPrefs();
    await _projector.reloadFromPrefs();
    await refreshSnapshot();
    notifyListeners();
  }

  /// Ensure the in-memory state is populated (first UI read before
  /// [initialize] completes).
  Future<void> ensureLoaded() async {
    await _stateRepository.read();
    if (_lastSnapshot.calculatedAt.millisecondsSinceEpoch == 0) {
      await refreshSnapshot();
    }
  }

  Future<void> _enqueue(Future<void> Function(void _) op) {
    _evaluateChain = _evaluateChain.then((v) => op(v)).catchError((Object e) {
      logger.w('Achievement evaluation failed (reconcile will compensate): $e');
    });
    return _evaluateChain;
  }
}
