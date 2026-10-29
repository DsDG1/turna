import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_import/adaptation/card_media_extractor.dart';
import 'package:turna/application/anki_import/adaptation/card_presentation_resolver.dart';
import 'package:turna/application/anki_import/recognition/recognize/result.dart';
import 'package:turna/application/anki_official/projection/official_anki_mapping_suggestion.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_payloads.dart';
import 'package:turna/domain/anki/adaptation/presentation_decision.dart';
import 'package:turna/domain/anki/canonical_card_key.dart';
import 'package:turna/domain/anki/card_presentation.dart';

/// P1 contract: one resolver, four outcomes, reasons recorded (ADR 0057 §1).
void main() {
  const resolver = OfficialCardPresentationResolver();

  OfficialAnkiRoleValues values({
    String target = 'hello',
    String native = 'merhaba',
    String? audio,
    String archetype = 'basicPair',
    double confidence = 0.95,
    bool violated = false,
    bool truncated = false,
    List<String> options = const <String>[],
    List<int>? correctIndices,
    List<MediaOccurrence> mediaOccurrences = const <MediaOccurrence>[],
  }) {
    return OfficialAnkiRoleValues(
      target: target,
      native: native,
      pronunciation: '',
      example: '',
      audio: audio,
      image: null,
      options: options,
      truncatedRequired: truncated,
      archetype: CardArchetype.values.firstWhere((a) => a.name == archetype),
      archetypeConfidence: confidence,
      archetypeViolated: violated,
      hasExplicitOptions: options.isNotEmpty,
      correctIndices: correctIndices,
      mediaOccurrences: mediaOccurrences,
    );
  }

  OfficialAnkiMappingSuggestion mapping({
    String archetype = 'basicPair',
    OfficialAnkiMappingStatus status = OfficialAnkiMappingStatus.manual,
    List<String> enabledKinds = const <String>[
      'flip',
      'multipleChoice',
      'multiSelect',
      'listenPick',
      'typeAnswer',
      'fillBlank',
      'canonicalLink',
    ],
  }) {
    return OfficialAnkiMappingSuggestion(
      candidates: const <OfficialAnkiFieldCandidate>[],
      status: status,
      archetype: archetype,
      enabledKinds: enabledKinds,
    );
  }

  test('a plain pair resolves to a structured flip and says nothing else',
      () {
    final resolution = resolver.resolve(
      values: values(),
      mapping: mapping(),
    );
    expect(resolution.kind, OfficialAnkiProjectionKind.flip);
    expect(resolution.decision, isA<StructuredCardDecision>());
    expect(resolution.decision.kind, CardPresentationKind.flip);
    expect(resolution.decision.reasons, isEmpty);
  });

  test('a truncated required field keeps the original card', () {
    final resolution = resolver.resolve(
      values: values(truncated: true),
      mapping: mapping(),
    );
    expect(resolution.kind, OfficialAnkiProjectionKind.canonicalLink);
    expect(resolution.decision, isA<OriginalCardDecision>());
    expect(
      resolution.decision.reasons,
      contains(PresentationReason.truncatedRequired),
    );
  });

  test('an unconfirmed low-confidence notetype keeps the original card', () {
    final resolution = resolver.resolve(
      values: values(confidence: 0.4),
      mapping: mapping(status: OfficialAnkiMappingStatus.review),
    );
    expect(resolution.kind, OfficialAnkiProjectionKind.canonicalLink);
    expect(
      resolution.decision.reasons,
      contains(PresentationReason.lowConfidence),
    );
  });

  test('a violated choice card with a long stem keeps the original card', () {
    final resolution = resolver.resolve(
      values: values(
        archetype: 'choice',
        violated: true,
        target: 'Which of these is the correct translation of the whole '
            'sentence the speaker just said?',
      ),
      mapping: mapping(archetype: 'choice'),
    );
    expect(resolution.kind, OfficialAnkiProjectionKind.canonicalLink);
    expect(
      resolution.decision.reasons,
      contains(PresentationReason.archetypeViolated),
    );
  });

  test('a choice card without a resolvable pool degrades and records why', () {
    final resolution = resolver.resolve(
      values: values(archetype: 'choice'),
      mapping: mapping(archetype: 'choice'),
    );
    expect(resolution.kind, OfficialAnkiProjectionKind.flip);
    expect(
      resolution.decision.reasons,
      contains(PresentationReason.missingOptions),
    );
  });

  test('a fully resolved choice card stays a multiple choice', () {
    final resolution = resolver.resolve(
      values: values(
        archetype: 'choice',
        options: const <String>['a', 'b', 'c'],
        correctIndices: const <int>[1],
      ),
      mapping: mapping(archetype: 'choice'),
    );
    expect(resolution.kind, OfficialAnkiProjectionKind.multipleChoice);
    expect(resolution.decision.kind, CardPresentationKind.multipleChoice);
    expect(resolution.decision.reasons, isEmpty);
  });

  test('an unknown stored kind is ignored, not coerced', () {
    final resolution = resolver.resolve(
      values: values(),
      mapping: mapping(),
      storedKindName: 'kind-from-a-newer-build',
    );
    expect(resolution.kind, OfficialAnkiProjectionKind.flip);
    expect(
      resolution.decision.reasons,
      contains(PresentationReason.unknownStoredKind),
    );
    expect(
      resolution.decision.reasons,
      isNot(contains(PresentationReason.storedKindDrift)),
    );
  });

  test('a stale stored kind is overridden and the drift is recorded', () {
    final resolution = resolver.resolve(
      values: values(archetype: 'cloze', target: 'a {{c1::b}} c'),
      mapping: mapping(archetype: 'cloze'),
      storedKindName: 'flip',
    );
    expect(resolution.kind, OfficialAnkiProjectionKind.fillBlank);
    expect(
      resolution.decision.reasons,
      contains(PresentationReason.storedKindDrift),
    );
  });

  test('a flip card with unproven media sides keeps the original card', () {
    final resolution = resolver.resolve(
      values: values(
        mediaOccurrences: const [
          MediaOccurrence(
            fieldIndex: 2,
            order: 0,
            kind: CanonicalMediaKind.audio,
            filename: 'clip.mp3',
            side: MediaOccurrenceSide.unknown,
          ),
        ],
      ),
      mapping: mapping(),
    );
    expect(resolution.kind, OfficialAnkiProjectionKind.canonicalLink);
    expect(resolution.decision, isA<OriginalCardDecision>());
    expect(
      resolution.decision.reasons,
      contains(PresentationReason.unknownMediaSide),
    );
  });

  test('a flip card with proven media sides stays a flip', () {
    final resolution = resolver.resolve(
      values: values(
        mediaOccurrences: const [
          MediaOccurrence(
            fieldIndex: 0,
            order: 0,
            kind: CanonicalMediaKind.audio,
            filename: 'prompt.mp3',
            side: MediaOccurrenceSide.front,
          ),
          MediaOccurrence(
            fieldIndex: 1,
            order: 1,
            kind: CanonicalMediaKind.image,
            filename: 'answer.png',
            side: MediaOccurrenceSide.back,
          ),
        ],
      ),
      mapping: mapping(),
    );
    expect(resolution.kind, OfficialAnkiProjectionKind.flip);
    expect(
      resolution.decision.reasons,
      isNot(contains(PresentationReason.unknownMediaSide)),
    );
  });

  group('opt-in presentations', () {
    MediaOccurrence frontImage() => const MediaOccurrence(
          fieldIndex: 3,
          order: 0,
          kind: CanonicalMediaKind.image,
          filename: 'prompt.png',
          side: MediaOccurrenceSide.front,
        );
    MediaOccurrence backImage() => const MediaOccurrence(
          fieldIndex: 3,
          order: 0,
          kind: CanonicalMediaKind.image,
          filename: 'answer.png',
          side: MediaOccurrenceSide.back,
        );
    MediaOccurrence frontAudio() => const MediaOccurrence(
          fieldIndex: 2,
          order: 0,
          kind: CanonicalMediaKind.audio,
          filename: 'prompt.mp3',
          side: MediaOccurrenceSide.front,
        );

    OfficialAnkiMappingSuggestion optIn(List<String> kinds) =>
        mapping(enabledKinds: kinds);

    test('image recall needs the opt-in and a proven prompt image', () {
      final resolution = resolver.resolve(
        values: values(mediaOccurrences: [frontImage()]),
        mapping: optIn(const ['imageRecall', 'flip', 'canonicalLink']),
      );
      expect(resolution.kind, OfficialAnkiProjectionKind.imageRecall);
      expect(resolution.decision.kind, CardPresentationKind.imageRecall);
    });

    test('an answer-side image never becomes an image prompt', () {
      final resolution = resolver.resolve(
        values: values(mediaOccurrences: [backImage()]),
        mapping: optIn(const ['imageRecall', 'flip', 'canonicalLink']),
      );
      expect(
        resolution.kind,
        isNot(OfficialAnkiProjectionKind.imageRecall),
        reason: '答案图当题面等于把答案当题干',
      );
      expect(resolution.kind, OfficialAnkiProjectionKind.flip);
    });

    test('image recall is not chosen without the opt-in', () {
      final resolution = resolver.resolve(
        values: values(mediaOccurrences: [frontImage()]),
        mapping: mapping(),
      );
      expect(resolution.kind, OfficialAnkiProjectionKind.flip);
    });

    test('dictation needs the opt-in, prompt audio and a short answer', () {
      final resolution = resolver.resolve(
        values: values(mediaOccurrences: [frontAudio()]),
        mapping: optIn(const ['dictation', 'flip', 'canonicalLink']),
      );
      expect(resolution.kind, OfficialAnkiProjectionKind.dictation);
      expect(resolution.decision.kind, CardPresentationKind.dictation);
    });

    test('a long target is not dictated', () {
      final resolution = resolver.resolve(
        values: values(
          mediaOccurrences: [frontAudio()],
          target: 'Bu çok uzun bir cümle olduğu için dikte edilemez, '
              'çünkü kısa cevap sınırını aşıyor ve tek satırda bitmiyor',
        ),
        mapping: optIn(const ['dictation', 'flip', 'canonicalLink']),
      );
      expect(resolution.kind, isNot(OfficialAnkiProjectionKind.dictation));
    });

    test('unproven media sides disable both opt-in kinds', () {
      const unprovenAudio = MediaOccurrence(
        fieldIndex: 2,
        order: 0,
        kind: CanonicalMediaKind.audio,
        filename: 'prompt.mp3',
        side: MediaOccurrenceSide.unknown,
      );
      final resolution = resolver.resolve(
        values: values(mediaOccurrences: [unprovenAudio]),
        mapping: optIn(const ['dictation', 'flip', 'canonicalLink']),
      );
      expect(resolution.kind, isNot(OfficialAnkiProjectionKind.dictation));
      expect(
        resolution.kind,
        OfficialAnkiProjectionKind.canonicalLink,
        reason: '面未证的 flip 也回原卡',
      );
    });
  });

  test('formal review keeps the original card in phase one', () {
    final resolution = resolver.resolve(
      values: values(),
      mapping: mapping(),
      formalReview: true,
    );
    expect(resolution.kind, OfficialAnkiProjectionKind.canonicalLink);
    expect(resolution.decision, isA<OriginalCardDecision>());
    expect(
      resolution.decision.reasons,
      contains(PresentationReason.formalReviewOriginalFirst),
    );
  });

  group('batch summary', () {
    test('counts every outcome and never hides the fallbacks', () {
      final decisions = <CardPresentationDecision>[
        resolver.resolve(values: values(), mapping: mapping()).decision,
        resolver.resolve(
          values: values(truncated: true),
          mapping: mapping(),
        ).decision,
        const NeedsCorrectionDecision(reasons: []),
        const UnavailableCardDecision(reasons: []),
      ];

      final summary = AdaptationBatchSummary.of(decisions);

      expect(summary.total, 4);
      expect(summary.structured, 1);
      expect(summary.originalCard, 1);
      expect(summary.needsCorrection, 1);
      expect(summary.unavailable, 1);
      expect(summary.structuredShare, 0.25);
    });

    test('an empty group is 0%, not 100%', () {
      expect(AdaptationBatchSummary.of(const []).structuredShare, 0);
    });
  });
}
