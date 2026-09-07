import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:turna/application/achievements/achievement_service.dart';
import 'package:turna/application/game_provider.dart';
import 'package:turna/application/gems_provider.dart';
import 'package:turna/application/study_stats_provider.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/study/study_log.dart';

/// Which review surface is settling; also the gem-ledger idempotency
/// prefix via [GemRewardEventIds.reviewSession] (`earn:<kind>Session:…`).
enum SessionSettlementSource { srs, anki }

/// Single settlement path for one completed review session: XP, gems,
/// study log, achievements — in that order.
///
/// Every review page (unified SRS review, official Anki review) must
/// settle through this service. The two hand-rolled copies it replaced had
/// drifted apart (XP fallback, gem kind / session sequence, error
/// handling) and wrote different semantics into the same pipelines.
///
/// Contract:
/// - Call exactly once per completed session; the caller owns the
///   once-guard. [settle] itself is safe to call with zero answered
///   cards (no-ops, writes nothing).
/// - [sessionSequence] scopes the gem reward's idempotency key: one page
///   instance = one sequence = one reward, so two sessions on the same
///   day both earn (the ledger dedups a repeated settle of the SAME
///   sequence).
/// - Settlement failures are logged, never thrown: the completion screen
///   must always finish, even when a writer is missing or fails.
class SessionSettlementService {
  SessionSettlementService({
    this.game,
    this.gems,
    this.study,
    this.achievements,
  });

  /// Resolves the production collaborators. Absent providers (tests,
  /// partial trees) simply skip their write.
  factory SessionSettlementService.fromContext(BuildContext context) {
    return SessionSettlementService(
      game: context.read<GameProvider?>(),
      gems: context.read<GemsProvider?>(),
      study: context.read<StudyStatsProvider?>(),
      achievements: getIt.isRegistered<AchievementService>()
          ? getIt<AchievementService>()
          : null,
    );
  }

  final GameProvider? game;
  final GemsProvider? gems;
  final StudyStatsProvider? study;
  final AchievementService? achievements;

  /// XP kept when [GameProvider] is unavailable. Performance-based so a
  /// degraded settle still reflects the session instead of a flat value.
  static int fallbackXp({required int remembered, required int forgotten}) =>
      remembered * 10 + forgotten * 2;

  /// Settles one session and returns the XP earned (fallback formula when
  /// no game writer is available, 0 for an empty session).
  Future<int> settle({
    required SessionSettlementSource source,
    required String sessionSequence,
    required int remembered,
    required int forgotten,
    required Duration elapsed,
  }) async {
    final total = remembered + forgotten;
    if (total == 0) return 0;

    var xp = fallbackXp(remembered: remembered, forgotten: forgotten);
    try {
      final game = this.game;
      if (game != null) {
        final awarded = await game.awardXP(
          XPEvent.srsReviewSession,
          multiplier: total.toDouble(),
        );
        if (awarded > 0) xp = awarded;
      }
      await gems?.earnGems(
        GemEvent.srsReviewSession,
        eventId: GemRewardEventIds.reviewSession(
          kind: switch (source) {
            SessionSettlementSource.srs => 'srs',
            SessionSettlementSource.anki => 'anki',
          },
          completedAt: DateTime.now(),
          sessionSequence: sessionSequence,
        ),
      );
      await study?.recordActivity(
        type: StudyActivityType.srsReview,
        xpEarned: xp,
        durationSeconds: elapsed.inSeconds,
        correctCount: remembered,
        incorrectCount: forgotten,
      );
      // Achievement evaluation after every authoritative write above; the
      // per-session delta feeds the durable totalReviewedCards projection.
      await achievements?.recordReviewSession(cardsAnswered: total);
    } catch (e) {
      debugPrint('[SessionSettlement] settlement failed: $e');
    }
    return xp;
  }
}
