/// Converts card HTML into plain visible/speakable text.
///
/// Drops `<script>`/`<style>`/`<head>` blocks (their text is not visible card
/// content), converts `<br>` to whitespace, strips remaining tags, decodes the
/// common entities, and collapses whitespace. The WebView text fallback
/// (desktop / web) renders through this same function, so TTS reads exactly
/// the text the user sees.
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
