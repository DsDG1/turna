// Package imports:
import 'package:freezed_annotation/freezed_annotation.dart';

// Project imports:
import 'package:turna/application/anki/anki_media_reference_extractor.dart';
import 'package:turna/application/anki/anki_models.dart';
import 'package:turna/application/anki/anki_template_renderer.dart';
import 'package:turna/application/anki_practice/card_text.dart';
import 'package:turna/application/anki_practice/embedded_options.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/domain/course/word_entry.dart';

part 'anki_card_adapter.freezed.dart';
part 'anki_card_adapter.g.dart';

/// How an Anki notetype maps to Turna card types.
enum NotetypeMappingType {
  /// Generic flip card (AnkiCard interaction). At adapt time the adapter
  /// auto-upgrades objectively-gradable cards (short answer, audio, cloze,
  /// embedded A/B/C options, multi-option fields) to the matching graded
  /// interaction — see [AnkiCardAdapter.adapt].
  ankiCard,

  /// Vocabulary card → WordEntry + MultipleChoice
  wordEntry,

  /// Expression/sentence card → FillBlank
  expression,

  /// Cloze deletion → FillBlank
  cloze,

  /// Choice quiz layout. Prefer option fields on the note (Option A/B/C…);
  /// otherwise prompt=front, answer=back, distractors from the deck.
  ///
  /// Single vs multi-select is resolved **per card** from the prompt wording
  /// and answer key (see [AnkiCardAdapter.adapt]) — not at notetype level.
  multipleChoice,

  /// Legacy alias of [multipleChoice]. Kept for JSON / stored mappings;
  /// new inference always writes [multipleChoice]. Adapt path is identical.
  multiSelect,

  /// Force a type-the-answer fill-in-the-blank (answer = back face)
  fillBlank,

  /// Legacy alias of [fillBlank]. Kept for JSON / stored mappings.
  typeAnswer,

  /// Force a listening question (audio on the front face drives
  /// ListenAndPick / TypeTheWord)
  listenPick,
}

/// Configurable mapping decision for a single Anki notetype.
@freezed
abstract class NotetypeMapping with _$NotetypeMapping {
  const factory NotetypeMapping({
    required NotetypeMappingType type,

    /// Index of the field used as front/prompt
    @Default(0) int frontFieldIndex,

    /// Index of the field used as back/answer
    @Default(1) int backFieldIndex,

    /// Optional reason (from AI identification)
    @Default('') String reason,
  }) = _NotetypeMapping;

  factory NotetypeMapping.fromJson(Map<String, dynamic> json) =>
      _$NotetypeMappingFromJson(json);
}

/// Result of adapting a single Anki note+card pair.
class AnkiAdaptResult {
  /// Optional WordEntry (only for wordEntry mapping type)
  final WordEntry? wordEntry;

  /// The interaction to render
  final Interaction interaction;

  /// Stable word id for SRS tracking
  final String wordId;

  const AnkiAdaptResult({
    this.wordEntry,
    required this.interaction,
    required this.wordId,
  });
}

/// Translates Anki notes + cards into Turna domain objects.
///
/// Two paths:
/// 1. Heuristic (offline, default) — field name pattern matching
/// 2. AI identification (online, optional) — LLM-based notetype analysis
class AnkiCardAdapter {
  /// Cloze deletion regex: {{c1::answer}} or {{c1::answer::hint}}
  static final _clozeRegex = RegExp(
    r'\{\{c\d+::(.*?)(?:::([^}]*))?\}\}',
    dotAll: true,
  );

  /// Extract media references (images + sounds) from a raw Anki field value
  /// and convert them to `anki://<importId>/<filename>` asset paths.
  static ({List<String> images, List<String> audios}) extractMedia(
    String rawField,
    String importId,
  ) =>
      const AnkiMediaReferenceExtractor().extract(rawField, importId);

