/// Safely extracts local media references from rendered Anki fields/templates.
///
/// Anki stores imported media by its original filename. References found in
/// card HTML are normalized back to that filename and represented with the
/// app's stable `anki://<importId>/<relative path>` scheme.
class AnkiMediaReferenceExtractor {
  const AnkiMediaReferenceExtractor();

  static final _mediaTagRegex = RegExp(
    r'''<(?:img|audio|source|video)\b[^>]*\bsrc\s*=\s*(?:"([^"]+)"|'([^']+)'|([^\s>]+))''',
    caseSensitive: false,
    dotAll: true,
  );

  static final _cssUrlRegex = RegExp(
    r'''url\(\s*(?:"([^"]+)"|'([^']+)'|([^\)\s]+))\s*\)''',
    caseSensitive: false,
  );

  static final _soundRegex = RegExp(
    r'\[sound:([^\]]+)\]',
    caseSensitive: false,
  );

  ({List<String> images, List<String> audios}) extract(
    String content,
    String importId,
  ) {
    final images = <String>[];
    final audios = <String>[];

    String? capturedValue(RegExpMatch match) =>
        match.group(1) ?? match.group(2) ?? match.group(3);

    for (final match in _mediaTagRegex.allMatches(content)) {
      final ref = _buildAsset(importId, capturedValue(match));
      if (ref == null) continue;

      final tag = match.group(0)!.toLowerCase();
      final before = content.substring(0, match.start).toLowerCase();
      final lastAudio = before.lastIndexOf('<audio');
      final lastAudioClose = before.lastIndexOf('</audio');
      final lastVideo = before.lastIndexOf('<video');
      final lastVideoClose = before.lastIndexOf('</video');
      final insideAudio = lastAudio > lastAudioClose;
      final insideVideo = lastVideo > lastVideoClose;
      final isAudio = tag.startsWith('<audio') ||
          (tag.startsWith('<source') &&
              insideAudio &&
              (!insideVideo || lastAudio > lastVideo));
      (isAudio ? audios : images).add(ref);
    }

    for (final match in _cssUrlRegex.allMatches(content)) {
      final ref = _buildAsset(importId, capturedValue(match));
      if (ref != null) images.add(ref);
    }

    for (final match in _soundRegex.allMatches(content)) {
      final ref = _buildAsset(importId, match.group(1));
      if (ref != null) audios.add(ref);
    }

    return (
      images: _deduplicate(images),
      audios: _deduplicate(audios),
    );
  }

  String? _buildAsset(String importId, String? rawValue) {
    final safeImportId = _safeRelativePath(importId, decodeUrl: false);
    if (safeImportId == null || safeImportId.contains('/')) return null;

    final safePath = _safeRelativePath(rawValue);
    if (safePath == null) return null;
    return 'anki://$safeImportId/$safePath';
  }

  String? _safeRelativePath(String? rawValue, {bool decodeUrl = true}) {
    if (rawValue == null) return null;
    var value = _decodeHtmlEntities(rawValue.trim());
    if (value.isEmpty || value.contains('\u0000')) return null;

    // Absolute, network and already-schemed references never point into the
    // imported media directory. Protocol-relative URLs are covered too.
    if (value.startsWith('/') ||
        value.startsWith(r'\') ||
        RegExp(r'^[A-Za-z]:').hasMatch(value) ||
        RegExp(r'^[A-Za-z][A-Za-z0-9+.-]*:').hasMatch(value)) {
      return null;
    }

    // Drop URL query/fragment suffixes without constructing a Uri first.
    // Uri parsing normalizes encoded `..` segments before our traversal
    // check and percent-encodes Unicode import ids, both of which are wrong
    // for Anki's literal media filenames.
    final query = value.indexOf('?');
    final fragment = value.indexOf('#');
    final suffixes = [query, fragment].where((index) => index >= 0);
    if (suffixes.isNotEmpty) {
      value = value.substring(0, suffixes.reduce((a, b) => a < b ? a : b));
    }
    if (decodeUrl) {
      try {
        // Make raw Unicode/HTML-decoded characters URI-safe without
        // double-encoding existing `%XX` sequences, then decode once.
        final encoded = Uri.encodeComponent(value).replaceAll('%25', '%');
        value = Uri.decodeComponent(encoded);
      } on ArgumentError {
        return null;
      }
    }

    value = value.replaceAll('\\', '/');
    final parts = value.split('/');
    if (parts.any((part) =>
        part.isEmpty ||
        part == '.' ||
        part == '..' ||
        part.contains('\u0000'))) {
      return null;
    }
    return parts.join('/');
  }

  String _decodeHtmlEntities(String value) {
    return value.replaceAllMapped(
      RegExp(r'&(#(?:x[0-9a-fA-F]+|[0-9]+)|amp|quot|apos|lt|gt);'),
      (match) {
        final entity = match.group(1)!;
        return switch (entity) {
          'amp' => '&',
          'quot' => '"',
          'apos' => "'",
          'lt' => '<',
          'gt' => '>',
          _ => _decodeNumericEntity(entity) ?? match.group(0)!,
        };
      },
    );
  }

  String? _decodeNumericEntity(String entity) {
    if (!entity.startsWith('#')) return null;
    final hex = entity.length > 2 && entity[1].toLowerCase() == 'x';
    final digits = entity.substring(hex ? 2 : 1);
    final codePoint = int.tryParse(digits, radix: hex ? 16 : 10);
    if (codePoint == null ||
        codePoint < 0 ||
        codePoint > 0x10ffff ||
        (codePoint >= 0xd800 && codePoint <= 0xdfff)) {
      return null;
    }
    return String.fromCharCode(codePoint);
  }

  List<String> _deduplicate(List<String> values) =>
      values.toSet().toList(growable: false);
}
