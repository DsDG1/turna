import 'package:turna/domain/anki/canonical_card_key.dart';
import 'package:turna/domain/anki/card_introduction_state.dart';
import 'package:turna/domain/course/srs_word.dart';

/// Pure eligibility rules for formal Anki review.
///
/// Formal review = authoritative due ∩ introduced ∩ not retired.
/// Imported history (reps/revlog) counts as introduced. Unlearned new
/// cards do not, even if the scheduler lists them as due.
class CardIntroductionEligibility {
  const CardIntroductionEligibility();

  static const defaultProfileId = 'profile-default-01';

  static String courseIdForLegacyImport(String importId) => 'anki-$importId';

  static String courseIdForOfficialSource(String sourceId) =>
      'official-anki-$sourceId';

  /// Official tree ids are `official-anki-{sourceId}-{s|u|l}…`.
  static String? officialSourceIdFromTreeId(String id) {
    final match = RegExp(
      r'^official-anki-(.+)-(s\d+|u[0-9a-f]{12}|l[0-9a-f]{12}-p\d+)$',
    ).firstMatch(id);
    return match?.group(1);
  }

  static int? cardIdFromWordId(String wordId) {
    final match = RegExp(r'-c(\d+)(?:-p|$)').firstMatch(wordId);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  static CanonicalCardKey? keyFromLegacyWordId({
    required String wordId,
    String profileId = defaultProfileId,
  }) {
    return CanonicalCardKeyAdapter.tryParseStoredWordId(
      profileId: profileId,
      rawId: wordId,
    );
  }

  static CanonicalCardKey? keyFromLessonAndWordId({
    required String lessonId,
    required String wordId,
    String profileId = defaultProfileId,
  }) {
    final cardId = cardIdFromWordId(wordId) ??
        cardIdFromWordId(wordId.replaceFirst('anki-review-', ''));
    if (cardId == null) return null;
    final officialSource = officialSourceIdFromTreeId(lessonId);
    if (officialSource != null) {
      return CanonicalCardKey(
        backend: AnkiBackendKind.official,
        profileId: profileId,
        sourceId: officialSource,
        cardId: cardId,
      );
    }
    return CanonicalCardKeyAdapter.tryParseStoredWordId(
      profileId: profileId,
      rawId: wordId.startsWith('anki-review-')
          ? wordId.substring('anki-review-'.length)
          : wordId,
    );
  }

  /// Whether a card may enter the formal review queue.
  bool isFormallyEligible({
    required CardIntroductionStatus? stored,
    required int reps,
    bool hasRevlog = false,
  }) {
    if (stored == CardIntroductionStatus.retired) return false;
    if (stored == CardIntroductionStatus.introduced) return true;
    if (reps > 0 || hasRevlog) return true;
    return false;
  }

  bool isFormallyEligibleWord(SrsWord word, {CardIntroductionStatus? stored}) {
    if (word.isSuspended || word.isBuried) return false;
    return isFormallyEligible(stored: stored, reps: word.reps);
  }

  /// Displayed formal due never exceeds how many cards are already introduced.
  /// Zero introduced ⇒ formal due is 0 even if the scheduler lists New cards.
  int formalDueCount({
    required int schedulerDue,
    required int introducedCount,
  }) {
    if (schedulerDue < 0) return 0;
    if (introducedCount <= 0) return 0;
    return schedulerDue < introducedCount ? schedulerDue : introducedCount;
  }

  CardIntroductionStatus initialStatus({
    required int reps,
    bool hasRevlog = false,
  }) {
    if (reps > 0 || hasRevlog) {
      return CardIntroductionStatus.introduced;
    }
    return CardIntroductionStatus.unintroduced;
  }
}
