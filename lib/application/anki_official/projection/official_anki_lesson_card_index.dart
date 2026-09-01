import 'package:flutter/foundation.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_store.dart';
import 'package:turna/application/anki_official/v2/official_anki_v2_course_read.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/course/interaction.dart';

/// v2 视图解析的中间载体（word/card/source 三元组）。
class _V2CardEntry {
  const _V2CardEntry({
    required this.wordId,
    required this.cardId,
    required this.sourceId,
  });

  final String wordId;
  final int cardId;
  final String sourceId;
}

/// One word of one Official card as the projection index recorded it.
class OfficialAnkiLessonCardEntry {
  const OfficialAnkiLessonCardEntry({
    required this.wordId,
    required this.cardId,
  });

  final String wordId;
  final int cardId;
}

/// P0 single source for "which Official cards belong to one course lesson".
///
/// Backed by the `official_anki_projection_index` rows the projection publish
/// wrote: `cardId`, `wordId` and `sourceId` are structured columns there, so
/// consumers (lesson-complete unlock, redo flush, new-card quota) resolve
/// cards without guessing identities out of interaction-id strings. Lessons
/// without rows — legacy imported courses, synthetic lessons — resolve to
/// `null` and keep their own behavior.
class OfficialAnkiLessonCardIndex {
  OfficialAnkiLessonCardIndex({
    required this.lessonId,
    required this.sourceId,
    required List<OfficialAnkiLessonCardEntry> entries,
  }) : entries = List.unmodifiable(_distinctByCardId(entries)) {
    _cardIdByWordId = {
      for (final entry in this.entries) entry.wordId: entry.cardId,
    };
  }

  final String lessonId;
  final String sourceId;
  final List<OfficialAnkiLessonCardEntry> entries;

  /// One projection kind per row means several rows can share a wordId;
  /// official card ids are millisecond timestamps so they are unique per
  /// source, and the projection store reads them in stable card-id order.
  static List<OfficialAnkiLessonCardEntry> _distinctByCardId(
    List<OfficialAnkiLessonCardEntry> entries,
  ) {
    final seen = <int>{};
    return [
      for (final entry in entries)
        if (seen.add(entry.cardId)) entry,
    ];
  }

  late final Map<String, int> _cardIdByWordId;

  /// Test seam. Production resolves through the projection store.
  static Future<OfficialAnkiLessonCardIndex?> Function(String lessonId)?
      debugResolver;

  /// Resolves the index for [lessonId], or `null` when this database never
  /// projected that lesson. Fail-closed: an unreadable index must not
  /// degrade into id-string guessing — the lesson's Official cards simply
  /// stay unresolved.
  ///
  /// v2 分叉（B6）：v2 视图供该课时 → 从 `anki_course_tree_view` 解析
  /// （wordId/cardId 都是视图结构列）；否则回落 v1 投影 index——两代
  /// 数据并存，读路径兼容（回退语义：v2 已导入的来源继续可学）。
  static Future<OfficialAnkiLessonCardIndex?> resolveForLesson(
    String lessonId,
  ) async {
    final resolver = debugResolver;
    if (resolver != null) return resolver(lessonId);
    if (!getIt.isRegistered<CourseDatabase>()) return null;
    try {
      final course = getIt<CourseDatabase>();
      final v2Entries = await _resolveV2Entries(course, lessonId);
      if (v2Entries != null) {
        if (v2Entries.isEmpty) return null;
        return OfficialAnkiLessonCardIndex(
          lessonId: lessonId,
          sourceId: v2Entries.first.sourceId,
          entries: [
            for (final entry in v2Entries)
              OfficialAnkiLessonCardEntry(
                wordId: entry.wordId,
                cardId: entry.cardId,
              ),
          ],
        );
      }
      final rows = await OfficialAnkiCourseProjectionStore(
        course,
      ).indexRowsForLesson(lessonId);
      if (rows.isEmpty) return null;
      return OfficialAnkiLessonCardIndex(
        lessonId: lessonId,
        sourceId: rows.first.sourceId,
        entries: [
          for (final row in rows)
            OfficialAnkiLessonCardEntry(
              wordId: row.wordId,
              cardId: row.cardId,
            ),
        ],
      );
    } catch (error) {
      debugPrint('OfficialAnkiLessonCardIndex resolve failed: $error');
      return null;
    }
  }

  /// v2 视图命中时返回课时条目；视图无此课时（v1 数据或 flag 关）返回
  /// null 走 v1 面。fail-closed：视图读失败按「非 v2 课时」处理。
  static Future<List<_V2CardEntry>?> _resolveV2Entries(
    CourseDatabase course,
    String lessonId,
  ) async {
    try {
      final catalog = OfficialAnkiCompositionRoot.readOnlyCatalog;
      if (catalog == null) return null;
      final read = OfficialAnkiV2CourseRead(catalog: catalog, course: course);
      if (!await read.isV2Lesson(lessonId)) return null;
      final entries = await read.lessonCardEntriesForLesson(lessonId);
      return [
        for (final entry in entries)
          _V2CardEntry(
            wordId: entry.wordId,
            cardId: entry.cardId,
            sourceId: entry.sourceId,
          ),
      ];
    } catch (_) {
      return null;
    }
  }

  /// Card ids of this lesson in stable card-id order.
  List<int> get cardIds => [for (final entry in entries) entry.cardId];

  /// Resolves the projection card behind a lesson interaction. Projector
  /// item ids are minted as `'$wordId-p{kind}-$ordinal'`
  /// ([officialAnkiItemId]), so a row matches when the interaction id is the
  /// wordId itself or starts with `'$wordId-'`; ShowWord items also carry
  /// the bare wordId.
  int? cardIdForInteraction(Interaction interaction) {
    if (interaction is ShowWord && interaction.wordId.isNotEmpty) {
      final byWord = _cardIdByWordId[interaction.wordId];
      if (byWord != null) return byWord;
    }
    return cardIdForInteractionId(interaction.id);
  }

  int? cardIdForInteractionId(String interactionId) {
    final exact = _cardIdByWordId[interactionId];
    if (exact != null) return exact;
    for (final entry in entries) {
      if (interactionId.startsWith('${entry.wordId}-')) return entry.cardId;
    }
    return null;
  }
}