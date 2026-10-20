// Lifecycle of one AI generation attempt.
//
// A version is created as [queued], flipped to [running] while the generator is
// working, and lands in exactly one terminal state. [interrupted] is written on
// the next app launch for rows that were still queued/running when the process
// died — an in-process background job cannot survive that.
enum AiPracticeStatus {
  queued,
  running,
  ready,
  failed,
  interrupted;

  bool get isTerminal =>
      this == AiPracticeStatus.ready ||
      this == AiPracticeStatus.failed ||
      this == AiPracticeStatus.interrupted;

  bool get isBusy =>
      this == AiPracticeStatus.queued || this == AiPracticeStatus.running;

  /// Parse a persisted wire name; unknown values degrade to [failed] so a
  /// renamed enum can never leave a row stuck "running" forever.
  static AiPracticeStatus fromWire(String? value) {
    for (final status in AiPracticeStatus.values) {
      if (status.name == value) return status;
    }
    return AiPracticeStatus.failed;
  }
}

/// Where the generation prompt got its target material from.
enum AiPracticeSource {
  mistakes,
  weakWords,
  difficult,
  custom;

  static AiPracticeSource fromWire(String? value) {
    for (final source in AiPracticeSource.values) {
      if (source.name == value) return source;
    }
    return AiPracticeSource.custom;
  }
}

/// How long a draft lives before the automatic sweep deletes it.
///
/// Counted from the course's creation time (not from last use): the promise is
/// "AI 生成的课程一周后自动过期，可收藏永久保存" — a rolling clock would make
/// the promise untestable for the learner. Favouriting clears the deadline.
const Duration kAiCourseDraftTtl = Duration(days: 7);

/// One generation attempt of a course.
///
/// Kept as its own row (table `ai_course_versions`) so a re-generation appends a
/// version instead of overwriting the previous content: the library can show
/// "第 3 版" and fall back to an older version when a re-generation fails.
class AiCourseVersion {
  const AiCourseVersion({
    required this.id,
    required this.courseId,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.sectionJson,
    this.requestJson = '{}',
    this.qualityJson,
    this.progressDone = 0,
    this.progressTotal = 0,
    this.errorMessage,
    this.explanation,
  });

  final String id;
  final String courseId;
  final AiPracticeStatus status;

  /// Canonical section JSON from `docs/authoring/course-layout.md`; null until
  /// the generator completes.
  final String? sectionJson;

  /// Generation spec snapshot used by retry after failure / interruption.
  final String requestJson;

  /// Machine-readable verification report (blocking + advisory findings) from
  /// [AiPracticeQualityReport.toJson]; null for versions produced before the
  /// gate existed.
  final String? qualityJson;

  final int progressDone;
  final int progressTotal;
  final String? errorMessage;
  final String? explanation;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get hasSection => sectionJson != null && sectionJson!.trim().isNotEmpty;

  bool get isPlayable => status == AiPracticeStatus.ready && hasSection;

  /// 0..1 progress for the job banner; 0 when the total is unknown.
  double get progress {
    if (progressTotal <= 0) return 0;
    return (progressDone / progressTotal).clamp(0.0, 1.0);
  }