  /// Adapt a single Anki note + card into Turna domain objects.
  ///
  /// [importId] is the UUID for this import session (used in id generation).
  /// [mapping] is the notetype mapping decision (from heuristic or AI).
  /// [notetype] provides the card templates — when it carries a template for
  /// [card]'s `ord`, the front/back faces are rendered from `qfmt`/`afmt`
  /// (direction-correct for reversed/multi-template cards); otherwise the
  /// mapping's field indexes are used as before.
  /// [distractors] provides other back-face values in the same deck for MCQ
  /// generation; [frontDistractors] does the same for front-face values
  /// (reversed cards answer with the front face).
  ///
  /// When [mapping] is [NotetypeMappingType.ankiCard] the adapter auto-decides
  /// per card: cloze markers → FillBlank, front-face audio + short answer →
  /// ListenAndPick/TypeTheWord, short answer + enough distractors →
  /// MultipleChoice, short answer alone → type-the-answer FillBlank, and only
  /// cards without an objectively gradable answer stay flip cards.
  AnkiAdaptResult adapt(
    AnkiNote note,
    AnkiCardData card, {
    required String importId,
    required NotetypeMapping mapping,
    AnkiNotetype? notetype,
    List<String> distractors = const [],
    List<String> frontDistractors = const [],
  }) {
    final wordId = 'anki-$importId-c${card.id}';
    final interactionId = '$wordId-c${card.ord}';

    // Render the card faces. Templates take precedence (direction-correct);
    // the field-index mapping is the fallback for imports without template
    // bodies.
    final (rawFront, rawBack) = _renderFaces(note, card, mapping, notetype);
    final front = _stripHtml(rawFront);
    final back = _stripHtml(rawBack);
    final frontMedia = extractMedia(rawFront, importId);
    final backMedia = extractMedia(rawBack, importId);

    // Pick the distractor pool matching the face the answer came from:
    // forward cards answer with the back field, reversed cards with the
    // front field.
    final backFieldValue =
        _stripHtml(_getRawField(note, mapping.backFieldIndex));
    final answerPool = back == backFieldValue ? distractors : frontDistractors;

    // Prefer structured option fields / embedded A/B/C lines when the
    // notetype is a real MCQ (or auto path). Deck distractors alone often
    // fail on dedicated quiz decks that carry options on the note itself.
    final choiceFromNote = _tryStructuredChoice(
      note: note,
      notetype: notetype,
      wordId: wordId,
      interactionId: interactionId,
      front: front,
      back: back,
      mapping: mapping,
      audioAssets: frontMedia.audios,
      imageAsset: frontMedia.images.isNotEmpty ? frontMedia.images.first : null,
    );

    switch (mapping.type) {
      case NotetypeMappingType.wordEntry:
        return _adaptWordEntry(
          note: note,
          wordId: wordId,
          interactionId: interactionId,
          front: front,
          back: back,
          importId: importId,
          audioAssets: frontMedia.audios,
          imageAsset:
              frontMedia.images.isNotEmpty ? frontMedia.images.first : null,
        );

      case NotetypeMappingType.expression:
        return _adaptExpression(
          wordId: wordId,
          interactionId: interactionId,
          front: front,
          back: back,
          audioAssets: frontMedia.audios,
          imageAssets: frontMedia.images,
        );

      case NotetypeMappingType.cloze:
        return _adaptCloze(
          wordId: wordId,
          interactionId: interactionId,
          text: front,
          ordinal: card.ord,
        );

      case NotetypeMappingType.multipleChoice:
      case NotetypeMappingType.multiSelect:
        // Choice cardinality is a property of the current card, not of the
        // whole note type. multiSelect is a legacy notetype alias of
        // multipleChoice; both prefer structured options then flip fallback.
        if (choiceFromNote != null) return choiceFromNote;
        return _adaptMcq(
          wordId: wordId,
          interactionId: interactionId,
          front: front,
          back: back,
          distractors: answerPool,
          audioAssets: frontMedia.audios,
          imageAsset:
              frontMedia.images.isNotEmpty ? frontMedia.images.first : null,
          fallback: () => _adaptAnkiCard(
            note: note,
            wordId: wordId,
            interactionId: interactionId,
            front: front,
            back: back,
            audioAssets: [...frontMedia.audios, ...backMedia.audios],
            imageAssets: [...frontMedia.images, ...backMedia.images],
          ),
        );

      case NotetypeMappingType.fillBlank:
      case NotetypeMappingType.typeAnswer:
        return _adaptTypeAnswer(
          wordId: wordId,
          interactionId: interactionId,
          front: front,
          back: back,
          audioAssets: frontMedia.audios,
          imageAssets: frontMedia.images,
        );

      case NotetypeMappingType.listenPick:
        return _adaptListen(
          wordId: wordId,
          interactionId: interactionId,
          back: back,
          audios: frontMedia.audios,
          distractors: answerPool,
          fallback: () => _adaptAnkiCard(
            note: note,
            wordId: wordId,
            interactionId: interactionId,
            front: front,
            back: back,
            audioAssets: [...frontMedia.audios, ...backMedia.audios],
            imageAssets: [...frontMedia.images, ...backMedia.images],
          ),
        );

      case NotetypeMappingType.ankiCard:
        if (choiceFromNote != null) return choiceFromNote;
        return _autoDecide(
          note: note,
          wordId: wordId,
          interactionId: interactionId,
          front: front,
          back: back,
          frontMedia: frontMedia,
          backMedia: backMedia,
          distractors: answerPool,
          notetype: notetype,
          ordinal: card.ord,
        );
    }
  }

