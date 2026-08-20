import 'package:turna/application/anki_practice/card_classifier_models.dart';
import 'package:turna/application/anki_practice/card_text.dart';
import 'package:turna/application/anki_practice/embedded_options.dart';

/// Pure-Dart heuristic card classifier.
/// Translates raw Anki card data into a structured [AnkiPracticeClassification].
class AnkiPracticeCardClassifier {
  static final RegExp _clozeRegex = RegExp(
    r'\{\{c\d+::(.*?)(?:::([^}]*))?\}\}',
    dotAll: true,
  );

  static final RegExp _complexHtmlTagRegex = RegExp(
    r'<(table|svg|audio|video|iframe|canvas|object|embed|form|input|button)\b',
    caseSensitive: false,
  );

  static final RegExp _scriptOrEventRegex = RegExp(
    r'<script\b|on[a-z]+\s*=|javascript:',
    caseSensitive: false,
  );

  static final RegExp _typeAnswerTemplateRegex = RegExp(
    r'\{\{type:',
    caseSensitive: false,
  );

  /// Classifies a card input into an [AnkiPracticeClassification].
  static AnkiPracticeClassification classify(AnkiPracticeCardInput input) {
    final combinedHtml = [
      input.rawQuestionHtml,
      input.rawAnswerHtml,
      input.qfmt,
      input.afmt,
      input.questionText,
      input.answerText,
      ...input.fields,
    ].join(' ');

    // ── 1. Fidelity Forced ───────────────────────────────────────────────
    if (_scriptOrEventRegex.hasMatch(combinedHtml) ||
        _typeAnswerTemplateRegex.hasMatch(combinedHtml)) {
      return const AnkiPracticeClassification(
        shape: AnkiPracticeShape.fidelity,
        confidence: 1.0,
        evidence: ['js_or_type_answer'],
      );
    }

    // ── Extract Media & Stripped Texts ──────────────────────────────────
    final frontAudio = CardText.extractAudioFilename(
      '${input.rawQuestionHtml} ${input.questionText} ${input.qfmt}',
    );
    final backAudio = CardText.extractAudioFilename(
      '${input.rawAnswerHtml} ${input.answerText} ${input.afmt}',
    );
    final audioFile = frontAudio ?? backAudio;

    final frontImage = CardText.extractImageFilename(
      '${input.rawQuestionHtml} ${input.questionText} ${input.qfmt}',
    );
    final backImage = CardText.extractImageFilename(
      '${input.rawAnswerHtml} ${input.answerText} ${input.afmt}',
    );
    final imageFile = frontImage ?? backImage;

    final question = input.questionText.isNotEmpty
        ? CardText.stripHtml(input.questionText)
        : (input.rawQuestionHtml.isNotEmpty
            ? CardText.stripHtml(input.rawQuestionHtml)
            : (input.fields.isNotEmpty ? CardText.stripHtml(input.fields[0]) : ''));

    final answer = input.answerText.isNotEmpty
        ? CardText.stripHtml(input.answerText)
        : (input.rawAnswerHtml.isNotEmpty
            ? CardText.stripHtml(input.rawAnswerHtml)
            : (input.fields.length > 1 ? CardText.stripHtml(input.fields[1]) : ''));

    final (pronunciation, example) = _extractAuxiliary(input);

    // ── 2. Complex HTML Check ───────────────────────────────────────────
    if (_complexHtmlTagRegex.hasMatch(combinedHtml)) {
      return AnkiPracticeClassification(
        shape: AnkiPracticeShape.fidelity,
        confidence: 0.95,
        evidence: const ['complex_html'],
        term: question,
        meaning: answer,
        audioFilename: audioFile,
        imageFilename: imageFile,
      );
    }

    // ── 3. Cloze Deletion ───────────────────────────────────────────────
    final isClozeCard = input.isCloze || _clozeRegex.hasMatch(input.rawQuestionHtml) || _clozeRegex.hasMatch(question);
    if (isClozeCard) {
      final textForCloze = input.rawQuestionHtml.isNotEmpty ? input.rawQuestionHtml : question;
      final clozeMatch = _clozeRegex.firstMatch(textForCloze);
      if (clozeMatch != null) {
        final answerPart = clozeMatch.group(1)?.trim() ?? '';
        final sentencePart = textForCloze.replaceAll(_clozeRegex, '_____');
        return AnkiPracticeClassification(
          shape: AnkiPracticeShape.cloze,
          confidence: 0.95,
          evidence: const ['cloze_marker'],
          term: question,
          meaning: answer,
          clozeAnswer: CardText.stripHtml(answerPart),
          clozeSentence: CardText.stripHtml(sentencePart),
          audioFilename: audioFile,
          imageFilename: imageFile,
        );
      }
      // If cloze was declared but we couldn't parse the deletion markers
      return AnkiPracticeClassification(
        shape: AnkiPracticeShape.fidelity,
        confidence: 0.85,
        evidence: const ['cloze_unparsed'],
        term: question,
        meaning: answer,
      );
    }

    // ── 4. Embedded Options (Quiz) ──────────────────────────────────────
    if (EmbeddedOptionsParser.looksLikeEmbeddedOptions(question)) {
      final parsed = EmbeddedOptionsParser.extractEmbeddedOptions(question);
      if (parsed != null && parsed.options.length >= 2) {
        final cardinality = EmbeddedOptionsParser.choiceCardinality(
          notetypeName: input.notetypeName,
          prompt: parsed.prompt,
        );
        final correct = EmbeddedOptionsParser.parseCorrectIndices(
          answer,
          parsed.options,
        );

        if (correct.isNotEmpty && cardinality != PracticeChoiceCardinality.conflict) {
          final isMulti = cardinality == PracticeChoiceCardinality.multi ||
              (cardinality == PracticeChoiceCardinality.unknown && correct.length > 1);

          if (isMulti && correct.length >= 2) {
            return AnkiPracticeClassification(
              shape: AnkiPracticeShape.quiz,
              confidence: 0.92,
              evidence: const ['embedded_options_multi'],
              term: parsed.prompt.isNotEmpty ? parsed.prompt : question,
              meaning: answer,
              options: parsed.options,
              correctIndices: correct,
              audioFilename: audioFile,
              imageFilename: imageFile,
            );
          } else if (!isMulti && correct.length == 1) {
            return AnkiPracticeClassification(
              shape: AnkiPracticeShape.quiz,
              confidence: 0.95,
              evidence: const ['embedded_options_single'],
              term: parsed.prompt.isNotEmpty ? parsed.prompt : question,
              meaning: answer,
              options: parsed.options,
              correctIndex: correct.first,
              audioFilename: audioFile,
              imageFilename: imageFile,
            );
          }
        }
      }
      // Iron law: If it looks like embedded options but failed to parse/align cleanly -> fidelity
      return AnkiPracticeClassification(
        shape: AnkiPracticeShape.fidelity,
        confidence: 0.90,
        evidence: const ['embedded_options_unparsed'],
        term: question,
        meaning: answer,
        looksLikeQuizButUnparsed: true,
      );
    }

    // ── 5. Front Audio + Short Answer (Listen) ──────────────────────────
    if (frontAudio != null && CardText.isShortAnswer(answer)) {
      return AnkiPracticeClassification(
        shape: AnkiPracticeShape.listen,
        confidence: 0.92,
        evidence: const ['front_audio_short_answer'],
        term: question,
        meaning: answer,
        pronunciation: pronunciation,
        example: example,
        audioFilename: frontAudio,
        imageFilename: imageFile,
      );
    }

    // ── 6. Vocabulary (Short Pair) ──────────────────────────────────────
    final isShortFront = CardText.isShortAnswer(question);
    final isShortBack = CardText.isShortAnswer(answer);
    final frontIsSentence = CardText.isSentence(question);
    final backIsSentence = CardText.isSentence(answer);

    if (isShortFront && isShortBack && !frontIsSentence && !backIsSentence && question.isNotEmpty && answer.isNotEmpty) {
      final nameEvidence = _hasVocabFieldNames(input.fieldNames);
      return AnkiPracticeClassification(
        shape: AnkiPracticeShape.vocab,
        confidence: nameEvidence ? 0.92 : 0.85,
        evidence: [nameEvidence ? 'short_pair_vocab_named' : 'short_pair_vocab'],
        term: question,
        meaning: answer,
        pronunciation: pronunciation,
        example: example,
        audioFilename: audioFile,
        imageFilename: imageFile,
      );
    }

    // ── 7. Expression ───────────────────────────────────────────────────
    if (frontIsSentence && isShortBack && question.isNotEmpty && answer.isNotEmpty) {
      return AnkiPracticeClassification(
        shape: AnkiPracticeShape.expression,
        confidence: 0.88,
        evidence: const ['sentence_plus_meaning'],
        term: question,
        meaning: answer,
        pronunciation: pronunciation,
        example: example,
        audioFilename: audioFile,
        imageFilename: imageFile,
      );
    }

    // ── 8. Typing / Flip / Fidelity ─────────────────────────────────────
    if (isShortBack && question.isNotEmpty) {
      final usableDistractors = input.siblingAnswers
          .where((s) => s.trim().isNotEmpty && s.toLowerCase() != answer.toLowerCase())
          .toSet()
          .toList();
      if (usableDistractors.length >= 2) {
        return AnkiPracticeClassification(
          shape: AnkiPracticeShape.vocab,
          confidence: 0.80,
          evidence: const ['short_answer_with_siblings'],
          term: question,
          meaning: answer,
          pronunciation: pronunciation,
          example: example,
          audioFilename: audioFile,
          imageFilename: imageFile,
        );
      } else {
        return AnkiPracticeClassification(
          shape: AnkiPracticeShape.typeAnswer,
          confidence: 0.75,
          evidence: const ['short_answer_type'],
          term: question,
          meaning: answer,
          pronunciation: pronunciation,
          example: example,
          audioFilename: audioFile,
          imageFilename: imageFile,
        );
      }
    }

    if (question.isNotEmpty || answer.isNotEmpty) {
      return AnkiPracticeClassification(
        shape: AnkiPracticeShape.flip,
        confidence: 0.70,
        evidence: const ['general_flip'],
        term: question,
        meaning: answer,
        pronunciation: pronunciation,
        example: example,
        audioFilename: audioFile,
        imageFilename: imageFile,
      );
    }

    return const AnkiPracticeClassification(
      shape: AnkiPracticeShape.fidelity,
      confidence: 0.50,
      evidence: ['empty_or_unknown'],
    );
  }

