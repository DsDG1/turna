class OfficialAnkiMime {
  OfficialAnkiMime._();

  static const binaryTypes = <String>{
    'image/png',
    'image/jpeg',
    'image/gif',
    'image/webp',
    'image/svg+xml',
    'audio/mpeg',
    'audio/ogg',
    'audio/wav',
    'audio/mp4',
    'video/mp4',
    'video/webm',
    'font/woff',
    'font/woff2',
    'font/ttf',
    'font/otf',
    'application/font-woff',
    'application/octet-stream',
  };

  static String mimeForName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.svg')) return 'image/svg+xml';
    if (lower.endsWith('.mp3')) return 'audio/mpeg';
    if (lower.endsWith('.ogg')) return 'audio/ogg';
    if (lower.endsWith('.wav')) return 'audio/wav';
    if (lower.endsWith('.m4a')) return 'audio/mp4';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.webm')) return 'video/webm';
    if (lower.endsWith('.css')) return 'text/css';
    if (lower.endsWith('.js')) return 'text/javascript';
    if (lower.endsWith('.html')) return 'text/html';
    if (lower.endsWith('.json')) return 'application/json';
    if (lower.endsWith('.woff')) return 'font/woff';
    if (lower.endsWith('.woff2')) return 'font/woff2';
    if (lower.endsWith('.ttf')) return 'font/ttf';
    if (lower.endsWith('.otf')) return 'font/otf';
    return 'application/octet-stream';
  }

  /// Image/audio/video/font use null (binary). Text uses utf-8.
  static String? encodingForMime(String mime) {
    final base = mime.split(';').first.trim().toLowerCase();
    if (base.startsWith('text/') ||
        base == 'application/json' ||
        base == 'application/javascript') {
      return 'utf-8';
    }
    return null;
  }

  static bool isUnknown(String mime) => mime == 'application/octet-stream';
}