  /// Auto-decide the interaction type for a card whose notetype mapped to
  /// the generic flip card. Only cards with no objectively gradable answer
  /// (long/empty back face) remain flip cards.
  AnkiAdaptResult _autoDecide({
    required AnkiNote note,
    required String wordId,
    required String interactionId,
    required String front,
    required String back,
    required ({List<String> images, List<String> audios}) frontMedia,
    required ({List<String> images, List<String> audios}) backMedia,
    required List<String> distractors,
    AnkiNotetype? notetype,
    required int ordinal,
  }) {
    AnkiAdaptResult flip() => _adaptAnkiCard(
          note: note,
          wordId: wordId,
          interactionId: interactionId,
          front: front,
          back: back,
          audioAssets: [...frontMedia.audios, ...backMedia.audios],
          imageAssets: [...frontMedia.images, ...backMedia.images],
        );

    if (back.isEmpty) return flip();

    // Cloze markers in the front → fill-in-the-blank.
    if (_clozeRegex.hasMatch(front)) {
      return _adaptCloze(
        wordId: wordId,
        interactionId: interactionId,
        text: front,
        ordinal: ordinal,
      );
    }

    // Front looks like a quiz stem with A./B. markers but we failed to split
    // options or the answer cardinality was ambiguous/conflicting — do NOT
    // fall through to deck-distractor MCQ. Preserve the canonical flip card.
    if (looksLikeEmbeddedOptions(front)) {
      return flip();
    }

    if (!_isShortAnswer(back)) return flip();

    // Front-face audio + short answer → listening question (the front may be
    // audio-only, i.e. no text at all).
    if (frontMedia.audios.isNotEmpty) {
      return _adaptListen(
        wordId: wordId,
        interactionId: interactionId,
        back: back,
        audios: frontMedia.audios,
        distractors: distractors,
        fallback: flip,
      );
    }

    if (front.isEmpty) return flip();

    // Ordinary short-answer vocabulary stays Flip. Deck-mate distractors
    // are not an option contract; explicit MCQ comes from note option
    // fields / embedded A/B/C via [choiceFromNote].
    return flip();
  }

