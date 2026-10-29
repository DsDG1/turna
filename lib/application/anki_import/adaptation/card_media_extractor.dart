import 'package:turna/application/anki_import/recognition/facts/text_metrics.dart';
import 'package:turna/domain/anki/canonical_card_key.dart';

/// One media reference as it appears on a card, in document order.
///
/// Identity is the **occurrence**, not the filename: the same clip may
/// intentionally appear twice on one card (ADR 0057 §5). [order] is the
/// card-wide position, [fieldIndex] the field it was found in.
class MediaOccurrence {
  const MediaOccurrence({
    required this.fieldIndex,
    required this.order,
    required this.kind,
    required this.filename,
    required this.side,
  });

  final int fieldIndex;
  final int order;
  final CanonicalMediaKind kind;
  final String filename;
  final MediaOccurrenceSide side;

  /// Whether the face is provable. Unproven occurrences force the card onto
  /// the original rendering instead of a guessed layout.
  bool get sideKnown => side != MediaOccurrenceSide.unknown;

  @override
  String toString() =>
      'MediaOccurrence(#$order field=$fieldIndex ${kind.name} $filename '
      '${side.name})';
}

/// Extracts [MediaOccurrence]s from raw note fields.
///
/// Scope, deliberately narrow (ADR 0057 §5 / plan §8.2):
/// - `[sound:…]`, `[anki:play:…]`, `<img src|srcset>`, `[image:…]`.
/// - Only fields the template actually renders are considered. When template
///   face facts are unavailable, only the role-bound fields passed in
///   [fallbackFieldIndices] are scanned — a hidden field's media must never be
///   promoted onto the card.
/// - No CSS, script, canvas, SVG or background-image analysis: those stay
///   "unknown" and leave the card on the original rendering.
abstract final class CardMediaExtractor {
  static final RegExp _soundMarker = RegExp(
    r'\[sound:([^\]\r\n]+)\]',
    caseSensitive: false,
  );
  static final RegExp _avMarker = RegExp(
    r'\[anki:play:[^\]]*?:([^\]\r\n]+)\]',
    caseSensitive: false,
  );
  static final RegExp _imageMarker = RegExp(
    r'\[image:([^\]\r\n]+)\]',
    caseSensitive: false,
  );
  static final RegExp _imgTag = RegExp(r'<img\b[^>]*>', caseSensitive: false);
  static final RegExp _srcAttr = RegExp(
    r'''\bsrc\s*=\s*["']([^"'>\s]+)["']''',
    caseSensitive: false,
  );
  static final RegExp _srcsetAttr = RegExp(
    r'''\bsrcset\s*=\s*["']([^"']+)["']''',
    caseSensitive: false,
  );

  static List<MediaOccurrence> extract({
    required List<String> fields,
    Set<int> frontFieldOrds = const <int>{},
    Set<int> backFieldOrds = const <int>{},
    Set<int> fallbackFieldIndices = const <int>{},
  }) {
    final facesKnown = frontFieldOrds.isNotEmpty || backFieldOrds.isNotEmpty;
    final out = <MediaOccurrence>[];
    for (var fieldIndex = 0; fieldIndex < fields.length; fieldIndex++) {
      if (!_fieldIsConsidered(
        fieldIndex: fieldIndex,
        facesKnown: facesKnown,
        frontFieldOrds: frontFieldOrds,
        backFieldOrds: backFieldOrds,
        fallbackFieldIndices: fallbackFieldIndices,
      )) {
        continue;
      }
      final raw = fields[fieldIndex];
      if (raw.isEmpty) continue;
      final side = _sideOf(
        fieldIndex: fieldIndex,
        facesKnown: facesKnown,
        frontFieldOrds: frontFieldOrds,
        backFieldOrds: backFieldOrds,
      );
      for (final hit in _hitsIn(raw)) {
        out.add(
          MediaOccurrence(
            fieldIndex: fieldIndex,
            order: out.length,
            kind: hit.kind,
            filename: hit.filename,
            side: side,
          ),
        );
      }
    }
    return out;
  }

  static bool _fieldIsConsidered({
    required int fieldIndex,
    required bool facesKnown,
    required Set<int> frontFieldOrds,
    required Set<int> backFieldOrds,
    required Set<int> fallbackFieldIndices,
  }) {
    if (!facesKnown) return fallbackFieldIndices.contains(fieldIndex);
    // A field on neither face is not rendered by this template at all.
    return frontFieldOrds.contains(fieldIndex) ||
        backFieldOrds.contains(fieldIndex);
  }

  static MediaOccurrenceSide _sideOf({
    required int fieldIndex,
    required bool facesKnown,
    required Set<int> frontFieldOrds,
    required Set<int> backFieldOrds,
  }) {
    if (!facesKnown) return MediaOccurrenceSide.unknown;
    // Front wins when a field appears on both: `{{FrontSide}}` on the back
    // re-displays front content, it does not make that content answer-only.
    if (frontFieldOrds.contains(fieldIndex)) return MediaOccurrenceSide.front;
    if (backFieldOrds.contains(fieldIndex)) return MediaOccurrenceSide.back;
    return MediaOccurrenceSide.unknown;
  }

  /// Media references inside one field, ordered by their position in the text.
  static List<({int at, CanonicalMediaKind kind, String filename})> _hitsIn(
    String raw,
  ) {
    final hits = <({int at, CanonicalMediaKind kind, String filename})>[];
    void collect(
      RegExp pattern,
      CanonicalMediaKind kind, {
      int group = 1,
    }) {
      for (final match in pattern.allMatches(raw)) {
        final name = _name(match.group(group));
        if (name == null) continue;
        hits.add((at: match.start, kind: kind, filename: name));
      }
    }

    collect(_soundMarker, CanonicalMediaKind.audio);
    collect(_avMarker, CanonicalMediaKind.audio);
    collect(_imageMarker, CanonicalMediaKind.image);
    // One image per <img> tag: srcset's first candidate wins over src, so a
    // responsive tag does not count twice.
    for (final tag in _imgTag.allMatches(raw)) {
      final tagText = tag.group(0)!;
      final srcset = _srcsetAttr.firstMatch(tagText);
      final src = _srcAttr.firstMatch(tagText);
      final rawName = srcset != null
          ? srcset.group(1)!.split(',').first.trim().split(RegExp(r'\s+')).first
          : src?.group(1);
      final name = _name(rawName);
      if (name == null) continue;
      hits.add((at: tag.start, kind: CanonicalMediaKind.image, filename: name));
    }
    hits.sort((a, b) => a.at.compareTo(b.at));
    return hits;
  }

  /// Decode percent-encoding once at this boundary, then take the basename.
  /// Unicode names are never NFC/NFD-renamed (ADR 0057 §5).
  static String? _name(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    String decoded;
    try {
      decoded = Uri.decodeComponent(trimmed);
    } on ArgumentError {
      decoded = trimmed;
    } on FormatException {
      decoded = trimmed;
    }
    return CardText.safeMediaName(decoded);
  }
}
