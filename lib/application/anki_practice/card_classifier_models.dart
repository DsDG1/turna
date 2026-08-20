/// Input data for card classification.
class AnkiPracticeCardInput {
  final int cardId;
  final int notetypeId;
  final String notetypeName;
  final bool isCloze;
  final int templateOrdinal;
  final List<String> fieldNames;
  final List<String> fields;
  final String questionText;
  final String answerText;
  final String rawQuestionHtml;
  final String rawAnswerHtml;
  final String qfmt;
  final String afmt;
  final List<String> tags;
  final List<String> deckPath;
  final List<String> siblingAnswers;

  const AnkiPracticeCardInput({
    this.cardId = 0,
    this.notetypeId = 0,
    this.notetypeName = '',
    this.isCloze = false,
    this.templateOrdinal = 0,
    this.fieldNames = const <String>[],
    this.fields = const <String>[],
    this.questionText = '',
    this.answerText = '',
    this.rawQuestionHtml = '',
    this.rawAnswerHtml = '',
    this.qfmt = '',
    this.afmt = '',
    this.tags = const <String>[],
    this.deckPath = const <String>[],
    this.siblingAnswers = const <String>[],
  });
}

/// The classified shape of a practice card.
enum AnkiPracticeShape {
  vocab,
  expression,
  cloze,
  quiz,
  listen,
  typeAnswer,
  flip,
  fidelity,
}

/// Output of the classification engine.
class AnkiPracticeClassification {
  final AnkiPracticeShape shape;
  final double confidence;
  final List<String> evidence;
  final String term;
  final String meaning;
  final String? example;
  final String? pronunciation;
  final String? audioFilename;
  final String? imageFilename;
  final List<String> options;
  final int? correctIndex;
  final List<int>? correctIndices;
  final String? clozeSentence;
  final String? clozeAnswer;
  final bool looksLikeQuizButUnparsed;

  const AnkiPracticeClassification({
    required this.shape,
    required this.confidence,
    this.evidence = const <String>[],
    this.term = '',
    this.meaning = '',
    this.example,
    this.pronunciation,
    this.audioFilename,
    this.imageFilename,
    this.options = const <String>[],
    this.correctIndex,
    this.correctIndices,
    this.clozeSentence,
    this.clozeAnswer,
    this.looksLikeQuizButUnparsed = false,
  });

  @override
  String toString() =>
      'AnkiPracticeClassification(shape: $shape, conf: $confidence, term: $term, meaning: $meaning, evidence: $evidence)';
}