  /// Infer a NotetypeMapping from field names using heuristics.
  static NotetypeMapping inferMapping(AnkiNotetype notetype) {
    final fields = notetype.fieldNames;
    final lowerFields = fields.map((f) => f.toLowerCase()).toList();
    final nameLower = notetype.name.toLowerCase();

    // Check for Cloze type first
    if (notetype.isCloze || _nameLooksLikeCloze(nameLower)) {
      return const NotetypeMapping(
        type: NotetypeMappingType.cloze,
        frontFieldIndex: 0,
        backFieldIndex: 0,
        reason: 'Cloze notetype detected',
      );
    }

    if (_nameLooksLikeImageOcclusion(nameLower) ||
        lowerFields.any(_looksLikeOcclusionField)) {
      return const NotetypeMapping(
        type: NotetypeMappingType.ankiCard,
        frontFieldIndex: 0,
        backFieldIndex: 0,
        reason: 'Image occlusion — keep original card',
      );
    }

    // Dedicated choice notetypes (option fields on the note). Single vs
    // multi is decided per card at adapt time — notetype maps only to
    // multipleChoice so the import UI is not forced to pick one.
    final layout = detectChoiceLayout(notetype);
    if (layout != null) {
      return NotetypeMapping(
        type: NotetypeMappingType.multipleChoice,
        frontFieldIndex: layout.promptIndex,
        backFieldIndex: layout.answerIndex,
        reason: layout.multi
            ? 'Choice option fields detected (multi-select name/fields; '
                'cardinality resolved per card)'
            : 'Choice option fields detected (single/multi resolved per card)',
      );
    }

    // Notetype name hints (no structured fields, still prefer MCQ auto path).
    if (_nameLooksLikeMultiSelect(nameLower) || _nameLooksLikeMcq(nameLower)) {
      return NotetypeMapping(
        type: NotetypeMappingType.multipleChoice,
        frontFieldIndex: _findFieldIndex(lowerFields, [
              'question',
              'prompt',
              'front',
              'title',
              '问题',
              '题目',
              '题干',
              '正面',
            ]) ??
            0,
        backFieldIndex: _findFieldIndex(lowerFields, [
              'answer',
              'answers',
              'correct',
              'back',
              '答案',
              '正确',
            ]) ??
            1,
        reason: _nameLooksLikeMultiSelect(nameLower)
            ? 'Notetype name suggests choice quiz '
                '(multi-select; cardinality resolved per card)'
            : 'Notetype name suggests choice quiz '
                '(single/multi resolved per card)',
      );
    }

    // Check for vocabulary patterns (Term/Translation, Word/Meaning, etc.)
    // Avoid treating lone "answer"/"a" as translation when other fields look
    // like options — already handled above.
    final termIdx = _findFieldIndex(lowerFields, [
      'term',
      'word',
      'vocabkanji',
      'vocab',
      'front',
      'question',
      'q',
      '单词',
      '正面',
      '问题',
    ]);
    final transIdx = _findFieldIndex(lowerFields, [
      'translation',
      'meaning',
      'vocabdef',
      'defsc',
      'deftc',
      'gloss',
      'back',
      'answer',
      'definition',
      '译',
      '释义',
      '翻译',
      '反面',
      '答案',
    ]);

    if (termIdx != null && transIdx != null) {
      // Check if it looks more like a sentence/expression
      final exprIdx = _findFieldIndex(lowerFields, [
        'expression',
        'sentence',
        'example',
        'context',
        '句',
        '例句',
        '表达',
      ]);

      if (exprIdx != null) {
        return NotetypeMapping(
          type: NotetypeMappingType.expression,
          frontFieldIndex: exprIdx,
          backFieldIndex: transIdx,
          reason: 'Expression/sentence field detected',
        );
      }

      return NotetypeMapping(
        type: NotetypeMappingType.wordEntry,
        frontFieldIndex: termIdx,
        backFieldIndex: transIdx,
        reason: 'Term/Translation pattern detected',
      );
    }

    // Check for expression/sentence patterns
    final sentenceIdx = _findFieldIndex(lowerFields, [
      'expression',
      'sentence',
      'example',
      'context',
      'text',
      '句',
      '例句',
      '表达',
      '文本',
    ]);
    if (sentenceIdx != null) {
      final answerIdx = _findFieldIndex(lowerFields, [
        'meaning',
        'translation',
        'answer',
        'back',
        '释义',
        '翻译',
        '答案',
        '反面',
      ]);
      return NotetypeMapping(
        type: NotetypeMappingType.expression,
        frontFieldIndex: sentenceIdx,
        backFieldIndex: answerIdx ?? (sentenceIdx == 0 ? 1 : 0),
        reason: 'Expression/sentence field detected',
      );
    }

    // Default: generic flip card (Front/Back or first two fields)
    final frontIdx = _findFieldIndex(lowerFields, [
          'front',
          'question',
          'q',
          'prompt',
          '正面',
          '问题',
          '前面',
        ]) ??
        0;
    final backIdx = _findFieldIndex(lowerFields, [
          'back',
          'answer',
          'a',
          'response',
          '反面',
          '答案',
          '后面',
        ]) ??
        (frontIdx == 0 ? 1 : 0);

    return NotetypeMapping(
      type: NotetypeMappingType.ankiCard,
      frontFieldIndex: frontIdx,
      backFieldIndex: backIdx,
      reason: 'Default flip card mapping',
    );
  }

  // ─── Private helpers ───────────────────────────────────────────────

  /// Maximum answer length eligible for objective grading (typing or picking
  /// a long answer is not practical — those cards stay flip cards).
  static const int shortAnswerMaxLength = 60;

