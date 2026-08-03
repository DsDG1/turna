/// Minimal renderer for Anki card templates (`qfmt` / `afmt`).
///
/// Supports the subset of Anki's mustache-like syntax needed to reproduce
/// card faces with the correct direction (notably "Basic (and reversed)"):
/// - `{{FieldName}}` — field substitution
/// - `{{cloze:Field}}` — renders the raw field value (cloze markers kept so
///   the adapter's cloze extraction still works downstream)
/// - `{{hint:Field}}` — dropped (hints are not shown in this app)
/// - `{{type:Field}}` — renders a non-answer placeholder on the question side
///   and the answer on the answer side
/// - other `filter:Field` forms — degraded to the plain field value
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

  /// Anki's inline audio marker. Fidelity HTML needs a real media element;
  /// structured adaptation can then discover the same audio through the
  /// normal media-tag extractor.
  static final _soundMarkerRegex =
      RegExp(r'\[sound:([^\]]+)\]', caseSensitive: false);

  /// Render [template] against [fields] (field name → raw value).
  ///
  /// [frontSide] is the already-rendered question side, substituted for
  /// `{{FrontSide}}` in answer templates. Pass `''` to drop the front side
  /// (used by the adapter to isolate the answer-only portion of `afmt`).
  /// Cloze rendering (fidelity track, deep-adaptation plan §5.3):
  /// - Default ([clozeOrd] null, [revealAllClozes] false): `{{cloze:Field}}`
  ///   returns the raw field with `{{cN::…}}` markers intact, so the adapter's
  ///   cloze extraction still works downstream.
  /// - [clozeOrd] set (front side): the active deletion is masked to
  ///   `[hint]` / `[…]`; other deletions are revealed.
  /// - [revealAllClozes] true (back side): every deletion is revealed.
  static String render(
    String template,
    Map<String, String> fields, {
    String frontSide = '',
    int? clozeOrd,
    bool revealAllClozes = false,
    bool revealTypeAnswers = false,
    String tags = '',
    String typeName = '',
    String deck = '',
    String subdeck = '',
    String cardName = '',
  }) {
    // Add Anki's special fields to the same context used by conditionals.
    // This makes `{{#Tags}}…{{/Tags}}` and deck-aware templates behave like
    // ordinary fields while retaining raw HTML for note fields.
    final contextFields = <String, String>{
      ...fields,
      'Tags': tags,
      'Type': typeName,
      'Deck': deck,
      'Subdeck': subdeck,
      'Card': cardName,
      'CardFlag': '',
    };
    var out = template;

    // Resolve conditional blocks (innermost first — the regex only matches
    // blocks without nested openers, so loop until no more matches).
    while (true) {
      final next = out.replaceAllMapped(_sectionRegex, (m) {
        final inverted = m.group(1) == '^';
        final name = m.group(2)!.trim();
        final body = m.group(3) ?? '';
        final empty = _isFieldEmpty(contextFields[name]);
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
            final value = contextFields[name] ?? '';
            if (clozeOrd != null) {
              return _renderSoundMarkers(_maskCloze(value, clozeOrd));
            }
            if (revealAllClozes) {
              return _renderSoundMarkers(_revealCloze(value));
            }
            return _renderSoundMarkers(value);
          case 'type':
            // The Flutter host owns grading, but the question face still gets
            // a real input so the WebView can report the learner's answer.
            if (!revealTypeAnswers) {
              return '<input id="typeans" class="anki-type-input" '
                  'data-anki-type-field="${_escapeAttribute(name)}" '
                  'autocomplete="off" autocapitalize="off" '
                  'spellcheck="false" placeholder="_____">';
            }
            final expected = _stripHtml(contextFields[name] ?? '');
            return '<span class="anki-type-answer" '
                'data-anki-type-expected="${_escapeAttribute(expected)}">'
                '${_renderSoundMarkers(contextFields[name] ?? '')}</span>';
          case 'text':
            return _stripHtml(contextFields[name] ?? '');
          case 'hint':
            return '';
          default:
            // Unknown filter — degrade to the plain field value.
            return _renderSoundMarkers(contextFields[name] ?? m.group(0)!);
        }
      }

      // Special Anki fields are present in [contextFields].
      switch (token) {
        case 'Tags':
        case 'Type':
        case 'Deck':
        case 'Subdeck':
        case 'Card':
        case 'CardFlag':
          return contextFields[token] ?? '';
      }

      // Plain field. Unknown fields degrade to empty (Anki renders unknown
      // field names as an error, but empty is friendlier for import).
      return _renderSoundMarkers(contextFields[token] ?? '');
    });

    return out;
  }

  /// Reads the expected value embedded in an answer face containing
  /// `{{type:Field}}`.
  static String? extractTypeAnswer(String html) {
    final match = RegExp(
      r'data-anki-type-expected="([^"]*)"',
      caseSensitive: false,
    ).firstMatch(html);
    if (match == null) return null;
    return match
        .group(1)!
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&');
  }

  /// A field counts as empty for `{{#Field}}` when its content has no
  /// visible text (HTML tags and whitespace stripped).
  static bool _isFieldEmpty(String? raw) {
    if (raw == null) return true;
    return raw.replaceAll(_htmlTagRegex, '').trim().isEmpty;
  }

  /// Cloze deletion marker: `{{cN::answer}}` or `{{cN::answer::hint}}`.
  static final _clozeMarkerRegex =
      RegExp(r'\{\{c(\d+)::(.*?)(?:::(.*?))?\}\}', dotAll: true);

  /// Front-side cloze: hide the active deletion (N == [ord]) as `[hint]` /
  /// `[…]`, reveal all other deletions' answers.
  static String _maskCloze(String value, int ord) {
    return value.replaceAllMapped(_clozeMarkerRegex, (m) {
      final n = int.tryParse(m.group(1) ?? '') ?? -1;
      final answer = m.group(2) ?? '';
      final hint = m.group(3);
      if (n == ord) {
        final h = (hint != null && hint.isNotEmpty) ? hint : '…';
        return '<span class="cloze">[$h]</span>';
      }
      return answer;
    });
  }

  /// Back-side cloze: reveal every deletion's answer.
  static String _revealCloze(String value) {
    return value.replaceAllMapped(_clozeMarkerRegex, (m) => m.group(2) ?? '');
  }

  static String _stripHtml(String value) {
    return value
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>', dotAll: true), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"');
  }

  static String _renderSoundMarkers(String value) {
    return value.replaceAllMapped(_soundMarkerRegex, (m) {
      final filename = m.group(1)?.trim() ?? '';
      if (filename.isEmpty) return '';
      return '<audio controls preload="none" '
          'src="${_escapeAttribute(filename)}"></audio>';
    });
  }

  static String _escapeAttribute(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('"', '&quot;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }
}
