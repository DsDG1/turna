import 'package:turna/application/anki/anki_study_session_host.dart';
import 'package:turna/application/anki/card_introduction_eligibility.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_formal_due_eligibility.dart';
import 'package:turna/domain/anki/canonical_card_key.dart';
import 'package:turna/domain/anki/card_presentation.dart';
import 'package:turna/domain/anki/study_models.dart';

/// Maps an Official review queue + projection presentations onto shared
/// [StudyItem]s for [StudySessionController] / [AnkiStudySessionHost].
///
/// Only cards in the exact formal-due set are assembled. Presentation is
/// required; cards without an active presentation are skipped.
class OfficialStudyBatchAssembler {
  const OfficialStudyBatchAssembler({
    this.profileId = CardIntroductionEligibility.defaultProfileId,
  });

  final String profileId;

  /// Build review items from pre-computed formal-due keys.
  List<StudyItem> assemble({
    required String sourceId,
    required String courseId,
    required Iterable<OfficialReviewQueueCard> queueCards,
    required Map<CanonicalCardKey, CardPresentation> presentations,
    required Set<CanonicalCardKey> formalDueCardKeys,
    int? limit,
  }) {
    final items = <StudyItem>[];
    for (final card in queueCards) {
      final key = CanonicalCardKey(
        backend: AnkiBackendKind.official,
        profileId: profileId,
        sourceId: sourceId,
        cardId: card.cardId,
      );
      if (!formalDueCardKeys.contains(key)) continue;
      final presentation = presentations[key];
      if (presentation == null) continue;
      items.add(
        AnkiStudySessionHost.itemFor(
          key: key,
          presentation: presentation,
          mode: StudyMode.review,
          courseId: courseId,
          placementId: '$sourceId-${card.cardId}',
        ),
      );
      if (limit != null && items.length >= limit) break;
    }
    return items;
  }

  /// Compute formal due from set inputs, then assemble queue ∩ eligible.
  List<StudyItem> assembleFromEligibility({
    required String sourceId,
    required String courseId,
    required Iterable<OfficialReviewQueueCard> queueCards,
    required Map<CanonicalCardKey, CardPresentation> presentations,
    required Set<CanonicalCardKey> activePlacementCardKeys,
    required Set<CanonicalCardKey> introducedCardKeys,
    Set<CanonicalCardKey> suspendedCardKeys = const {},
    Set<CanonicalCardKey> buriedCardKeys = const {},
    Set<CanonicalCardKey> retiredCardKeys = const {},
    int? limit,
  }) {
    final schedulerDue = <CanonicalCardKey>{
      for (final card in queueCards)
        CanonicalCardKey(
          backend: AnkiBackendKind.official,
          profileId: profileId,
          sourceId: sourceId,
          cardId: card.cardId,
        ),
    };
    final formalDue = computeFormalDueCardKeys(
      officialSchedulerDueCardKeys: schedulerDue,
      activePlacementCardKeys: activePlacementCardKeys,
      introducedCardKeys: introducedCardKeys,
      suspendedCardKeys: suspendedCardKeys,
      buriedCardKeys: buriedCardKeys,
      retiredCardKeys: retiredCardKeys,
    );
    return assemble(
      sourceId: sourceId,
      courseId: courseId,
      queueCards: queueCards,
      presentations: presentations,
      formalDueCardKeys: formalDue,
      limit: limit,
    );
  }
}