  /// Render the (rawFront, rawBack) faces for a card. When the notetype has
  /// a template body for [card]'s `ord`, `qfmt` renders the front and `afmt`
  /// (with `{{FrontSide}}` dropped) renders the back — this keeps reversed
  /// and multi-template cards direction-correct. Falls back to the mapping's
  /// field indexes when no template body is available.
  (String, String) _renderFaces(
    AnkiNote note,
    AnkiCardData card,
    NotetypeMapping mapping,
    AnkiNotetype? notetype,
  ) {
    final templates = notetype?.templates ?? const <AnkiTemplate>[];
    if (notetype != null &&
        card.ord >= 0 &&
        card.ord < templates.length &&
        (templates[card.ord].qfmt.isNotEmpty ||
            templates[card.ord].afmt.isNotEmpty)) {
      final fields = <String, String>{
        for (var i = 0; i < notetype.fieldNames.length; i++)
          notetype.fieldNames[i]: _getRawField(note, i),
      };
      final template = templates[card.ord];
      final rawFront = AnkiTemplateRenderer.render(template.qfmt, fields);
      // `afmt` typically embeds `{{FrontSide}}` — drop it so the back face
      // carries only the answer portion.
      final rawBack =
          AnkiTemplateRenderer.render(template.afmt, fields, frontSide: '');
      if (rawFront.trim().isNotEmpty) return (rawFront, rawBack);
    }
    return (
      _getRawField(note, mapping.frontFieldIndex),
      _getRawField(note, mapping.backFieldIndex),
    );
  }

  /// Whether [answer] is short enough to grade objectively (typed or picked).
  static bool _isShortAnswer(String answer) => CardText.isShortAnswer(answer);

  /// Unique distractor values excluding the correct [answer].
  static List<String> _usableDistractors(List<String> pool, String answer) {
    final seen = <String>{answer};
    final result = <String>[];
    for (final d in pool) {
      if (d.isEmpty || seen.contains(d)) continue;
      seen.add(d);
      result.add(d);
    }
    return result;
  }

  String _getRawField(AnkiNote note, int index) {
    if (index < 0 || index >= note.fields.length) return '';
    return note.fields[index];
  }

  /// Strip basic HTML tags from Anki field content.
  static String stripHtmlPublic(String html) => CardText.stripHtml(html);

  /// Public alias for the short-answer check, used by [AnkiRenderPolicy].
  static bool isShortAnswerPublic(String answer) => CardText.isShortAnswer(answer);

  /// Split Anki's space-separated `tags` string into a clean list.
  static List<String> splitTags(String tags) => CardText.splitTags(tags);

  static String _stripHtml(String html) => CardText.stripHtml(html);

  static int? _findFieldIndex(List<String> lowerFields, List<String> patterns) {
    for (var i = 0; i < lowerFields.length; i++) {
      for (final pattern in patterns) {
        if (lowerFields[i].contains(pattern)) return i;
      }
    }
    return null;
  }

  AnkiAdaptResult _adaptWordEntry({
    required AnkiNote note,
    required String wordId,
    required String interactionId,
    required String front,
    required String back,
    required String importId,
    List<String> audioAssets = const [],
    String? imageAsset,
  }) {
    final wordEntry = WordEntry(
      id: wordId,
      term: front,
      translation: back,
      audioAsset: audioAssets.isNotEmpty ? audioAssets.first : null,
      tags: ['anki:$importId', ...splitTags(note.tags)],
    );

    // Vocabulary stays a flip card. Sibling deck meanings are not a
    // structured option contract and must not become a formal MCQ.
    final interaction = Interaction.ankiCard(
      id: interactionId,
      front: front,
      back: back,
      audioAssets: audioAssets,
      imageAssets: imageAsset != null ? [imageAsset] : const [],
      sourceNoteId: wordId,
    );

    return AnkiAdaptResult(
      wordEntry: wordEntry,
      interaction: interaction,
      wordId: wordId,
    );
  }

  /// Generic multiple-choice question (prompt = front face, answer = back
  /// face). Falls back to [fallback] when the deck cannot supply enough
  /// distinct distractors — no '—' padding; a degraded question is worse
  /// than an honest type-the-answer one.
  ///
  /// [minDistractors] defaults to 2 (3 options total including the answer).
  AnkiAdaptResult _adaptMcq({
    required String wordId,
    required String interactionId,
    required String front,
    required String back,
    required List<String> distractors,
    required AnkiAdaptResult Function() fallback,
    int minDistractors = 2,
    List<String> audioAssets = const [],
    String? imageAsset,
  }) {
    if (front.isEmpty || !_isShortAnswer(back)) return fallback();

    final usable = _usableDistractors(distractors, back)..shuffle();
    if (usable.length < minDistractors) return fallback();

    final take = usable.length >= 3 ? 3 : usable.length;
    final options = <String>[back, ...usable.take(take)]..shuffle();
    final interaction = Interaction.multipleChoice(
      id: interactionId,
      prompt: front,
      options: options,
      correctIndex: options.indexOf(back),
      imageAsset: imageAsset,
      audioAssets: audioAssets,
    );

    return AnkiAdaptResult(interaction: interaction, wordId: wordId);
  }

