import 'package:turna/application/anki_import/adaptation/card_media_extractor.dart';
import 'package:turna/application/anki_import/recognition/facts/text_metrics.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/domain/anki/adaptation/card_adaptation_plan.dart';
import 'package:turna/domain/anki/canonical_card_key.dart';

/// One face of a plan-laid-out card: the text blocks joined in order, plus the
/// media the plan put on that face.
class CardDocumentFace {
  const CardDocumentFace({
    required this.text,
    required this.audio,
    required this.images,
  });

  static const CardDocumentFace empty =
      CardDocumentFace(text: '', audio: [], images: []);

  final String text;
  final List<String> audio;
  final List<String> images;

  bool get isEmpty => text.isEmpty && audio.isEmpty && images.isEmpty;
}

/// What the plan's layout actually produces for one card.
///
/// [unsupported] means a block could not be honoured (field out of range, or
/// content the app cannot render as plain text). The caller must fall back to
/// the original card instead of rendering half a layout (ADR 0057 §5).
class CardDocument {
  const CardDocument({
    required this.front,
    required this.back,
    this.unsupported = false,
  });

  final CardDocumentFace front;
  final CardDocumentFace back;
  final bool unsupported;

  static const CardDocument empty = CardDocument(
    front: CardDocumentFace.empty,
    back: CardDocumentFace.empty,
  );
}

/// Composes the plan's ordered blocks into per-face text + media.
///
/// Honest boundary: this enforces **which** fields and media land on **which
/// face**, not the exact interleaving of text and media inside a face — the
/// flip renderer shows text then media. Interleaved layout needs a dedicated
/// card-document renderer, which the plan defers.
CardDocument buildCardDocument({
  required CardAdaptationPlan plan,
  required OfficialAnkiProjectionRow row,
}) {
  if (plan.front.isEmpty && plan.back.isEmpty) return CardDocument.empty;

  // The plan names its fields explicitly, so every field is a candidate; the
  // extractor still refuses names that traverse or carry a scheme.
  final occurrences = CardMediaExtractor.extract(
    fields: row.fields,
    fallbackFieldIndices: {for (var i = 0; i < row.fields.length; i++) i},
  );

  var unsupported = false;

  CardDocumentFace face(List<AdaptationBlock> blocks) {
    final texts = <String>[];
    final audio = <String>[];
    final images = <String>[];
    for (final block in blocks) {
      if (block.fieldIndex < 0 || block.fieldIndex >= row.fields.length) {
        unsupported = true;
        continue;
      }
      final raw = row.fields[block.fieldIndex];
      switch (block.kind) {
        case 'text':
        case 'richText':
          if (cardCarriesUnsupportedStructure(raw)) {
            // Scripts, SVG, tables, embedded media widgets: the plain renderer
            // would corrupt them, so the whole card keeps the original face.
            unsupported = true;
            continue;
          }
          final text = CardText.shortText(raw);
          if (text.isNotEmpty) texts.add(text);
        case 'audioGroup':
          audio.addAll(_mediaOf(occurrences, block, CanonicalMediaKind.audio));
        case 'imageGroup':
          images.addAll(_mediaOf(occurrences, block, CanonicalMediaKind.image));
        default:
          unsupported = true;
      }
    }
    return CardDocumentFace(
      text: texts.join('\n'),
      audio: audio,
      images: images,
    );
  }

  return CardDocument(
    front: face(plan.front),
    back: face(plan.back),
    unsupported: unsupported,
  );
}

/// `all` keeps every occurrence of the field in document order; `first` keeps
/// only the first one. Anything else is already rejected by the validator.
List<String> _mediaOf(
  List<MediaOccurrence> occurrences,
  AdaptationBlock block,
  CanonicalMediaKind kind,
) {
  final matches = <String>[
    for (final occurrence in occurrences)
      if (occurrence.fieldIndex == block.fieldIndex && occurrence.kind == kind)
        occurrence.filename,
  ];
  if (matches.isEmpty) return const <String>[];
  return block.selection == 'first' ? [matches.first] : matches;
}

/// Whether a field's raw value contains structure the plain renderer cannot
/// honour: scripts, event handlers, embedded widgets, tables, SVG.
///
/// One definition, two consumers: this file (does the plan's layout survive?)
/// and the projection payloads (is the card's archetype violated?). Keeping
/// two near-copies of this list is exactly how they drift apart.
bool cardCarriesUnsupportedStructure(String raw) {
  final lower = raw.toLowerCase();
  if (lower.contains('<script') || lower.contains('javascript:')) return true;
  if (_handlerPattern.hasMatch(raw)) return true;
  return _embeddedStructurePattern.hasMatch(raw);
}

final RegExp _embeddedStructurePattern = RegExp(
  r'<(table|svg|video|iframe|canvas|object|embed|form|input|button)\b',
  caseSensitive: false,
);
final RegExp _handlerPattern = RegExp(r'on[a-z]+\s*=', caseSensitive: false);
