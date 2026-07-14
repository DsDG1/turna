// Unit tests for MistakeProvider: FIFO log, 30-entry cap, rewrite removal,
// SharedPreferences persistence, and Interaction snapshot round-trip.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:varnamala/application/mistake_provider.dart';
import 'package:varnamala/domain/course/interaction.dart';
import 'package:varnamala/domain/course/mistake_entry.dart';
import 'package:varnamala/service/locator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppPrefs prefs;
  late MistakeProvider mistakes;

  setUp(() async {
    // setMockInitialValues does not clear an already-cached
    // StreamingSharedPreferences instance, so reset the mistake key
    // explicitly between tests to avoid cross-test state leakage.
    SharedPreferences.setMockInitialValues({});
    final sp = await StreamingSharedPreferences.instance;
    prefs = AppPrefs(sp);
    await prefs.preferences.setString(LocalStateKeys.mistakeLog, '[]');
    mistakes = MistakeProvider(prefs);
  });

  MistakeEntry entry({
    required String id,
    String? wordId,
    String? grammarPointId,
    Interaction? snapshot,
  }) =>
      MistakeEntry(
        id: id,
        lessonId: 'lesson-1',
        stageId: 'stage-1',
        interactionId: 'item-$id',
        wordId: wordId,
        grammarPointId: grammarPointId,
        interactionSnapshot: snapshot ??
            Interaction.multipleChoice(
              id: 'item-$id',
              prompt: 'Pick one',
              options: ['a', 'b', 'c'],
              correctIndex: 0,
            ),
        userAnswer: 'wrong',
        correctAnswer: 'a',
        timestamp: DateTime(2026, 7, 10),
      );

  group('record & count', () {
    test('record appends and increments count', () async {
      await mistakes.record(entry(id: 'm-1'));
      await mistakes.record(entry(id: 'm-2'));
      expect(mistakes.count, 2);
      expect(mistakes.entries.map((e) => e.id).toList(), ['m-1', 'm-2']);
    });

    test('FIFO cap: the oldest entry is evicted at 31 entries', () async {
      for (var i = 0; i < MistakeProvider.maxEntries + 1; i++) {
        await mistakes.record(entry(id: 'm-$i'));
      }
      expect(mistakes.count, MistakeProvider.maxEntries);
      // m-0 was the first inserted → evicted.
      expect(mistakes.entries.first.id, 'm-1');
      expect(mistakes.entries.last.id, 'm-${MistakeProvider.maxEntries}');
    });
  });

  group('recordRewrite', () {
    test('a single rewrite increments rewriteCount but keeps the entry',
        () async {
      await mistakes.record(entry(id: 'm-1'));
      await mistakes.recordRewrite('m-1');
      expect(mistakes.count, 1);
      expect(mistakes.entries.first.rewriteCount, 1);
    });

    test('rewriting the same entry twice removes it', () async {
      await mistakes.record(entry(id: 'm-1'));
      await mistakes.recordRewrite('m-1');
      await mistakes.recordRewrite('m-1');
      expect(mistakes.count, 0);
    });

    test('recordRewrite on an unknown id is a no-op', () async {
      await mistakes.record(entry(id: 'm-1'));
      await mistakes.recordRewrite('missing');
      expect(mistakes.count, 1);
      expect(mistakes.entries.first.rewriteCount, 0);
    });
  });

  group('clear & snapshot', () {
    test('clear empties the log', () async {
      await mistakes.record(entry(id: 'm-1'));
      await mistakes.record(entry(id: 'm-2'));
      await mistakes.clear();
      expect(mistakes.count, 0);
    });

    test('toInteraction returns the stored snapshot', () async {
      const snapshot = Interaction.fillBlank(
        id: 'item-fb',
        sentence: '___ there',
        answer: 'hi',
      );
      final mistake = entry(id: 'm-1', snapshot: snapshot);
      await mistakes.record(mistake);
      final stored = mistakes.entries.first;
      expect(mistakes.toInteraction(stored), isA<FillBlank>());
      expect((mistakes.toInteraction(stored)! as FillBlank).answer, 'hi');
    });

    test('Interaction snapshot survives JSON round-trip through prefs',
        () async {
      await mistakes.record(entry(id: 'm-1'));
      // A fresh provider reading the same prefs must rebuild the snapshot.
      final reloaded = MistakeProvider(prefs);
      final stored = reloaded.entries.first;
      expect(stored.interactionSnapshot, isA<MultipleChoice>());
      expect((stored.interactionSnapshot! as MultipleChoice).correctIndex, 0);
    });
  });

  group('persistence resilience', () {
    test('a corrupted mistakeLog degrades to an empty log', () async {
      await prefs.preferences.setString(LocalStateKeys.mistakeLog, 'not-json');
      final corrupted = MistakeProvider(prefs);
      expect(corrupted.entries, isEmpty);
      expect(corrupted.count, 0);
    });
  });
}