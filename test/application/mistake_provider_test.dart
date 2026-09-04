// Unit tests for MistakeProvider: FIFO log, 30-entry cap, rewrite removal,
// SharedPreferences persistence, dashboard aggregates, and Interaction
// snapshot round-trip.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/diagnostics/storage_write_telemetry.dart';
import 'package:turna/application/mistake_provider.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/domain/course/mistake_entry.dart';
import 'package:turna/service/locator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppPrefs prefs;
  late MistakeProvider mistakes;

  setUp(() async {
    // setMockInitialValues does not clear an already-cached
    // StreamingSharedPreferences instance, so reset the mistake keys
    // explicitly between tests to avoid cross-test state leakage.
    SharedPreferences.setMockInitialValues({});
    final sp = await StreamingSharedPreferences.instance;
    prefs = AppPrefs(sp);
    await prefs.preferences.setString(LocalStateKeys.mistakeLog, '[]');
    await prefs.preferences.setString(
      LocalStateKeys.mistakeDailyCounts,
      '{}',
    );
    await prefs.preferences.setInt(LocalStateKeys.mistakeMasteredTotal, 0);
    StorageWriteTelemetry.instance.clear();
    mistakes = MistakeProvider(prefs);
  });

  MistakeEntry entry({
    required String id,
    String? wordId,
    String? grammarPointId,
    Interaction? snapshot,
    DateTime? timestamp,
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
        timestamp: timestamp ?? DateTime(2026, 7, 10),
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

    test('bounded full-rewrite baseline stays below migration threshold',
        () async {
      for (var i = 0; i < MistakeProvider.maxEntries + 1; i++) {
        await mistakes.record(entry(id: 'baseline-$i'));
      }
      final writes = StorageWriteTelemetry.instance.samples
          .where((sample) => sample.key == LocalStateKeys.mistakeLog)
          .toList();
      final maximumBytes = writes
          .map((sample) => sample.estimatedBytes)
          .reduce((a, b) => a > b ? a : b);
      expect(writes, hasLength(MistakeProvider.maxEntries + 1));
      expect(maximumBytes, lessThan(64 * 1024));
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

  group('removeForAnkiDeletion', () {    MistakeEntry ankiEntry(
      String id, {
      required String lessonId,
      String? wordId,
    }) =>
        entry(id: id, wordId: wordId).copyWith(lessonId: lessonId);

    test('legacy prefix removes word-id and lesson-id entries, keeps others',
        () async {
      await mistakes.record(ankiEntry(
        'm-course',
        lessonId: 'anki-user-u1-l0-s0', // course-path mistake (wordId null)
      ));
      await mistakes.record(ankiEntry(
        'm-review',
        lessonId: 'srs-review',
        wordId: 'anki-user-c42', // unified-review mistake
      ));
      await mistakes.record(ankiEntry(
        'm-sibling',
        lessonId: 'anki-user2-u1-l0-s0',
        wordId: 'anki-user2-c42', // prefix sibling must survive
      ));
      await mistakes.record(entry(id: 'm-builtin', wordId: 'word-7'));

      await mistakes.removeForAnkiDeletion(idPrefixes: ['anki-user-']);

      expect(mistakes.entries.map((e) => e.id), {'m-sibling', 'm-builtin'});
    });

    test('official card ids catch word ids without the sourceId', () async {
      await mistakes.record(ankiEntry(
        'm-practice',
        lessonId: 'official-review',
        wordId: 'official-anki-review-c31', // practice-review format
      ));
      await mistakes.record(ankiEntry(
        'm-projection',
        lessonId: 'official-anki-src-o-l1-p1',
        wordId: 'official-anki-a1b2c3d4e5f6-c31', // projection format
      ));
      await mistakes.record(ankiEntry(
        'm-unified',
        lessonId: 'srs-review',
        wordId: 'official-anki-src-o-c31', // ledger format (prefix-matched)
      ));
      await mistakes.record(ankiEntry(
        'm-other-card',
        lessonId: 'official-review',
        wordId: 'official-anki-review-c99',
      ));

      await mistakes.removeForAnkiDeletion(
        idPrefixes: ['official-anki-src-o-'],
        cardIds: const {31},
      );

      expect(mistakes.entries.map((e) => e.id), {'m-other-card'});
    });

    test('no prefixes and no card ids is a no-op', () async {
      await mistakes.record(entry(id: 'm-1'));
      await mistakes.removeForAnkiDeletion();
      expect(mistakes.count, 1);
    });
  });

  group('dashboard aggregates', () {
    test('record bumps the per-day count of the entry local day', () async {
      final now = DateTime.now();
      await mistakes.record(entry(id: 'm-1', timestamp: now));
      await mistakes.record(entry(id: 'm-2', timestamp: now));
      expect(mistakes.dailyCounts[MistakeProvider.dayKey(now)], 2);
      // Aggregates persist: a fresh provider reading the same prefs sees them.
      final reloaded = MistakeProvider(prefs);
      expect(reloaded.dailyCounts[MistakeProvider.dayKey(now)], 2);
    });

    test('days outside the 30-day window are pruned on write', () async {
      final now = DateTime.now();
      final stale = now.subtract(const Duration(days: 40));
      await mistakes.record(entry(id: 'm-stale', timestamp: stale));
      await mistakes.record(entry(id: 'm-fresh', timestamp: now));
      expect(mistakes.dailyCounts.containsKey(MistakeProvider.dayKey(stale)),
          isFalse);
      expect(mistakes.dailyCounts[MistakeProvider.dayKey(now)], 1);
    });

    test('masteredTotal counts rewrite completions and review removals only',
        () async {
      await mistakes.record(entry(id: 'm-rewrite'));
      await mistakes.record(entry(id: 'm-review'));
      await mistakes.record(
        entry(id: 'm-anki').copyWith(lessonId: 'anki-x-l0'),
      );

      await mistakes.recordRewrite('m-rewrite');
      await mistakes.recordRewrite('m-rewrite'); // goal reached → mastered
      await mistakes.removeByIds({'m-review'}); // review correct → mastered
      expect(mistakes.masteredTotal, 2);

      // Deck uninstall removals must NOT count as mastered.
      await mistakes.removeForAnkiDeletion(idPrefixes: ['anki-x-']);
      expect(mistakes.count, 0);
      expect(mistakes.masteredTotal, 2);
    });

    test('clear resets the aggregates together with the log', () async {
      final now = DateTime.now();
      await mistakes.record(entry(id: 'm-1', timestamp: now));
      await mistakes.recordRewrite('m-1');
      await mistakes.recordRewrite('m-1');
      expect(mistakes.masteredTotal, 1);

      await mistakes.clear();
      expect(mistakes.count, 0);
      expect(mistakes.masteredTotal, 0);
      expect(mistakes.dailyCounts, isEmpty);
    });

    test('legacy prefs without aggregate keys degrade gracefully', () async {
      // Nothing has touched the aggregate keys in this provider's prefs.
      final legacy = MistakeProvider(prefs);
      expect(legacy.dailyCounts, isEmpty);
      expect(legacy.masteredTotal, 0);
    });

    test('a corrupted dailyCounts payload degrades to an empty map',
        () async {
      await prefs.preferences.setString(
        LocalStateKeys.mistakeDailyCounts,
        'not-json',
      );
      final corrupted = MistakeProvider(prefs);
      expect(corrupted.dailyCounts, isEmpty);
    });

    test('reloadFromPrefs re-reads aggregates after an external restore',
        () async {
      final now = DateTime.now();
      await mistakes.record(entry(id: 'm-1', timestamp: now));
      expect(mistakes.dailyCounts[MistakeProvider.dayKey(now)], 1);

      // Simulate an external restore overwriting the raw prefs values.
      await prefs.preferences.setString(
        LocalStateKeys.mistakeDailyCounts,
        '{"${MistakeProvider.dayKey(now)}": 7}',
      );
      await prefs.preferences.setInt(LocalStateKeys.mistakeMasteredTotal, 9);
      mistakes.reloadFromPrefs();
      expect(mistakes.dailyCounts[MistakeProvider.dayKey(now)], 7);
      expect(mistakes.masteredTotal, 9);
    });
  });
}
