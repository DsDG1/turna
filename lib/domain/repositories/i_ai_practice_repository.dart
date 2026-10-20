// Project imports:
import 'package:turna/domain/ai/ai_course.dart';

/// Persistence contract for the AI course library.
///
/// The library lives in its own tables (`ai_courses` + `ai_course_versions`),
/// not in the course tree: generated drafts must survive a bundled-content
/// reseed (`DatabaseSeeder` clears the language course tables on version
/// bumps), and they must not show up in the Learn tab until the learner
/// explicitly asks for them. The collection/version split is ADR 0054.
abstract class IAiPracticeRepository {
  /// Newest-first courses with their versions, optionally scoped to one
  /// language.
  Future<List<AiCourse>> list({String? languageCode, int? limit});

  Future<AiCourse?> byId(String id);

  /// Insert or replace the collection row (identity, favourite, expiry).
  Future<void> upsertCourse(AiCourse course);

  /// Insert or replace one generation attempt.
  Future<void> upsertVersion(AiCourseVersion version);

  /// Delete the given courses together with all of their versions. Unknown ids
  /// are ignored.
  Future<void> deleteMany(Iterable<String> ids);

  /// Favourite ("收藏") or un-favourite courses.
  ///
  /// Favouriting clears the expiry deadline (permanent); un-favouriting sets a
  /// fresh [kAiCourseDraftTtl] deadline from [now] so the draft never expires
  /// the instant it is un-favourited.
  Future<void> setPinned(
    Iterable<String> ids, {
    required bool pinned,
    DateTime? now,
  });

  /// Startup sweep: every version still queued/running belongs to a dead
  /// process. Rewrites them to [AiPracticeStatus.interrupted] with a
  /// user-facing reason and returns how many rows were changed.
  Future<int> markInterruptedOnStartup();

  /// Delete every un-favourited course whose deadline has passed, with its
  /// versions. Returns how many courses were removed.
  Future<int> pruneExpired({required DateTime now});
}