  /// Type-the-answer question: the front face is the prompt, the user types
  /// the back face. Rendered as a [FillBlank] whose sentence carries an
  /// explicit `_____` marker when the front has none.
  AnkiAdaptResult _adaptTypeAnswer({
    required String wordId,
    required String interactionId,
    required String front,
    required String back,
    List<String> audioAssets = const [],
    List<String> imageAssets = const [],
  }) {
    if (front.isEmpty || !_isShortAnswer(back)) {
      return _adaptAnkiCard(
        note: null,
        wordId: wordId,
        interactionId: interactionId,
        front: front,
        back: back,
        audioAssets: audioAssets,
        imageAssets: imageAssets,
      );
    }
    final interaction = Interaction.fillBlank(
      id: interactionId,
      sentence: front.contains('_____') ? front : '$front\n_____',
      answer: back,
      audioAssets: audioAssets,
      imageAssets: imageAssets,
    );

    return AnkiAdaptResult(interaction: interaction, wordId: wordId);
  }

  /// Listening question driven by the front-face audio: pick the heard
  /// answer among distractors, or type it when the deck is too small.
  /// Falls back to [fallback] (usually the flip card) when there is no audio
  /// or the answer is not short.
  AnkiAdaptResult _adaptListen({
    required String wordId,
    required String interactionId,
    required String back,
    required List<String> audios,
    required List<String> distractors,
    required AnkiAdaptResult Function() fallback,
  }) {
    if (audios.isEmpty || !_isShortAnswer(back)) return fallback();

    final audio = audios.first;
    final usable = _usableDistractors(distractors, back)..shuffle();

    final Interaction interaction;
    if (usable.length >= 3) {
      final options = <String>[back, ...usable.take(3)]..shuffle();
      interaction = Interaction.listenAndPick(
        id: interactionId,
        audioAsset: audio,
        prompt: '',
        options: options,
        correctIndex: options.indexOf(back),
      );
    } else {
      interaction = Interaction.typeTheWord(
        id: interactionId,
        audioAsset: audio,
        prompt: '',
        expected: back,
      );
    }

    return AnkiAdaptResult(interaction: interaction, wordId: wordId);
  }

  AnkiAdaptResult _adaptExpression({
    required String wordId,
    required String interactionId,
    required String front,
    required String back,
    List<String> audioAssets = const [],
    List<String> imageAssets = const [],
  }) {
    // Create a fill-in-the-blank from the expression
    // Use the back (meaning) as the answer, front as the sentence context
    final interaction = Interaction.fillBlank(
      id: interactionId,
      sentence: front,
      answer: back,
      hint: 'Translate this expression',
      audioAssets: audioAssets,
      imageAssets: imageAssets,
    );

    return AnkiAdaptResult(
      interaction: interaction,
      wordId: wordId,
    );
  }

  AnkiAdaptResult _adaptCloze({
    required String wordId,
    required String interactionId,
    required String text,
    required int ordinal,
  }) {
    // Anki card ordinals are 0-based: ord 0 tests deletion c1. Blank only
    // the card's own deletion and reveal the others, matching the fidelity
    // renderer (`clozeOrd: card.ord + 1`) — the old firstMatch/replaceAll
    // version always quizzed c1's answer on every card of the note.
    final own = RegExp(
      '\\{\\{c${ordinal + 1}::(.*?)(?:::([^}]*))?\\}\\}',
      dotAll: true,
    );
    final match = own.firstMatch(text);
    if (match != null) {
      final answer = match.group(1) ?? '';
      final hint = match.group(2);
      final sentence = text
          .replaceAllMapped(own, (_) => '_____')
          .replaceAllMapped(_clozeRegex, (m) => m.group(1) ?? '');

      final interaction = Interaction.fillBlank(
        id: interactionId,
        sentence: _stripHtml(sentence),
        answer: _stripHtml(answer),
        hint: hint != null && hint.isNotEmpty ? _stripHtml(hint) : null,
      );

      return AnkiAdaptResult(
        interaction: interaction,
        wordId: wordId,
      );
    }

    // Fallback: no cloze pattern found, use as flip card
    return _adaptAnkiCard(
      note: null,
      wordId: wordId,
      interactionId: interactionId,
      front: _stripHtml(text),
      back: '',
    );
  }

