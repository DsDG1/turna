// Project imports:
import 'package:turna/application/anki/anki_card_adapter.dart';
import 'package:turna/application/anki/anki_models.dart';

/// How a card should be rendered in the review session
/// (deep-adaptation plan §3.2.1 / §3.2.3).
enum AnkiRenderMode {
  /// WebView HTML flip (preserves templates/CSS/JS/media). Used for cards the
  /// structured track can't faithfully grade - complex templates, JS, embedded
  /// options that don't parse, long answers, image/table content.
  fidelity,

  /// Native [Interaction] (MultipleChoice / MultiSelect / FillBlank /
  /// type-the-answer / listening) - objectively gradable via the adapter.
  structured,

  /// Default before the policy runs; treated as structured by the assembler
  /// when no decision is made.
  hybrid,
}

/// Per-card fidelity-vs-structured decision (deep-adaptation plan §3.2.3).
///
/// Pure function - no DB, no IO - so it unit-tests cleanly. The deck assembler
/// calls this at import to set `anki_cards_meta.render_mode` and to decide
/// whether to build a structured [Interaction] or leave the card for the
/// fidelity review path (which renders it from the NoteStore on demand).
///
/// Rules (in priority order):
/// 1. Notetype templates contain `<script>` / `on*=` -> fidelity (JS needs the
///    WebView; structured stripping would drop the behaviour).
/// 2. `{{type:...}}` answer fields -> fidelity (the native structured track
///    does not implement Anki's interactive type-answer widget).
/// 3. Cloze notetype -> structured (adapter extracts/masks cloze deletions).
/// 4. Explicit option-field notetypes (multipleChoice / multiSelect) ->
///    structured.
/// 5. Embedded A/B/C options that PARSE -> structured (adapter builds a choice
///    interaction).
/// 6. Complex HTML (`<img>` / `<table>` / `<audio>` / ...) in a face ->
///    fidelity (preserve formatting the structured strip would lose).
/// 7. `looksLikeEmbeddedOptions` but can't parse -> fidelity (铁律: never fake
///    an MCQ from deck distractors; show the original card).
/// 8. wordEntry / ankiCard with a short answer and a non-empty front ->
///    structured (MCQ / type-the-answer).
/// 9. Otherwise (long answer, empty front) -> fidelity (flip shows full HTML).
class AnkiRenderPolicy {
  const AnkiRenderPolicy();

  /// `<script>` tag or inline `on*=` event handler.
  static final _jsRegex =
      RegExp(r'<script|\son[a-z]+\s*=', caseSensitive: false);

  static final _typeAnswerRegex =
      RegExp(r'\{\{\s*type\s*:', caseSensitive: false);

  /// Block-level / media HTML that the structured strip would flatten.
  static final _complexHtmlRegex = RegExp(
    r'<(?:img|table|svg|audio|video|iframe|canvas)\b',
    caseSensitive: false,
  );

  AnkiRenderMode decide({
    required AnkiNotetype notetype,
    required AnkiNote note,
    required AnkiCardData card,
    required NotetypeMapping mapping,
  }) {
    // 1. JS in any template -> fidelity.
    if (_notetypeHasJs(notetype)) return AnkiRenderMode.fidelity;

    // 2. Anki's type-answer filter is interactive; rendering its field as
    // plain text would make the card look gradable while silently removing
    // the answer-entry behaviour.
    if (_notetypeHasTypeAnswer(notetype)) return AnkiRenderMode.fidelity;

    final rawFront = _field(note, mapping.frontFieldIndex);
    final rawBack = _field(note, mapping.backFieldIndex);
    final front = AnkiCardAdapter.stripHtmlPublic(rawFront);
    final back = AnkiCardAdapter.stripHtmlPublic(rawBack);
    final template = _templateFor(notetype, card.ord);

    // 2. Cloze -> structured FillBlank.
    if (notetype.isCloze) return AnkiRenderMode.structured;

    // 3. Explicit option-field notetypes -> structured.
    if (mapping.type == NotetypeMappingType.multipleChoice ||
        mapping.type == NotetypeMappingType.multiSelect) {
      return AnkiRenderMode.structured;
    }

    // 4. Embedded options that parse -> structured.
    if (AnkiCardAdapter.extractEmbeddedOptions(front) != null) {
      return AnkiRenderMode.structured;
    }

    // 5. Complex HTML (images/tables/audio/...) -> fidelity.
    if (_complexHtmlRegex.hasMatch(rawFront) ||
        _complexHtmlRegex.hasMatch(rawBack) ||
        (template != null &&
            (_complexHtmlRegex.hasMatch(template.qfmt) ||
                _complexHtmlRegex.hasMatch(template.afmt)))) {
      return AnkiRenderMode.fidelity;
    }

    // 6. Looks like a quiz stem with A./B./C. markers but won't parse ->
    //    fidelity (铁律: don't fabricate an MCQ from deck distractors).
    if (AnkiCardAdapter.looksLikeEmbeddedOptions(front)) {
      return AnkiRenderMode.fidelity;
    }

    // 7. wordEntry / ankiCard with a short answer -> structured.
    if ((mapping.type == NotetypeMappingType.wordEntry ||
            mapping.type == NotetypeMappingType.ankiCard) &&
        AnkiCardAdapter.isShortAnswerPublic(back) &&
        front.isNotEmpty) {
      return AnkiRenderMode.structured;
    }

    // 8. Long answer / empty front -> fidelity.
    return AnkiRenderMode.fidelity;
  }

  static bool _notetypeHasJs(AnkiNotetype nt) {
    for (final t in nt.templates) {
      if (_jsRegex.hasMatch(t.qfmt) || _jsRegex.hasMatch(t.afmt)) return true;
    }
    return false;
  }

  static bool _notetypeHasTypeAnswer(AnkiNotetype nt) {
    for (final t in nt.templates) {
      if (_typeAnswerRegex.hasMatch(t.qfmt) ||
          _typeAnswerRegex.hasMatch(t.afmt)) {
        return true;
      }
    }
    return false;
  }

  static AnkiTemplate? _templateFor(AnkiNotetype nt, int ord) {
    if (ord < 0 || ord >= nt.templates.length) return null;
    return nt.templates[ord];
  }

  static String _field(AnkiNote note, int index) {
    if (index < 0 || index >= note.fields.length) return '';
    return note.fields[index];
  }
}
