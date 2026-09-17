import 'package:flutter/widgets.dart';
import 'package:turna/application/study_session/session_settlement_service.dart';

/// Settlement coordinator for Anki review sessions.
///
/// Encapsulates XP and gem reward settlement:
/// - Guarantees exactly-once execution per review session.
/// - Scopes the gem reward idempotency key via [sessionSequence].
/// - Tracks elapsed session time and earned XP.
class AnkiReviewSessionSettlement {
  AnkiReviewSessionSettlement({
    String? sessionSequence,
    DateTime? startedAt,
  })  : sessionSequence =
            sessionSequence ?? DateTime.now().microsecondsSinceEpoch.toString(),
        startedAt = startedAt ?? DateTime.now();

  /// Scopes the settlement gem reward's idempotency key so every completed
  /// session earns exactly once.
  final String sessionSequence;

  /// The timestamp when this review session was initialized.
  final DateTime startedAt;

  bool _isRecorded = false;
  int _earnedXp = 0;

  /// Whether settlement has already run for this session.
  bool get isRecorded => _isRecorded;

  /// The XP awarded by the settlement service, or 0 if not yet settled.
  int get earnedXp => _earnedXp;

  /// Settles the session with the user's progress.
  ///
  /// Returns the earned XP (or current XP if already recorded or total is 0).
  Future<int> recordCompletion({
    required BuildContext context,
    required int total,
    required int remembered,
    required int forgotten,
    Duration? elapsed,
    SessionSettlementService? service,
  }) async {
    if (total <= 0 || _isRecorded) return _earnedXp;
    _isRecorded = true;
    final settlementService =
        service ?? SessionSettlementService.fromContext(context);
    final sessionElapsed = elapsed ?? DateTime.now().difference(startedAt);
    final xp = await settlementService.settle(
      source: SessionSettlementSource.anki,
      sessionSequence: sessionSequence,
      remembered: remembered,
      forgotten: forgotten,
      elapsed: sessionElapsed,
    );
    _earnedXp = xp;
    return xp;
  }
}
