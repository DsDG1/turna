import 'package:flutter/foundation.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_store.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/course/interaction.dart';

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
  static Future<OfficialAnkiLessonCardIndex?> resolveForLesson(
    String lessonId,
  ) async {
    final resolver = debugResolver;
    if (resolver != null) return resolver(lessonId);
    if (!getIt.isRegistered<CourseDatabase>()) return null;
    try {
      final rows = await OfficialAnkiCourseProjectionStore(
        getIt<CourseDatabase>(),
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