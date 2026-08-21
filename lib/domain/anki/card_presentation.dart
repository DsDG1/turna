import 'package:turna/domain/anki/canonical_card_key.dart';
import 'package:turna/domain/course/interaction.dart';

enum CardPresentationKind {
  multipleChoice,
  multiSelect,
  fillBlank,
  listenAndPick,
  typeAnswer,
  flip,
  fidelity,
}

sealed class CardPresentation {
  const CardPresentation();

  CanonicalCardKey get cardKey;
  CardPresentationKind get kind;
  String get sourceFingerprint;
  int get classifierVersion;
  int get mappingVersion;
}

class StructuredCardPresentation extends CardPresentation {
  const StructuredCardPresentation({
    required this.cardKey,
    required this.kind,
    required this.interaction,
    required this.sourceFingerprint,
    this.classifierVersion = 1,
    this.mappingVersion = 1,
  });

  @override
  final CanonicalCardKey cardKey;
  @override
  final CardPresentationKind kind;
  final Interaction interaction;
  @override
  final String sourceFingerprint;
  @override
  final int classifierVersion;
  @override
  final int mappingVersion;
}

class FlipCardPresentation extends CardPresentation {
  const FlipCardPresentation({
    required this.cardKey,
    required this.frontText,
    required this.backText,
    required this.sourceFingerprint,
    this.pronunciation,
    this.hint,
    this.media = const [],
    this.classifierVersion = 1,
    this.mappingVersion = 1,
  });

  @override
  final CanonicalCardKey cardKey;
  @override
  CardPresentationKind get kind => CardPresentationKind.flip;
  final String frontText;
  final String backText;
  final String? pronunciation;
  final String? hint;
  final List<CanonicalMediaRef> media;
  @override
  final String sourceFingerprint;
  @override
  final int classifierVersion;
  @override
  final int mappingVersion;
}

class FidelityCardPresentation extends CardPresentation {
  const FidelityCardPresentation({
    required this.cardKey,
    required this.templateRef,
    required this.sourceFingerprint,
    this.classifierVersion = 1,
    this.mappingVersion = 1,
  });

  @override
  final CanonicalCardKey cardKey;
  @override
  CardPresentationKind get kind => CardPresentationKind.fidelity;
  final CanonicalTemplateRef templateRef;
  @override
  final String sourceFingerprint;
  @override
  final int classifierVersion;
  @override
  final int mappingVersion;
}

class PresentationCandidate {
  const PresentationCandidate({
    required this.courseId,
    required this.cardKey,
    required this.kind,
    required this.payloadJson,
    required this.sourceFingerprint,
    this.mappingVersion = 1,
    this.classifierVersion = 1,
    this.userConfirmed = false,
  });

  final String courseId;
  final CanonicalCardKey cardKey;
  final CardPresentationKind kind;
  final String payloadJson;
  final String sourceFingerprint;
  final int mappingVersion;
  final int classifierVersion;
  final bool userConfirmed;
}