  static bool _hasVocabFieldNames(List<String> fieldNames) {
    final lower = fieldNames.map((f) => f.toLowerCase().trim()).toList();
    final hasFront = lower.any((f) =>
        f == 'front' ||
        f == 'word' ||
        f == 'term' ||
        f == 'target' ||
        f == '正面' ||
        f == '单词' ||
        f == '词');
    final hasBack = lower.any((f) =>
        f == 'back' ||
        f == 'meaning' ||
        f == 'translation' ||
        f == 'native' ||
        f == '反面' ||
        f == '释义' ||
        f == '翻译');
    return hasFront && hasBack;
  }

  static (String? pronunciation, String? example) _extractAuxiliary(
    AnkiPracticeCardInput input,
  ) {
    String? pronunciation;
    String? example;
    for (var i = 0; i < input.fieldNames.length && i < input.fields.length; i++) {
      final name = input.fieldNames[i].toLowerCase();
      final val = CardText.stripHtml(input.fields[i]);
      if (val.isEmpty) continue;
      if (name.contains('pronun') || name.contains('ipa') || name.contains('发音') || name.contains('拼音')) {
        pronunciation ??= val;
      } else if (name.contains('example') || name.contains('例句') || name.contains('context')) {
        example ??= val;
      }
    }
    return (pronunciation, example);
  }
}
