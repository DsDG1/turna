import 'package:turna/application/study_session/study_session_controller.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/anki/canonical_card_key.dart';
import 'package:turna/domain/anki/card_presentation.dart';
import 'package:turna/domain/anki/presentation_receipt.dart';
import 'package:turna/domain/anki/study_models.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/domain/review/recall_outcome.dart';

/// Production study-session entry used by course learn and formal review.
///
/// UI hosts must open a controller through this type so learn/review share
/// one card lifecycle and one ledger writer.
class AnkiStudySessionHost {
  AnkiStudySessionHost({
    required this.resolver,
    this.onEffects,
    this.onEffectsUndone,
  });

  final StudyLedgerResolver resolver;
  final Future<void> Function(StudyItem item, StudyEventReceipt receipt)?
      onEffects;
  final Future<void> Function(StudyEventReceipt receipt)? onEffectsUndone;

  static AnkiStudySessionHost? debugOverride;

  static AnkiStudySessionHost? resolveOrNull() {
    if (debugOverride != null) return debugOverride;
    if (getIt.isRegistered<AnkiStudySessionHost>()) {
      return getIt<AnkiStudySessionHost>();
    }
    return null;
  }

  static StudyLedgerOwner ownerFor(CanonicalCardKey key) {
    return switch (key.backend) {
      AnkiBackendKind.official => StudyLedgerOwner.officialAnki,
      AnkiBackendKind.legacyTurna ||
      AnkiBackendKind.localCanonical =>
        StudyLedgerOwner.turnaFsrs,
    };
  }

  static StudyItem itemFromReviewCard({
    required String wordId,
    required Interaction interaction,
    required StudyMode mode,
    required String courseId,
    String profileId = 'profile-default-01',
  }) {
    final key = CanonicalCardKeyAdapter.tryParseStoredWordId(
          profileId: profileId,
          rawId: wordId,
        ) ??
        CanonicalCardKey(
          backend: AnkiBackendKind.legacyTurna,
          profileId: profileId,
          sourceId: 'legacy',
          cardId: 0,
        );
    final CardPresentation presentation;
    if (interaction is AnkiCard) {
      presentation = FlipCardPresentation(
        cardKey: key,
        frontText: interaction.front,
        backText: interaction.back,
        hint: interaction.hint,
        sourceFingerprint: 'review',
      );
    } else if (interaction is AnkiHtmlCard) {
      presentation = FidelityCardPresentation(
        cardKey: key,
        templateRef: const CanonicalTemplateRef(notetypeId: 0, ordinal: 0),
        sourceFingerprint: 'review',
      );
    } else {
      presentation = StructuredCardPresentation(
        cardKey: key,
        kind: CardPresentationKind.multipleChoice,
        interaction: interaction,
        sourceFingerprint: 'review',
      );
    }
    return itemFor(
      key: key,
      presentation: presentation,
      mode: mode,
      courseId: courseId,
    );
  }

  static StudyItem itemFor({
    required CanonicalCardKey key,
    required CardPresentation presentation,
    required StudyMode mode,
    required String courseId,
    String placementId = '',
    StudyCapabilities? capabilities,
  }) {
    final owner = mode == StudyMode.practice || mode == StudyMode.preview
        ? StudyLedgerOwner.none
        : ownerFor(key);
    return StudyItem(
      // Anki card ids are millisecond timestamps, so two imports routinely
      // carry the same cardId. Include sourceId or the review-all-decks flow
      // keys WebView interactions by an id that collides across imports and
      // shows the wrong card face.
      sessionItemId: '${mode.name}-${key.sourceId}-${key.cardId}',
      courseId: courseId,
      placementId: placementId.isEmpty ? '${key.sourceId}-${key.cardId}' : placementId,
      cardKey: key,
      presentation: presentation,
      mode: mode,
      ledgerOwner: owner,
      capabilities: capabilities ?? StudyCapabilities.forMode(mode),
    );
  }

  /// Course-lesson item: always practice (no ledger write). Doc 35 L2:
  /// the Turna-FSRS writer for Anki cards is retired, so legacy imports
  /// study like official ones — flip through + introduction only.
  static StudyItem itemForCourse({
    required CanonicalCardKey key,
    required CardPresentation presentation,
    required String courseId,
    String placementId = '',
  }) {
    return itemFor(
      key: key,
      presentation: presentation,
      mode: StudyMode.practice,
      courseId: courseId,
      placementId: placementId,
      capabilities: StudyCapabilities.coursePractice(),
    );
  }

  /// Open a shared session whose Official answers write [OfficialStudyLedger].
  StudySessionController openOfficialReview(
    List<StudyItem> items, {
    required StudyLedger officialLedger,
  }) {
    return StudySessionController(
      items: items,
      ledgerResolver: StudyLedgerResolver(
        official: officialLedger,
      ),
      onEffects: onEffects,
      onEffectsUndone: onEffectsUndone,
    );
  }

  StudySessionController open(List<StudyItem> items) {
    return StudySessionController(
      items: items,
      ledgerResolver: resolver,
      onEffects: onEffects,
      onEffectsUndone: onEffectsUndone,
    );
  }

  /// Drive one learn/review card through the shared state machine.
  Future<StudySessionController> startCard({
    required StudyItem item,
  }) async {
    final controller = open([item]);
    await controller.start();
    return controller;
  }

  static void presentBothSides(StudySessionController controller) {
    final item = controller.currentItem;
    if (item == null) return;
    controller.acceptPresentation(
      PresentationReceipt(
        cardKey: item.cardKey,
        generation: controller.generation,
        side: PresentationSide.question,
        renderer: PresentationRendererKind.flutterFlip,
        presentedAt: DateTime.now(),
      ),
    );
  }

  static Future<void> revealAndPresentAnswer(
    StudySessionController controller, {
    void Function()? onOfficialShowAnswer,
  }) async {
    await controller.revealAnswer();
    onOfficialShowAnswer?.call();
    final item = controller.currentItem;
    if (item == null) return;
    controller.acceptPresentation(
      PresentationReceipt(
        cardKey: item.cardKey,
        generation: controller.generation,
        side: PresentationSide.answer,
        renderer: PresentationRendererKind.flutterFlip,
        presentedAt: DateTime.now(),
      ),
    );
  }

  /// Shared learn/review drive: start → question ACK → reveal → answer ACK
  /// → one ledger commit (or practice no-op).
  Future<StudySessionController> driveFlip({
    required StudyItem item,
    required RecallOutcome outcome,
  }) async {
    final controller = await startCard(item: item);
    presentBothSides(controller);
    await revealAndPresentAnswer(controller);
    await controller.submitRecall(outcome);
    return controller;
  }
}