  AnkiAdaptResult _adaptAnkiCard({
    required AnkiNote? note,
    required String wordId,
    required String interactionId,
    required String front,
    required String back,
    List<String> audioAssets = const [],
    List<String> imageAssets = const [],
  }) {
    final interaction = Interaction.ankiCard(
      id: interactionId,
      front: front,
      back: back,
      audioAssets: audioAssets,
      imageAssets: imageAssets,
      sourceNoteId: note?.id.toString(),
    );

    return AnkiAdaptResult(
      interaction: interaction,
      wordId: wordId,
    );
  }

  // ─── Structured MCQ / multi-select ────────────────────────────────

  /// Try to build MultipleChoice or MultiSelect from note option fields or
  /// A/B/C lines embedded in the front face. Returns null when the note is
  /// not a structured choice card.
  AnkiAdaptResult? _tryStructuredChoice({
    required AnkiNote note,
    required AnkiNotetype? notetype,
    required String wordId,
    required String interactionId,
    required String front,
    required String back,
    required NotetypeMapping mapping,
    List<String> audioAssets = const [],
    String? imageAsset,
  }) {
    final cardinality = _choiceCardinality(
      notetype: notetype,
      prompt: front,
    );

    // 1) Dedicated option fields on the notetype (Option A / Q_1 / 选项A …).
    if (notetype != null) {
      final layout = detectChoiceLayout(notetype);
      if (layout != null) {
        final options = <String>[];
        for (final i in layout.optionIndices) {
          final v = _stripHtml(_getRawField(note, i));
          if (v.isNotEmpty) options.add(v);
        }
        if (options.length >= 2) {
          final prompt = _stripHtml(_getRawField(note, layout.promptIndex));
          final answerRaw = _stripHtml(_getRawField(note, layout.answerIndex));
          final built = _buildChoiceInteraction(
            wordId: wordId,
            interactionId: interactionId,
            prompt: prompt.isNotEmpty ? prompt : front,
            options: options,
            answerRaw: answerRaw.isNotEmpty ? answerRaw : back,
            expectedCardinality: cardinality,
            audioAssets: audioAssets,
            imageAsset: imageAsset,
          );
          if (built != null) return built;
        }
      }
    }

    // 2) Options listed inside the front face (A. … / B. …).
    final embedded = extractEmbeddedOptions(front);
    if (embedded != null) {
      // The rendered answer face can contain FrontSide, repeated option
      // labels, explanations, and arbitrary template text. It is therefore
      // not an answer-key source. Only the explicitly mapped raw field is
      // eligible for deterministic structured grading.
      final answerRaw = _stripHtml(
        _getRawField(note, mapping.backFieldIndex),
      );
      return _buildChoiceInteraction(
        wordId: wordId,
        interactionId: interactionId,
        prompt: embedded.prompt.isNotEmpty ? embedded.prompt : front,
        options: embedded.options,
        answerRaw: answerRaw,
        expectedCardinality: cardinality,
        audioAssets: audioAssets,
        imageAsset: imageAsset,
      );
    }

    return null;
  }

  /// Build [MultipleChoice] or [MultiSelect] from explicit [options] + an
  /// answer key/text. Returns null when the answer cannot be resolved.
  AnkiAdaptResult? _buildChoiceInteraction({
    required String wordId,
    required String interactionId,
    required String prompt,
    required List<String> options,
    required String answerRaw,
    required _ChoiceCardinality expectedCardinality,
    List<String> audioAssets = const [],
    String? imageAsset,
  }) {
    if (prompt.isEmpty || options.length < 2) return null;

    final correct = parseCorrectIndices(answerRaw, options);
    if (correct.isEmpty) return null;
    if (expectedCardinality == _ChoiceCardinality.conflict) return null;

    // Explicit per-card wording is a hard constraint. Contradictory data is
    // never repaired by silently changing the question type: the canonical
    // Anki card remains available and callers fall back to it.
    if (expectedCardinality == _ChoiceCardinality.single &&
        correct.length != 1) {
      return null;
    }
    if (expectedCardinality == _ChoiceCardinality.multi && correct.length < 2) {
      return null;
    }
    // When the question does not explicitly state its cardinality, the
    // complete answer-key expression is deterministic evidence: one answer
    // means single choice, multiple answers mean multi-select. This is what
    // allows one Anki note type to safely mix both kinds card-by-card.
    final resolvedCardinality =
        expectedCardinality == _ChoiceCardinality.unknown
            ? (correct.length == 1
                ? _ChoiceCardinality.single
                : _ChoiceCardinality.multi)
            : expectedCardinality;

    if (resolvedCardinality == _ChoiceCardinality.multi) {
      final indices = correct.toList()..sort();
      return AnkiAdaptResult(
        interaction: Interaction.multiSelect(
          id: interactionId,
          prompt: prompt,
          options: options,
          correctIndices: indices,
          minSelections: indices.length,
          maxSelections: indices.length,
          imageAsset: imageAsset,
        ),
        wordId: wordId,
      );
    }

    return AnkiAdaptResult(
      interaction: Interaction.multipleChoice(
        id: interactionId,
        prompt: prompt,
        options: options,
        correctIndex: correct.first,
        imageAsset: imageAsset,
        audioAssets: audioAssets,
      ),
      wordId: wordId,
    );
  }

