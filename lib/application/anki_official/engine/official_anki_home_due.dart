import 'package:turna/application/anki/anki_review_assembler.dart';
import 'package:turna/domain/course/srs_word.dart';

/// Dual-source home due. Never merge Official and Turna stores into one writer.
class OfficialAnkiHomeDue {
  OfficialAnkiHomeDue._();

  static var officialDue = 0;
  static var turnaDue = 0;
  static Set<String> officialImportIds = {};
  static Map<String, int> officialDueByImport = {};
  static bool officialDueUnavailable = false;

  static void reset() {
    officialDue = 0;
    turnaDue = 0;
    officialImportIds = {};
    officialDueByImport = {};
    officialDueUnavailable = false;
  }

  static int legacyAnkiDueExcludingOfficial(Iterable<SrsWord> dueWords) {
    var n = 0;
    for (final word in dueWords) {
      if (!word.wordId.startsWith(AnkiReviewAssembler.ankiPrefix)) continue;
      final importId = AnkiReviewAssembler.importIdFromWordId(word.wordId);
      if (officialImportIds.contains(importId)) continue;
      n++;
    }
    return n;
  }

  static int aggregatedAnkiDue(Iterable<SrsWord> dueWords) {
    return legacyAnkiDueExcludingOfficial(dueWords) + officialDue;
  }
}
