import 'package:turna/application/study_session/study_session_controller.dart';
import 'package:turna/domain/anki/card_presentation.dart';
import 'package:turna/domain/anki/presentation_receipt.dart';

/// Simulates the renderer callback in controller-only tests.
void acknowledgeStudyFace(
  StudySessionController controller,
  PresentationSide side,
) {
  final item = controller.currentItem!;
  controller.acceptPresentation(PresentationReceipt(
    cardKey: item.cardKey,
    generation: controller.generation,
    side: side,
    renderer: switch (item.presentation) {
      FidelityCardPresentation() => PresentationRendererKind.officialTemplate,
      FlipCardPresentation() => PresentationRendererKind.flutterFlip,
      StructuredCardPresentation() =>
        PresentationRendererKind.flutterStructured,
    },
    presentedAt: DateTime.now(),
  ));
}
