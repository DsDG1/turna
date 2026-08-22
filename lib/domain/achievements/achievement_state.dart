// Dart imports:
import 'dart:convert';

import 'package:turna/domain/achievements/achievement_definition.dart';

/// How a tier unlock entered the state document.
enum AchievementUnlockOrigin {
  /// Real-time unlock from a formal learning event. Pays gem rewards.
  live,

  /// One-time v1 -> v2 migration backfill. Never pays gems, never pops up.
  migration,

  /// Fun Lab preview placeholder — never persisted as real state.
  funPreview;

  String get serializedName => name;

  static AchievementUnlockOrigin fromSerialized(String value) =>
      AchievementUnlockOrigin.values.firstWhere(
        (o) => o.name == value,
        orElse: () => AchievementUnlockOrigin.live,
      );
}

/// Persisted per-tier unlock record. Once written, a record is never removed
/// by metric drops — only an explicit account reset clears the document.
class AchievementTierState {
  final String tierId;
  final DateTime unlockedAt;

  /// Two-phase reward: the unlock is persisted with `rewardGranted=false`
  /// first; the startup recovery re-pays any unlock whose grant never landed.
  final bool rewardGranted;
  final DateTime? rewardGrantedAt;

  /// Whether the user has seen the unlock surface (completion-page banner or
  /// achievements page). Migration backfills are born seen.
  final bool seen;
  final DateTime? seenAt;
  final AchievementUnlockOrigin origin;

  const AchievementTierState({
    required this.tierId,
    required this.unlockedAt,
    this.rewardGranted = false,
    this.rewardGrantedAt,
    this.seen = false,
    this.seenAt,
    this.origin = AchievementUnlockOrigin.live,
  });

  AchievementTierState copyWith({
    bool? rewardGranted,
    DateTime? rewardGrantedAt,
    bool? seen,
    DateTime? seenAt,
  }) =>
      AchievementTierState(
        tierId: tierId,
        unlockedAt: unlockedAt,
        rewardGranted: rewardGranted ?? this.rewardGranted,
        rewardGrantedAt: rewardGrantedAt ?? this.rewardGrantedAt,
        seen: seen ?? this.seen,
        seenAt: seenAt ?? this.seenAt,
        origin: origin,
      );

  Map<String, dynamic> toJson() => {
        'tierId': tierId,
        'unlockedAt': unlockedAt.toIso8601String(),
        'rewardGranted': rewardGranted,
        'rewardGrantedAt': rewardGrantedAt?.toIso8601String(),
        'seen': seen,
        'seenAt': seenAt?.toIso8601String(),
        'origin': origin.serializedName,
      };

  static AchievementTierState fromJson(Map<String, dynamic> json) =>
      AchievementTierState(
        tierId: json['tierId'] as String,
        unlockedAt: DateTime.parse(json['unlockedAt'] as String),
        rewardGranted: (json['rewardGranted'] as bool?) ?? false,
        rewardGrantedAt: json['rewardGrantedAt'] == null
            ? null
            : DateTime.parse(json['rewardGrantedAt'] as String),
        seen: (json['seen'] as bool?) ?? false,
        seenAt: json['seenAt'] == null
            ? null
            : DateTime.parse(json['seenAt'] as String),
        origin: AchievementUnlockOrigin.fromSerialized(
          (json['origin'] as String?) ?? 'live',
        ),
      );
}

/// Versioned v2 achievement state document, persisted as JSON at
/// `achievements.state.v2`.
class AchievementStateDocument {
  static const int currentSchemaVersion = 2;

  final int schemaVersion;
  final Map<String, AchievementTierState> unlockedTiers;
  final DateTime updatedAt;

  /// Unknown v1 ids and legacy counters that could not be mapped losslessly.
  /// Diagnostics only — never blocks startup.
  final List<String> migrationDiagnostics;

  AchievementStateDocument({
    this.schemaVersion = currentSchemaVersion,
    this.unlockedTiers = const {},
    DateTime? updatedAt,
    this.migrationDiagnostics = const [],
  }) : updatedAt = updatedAt ?? _epoch;

  static final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(0);

  AchievementStateDocument copyWith({
    Map<String, AchievementTierState>? unlockedTiers,
    DateTime? updatedAt,
    List<String>? migrationDiagnostics,
  }) =>
      AchievementStateDocument(
        schemaVersion: schemaVersion,
        unlockedTiers: unlockedTiers ?? this.unlockedTiers,
        updatedAt: updatedAt ?? this.updatedAt,
        migrationDiagnostics: migrationDiagnostics ?? this.migrationDiagnostics,
      );

  AchievementTierState? tierState(String tierId) => unlockedTiers[tierId];

  bool isUnlocked(String tierId) => unlockedTiers.containsKey(tierId);

  String encode() => jsonEncode(toJson());

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'unlockedTiers': {
          for (final e in unlockedTiers.entries) e.key: e.value.toJson(),
        },
        'updatedAt': updatedAt.toIso8601String(),
        'migrationDiagnostics': migrationDiagnostics,
      };

  static AchievementStateDocument fromJson(Map<String, dynamic> json) =>
      AchievementStateDocument(
        schemaVersion: (json['schemaVersion'] as num?)?.toInt() ??
            currentSchemaVersion,
        unlockedTiers: {
          for (final entry in ((json['unlockedTiers'] as Map?)
                      ?.cast<String, dynamic>() ??
                  const <String, dynamic>{})
              .entries)
            entry.key: AchievementTierState.fromJson(
              entry.value as Map<String, dynamic>,
            ),
        },
        updatedAt: json['updatedAt'] == null
            ? null
            : DateTime.parse(json['updatedAt'] as String),
        migrationDiagnostics: ((json['migrationDiagnostics'] as List?)
                ?.map((e) => e.toString()) ??
            const [])
            .toList(growable: false),
      );

  /// Corrupt / empty payload fallback.
  static AchievementStateDocument get empty => AchievementStateDocument();
}

/// Read-only projection consumed by UI. The UI never derives "unlocked" from
/// raw counters — it reads this view, which combines the catalog, the
/// persisted state document, and the current metric snapshot.
class AchievementSeriesProgress {
  final String seriesId;

  /// Live metric value (may drop below already-unlocked targets, e.g. streak).
  final int currentProgress;

  /// Tiers whose target has been reached AND is persisted in the state
  /// document. 0..totalTierCount — a fresh account is 0, not 1.
  final int completedTierCount;
  final int totalTierCount;

  /// Definition of the first tier whose target exceeds [currentProgress];
  /// null when the series is complete.
  final AchievementTierDefinition? nextTier;

  /// Any persisted tier of this series the user has not seen yet.
  final bool hasUnseenUnlock;

  const AchievementSeriesProgress({
    required this.seriesId,
    required this.currentProgress,
    required this.completedTierCount,
    required this.totalTierCount,
    required this.nextTier,
    required this.hasUnseenUnlock,
  });

  bool get isSeriesComplete => completedTierCount >= totalTierCount;

  bool get hasAnyUnlock => completedTierCount > 0;
}
