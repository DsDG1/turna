// Package imports:
import 'package:path/path.dart' as p;

// Project imports:
import 'package:varnamala/application/anki/anki_models.dart';
import 'package:varnamala/application/anki/anki_template_renderer.dart';

/// Renders Anki card faces as full HTML documents for the fidelity WebView
/// (deep-adaptation plan §5.1).
///
/// Pipeline: notetype templates (`qfmt`/`afmt`) + raw note fields ->
/// `AnkiTemplateRenderer.render` (with cloze masking / FrontSide) -> `wrap`
/// (inject notetype `css` + a base reset + a `<base href>` for media).
///
/// The output is a complete `<!DOCTYPE html>` document the WebView loads
/// directly; the app's SRS buttons handle grading (no in-page JS).
class AnkiCardHtmlRenderer {
  const AnkiCardHtmlRenderer();

  /// Render the question face (`qfmt`) with the active cloze deletion masked.
  String renderFront({
    required AnkiNotetype notetype,
    required AnkiNote note,
    required AnkiCardData card,
    String mediaBasePath = '',
  }) {
    final template = _templateFor(notetype, card.ord);
    final fields = _fieldMap(notetype, note);
    final body = AnkiTemplateRenderer.render(
      template.qfmt,
      fields,
      clozeOrd: notetype.isCloze ? card.ord + 1 : null,
      revealTypeAnswers: false,
      tags: note.tags,
      typeName: notetype.name,
      cardName: template.name,
    );
    return _wrap(
      css: notetype.css,
      body: body,
      mediaBasePath: mediaBasePath,
    );
  }

  /// Render the answer face (`afmt`) with `{{FrontSide}}` prepended (the
  /// rendered question) and all cloze deletions revealed.
  String renderBack({
    required AnkiNotetype notetype,
    required AnkiNote note,
    required AnkiCardData card,
    String mediaBasePath = '',
  }) {
    final template = _templateFor(notetype, card.ord);
    final fields = _fieldMap(notetype, note);
    final frontBody = AnkiTemplateRenderer.render(
      template.qfmt,
      fields,
      clozeOrd: notetype.isCloze ? card.ord + 1 : null,
      tags: note.tags,
      typeName: notetype.name,
      cardName: template.name,
    );
    final body = AnkiTemplateRenderer.render(
      template.afmt,
      fields,
      frontSide: frontBody,
      revealAllClozes: notetype.isCloze,
      revealTypeAnswers: true,
      tags: note.tags,
      typeName: notetype.name,
      cardName: template.name,
    );
    return _wrap(
      css: notetype.css,
      body: body,
      mediaBasePath: mediaBasePath,
    );
  }

  /// Return the plain answer behind the first `{{type:Field}}` token in the
  /// selected card template, or null for ordinary cards.
  String? typeAnswer({
    required AnkiNotetype notetype,
    required AnkiNote note,
    required AnkiCardData card,
  }) {
    final template = _templateFor(notetype, card.ord);
    final fields = _fieldMap(notetype, note);
    final match = RegExp(r'\{\{type:([^}]+)\}\}', caseSensitive: false)
        .firstMatch('${template.qfmt} ${template.afmt}');
    if (match == null) return null;
    final value = fields[match.group(1)!.trim()];
    if (value == null) return null;
    return value
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .trim();
  }

  /// Pick the template for [ord] (which card of a multi-template notetype).
  /// Falls back to a generic Front/Back flip when templates were not captured.
  AnkiTemplate _templateFor(AnkiNotetype nt, int ord) {
    if (nt.templates.isEmpty) {
      final f0 = nt.fieldNames.isNotEmpty ? nt.fieldNames[0] : 'Front';
      final f1 = nt.fieldNames.length > 1 ? nt.fieldNames[1] : 'Back';
      return AnkiTemplate(
        name: '',
        qfmt: '{{$f0}}',
        afmt: '{{$f0}}<hr id="answer">{{$f1}}',
      );
    }
    return nt.templates[ord.clamp(0, nt.templates.length - 1)];
  }

  /// Map notetype field names -> note field values (raw HTML preserved).
  Map<String, String> _fieldMap(AnkiNotetype nt, AnkiNote note) {
    final m = <String, String>{};
    for (var i = 0; i < nt.fieldNames.length && i < note.fields.length; i++) {
      m[nt.fieldNames[i]] = note.fields[i];
    }
    return m;
  }

