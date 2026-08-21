import 'package:turna/application/anki/card_introduction_eligibility.dart';
import 'package:turna/application/anki/card_introduction_store.dart';
import 'package:turna/application/anki_official/official_anki_ids.dart';
import 'package:turna/domain/course/srs_word.dart';

/// Dual-source home due. Never merge Official and Turna stores into one writer.
class OfficialAnkiHomeDue {
  OfficialAnkiHomeDue._();

  static var officialDue = 0;
  static var turnaDue = 0;
  static Set<String> officialImportIds = {};
  static Map<String, int> officialDueByImport = {};
  static bool officialDueUnavailable = false;
  static var unintroducedNew = 0;

  static void reset() {
    officialDue = 0;
    turnaDue = 0;
    officialImportIds = {};
    officialDueByImport = {};
    officialDueUnavailable = false;
    unintroducedNew = 0;
  }

  static int legacyAnkiDueExcludingOfficial(Iterable<SrsWord> dueWords) {
    final intro = CardIntroductionStore.resolve();
    var n = 0;
    for (final word in dueWords) {
      if (!word.wordId.startsWith(LegacyAnkiIdentifiers.ankiPrefix)) continue;
      final importId = LegacyAnkiIdentifiers.importIdFromWordId(word.wordId);
      if (officialImportIds.contains(importId)) continue;
      if (!intro.isFormallyEligibleWord(word)) continue;
      n++;
    }
    return n;
  }

  static int aggregatedAnkiDue(Iterable<SrsWord> dueWords) {
    return legacyAnkiDueExcludingOfficial(dueWords) + introducedOfficialDue;
  }

  static int get introducedOfficialDue {
    var total = 0;
    for (final importId in officialImportIds) {
      total += formalOfficialDueForImport(importId);
    }
    return total;
  }

  static int formalOfficialDueForImport(String importId) {
    final schedulerDue = officialDueByImport[importId] ?? 0;
    final introduced = CardIntroductionStore.resolve()
        .introducedCountForSource(importId);
    return const CardIntroductionEligibility().formalDueCount(
      schedulerDue: schedulerDue,
      introducedCount: introduced,
    );
  }

  static int get unintroducedOfficialDue {
    var raw = 0;
    for (final importId in officialImportIds) {
      raw += officialDueByImport[importId] ?? 0;
    }
    final introduced = introducedOfficialDue;
    final leftover = raw - introduced;
    return leftover < 0 ? 0 : leftover;
  }
}