  AiCourseVersion copyWith({
    String? id,
    String? courseId,
    AiPracticeStatus? status,
    String? sectionJson,
    String? requestJson,
    String? qualityJson,
    int? progressDone,
    int? progressTotal,
    String? errorMessage,
    String? explanation,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AiCourseVersion(
      id: id ?? this.id,
      courseId: courseId ?? this.courseId,
      status: status ?? this.status,
      sectionJson: sectionJson ?? this.sectionJson,
      requestJson: requestJson ?? this.requestJson,
      qualityJson: qualityJson ?? this.qualityJson,
      progressDone: progressDone ?? this.progressDone,
      progressTotal: progressTotal ?? this.progressTotal,
      errorMessage: errorMessage ?? this.errorMessage,
      explanation: explanation ?? this.explanation,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// One AI-generated course in the library — the *collection*, not a single
/// generation result.
///
/// The two-table split (`ai_courses` + `ai_course_versions`) is what makes the
/// library feel like a course shelf instead of a task log: the collection owns
/// identity (title, language, topic, favourite, expiry) and stays put when a
/// version is regenerated; the version owns one immutable generation attempt
/// (status, section JSON, verification report, progress).
///
/// Generated content is deliberately **not** written into `sections` / `units` /
/// `lessons`: `DatabaseSeeder` clears those tables when the bundled content
/// version changes, and the Learn tab must not start listing AI drafts.
class AiCourse {
  const AiCourse({
    required this.id,
    required this.languageCode,
    required this.title,
    required this.source,
    required this.createdAt,
    required this.updatedAt,
    this.level = 'A1',
    this.topic = '',
    this.pinned = false,
    this.expiresAt,
    this.versions = const <AiCourseVersion>[],
  });

  final String id;
  final String languageCode;
  final String title;
  final AiPracticeSource source;

  /// CEFR-ish level the course was generated for (`A1`..`C1`).
  final String level;

  /// Free-form topic from the request spec; the section tree shows it as the
  /// course description.
  final String topic;

  /// Favourited: permanent, never swept by the expiry job.
  final bool pinned;

  /// When the draft is deleted; null means permanent (favourited).
  final DateTime? expiresAt;

  /// Every generation attempt, newest first.
  final List<AiCourseVersion> versions;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// Newest version, or null when the course was never generated.
  AiCourseVersion? get latestVersion =>
      versions.isEmpty ? null : versions.first;

  /// The version a learner would open: newest playable one. A failed
  /// re-generation must not hide the previous working content.
  AiCourseVersion? get playableVersion {
    for (final version in versions) {
      if (version.isPlayable) return version;
    }
    return null;
  }

  AiPracticeStatus get status =>
      latestVersion?.status ?? AiPracticeStatus.queued;

  bool get isPlayable => playableVersion != null;

  bool get isBusy => versions.any((version) => version.status.isBusy);

  bool get isFailed =>
      latestVersion != null &&
      (latestVersion!.status == AiPracticeStatus.failed ||
          latestVersion!.status == AiPracticeStatus.interrupted) &&
      !isPlayable;

  // ── Card-facing conveniences ─────────────────────────────────────────────
  // The library card and the job banner render one line per course; routing
  // them through the newest/playable version here keeps that mapping in one
  // place instead of scattering `latestVersion?` across the widget tree.

  String? get errorMessage => latestVersion?.errorMessage;

  String? get explanation => playableVersion?.explanation;

  String? get sectionJson => playableVersion?.sectionJson;

  String? get qualityJson => latestVersion?.qualityJson;

  /// Spec snapshot of the newest version (used by retry).
  String get requestJson => latestVersion?.requestJson ?? '{}';

  int get progressDone => latestVersion?.progressDone ?? 0;

  int get progressTotal => latestVersion?.progressTotal ?? 0;

  double get progress => latestVersion?.progress ?? 0;

  /// Whole-days left before expiry, rounding up so "6h left" reads as 1 day.
  /// Null when permanent.
  int? daysLeft(DateTime now) {
    final deadline = expiresAt;
    if (deadline == null) return null;
    final left = deadline.difference(now);
    if (left.isNegative) return 0;
    return (left.inHours / 24).ceil();
  }

  bool isExpiringSoon(DateTime now) {
    final days = daysLeft(now);
    return days != null && days <= 2;
  }

  bool isExpired(DateTime now) {
    final deadline = expiresAt;
    return deadline != null && !deadline.isAfter(now);
  }

  AiCourse copyWith({
    String? id,
    String? languageCode,
    String? title,
    AiPracticeSource? source,
    String? level,
    String? topic,
    bool? pinned,
    DateTime? expiresAt,
    bool clearExpiry = false,
    List<AiCourseVersion>? versions,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AiCourse(
      id: id ?? this.id,
      languageCode: languageCode ?? this.languageCode,
      title: title ?? this.title,
      source: source ?? this.source,
      level: level ?? this.level,
      topic: topic ?? this.topic,
      pinned: pinned ?? this.pinned,
      expiresAt: clearExpiry ? null : (expiresAt ?? this.expiresAt),
      versions: versions ?? this.versions,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
