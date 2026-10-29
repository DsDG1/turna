import 'package:turna/domain/anki/canonical_card_key.dart';
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
    // Sides come from the same facts the lesson renderer uses (ADR 0057 §5).
    // Proven front media shows on the question face; everything else — proven
    // answer media and unproven media — is built only after the reveal.
    return StandardCourseCardContent(
      frontText: presentation.frontText,
      backText: presentation.backText,
      backNote: presentation.hint,
      frontAudioAssets: presentation.frontAudioMedia,
      frontImageAssets: presentation.frontImageMedia,
      backAudioAssets: [
        ...presentation.backAudioMedia,
        ...presentation.media
            .where((ref) =>
                ref.side == MediaOccurrenceSide.unknown &&
                ref.kind == CanonicalMediaKind.audio)
            .map((ref) => ref.filename),
      ],
      backImageAssets: [
        ...presentation.backImageMedia,
        ...presentation.media
            .where((ref) =>
                ref.side == MediaOccurrenceSide.unknown &&
                ref.kind == CanonicalMediaKind.image)
            .map((ref) => ref.filename),
      ],
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
        css: interaction.css,
        mediaBasePath: interaction.mediaBasePath.isEmpty
            ? null
            : interaction.mediaBasePath,
      );
    }
  }
  return const StandardCourseCardContent(frontText: '', backText: '');
}
