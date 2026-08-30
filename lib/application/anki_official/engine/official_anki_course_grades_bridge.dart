import 'dart:async';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:flutter/foundation.dart' show debugPrint;

abstract class OfficialAnkiCourseGradesBridge {
  Future<bool> answerOfficialCard({
    required String wordId,
    required String rating,
    int millisecondsTaken = 0,
  });
}

class OfficialAnkiCourseGradesBridgeImpl
    implements OfficialAnkiCourseGradesBridge {
  const OfficialAnkiCourseGradesBridgeImpl({
    this.flags,
    this.onAnswer,
  });

  final OfficialAnkiFeatureFlags? flags;
  final Future<bool> Function(int cardId, String rating, int millisecondsTaken)?
      onAnswer;

  @override
  Future<bool> answerOfficialCard({
    required String wordId,
    required String rating,
    int millisecondsTaken = 0,
  }) async {
    final effectiveFlags = flags ?? OfficialAnkiFeatureFlags.current;
    if (!effectiveFlags.allowsCourseGradesScheduler) {
      return false;
    }
    if (!wordId.startsWith('official-anki-') ||
        wordId.startsWith('official-anki-link-')) {
      return false;
    }

    final cardIdMatch = RegExp(r'-c(\d+)$').firstMatch(wordId);
    if (cardIdMatch == null) return false;
    final cardId = int.tryParse(cardIdMatch.group(1) ?? '');
    if (cardId == null) return false;

    try {
      if (onAnswer != null) {
        return await onAnswer!(cardId, rating, millisecondsTaken);
      }
      return false;
    } catch (suppressed) {
      debugPrint('[OfficialAnkiCourseGradesBridge] [OfficialAnkiCourseGradesBridge] course-grades bridge suppressed: $suppressed');
      return false;
    }
  }
}