  /// Layout of a multi-option notetype: prompt field, answer field, option
  /// field indices, and whether the notetype is multi-select.
  @visibleForTesting
  static ChoiceFieldLayout? detectChoiceLayout(AnkiNotetype notetype) {
    final layout = EmbeddedOptionsParser.detectChoiceLayout(
      fieldNames: notetype.fieldNames,
      notetypeName: notetype.name,
    );
    if (layout == null) return null;
    return ChoiceFieldLayout(
      promptIndex: layout.promptIndex,
      answerIndex: layout.answerIndex,
      optionIndices: layout.optionIndices,
      multi: layout.multi,
    );
  }

  /// Whether a (lowercased) field name looks like an MCQ option column.
  @visibleForTesting
  static bool isOptionFieldName(String lower) =>
      EmbeddedOptionsParser.isOptionFieldName(lower);

  static bool _nameLooksLikeMcq(String nameLower) =>
      EmbeddedOptionsParser.nameLooksLikeMcq(nameLower);

  static bool _nameLooksLikeMultiSelect(String nameLower) =>
      EmbeddedOptionsParser.nameLooksLikeMultiSelect(nameLower);

  static bool _nameLooksLikeCloze(String nameLower) {
    return nameLower.contains('cloze') ||
        nameLower.contains('填空') ||
        nameLower.contains('挖空');
  }

  static bool _nameLooksLikeImageOcclusion(String nameLower) {
    return nameLower.contains('occlusion') ||
        nameLower.contains('遮图') ||
        nameLower.contains('图片遮盖') ||
        nameLower.contains('image cloze');
  }

  static bool _looksLikeOcclusionField(String lower) {
    return lower.contains('occlusion') || lower == 'mask';
  }

  static _ChoiceCardinality _choiceCardinality({
    required AnkiNotetype? notetype,
    required String prompt,
  }) {
    final c = EmbeddedOptionsParser.choiceCardinality(
      notetypeName: notetype?.name ?? '',
      prompt: prompt,
    );
    return switch (c) {
      PracticeChoiceCardinality.single => _ChoiceCardinality.single,
      PracticeChoiceCardinality.multi => _ChoiceCardinality.multi,
      PracticeChoiceCardinality.unknown => _ChoiceCardinality.unknown,
      PracticeChoiceCardinality.conflict => _ChoiceCardinality.conflict,
    };
  }

  /// Parse correct option indices from an answer field.
  @visibleForTesting
  static List<int> parseCorrectIndices(String answerRaw, List<String> options) =>
      EmbeddedOptionsParser.parseCorrectIndices(answerRaw, options);

  /// Whether [text] looks like it contains lettered options (A./B. …), even
  /// when they are jammed into one paragraph without newlines.
  static bool looksLikeEmbeddedOptions(String text) =>
      EmbeddedOptionsParser.looksLikeEmbeddedOptions(text);

  /// Extract `A. option` / `1) option` options from a front-face string.
  static ({String prompt, List<String> options})? extractEmbeddedOptions(
    String front,
  ) {
    final parsed = EmbeddedOptionsParser.extractEmbeddedOptions(front);
    if (parsed == null) return null;
    return (prompt: parsed.prompt, options: parsed.options);
  }
}

enum _ChoiceCardinality { single, multi, unknown, conflict }

/// Detected MCQ field layout on an Anki notetype.
class ChoiceFieldLayout {
  final int promptIndex;
  final int answerIndex;
  final List<int> optionIndices;
  final bool multi;

  const ChoiceFieldLayout({
    required this.promptIndex,
    required this.answerIndex,
    required this.optionIndices,
    this.multi = false,
  });
}
