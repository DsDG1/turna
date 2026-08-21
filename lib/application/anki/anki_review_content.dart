import 'package:turna/domain/anki/card_presentation.dart';
import 'package:turna/domain/anki/study_models.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/domain/review/review_item.dart';

/// Map a [StudyItem]'s presentation onto the render payload consumed by
/// [StudyCardSurface].
///
/// Flip and structured presentations carry their own content; fidelity cards
/// carry only a template ref, so their [AnkiHtmlCard] source interaction —
/// collected by the review host while assembling the batch — supplies the
/// HTML faces for the WebView body.
ReviewContentBodyData reviewContentFor(
  StudyItem item, {
  Map<String, AnkiHtmlCard>? fidelityInteractions,
}) {
  final presentation = item.presentation;
  if (presentation is FlipCardPresentation) {
    return StandardCourseCardContent(
      frontText: presentation.frontText,
      backText: presentation.backText,
      backNote: presentation.hint,
    );
  }
  if (presentation is StructuredCardPresentation) {
    return StandardCourseCardContent(
      frontText: interactionPromptLabel(presentation.interaction),
      backText: interactionCorrectAnswerLabel(presentation.interaction) ?? '—',
      interaction: presentation.interaction,
    );
  }
  if (presentation is FidelityCardPresentation) {
    final interaction = fidelityInteractions?[item.sessionItemId];
    if (interaction != null) {
      return OfficialTemplateContent(
        frontHtml: interaction.frontHtml,
        backHtml: interaction.backHtml,
        mediaBasePath:
            interaction.mediaBasePath.isEmpty ? null : interaction.mediaBasePath,
      );
    }
  }
  return const StandardCourseCardContent(frontText: '', backText: '');
}
