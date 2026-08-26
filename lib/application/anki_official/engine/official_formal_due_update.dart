import 'package:flutter/foundation.dart';
import 'package:turna/application/anki_official/engine/official_formal_due_repository.dart';

/// The complete formal-due write model for ONE logical refresh (plan
/// maintainability Wave 1). A single [OfficialFormalDueUpdate] carries every
/// collection of every source; committing it bumps the snapshot generation
/// exactly once and notifies listeners exactly once.
///
/// Builders MUST populate every field they know about. A missing source key
/// means "this source has no data", not "keep the previous value" — the only
/// way to preserve previous values is a repository mutation
/// ([OfficialFormalDueRepository.mutateSource]) which still commits a full
/// snapshot.
@immutable
class OfficialFormalDueUpdate {
  const OfficialFormalDueUpdate({
    required this.bySource,
    required this.rawDueBySource,
    required this.turnaDue,
    required this.unintroducedNew,
    this.unavailable = false,
    this.error,
  });

  /// Per-source six-set state. Sources absent from this map disappear from
  /// the next snapshot — an intentional full refresh replaces everything.
  final Map<String, OfficialFormalDuePerSource> bySource;

  /// Scheduler counts as reported by the engine (pre-eligibility).
  final Map<String, int> rawDueBySource;

  /// Turna-side (Legacy SRS) due total, if this refresh also collected it.
  final int turnaDue;

  final int unintroducedNew;

  /// True when collection failed; the previous snapshot's sets stay visible.
  final bool unavailable;

  final Object? error;
}
