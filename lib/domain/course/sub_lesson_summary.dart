// Dart imports:
import 'dart:convert';

// Package imports:
import 'package:freezed_annotation/freezed_annotation.dart';

// Project imports:
import 'package:turna/domain/course/sub_lesson.dart';

part 'sub_lesson_summary.freezed.dart';
part 'sub_lesson_summary.g.dart';

/// Lightweight L1 metadata for one sub-lesson of a [Lesson].
///
/// The course tree (L1) renders one node per sub-lesson, but deliberately
/// does not load lesson bodies: `Lesson.content.subLessons` stays empty on
/// the tree (a populated `content` would make
/// `LessonViewModel._lessonHasBody` treat L1 rows as playable and bypass
/// the L2 body load). This summary carries just enough — id, name, order —
/// for the tree to lay out and navigate to sub-lesson nodes. The full
/// [SubLesson] (with stages) only exists on the L2 body.
@freezed
abstract class SubLessonSummary with _$SubLessonSummary {
  const factory SubLessonSummary({
    required String id,

    /// Display title of the sub-lesson; becomes the tree node's label.
    required String name,

    /// Ordering index inside the parent lesson (list position at seed time).
    @Default(0) int sortOrder,
  }) = _SubLessonSummary;

  factory SubLessonSummary.fromJson(Map<String, dynamic> json) =>
      _$SubLessonSummaryFromJson(json);
}

/// Single encode/decode point for the `lessons.sub_lesson_summaries`
/// column, shared by every DB writer (seeder, AI course provider) and
/// reader (repository) so the wire shape never forks.
abstract final class SubLessonSummariesCodec {
  static const String _idKey = 'id';
  static const String _nameKey = 'name';
  static const String _sortOrderKey = 'sortOrder';

  /// Decode the stored column value. A corrupted blob degrades to an empty
  /// list (the tree falls back to a single lesson node) instead of failing
  /// the whole section load — same policy as `CourseRepository._toLesson`
  /// for corrupted content blobs.
  static List<SubLessonSummary> decode(String json) {
    if (json.trim().isEmpty) return const <SubLessonSummary>[];
    try {
      final decoded = jsonDecode(json);
      if (decoded is! List) return const <SubLessonSummary>[];
      return [
        for (final entry in decoded)
          if (entry is Map<String, dynamic>)
            SubLessonSummary(
              id: entry[_idKey] as String? ?? '',
              name: entry[_nameKey] as String? ?? '',
              sortOrder: entry[_sortOrderKey] as int? ?? 0,
            ),
      ]..removeWhere((s) => s.id.isEmpty);
    } catch (_) {
      return const <SubLessonSummary>[];
    }
  }

  static String encode(List<SubLessonSummary> summaries) => jsonEncode([
        for (final s in summaries)
          {
            _idKey: s.id,
            _nameKey: s.name,
            _sortOrderKey: s.sortOrder,
          },
      ]);

  /// Derive summaries from a parsed L2 body, in list order. `sortOrder` is
  /// the list position, so ordering stays deterministic even if a reader
  /// sorts by the column instead of the array.
  static List<SubLessonSummary> fromSubLessons(List<SubLesson> subs) => [
        for (var i = 0; i < subs.length; i++)
          SubLessonSummary(id: subs[i].id, name: subs[i].name, sortOrder: i),
      ];

  /// Encode the column value straight from a stored `content_json` blob.
  /// The one-time v34 migration backfill path: rather than materializing
  /// full [SubLesson]s, pull `id` / `name` off the raw map. Any parse
  /// failure yields `'[]'` (single-node fallback), never a migration crash.
  static String encodeFromContentJson(String contentJson) {
    try {
      final decoded = jsonDecode(contentJson);
      if (decoded is! Map<String, dynamic>) return '[]';
      final subs = decoded['subLessons'];
      if (subs is! List) return '[]';
      return jsonEncode([
        for (var i = 0; i < subs.length; i++)
          if (subs[i] is Map<String, dynamic>)
            {
              _idKey: (subs[i] as Map<String, dynamic>)[_idKey] ?? '',
              _nameKey: (subs[i] as Map<String, dynamic>)[_nameKey] ?? '',
              _sortOrderKey: i,
            },
      ].where((entry) => (entry[_idKey] as String).isNotEmpty).toList());
    } catch (_) {
      return '[]';
    }
  }
}
