import '../config.dart';

/// Pure-Dart string and media parsing helpers for recognition and
/// projection (absorbs the old `anki_practice/card_text.dart`).
class CardText {
  static final RegExp _soundMarkerRegex = RegExp(
    r'\[sound:[^\]]+\]|\[anki:play:[^\]]+\]',
    caseSensitive: false,
  );

  static final RegExp _htmlTagRegex = RegExp(r'<[^>]+>');
  static final RegExp _numericEntityRegex =
      RegExp(r'&#(?:x([0-9a-fA-F]+)|([0-9]+));');

  static String _decodeNumericEntity(Match m) {
    final hex = m.group(1);
    final codePoint = hex != null
        ? int.tryParse(hex, radix: 16)
        : int.tryParse(m.group(2)!);
    if (codePoint == null ||
        codePoint <= 0 ||
        codePoint > 0x10FFFF ||
        (codePoint >= 0xD800 && codePoint <= 0xDFFF)) {
      return m.group(0)!;
    }
    return String.fromCharCode(codePoint);
  }

  /// Strip HTML tags and decode common HTML entities.
  static String stripHtml(String html) {
    return html
        .replaceAll(_soundMarkerRegex, '')
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(_htmlTagRegex, '')
        // Mirror core stripHtml's numeric decoding (İ = &#304; / &#x130;):
        // recognition metrics must see the same text TTS reads.
        .replaceAllMapped(_numericEntityRegex, _decodeNumericEntity)
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        // &amp; decodes LAST: decoding it earlier would double-unescape
        // sequences like `&amp;lt;` (literal "&lt;") into "<".
        .replaceAll('&amp;', '&')
        .trim();
  }

  /// Whether [text] contains HTML tags or sound markers.
  static bool hasHtml(String text) {
    return text.contains('<') ||
        text.contains('[sound:') ||
        text.contains('[anki:play:');
  }

  /// Collapse whitespace and strip tags/sound markers to one plain line.
  static String shortText(String raw) {
    return raw
        .replaceAll(_htmlTagRegex, ' ')
        .replaceAll(RegExp(r'\[sound:[^\]]+\]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Safe media basename without directory traversal or schemes.
  static String? safeMediaName(String raw) {
    final name = raw.trim().split(RegExp(r'[/\\]')).last;
    if (name.isEmpty) return null;
    if (name.contains('://') || name.startsWith('file:')) return null;
    if (name.contains('..')) return null;
    return name;
  }

  /// Extract audio filename from `[sound:...]` or `[anki:play:...]`.
  static String? extractAudioFilename(String raw) {
    final sound = RegExp(
      r'\[sound:([^\]\r\n]+)\]',
      caseSensitive: false,
    ).firstMatch(raw);
    if (sound != null) return safeMediaName(sound.group(1)!);
    final av = RegExp(
      r'\[anki:play:[^\]]*?:([^\]\r\n]+)\]',
      caseSensitive: false,
    ).firstMatch(raw);
    if (av != null) return safeMediaName(av.group(1)!);
    return null;
  }

  /// Extract image filename from `<img src="...">` or `[image:...]`.
  static String? extractImageFilename(String raw) {
    final img = RegExp(
      r'''<img[^>]+src=["']([^"'>\s]+)["']''',
      caseSensitive: false,
    ).firstMatch(raw);
    if (img != null) return safeMediaName(img.group(1)!);
    final customImg = RegExp(
      r'\[image:([^\]\r\n]+)\]',
      caseSensitive: false,
    ).firstMatch(raw);
    if (customImg != null) return safeMediaName(customImg.group(1)!);
    return null;
  }

  /// First audio or image filename, whichever appears.
  static String? extractMediaFilename(String raw) {
    return extractAudioFilename(raw) ?? extractImageFilename(raw);
  }

  /// Check whether an answer is short enough to grade objectively.
  static bool isShortAnswer(
    String answer, {
    int maxLength = shortAnswerMaxLength,
  }) {
    final trimmed = answer.trim();
    return trimmed.isNotEmpty &&
        trimmed.length <= maxLength &&
        !trimmed.contains('\n');
  }

  /// Check whether text looks like a sentence rather than an isolated
  /// word/phrase.
  static bool isSentence(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    if (RegExp(r'[。！？!?]').hasMatch(trimmed)) return true;
    final words =
        trimmed.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    return words.length >= 6 || trimmed.length > 50;
  }

  /// Plain, non-empty, tag-free single run of text.
  static bool isPlainTextSample(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return false;
    if (trimmed.contains('<') || trimmed.contains('[sound:')) return false;
    return true;
  }

  /// Split Anki space-separated tag string.
  static List<String> splitTags(String tags) {
    if (tags.trim().isEmpty) return const [];
    return tags
        .split(' ')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
  }
}