  /// Wrap [body] in a full HTML document with the notetype [css] and a media
  /// `<base href>` so relative `<img src>` / `<audio src>` resolve.
  String _wrap({
    required String css,
    required String body,
    required String mediaBasePath,
  }) =>
      wrapBody(body, css: css, mediaBasePath: mediaBasePath);

  /// Wrap a pre-rendered [body] (e.g. cached decrypted HTML from the "智能去解密"
  /// path) in a full document with the notetype [css] + base reset. Used by the
  /// review path to serve cached HTML without re-running the template JS.
  static String wrapBody(String body,
      {String css = '', String mediaBasePath = ''}) {
    final base = mediaBasePath.isEmpty
        ? ''
        : '<base href="${_fileUri(mediaBasePath)}/">';
    final safeBody = _sanitizeResourceUrls(body);
    final safeCss = _sanitizeResourceUrls(css);
    return '<!DOCTYPE html><html><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width, initial-scale=1.0">'
        '<meta http-equiv="Content-Security-Policy" content="default-src '
        "'none'; img-src file: data: blob:; media-src file: data: blob:; "
        "font-src file: data:; style-src 'unsafe-inline'; "
        "script-src 'unsafe-inline'; connect-src 'none'; "
        "frame-src 'none'; object-src 'none'\">"
        '$base<style>$_baseCss\n$safeCss</style></head>'
        '<body>$safeBody</body></html>';
  }

  /// Keep relative Anki media references, data/blob URLs and fragments, but
  /// neutralize absolute/network/javascript resource URLs supplied by an
  /// untrusted template. The trusted `<base>` above is the only file root.
  static String _sanitizeResourceUrls(String input) {
    final attributes = RegExp(
      r'''(\s(?:src|href|action)\s*=\s*)(["'])([^"']*)\2''',
      caseSensitive: false,
    );
    var result = input.replaceAll(
      RegExp(r'<base\b[^>]*>', caseSensitive: false),
      '',
    );
    result = result.replaceAllMapped(attributes, (match) {
      final value = match.group(3)!.trim();
      if (!_isUnsafeResourceUrl(value)) return match.group(0)!;
      return '${match.group(1)}${match.group(2)}about:blank${match.group(2)}';
    });
    final cssUrls = RegExp(
      r'''url\(\s*(["']?)([^)"']+)\1\s*\)''',
      caseSensitive: false,
    );
    result = result.replaceAllMapped(cssUrls, (match) {
      final value = match.group(2)!.trim();
      return _isUnsafeResourceUrl(value)
          ? 'url("about:blank")'
          : match.group(0)!;
    });
    return result;
  }

  static bool _isUnsafeResourceUrl(String value) {
    final lower = value.toLowerCase();
    if (lower.isEmpty ||
        lower.startsWith('#') ||
        lower.startsWith('data:') ||
        lower.startsWith('blob:')) {
      return false;
    }
    return lower.startsWith('/') ||
        lower.startsWith(r'\') ||
        lower.startsWith('//') ||
        RegExp(r'^[a-z][a-z0-9+.-]*:', caseSensitive: false).hasMatch(lower);
  }

  /// Minimal reset so cards are readable before the notetype css applies;
  /// also styles the `.cloze` masking spans emitted by AnkiTemplateRenderer.
  static const _baseCss =
      'body{margin:12px;font-family:-apple-system,system-ui,sans-serif;'
      'font-size:18px;line-height:1.4;word-wrap:break-word;'
      '-webkit-text-size-adjust:100%;}'
      'img{max-width:100%;height:auto;}'
      '.cloze{color:#888;font-weight:bold;}'
      '.anki-type-answer{display:inline-block;min-width:8em;'
      'border-bottom:2px solid currentColor;vertical-align:bottom;}'
      '.anki-type-input{display:inline-block;min-width:12em;'
      'padding:8px;border:1px solid #aaa;border-radius:6px;'
      'font:inherit;color:inherit;background:transparent;}'
      'hr#answer{border:1px solid #ddd;border-bottom:none;margin:12px 0;}';

  /// Convert a filesystem path to a `file://` URI (handles backslashes on
  /// Windows so the WebView resolves the `<base href>` correctly).
  static String _fileUri(String path) {
    return Uri.file(path, windows: p.separator == '\\').toString();
  }
}
