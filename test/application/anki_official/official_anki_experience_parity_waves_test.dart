import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/engine/official_anki_course_grades_bridge.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_practice/card_classifier.dart';
import 'package:turna/application/anki_practice/card_classifier_models.dart';
import 'package:turna/domain/course/interaction.dart';

class _FakeGradesBridge implements OfficialAnkiCourseGradesBridge {
  final List<({String wordId, String rating})> answered = [];

  @override
  Future<bool> answerOfficialCard({
    required String wordId,
    required String rating,
    int millisecondsTaken = 0,
  }) async {
    answered.add((wordId: wordId, rating: rating));
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('P1 & P2: Practice Classifier and Media / Typing Extraction', () {
    test('classifier extracts audio and image tags and categorizes quiz', () {
      const input = AnkiPracticeCardInput(
        cardId: 101,
        rawQuestionHtml:
            'What is this? [sound:test_audio.mp3] <img src="test_img.png"><br>A. Cat<br>B. Dog',
        rawAnswerHtml: 'A',
      );
      final c = AnkiPracticeCardClassifier.classify(input);
      expect(c.shape, AnkiPracticeShape.quiz);
      expect(c.audioFilename, 'test_audio.mp3');
      expect(c.imageFilename, 'test_img.png');
      expect(c.options, containsAll(['Cat', 'Dog']));
      expect(c.correctIndex, 0);
    });

    test('classifier parses cloze deletion cleanly', () {
      const input = AnkiPracticeCardInput(
        cardId: 102,
        rawQuestionHtml: 'The {{c1::quick}} brown fox jumps',
        rawAnswerHtml: 'quick',
      );
      final c = AnkiPracticeCardClassifier.classify(input);
      expect(c.shape, AnkiPracticeShape.cloze);
      expect(c.clozeAnswer, 'quick');
      expect(c.clozeSentence, contains('_____'));
    });

    test('complex javascript or type-answer forces fidelity', () {
      const input = AnkiPracticeCardInput(
        cardId: 103,
        rawQuestionHtml: '<script>console.log("hello");</script>Front',
        rawAnswerHtml: 'Back',
      );
      final c = AnkiPracticeCardClassifier.classify(input);
      expect(c.shape, AnkiPracticeShape.fidelity);
    });
  });

  group('P5: Course Grades Scheduler Bridge', () {
    test('fails closed when courseGradesScheduler flag is off (default)',
        () async {
      final bridge = _FakeGradesBridge();
      const defaultFlags = OfficialAnkiFeatureFlags(
        engine: true,
        import: true,
        catalogReady: true,
        runtimeCapable: true,
        platformReady: true,
        renderer: true,
        scheduler: true,
        courseGradesScheduler: false,
      );

      final impl = OfficialAnkiCourseGradesBridgeImpl(
        flags: defaultFlags,
        onAnswer: (cardId, rating, ms) async {
          bridge.answered.add((wordId: 'official-anki-p-c$cardId', rating: rating));
          return true;
        },
      );

      final ok = await impl.answerOfficialCard(
        wordId: 'official-anki-prof-c101',
        rating: 'good',
      );

      expect(ok, isFalse, reason: 'must return false when flag is off');
      expect(bridge.answered, isEmpty);
    });

    test('deduplicates per cardId and ignores canonicalLink preview cards',
        () async {
      final bridge = _FakeGradesBridge();
      const enabledFlags = OfficialAnkiFeatureFlags(
        engine: true,
        import: true,
        catalogReady: true,
        runtimeCapable: true,
        platformReady: true,
        renderer: true,
        scheduler: true,
        courseGradesScheduler: true,
      );

      expect(enabledFlags.allowsCourseGradesScheduler, isTrue);

      final impl = OfficialAnkiCourseGradesBridgeImpl(
        flags: enabledFlags,
        onAnswer: (cardId, rating, ms) async {
          bridge.answered.add((wordId: 'official-anki-p-c$cardId', rating: rating));
          return true;
        },
      );

      // 1. Regular official card
      final ok1 = await impl.answerOfficialCard(
        wordId: 'official-anki-prof-c205',
        rating: 'good',
      );
      expect(ok1, isTrue);
      expect(bridge.answered.length, 1);
      expect(bridge.answered.first.rating, 'good');

      // 2. Canonical link card (must be ignored)
      final ok2 = await impl.answerOfficialCard(
        wordId: 'official-anki-link-src1-c205',
        rating: 'good',
      );
      expect(ok2, isFalse,
          reason: 'canonicalLink cards must never write scheduler');
      expect(bridge.answered.length, 1);
    });
  });
}
