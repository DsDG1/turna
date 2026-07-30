// Package imports:
import 'package:freezed_annotation/freezed_annotation.dart';

// Project imports:
import 'package:varnamala/application/anki/anki_models.dart';
import 'package:varnamala/application/anki/anki_template_renderer.dart';
import 'package:varnamala/domain/course/interaction.dart';
import 'package:varnamala/domain/course/word_entry.dart';

part 'anki_card_adapter.freezed.dart';
part 'anki_card_adapter.g.dart';

/// How an Anki notetype maps to Varnamala card types.
enum NotetypeMappingType {
  /// Generic flip card (AnkiCard interaction). At adapt time the adapter
  /// auto-upgrades objectively-gradable cards (short answer, audio, cloze)
  /// to the matching graded interaction — see [AnkiCardAdapter.adapt].
  ankiCard,

  /// Vocabulary card → WordEntry + MultipleChoice
  wordEntry,

  /// Expression/sentence card → FillBlank
  expression,

  /// Cloze deletion → FillBlank
  cloze,

  /// Force a multiple-choice question (answer = back face, distractors from
  /// the deck)
  multipleChoice,

  /// Force a type-the-answer fill-in-the-blank (answer = back face)
  fillBlank,

  /// Alias of [fillBlank] — type the back face as the answer.
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

/// Translates Anki notes + cards into Varnamala domain objects.
///
/// Two paths:
/// 1. Heuristic (offline, default) — field name pattern matching
/// 2. AI identification (online, optional) — LLM-based notetype analysis
class AnkiCardAdapter {
  /// Cloze deletion regex: {{c1::answer}} or {{c1::answer::hint}}
  static final _clozeRegex = RegExp(r'\{\{c\d+::([^}:]+)(?:::([^}]*))?\}\}');

  /// `<img src="...">` references in Anki field HTML.
  static final _imgRegex =
      RegExp(r'<img[^>]+src="([^"]+)"[^>]*/?>', caseSensitive: false);

  /// `[sound:filename]` markers in Anki field content.
  static final _soundRegex = RegExp(r'\[sound:([^\]]+)\]');

  /// Extract media references (images + sounds) from a raw Anki field value
  /// and convert them to `anki://<importId>/<filename>` asset paths.
  static ({List<String> images, List<String> audios}) extractMedia(
    String rawField,
    String importId,
  ) {
    final images = [
      for (final m in _imgRegex.allMatches(rawField))
        'anki://$importId/${m.group(1)}',
    ];
    final audios = [
      for (final m in _soundRegex.allMatches(rawField))
        'anki://$importId/${m.group(1)}',
    ];
    return (images: images, audios: audios);
  }

  /// Adapt a single Anki note + card into Varnamala domain objects.
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
    final wordId = 'anki-$importId-n${note.id}';
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
    final backFieldValue = _stripHtml(_getRawField(note, mapping.backFieldIndex));
    final answerPool = back == backFieldValue ? distractors : frontDistractors;

