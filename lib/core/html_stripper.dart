/// Converts card HTML into plain visible/speakable text.
///
/// Drops `<script>`/`<style>`/`<head>` blocks (their text is not visible card
/// content), converts `<br>` to whitespace, strips remaining tags, decodes
/// entities (numeric decimal/hex plus the common named set), and collapses
/// whitespace. The WebView text fallback (desktop / web) renders through this
/// same function, so TTS reads exactly the text the user sees.
String stripHtml(String html) {
  if (html.isEmpty) return '';
  var t = html
      .replaceAll(RegExp(r'<script[^>]*>.*?</script>', dotAll: true), '')
      .replaceAll(RegExp(r'<style[^>]*>.*?</style>', dotAll: true), '')
      .replaceAll(RegExp(r'<head[^>]*>.*?</head>', dotAll: true), '')
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAllMapped(_numericEntity, _decodeNumericEntity)
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      // &amp; decodes LAST: decoding it earlier would double-unescape
      // sequences like `&amp;lt;` (literal "&lt;") into "<".
      .replaceAll('&amp;', '&');
  return t.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Numeric character references: `&#304;` (decimal) and `&#x130;` (hex).
/// Anki exporters frequently emit these for Turkish letters (İ = U+0130),
/// which the named-entity table above cannot express.
final RegExp _numericEntity = RegExp(r'&#(?:x([0-9a-fA-F]+)|([0-9]+));');

String _decodeNumericEntity(Match m) {
  final hex = m.group(1);
  final codePoint = hex != null
      ? int.tryParse(hex, radix: 16)
      : int.tryParse(m.group(2)!);
  if (codePoint == null ||
      codePoint <= 0 ||
      codePoint > 0x10FFFF ||
      // Surrogate halves are not valid standalone characters.
      (codePoint >= 0xD800 && codePoint <= 0xDFFF)) {
    // Malformed reference: leave it verbatim instead of eating the text.
    return m.group(0)!;
  }
  return String.fromCharCode(codePoint);
}
