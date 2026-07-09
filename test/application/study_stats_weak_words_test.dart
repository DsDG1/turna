// Regression: getWeakWords used to silently return an empty list with the
// comment "we can't fully parse it here without importing MistakeEntry".
// After the fix it parses the MistakeEntry log and aggregates by wordId.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:words625/application/study_stats_provider.dart';
import 'package:words625/courses/languages/swahili_vocab.dart';
import 'package:words625/data/study_log_repository.dart';
import 'package:words625/domain/course/interaction.dart';
import 'package:words625/domain/course/mistake_entry.dart';
import 'package:words625/domain/course/word_entry.dart';
import 'package:words625/service/locator.dart';

class _TestVocab {
  static WordEntry of(String id) => WordEntry(
        id: id,
        term: 'hello',
        translation: 'greeting',
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppPrefs prefs;
  late StudyStatsProvider provider;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final sp = await StreamingSharedPreferences.instance;
    prefs = AppPrefs(sp);
    final repo = StudyLogRepository(prefs);
    provider = StudyStatsProvider(repo, prefs);
  });

  Future<void> seedMistakes(List<MistakeEntry> entries) async {
    final body = jsonEncode(entries.map((e) => e.toJson()).toList());
    await prefs.setString(LocalStateKeys.mistakeLog, body);
  }

  test('aggregates mistakes by wordId and sorts by count desc', () async {
    final now = DateTime(2026, 7, 9, 12);
    await seedMistakes([
      MistakeEntry(
        id: '1',
        lessonId: 'l-a',
        stageId: 's',
        interactionId: 'i',
        wordId: 'w-hello',
        grammarPointId: null,
        interactionSnapshot: const Interaction.showWord(id: 'i', wordId: 'w-hello'),
        userAnswer: 'x',
        correctAnswer: 'hello',
        timestamp: now.subtract(const Duration(minutes: 5)),
      ),
      MistakeEntry(
        id: '2',
        lessonId: 'l-a',
        stageId: 's',
        interactionId: 'i',
        wordId: 'w-hello',
        grammarPointId: null,
        interactionSnapshot: const Interaction.showWord(id: 'i', wordId: 'w-hello'),
        userAnswer: 'x',
        correctAnswer: 'hello',
        timestamp: now.subtract(const Duration(minutes: 4)),
      ),
      MistakeEntry(
        id: '3',
        lessonId: 'l-a',
        stageId: 's',
        interactionId: 'i',
        wordId: 'w-bye',
        grammarPointId: null,
        interactionSnapshot: const Interaction.showWord(id: 'i', wordId: 'w-bye'),
        userAnswer: 'y',
        correctAnswer: 'bye',
        timestamp: now.subtract(const Duration(minutes: 3)),
      ),
    ]);

    final words = await provider.getWeakWords();
    expect(words.length, 2);
    // Sorted by mistakeCount desc — w-hello (2) before w-bye (1).
    expect(words.first.wordId, 'w-hello');
    expect(words.first.mistakeCount, 2);
    expect(words.last.wordId, 'w-bye');
    expect(words.last.mistakeCount, 1);
  });

  test('limits results to the requested count', () async {
    final now = DateTime.now();
    await seedMistakes([
      for (var i = 0; i < 5; i++)
        MistakeEntry(
          id: 'm-$i',
          lessonId: 'l',
          stageId: 's',
          interactionId: 'i-$i',
          wordId: 'w-$i',
          grammarPointId: null,
          interactionSnapshot: const Interaction.showWord(id: 'i', wordId: 'w'),
          userAnswer: 'x',
          correctAnswer: 'c',
          timestamp: now.subtract(Duration(minutes: i)),
        ),
    ]);

    final words = await provider.getWeakWords(limit: 3);
    expect(words.length, 3);
  });

  test('vocab lookup yields displayTerm / translation', () async {
    // Inject a vocab entry directly so we don't depend on setupLocator.
    const testId = 'w-weak-test';
    swahiliVocabById[testId] = _TestVocab.of(testId);
    addTearDown(() => swahiliVocabById.remove(testId));

    final now = DateTime.now();
    await seedMistakes([
      MistakeEntry(
        id: 'm-known',
        lessonId: 'l',
        stageId: 's',
        interactionId: 'i',
        wordId: testId,
        grammarPointId: null,
        interactionSnapshot: const Interaction.showWord(id: 'i', wordId: 'x'),
        userAnswer: 'x',
        correctAnswer: 'c',
        timestamp: now,
      ),
    ]);

    final words = await provider.getWeakWords();
    expect(words.length, 1);
    expect(words.first.wordId, testId);
    expect(words.first.displayText, 'hello');
    expect(words.first.translation, 'greeting');
  });
}
