// Package imports:
import 'package:freezed_annotation/freezed_annotation.dart';

// Project imports:
import 'package:varnamala/application/anki/anki_models.dart';
import 'package:varnamala/domain/course/interaction.dart';
import 'package:varnamala/domain/course/word_entry.dart';

part 'anki_card_adapter.freezed.dart';
part 'anki_card_adapter.g.dart';

/// How an Anki notetype maps to Varnamala card types.
enum NotetypeMappingType {
  /// Generic flip card (AnkiCard interaction)
  ankiCard,

  /// Vocabulary card → WordEntry + MultipleChoice
  wordEntry,

  /// Expression/sentence card → FillBlank
  expression,

  /// Cloze deletion → FillBlank
  cloze,
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
  /// [distractors] provides other terms in the same deck for MCQ generation.
  AnkiAdaptResult adapt(
    AnkiNote note,
    AnkiCardData card, {
    required String importId,
    required NotetypeMapping mapping,
    List<String> distractors = const [],
  }) {
    final wordId = 'anki-$importId-n${note.id}';
    final interactionId = '$wordId-c${card.ord}';

    // Get field values safely (raw first for media extraction, then stripped)
    final rawFront = _getRawField(note, mapping.frontFieldIndex);
    final rawBack = _getRawField(note, mapping.backFieldIndex);
    final front = _stripHtml(rawFront);
    final back = _stripHtml(rawBack);
    final frontMedia = extractMedia(rawFront, importId);
    final backMedia = extractMedia(rawBack, importId);

    switch (mapping.type) {
      case NotetypeMappingType.wordEntry:
        return _adaptWordEntry(
          note: note,
          wordId: wordId,
          interactionId: interactionId,
          front: front,
          back: back,
          importId: importId,
          distractors: distractors,
          audioAsset:
              frontMedia.audios.isNotEmpty ? frontMedia.audios.first : null,
        );

      case NotetypeMappingType.expression:
        return _adaptExpression(
          wordId: wordId,
          interactionId: interactionId,
          front: front,
          back: back,
        );

      case NotetypeMappingType.cloze:
        return _adaptCloze(
          wordId: wordId,
          interactionId: interactionId,
          text: front,
        );

      case NotetypeMappingType.ankiCard:
        return _adaptAnkiCard(
          note: note,
          wordId: wordId,
          interactionId: interactionId,
          front: front,
          back: back,
          audioAssets: [...frontMedia.audios, ...backMedia.audios],
          imageAssets: [...frontMedia.images, ...backMedia.images],
        );
    }
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

  String _getRawField(AnkiNote note, int index) {
    if (index < 0 || index >= note.fields.length) return '';
    return note.fields[index];
  }

  /// Strip basic HTML tags from Anki field content.
  static String stripHtmlPublic(String html) => _stripHtml(html);

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
    String? audioAsset,
  }) {
    final wordEntry = WordEntry(
      id: wordId,
      term: front,
      translation: back,
      audioAsset: audioAsset,
      tags: ['anki:$importId'],
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
    );

    return AnkiAdaptResult(
      wordEntry: wordEntry,
      interaction: interaction,
      wordId: wordId,
    );
  }

  AnkiAdaptResult _adaptExpression({
    required String wordId,
    required String interactionId,
    required String front,
    required String back,
  }) {
    // Create a fill-in-the-blank from the expression
    // Use the back (meaning) as the answer, front as the sentence context
    final interaction = Interaction.fillBlank(
      id: interactionId,
      sentence: front,
      answer: back,
      hint: 'Translate this expression',
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