    switch (mapping.type) {
      case NotetypeMappingType.wordEntry:
        return _adaptWordEntry(
          note: note,
          wordId: wordId,
          interactionId: interactionId,
          front: front,
          back: back,
          importId: importId,
          distractors: answerPool,
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
        );

      case NotetypeMappingType.multipleChoice:
        return _adaptMcq(
          wordId: wordId,
          interactionId: interactionId,
          front: front,
          back: back,
          distractors: answerPool,
          audioAssets: frontMedia.audios,
          imageAsset:
              frontMedia.images.isNotEmpty ? frontMedia.images.first : null,
          fallback: () => _adaptTypeAnswer(
            wordId: wordId,
            interactionId: interactionId,
            front: front,
            back: back,
            audioAssets: frontMedia.audios,
            imageAssets: frontMedia.images,
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
        return _autoDecide(
          note: note,
          wordId: wordId,
          interactionId: interactionId,
          front: front,
          back: back,
          frontMedia: frontMedia,
          backMedia: backMedia,
          distractors: answerPool,
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
      );
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

    // Short answer + enough distractors → MCQ; otherwise type the answer.
    return _adaptMcq(
      wordId: wordId,
      interactionId: interactionId,
      front: front,
      back: back,
      distractors: distractors,
      audioAssets: frontMedia.audios,
      imageAsset: frontMedia.images.isNotEmpty ? frontMedia.images.first : null,
      fallback: () => _adaptTypeAnswer(
        wordId: wordId,
        interactionId: interactionId,
        front: front,
        back: back,
        audioAssets: frontMedia.audios,
        imageAssets: frontMedia.images,
      ),
    );
  }

  /// Infer a NotetypeMapping from field names using heuristics.
  static NotetypeMapping inferMapping(AnkiNotetype notetype) {
    final fields = notetype.fieldNames;
    final lowerFields = fields.map((f) => f.toLowerCase()).toList();

    // Check for Cloze type first
    if (notetype.isCloze) {
      return const NotetypeMapping(
        type: NotetypeMappingType.cloze,
        frontFieldIndex: 0,
        backFieldIndex: 0,
        reason: 'Cloze notetype detected',
      );
    }

    // Check for vocabulary patterns (Term/Translation, Word/Meaning, etc.)
    final termIdx = _findFieldIndex(lowerFields, [
      'term', 'word', 'front', 'question', 'q',
      '词', '单词', '正面', '问题',
    ]);
    final transIdx = _findFieldIndex(lowerFields, [
      'translation', 'meaning', 'back', 'answer', 'a', 'definition',
      '译', '释义', '翻译', '反面', '答案',
    ]);

    if (termIdx != null && transIdx != null) {
      // Check if it looks more like a sentence/expression
      final exprIdx = _findFieldIndex(lowerFields, [
        'expression', 'sentence', 'example', 'context',
        '句', '例句', '表达',
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
      'expression', 'sentence', 'example', 'context', 'text',
      '句', '例句', '表达', '文本',
    ]);
    if (sentenceIdx != null) {
      final answerIdx = _findFieldIndex(lowerFields, [
        'meaning', 'translation', 'answer', 'back',
        '释义', '翻译', '答案', '反面',
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
      'front', 'question', 'q', 'prompt',
      '正面', '问题', '前面',
    ]) ?? 0;
    final backIdx = _findFieldIndex(lowerFields, [
      'back', 'answer', 'a', 'response',
      '反面', '答案', '后面',
    ]) ?? (frontIdx == 0 ? 1 : 0);

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
  static bool _isShortAnswer(String answer) {
    return answer.isNotEmpty &&
        answer.length <= shortAnswerMaxLength &&
        !answer.contains('\n');
  }

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
  static String stripHtmlPublic(String html) => _stripHtml(html);

  /// Split Anki's space-separated `tags` string into a clean list.
  static List<String> splitTags(String tags) {
    if (tags.isEmpty) return const [];
    return tags
        .split(' ')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
  }

  static String _stripHtml(String html) {
    return html
        .replaceAll(_soundRegex, '')
        .replaceAll(RegExp(r'<br\s*/?>'), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .trim();
  }

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
    required List<String> distractors,
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

    // Build MultipleChoice with distractors
    final options = <String>[back];
    final shuffledDistractors = List<String>.from(distractors)
      ..removeWhere((d) => d == back)
      ..shuffle();
    options.addAll(shuffledDistractors.take(3));
    // Pad with generic options if not enough distractors
    while (options.length < 4) {
      options.add('—');
    }
    options.shuffle();
    final correctIndex = options.indexOf(back);

    final interaction = Interaction.multipleChoice(
      id: interactionId,
      prompt: front,
      options: options,
      correctIndex: correctIndex,
      imageAsset: imageAsset,
      audioAssets: audioAssets,
    );

    return AnkiAdaptResult(
      wordEntry: wordEntry,
      interaction: interaction,
      wordId: wordId,
    );
  }

  /// Generic multiple-choice question (prompt = front face, answer = back
  /// face). Falls back to [fallback] when the deck cannot supply at least 3
  /// distinct distractors — no '—' padding here, a degraded question is
  /// worse than an honest type-the-answer one.
  AnkiAdaptResult _adaptMcq({
    required String wordId,
    required String interactionId,
    required String front,
    required String back,
    required List<String> distractors,
    required AnkiAdaptResult Function() fallback,
    List<String> audioAssets = const [],
    String? imageAsset,
  }) {
    if (front.isEmpty || !_isShortAnswer(back)) return fallback();

    final usable = _usableDistractors(distractors, back)..shuffle();
    if (usable.length < 3) return fallback();

    final options = <String>[back, ...usable.take(3)]..shuffle();
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
  }) {
    // Extract cloze deletion: {{c1::answer}} → blank + answer
    final match = _clozeRegex.firstMatch(text);
    if (match != null) {
      final answer = match.group(1) ?? '';
      final hint = match.group(2);
      final sentence = text.replaceAll(_clozeRegex, '_____');

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
}
