import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/weak_word_quiz_assembler.dart';
import 'package:turna/courses/languages/vocab.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/domain/course/mistake_entry.dart';
import 'package:turna/domain/course/word_entry.dart';

void main() {
  final now = DateTime(2026, 7, 11, 12);

  setUp(() {
    vocabById
      ..clear()
      ..addAll({
        'w-a': const WordEntry(
          id: 'w-a',
          term: 'Jambo',
          translation: 'Hi',
        ),
        'w-b': const WordEntry(
          id: 'w-b',
          term: 'Sawa',
          translation: 'OK',
        ),
        'w-c': const WordEntry(
          id: 'w-c',
          term: 'Ndio',
          translation: 'Yes',
        ),
        'w-d': const WordEntry(
          id: 'w-d',
          term: 'Hapana',
          translation: 'No',
        ),
      });
  });

  tearDown(vocabById.clear);

  MistakeEntry mistake(String id, String wordId, DateTime ts) => MistakeEntry(
        id: id,
        lessonId: 'l1',
        stageId: 's1',
        interactionId: 'i1',
        wordId: wordId,
        userAnswer: 'x',
        correctAnswer: 'y',
        timestamp: ts,
      );

  test('requires minMistakes within window', () {
    final entries = [
      mistake('1', 'w-a', now.subtract(const Duration(days: 1))),
      mistake('2', 'w-a', now.subtract(const Duration(days: 2))),
      mistake('3', 'w-b', now.subtract(const Duration(days: 1))), // only once
      mistake(
          '4', 'w-c', now.subtract(const Duration(days: 40))), // outside window
      mistake('5', 'w-c', now.subtract(const Duration(days: 41))),
    ];

    final weak = WeakWordQuizAssembler.aggregateWeakWords(
      entries,
      now: now,
    );
    expect(weak.map((w) => w.wordId), ['w-a']);
    expect(weak.single.mistakeCount, 2);
  });

  test('assemble builds MCQ items capped at max', () {
    final weak = WeakWordQuizAssembler.aggregateWeakWords([
      for (var i = 0; i < 2; i++)
        mistake('a$i', 'w-a', now.subtract(Duration(days: i))),
      for (var i = 0; i < 2; i++)
        mistake('b$i', 'w-b', now.subtract(Duration(days: i))),
    ], now: now);

    final lesson = WeakWordQuizAssembler.assembleFromWeakWords(
      weak,
      random: null,
      maxItems: 10,
    );
    final items = lesson.flattenedStages.expand((s) => s.items).toList();
    expect(items.length, 2);
    expect(items.every((i) => i is MultipleChoice || i is TypeTheWord), isTrue);
  });
}
