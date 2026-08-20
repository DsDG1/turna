/// Pure-Dart string and media parsing helpers for Anki practice cards.
class CardText {
  static final RegExp _soundMarkerRegex = RegExp(
    r'\[sound:[^\]]+\]|\[anki:play:[^\]]+\]',
    caseSensitive: false,
  );

  static const int defaultShortAnswerMaxLength = 60;

  /// Strip HTML tags and decode common HTML entities.
  static String stripHtml(String html) {
    return html
        .replaceAll(_soundMarkerRegex, '')
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .trim();
  }

  /// Whether [text] contains HTML tags or sound markers.
  static bool hasHtml(String text) {
    return text.contains('<') || text.contains('[sound:') || text.contains('[anki:play:');
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
    final sound = RegExp(r'\[sound:([^\]\r\n]+)\]', caseSensitive: false).firstMatch(raw);
    if (sound != null) return safeMediaName(sound.group(1)!);
    final av = RegExp(r'\[anki:play:[^\]]*?:([^\]\r\n]+)\]', caseSensitive: false).firstMatch(raw);
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
    final customImg = RegExp(r'\[image:([^\]\r\n]+)\]', caseSensitive: false).firstMatch(raw);
    if (customImg != null) return safeMediaName(customImg.group(1)!);
    return null;
  }

  /// Check whether an answer is short enough to grade objectively.
  static bool isShortAnswer(String answer, {int maxLength = defaultShortAnswerMaxLength}) {
    final trimmed = answer.trim();
    return trimmed.isNotEmpty && trimmed.length <= maxLength && !trimmed.contains('\n');
  }

  /// Check whether text looks like a sentence rather than an isolated word/phrase.
  static bool isSentence(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    if (RegExp(r'[。！？!?]').hasMatch(trimmed)) return true;
    final words = trimmed.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    return words.length >= 6 || trimmed.length > 50;
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
