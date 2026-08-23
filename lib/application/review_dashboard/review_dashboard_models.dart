/// Stable identity of a learning source (Plan 3 §16.2).
///
/// `kind` distinguishes built-in course decks, grammar, legacy Anki imports
/// (cards introduced into the SRS state with `anki-<importId>-c…` word ids)
/// and official-Anki decks. Identity is captured at aggregation time from the
/// owning store — never re-parsed from card-id strings by consumers.
enum LearningSourceKind { course, grammar, ankiLegacy, ankiOfficial }

class LearningSourceRef {
  const LearningSourceRef({
    required this.kind,
    required this.sourceId,
    required this.displayName,
    this.ownerId,
    this.active = true,
  });

  final LearningSourceKind kind;

  /// Stable id: 'course' | 'grammar' | anki importId | official deck id.
  final String sourceId;
  final String displayName;
  final String? ownerId;
  final bool active;

  String get label => displayName;
}

/// Today's headline numbers. `todayXp`/`xpGoal` come from the study daily
/// stats and the user's configured goal; goal fields are null when unset.
class TodayProgress {
  const TodayProgress({
    required this.reviewedToday,
    required this.correctToday,
    required this.completedCards,
    this.todayXp,
    this.xpGoal,
  });

  final int reviewedToday;
  final int correctToday;

  /// Distinct cards answered today.
  final int completedCards;
  final int? todayXp;
  final int? xpGoal;

  bool get hasGoal => xpGoal != null && xpGoal! > 0;
}

class DueSummary {
  const DueSummary({
    required this.due,
    required this.newCards,
    required this.overdue,
  });

  /// Cards with dueAt <= now that were introduced before (relearning+review).
  final int due;

  /// Cards never reviewed (reps == 0).
  final int newCards;

  /// Cards whose dueAt is before the start of the local day.
  final int overdue;

  int get actionableTotal => due + newCards;
}

class StreakSummary {
  const StreakSummary({
    required this.currentStreakDays,
    required this.activeDaysThisWeek,
    this.protectedByVoucher = false,
  });

  final int currentStreakDays;
  final int activeDaysThisWeek;

  /// True when the displayed streak includes a 保护券 day (never fabricated
  /// study logs — display-only protection per Plan 2 §8.5).
  final bool protectedByVoucher;
}

/// One aggregated day point for the light 7-day chart. Bounded data: the
/// dashboard only ever loads seven of these, not the full history.
class DailyActivityPoint {
  const DailyActivityPoint({
    required this.localDay,
    required this.reviewedCount,
    required this.activeMinutes,
  });

  /// Local calendar day (midnight, device timezone).
  final DateTime localDay;
  final int reviewedCount;
  final int activeMinutes;
}

class StudyQuality {
  const StudyQuality({
    required this.studyMinutes,
    this.firstAnswerAccuracy,
    this.accuracySampleSize = 0,
  });

  final int studyMinutes;

  /// Null when no answers today — the UI must show 暂无数据, never 0%/100%
  /// (Plan 3 §14.5).
  final double? firstAnswerAccuracy;
  final int accuracySampleSize;
}

class ReviewSourceSummary {
  const ReviewSourceSummary({
    required this.source,
    required this.dueToday,
    required this.totalCards,
  });

  final LearningSourceRef source;
  final int dueToday;
  final int totalCards;
}

/// The single consistent snapshot the dashboard home subscribes to
/// (Plan 3 §16.1). One load = one data revision; no per-section futures.
class ReviewDashboardSnapshot {
  const ReviewDashboardSnapshot({
    required this.generatedAt,
    required this.dataRevision,
    required this.today,
    required this.due,
    required this.streak,
    required this.last7Days,
    required this.todayQuality,
    required this.sources,
    this.isStale = false,
  });

  final DateTime generatedAt;
  final int dataRevision;
  final TodayProgress today;
  final DueSummary due;
  final StreakSummary streak;
  final List<DailyActivityPoint> last7Days;
  final StudyQuality todayQuality;

  /// Sources ordered by dueToday desc then displayName; the UI shows the
  /// first few plus a "全部" rollup row is NOT included (course/grammar/anki
  /// each get their own row).
  final List<ReviewSourceSummary> sources;
  final bool isStale;
}
