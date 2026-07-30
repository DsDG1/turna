/// Minimal renderer for Anki card templates (`qfmt` / `afmt`).
///
/// Supports the subset of Anki's mustache-like syntax needed to reproduce
/// card faces with the correct direction (notably "Basic (and reversed)"):
/// - `{{FieldName}}` — field substitution
/// - `{{cloze:Field}}` — renders the raw field value (cloze markers kept so
///   the adapter's cloze extraction still works downstream)
/// - `{{hint:Field}}` — dropped (hints are not shown in this app)
/// - `{{type:Field}}` / other `filter:Field` forms — degraded to the plain
///   field value
/// - `{{#Field}}...{{/Field}}` — render the block only when the field is
///   non-empty (HTML tags ignored for the emptiness check)
/// - `{{^Field}}...{{/Field}}` — inverted conditional
/// - `{{FrontSide}}` — substituted with [frontSide] (answer-side templates)
/// - Special fields (`{{Tags}}`, `{{Type}}`, `{{Deck}}`, `{{Subdeck}}`,
///   `{{Card}}`, `{{Subdeck}}`) — rendered as empty
///
/// Anything unrecognized is left as-is rather than throwing — a malformed or
/// exotic template degrades to a partially-rendered string instead of
/// breaking the whole import.
///
/// Conditional blocks are resolved innermost-first but must not overlap
/// (overlapping blocks are not valid Anki templates anyway).
library;

class AnkiTemplateRenderer {
  AnkiTemplateRenderer._();

  /// Conditional block: `{{#Field}}...{{/Field}}` or `{{^Field}}...{{/Field}}`.
  static final _sectionRegex = RegExp(
    r'\{\{([#^])([^}:/]+)\}\}((?:(?!\{\{[#^]).)*?)\{\{/\2\}\}',
    dotAll: true,
  );

  /// Simple replacement: `{{Field}}`, `{{cloze:Field}}`, `{{hint:Field}}`,
  /// `{{type:Field}}` etc.
  static final _replacementRegex = RegExp(r'\{\{([^}]+)\}\}');

  static final _htmlTagRegex = RegExp(r'<[^>]+>');

  /// Render [template] against [fields] (field name → raw value).
  ///
  /// [frontSide] is the already-rendered question side, substituted for
  /// `{{FrontSide}}` in answer templates. Pass `''` to drop the front side
  /// (used by the adapter to isolate the answer-only portion of `afmt`).
  static String render(
    String template,
    Map<String, String> fields, {
    String frontSide = '',
  }) {
    var out = template;

    // Resolve conditional blocks (innermost first — the regex only matches
    // blocks without nested openers, so loop until no more matches).
    while (true) {
      final next = out.replaceAllMapped(_sectionRegex, (m) {
        final inverted = m.group(1) == '^';
        final name = m.group(2)!.trim();
        final body = m.group(3) ?? '';
        final empty = _isFieldEmpty(fields[name]);
        return (inverted ? empty : !empty) ? body : '';
      });
      if (next == out) break;
      out = next;
    }

    // Simple replacements.
    out = out.replaceAllMapped(_replacementRegex, (m) {
      final token = m.group(1)!.trim();

      if (token == 'FrontSide') return frontSide;

      final colon = token.indexOf(':');
      if (colon >= 0) {
        final filter = token.substring(0, colon).trim().toLowerCase();
        final name = token.substring(colon + 1).trim();
        switch (filter) {
          case 'cloze':
          case 'type':
          case 'text':
            return fields[name] ?? '';
          case 'hint':
            return '';
          default:
            // Unknown filter — degrade to the plain field value.
            return fields[name] ?? m.group(0)!;
        }
      }

      // Special Anki fields we don't model — render empty.
      switch (token) {
        case 'Tags':
        case 'Type':
        case 'Deck':
        case 'Subdeck':
        case 'Card':
        case 'CardFlag':
          return '';
      }

      // Plain field. Unknown fields degrade to empty (Anki renders unknown
      // field names as an error, but empty is friendlier for import).
      return fields[token] ?? '';
    });

    return out;
  }

  /// A field counts as empty for `{{#Field}}` when its content has no
  /// visible text (HTML tags and whitespace stripped).
  static bool _isFieldEmpty(String? raw) {
    if (raw == null) return true;
    return raw.replaceAll(_htmlTagRegex, '').trim().isEmpty;
  }
}
