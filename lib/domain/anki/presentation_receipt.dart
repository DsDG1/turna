import 'package:turna/domain/anki/canonical_card_key.dart';

enum PresentationSide { question, answer }

enum PresentationRendererKind {
  flutterStructured,
  flutterFlip,
  officialTemplate,
  fallbackText,
}

class PresentationReceipt {
  const PresentationReceipt({
    required this.cardKey,
    required this.generation,
    required this.side,
    required this.renderer,
    required this.presentedAt,
    this.ok = true,
    this.code,
  });

  final CanonicalCardKey cardKey;
  final int generation;
  final PresentationSide side;
  final PresentationRendererKind renderer;
  final DateTime presentedAt;
  final bool ok;
  final String? code;

  bool matches({
    required CanonicalCardKey cardKey,
    required int generation,
    required PresentationSide side,
  }) {
    return ok &&
        this.cardKey == cardKey &&
        this.generation == generation &&
        this.side == side;
  }
}
