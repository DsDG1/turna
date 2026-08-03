/// Converts card HTML into plain speakable text for TTS.
///
/// Drops `<script>`/`<style>`/`<head>` blocks (their text is not visible card
/// content), converts `<br>` to newlines, strips remaining tags, decodes the
/// common entities, and collapses whitespace. Mirrors the stripping already
/// done by the WebView text fallback so TTS reads the same text the user sees.
String stripHtml(String html) {
  if (html.isEmpty) return '';
  var t = html
      .replaceAll(RegExp(r'<script[^>]*>.*?</script>', dotAll: true), '')
      .replaceAll(RegExp(r'<style[^>]*>.*?</style>', dotAll: true), '')
      .replaceAll(RegExp(r'<head[^>]*>.*?</head>', dotAll: true), '')
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'");
  return t.replaceAll(RegExp(r'\s+'), ' ').trim();
}
