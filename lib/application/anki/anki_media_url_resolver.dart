// Package imports:
import 'package:path/path.dart' as p;

/// Resolves Anki media references to filesystem paths / URIs for the fidelity
/// WebView (deep-adaptation plan §5.1 / §5.2).
///
/// Anki cards reference media three ways:
/// - `anki://<importId>/<file>` - the app's internal scheme (see
///   `AnkiAudioResolver` / `extractMedia`); `<file>` may carry the importId
///   prefix segment.
/// - relative paths (`<img src="foo.jpg">`) - resolved against the import's
///   extracted media directory (also handled by the document `<base href>`).
/// - absolute `http(s):` / `data:` / `file:` URIs - passed through unchanged.
class AnkiMediaUrlResolver {
  const AnkiMediaUrlResolver();

  /// Resolve [ref] (an `<img src>` / `<audio src>` value) against [mediaDir]
  /// (the import's extracted media directory).
  String resolve(String ref, {required String mediaDir}) {
    if (ref.startsWith('anki://')) {
      final rest = ref.substring('anki://'.length);
      // Drop the leading importId segment if present (`anki://imp1/foo.jpg`).
      final name =
          rest.contains('/') ? rest.substring(rest.indexOf('/') + 1) : rest;
      final safe = _safeRelativePath(name);
      return safe == null ? '' : p.join(mediaDir, safe);
    }
    if (ref.startsWith('http://') ||
        ref.startsWith('https://') ||
        ref.startsWith('data:') ||
        ref.startsWith('file://')) {
      return ref;
    }
    // Relative path -> media dir.
    final safe = _safeRelativePath(ref);
    return safe == null ? '' : p.join(mediaDir, safe);
  }

  String? _safeRelativePath(String raw) {
    final normalized = raw.replaceAll('\\', '/');
    if (normalized.isEmpty ||
        normalized.startsWith('/') ||
        RegExp(r'^[A-Za-z]:').hasMatch(normalized)) return null;
    final parts = normalized.split('/');
    if (parts.any((part) => part.isEmpty || part == '..')) return null;
    return parts.join(p.separator);
  }
}
