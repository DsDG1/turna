// JSON round-trip for MistakeEntry.grammarPointId and Interaction.grammarPointId.

import 'package:flutter_test/flutter_test.dart';
import 'package:varnamala/domain/course/interaction.dart';
import 'package:varnamala/domain/course/mistake_entry.dart';

void main() {
  test('MistakeEntry preserves grammarPointId through JSON', () {
    final entry = MistakeEntry(
      id: 'm1',
      lessonId: 'l-test',
      stageId: 'stage-check',
      interactionId: 'mc-1',
      grammarPointId: 'gp.greetings',
      userAnswer: 'Hapana',
      correctAnswer: 'Ndiyo',
      timestamp: DateTime.utc(2026, 1, 1),
      interactionSnapshot: const Interaction.multipleChoice(
        id: 'mc-1',
        prompt: 'Which means Yes?',
        options: ['Ndiyo', 'Hapana'],
        correctIndex: 0,
        grammarPointId: 'gp.greetings',
      ),
    );

    final decoded = MistakeEntry.fromJson(entry.toJson());
    expect(decoded.grammarPointId, 'gp.greetings');
    expect(interactionGrammarPointId(decoded.interactionSnapshot!),
        'gp.greetings');
  });

  test('interactionGrammarPointId reads optional field on all variants used',
      () {
    const mc = Interaction.multipleChoice(
      id: 'a',
      prompt: 'p',
      options: ['x', 'y'],
      correctIndex: 0,
      grammarPointId: 'gp.a',
    );
    const fb = Interaction.fillBlank(
      id: 'b',
      sentence: '___',
      answer: 'x',
      grammarPointId: 'gp.b',
    );
    const bare = Interaction.multipleChoice(
      id: 'c',
      prompt: 'p',
      options: ['x'],
      correctIndex: 0,
    );

    expect(interactionGrammarPointId(mc), 'gp.a');
    expect(interactionGrammarPointId(fb), 'gp.b');
    expect(interactionGrammarPointId(bare), isNull);
  });
}
