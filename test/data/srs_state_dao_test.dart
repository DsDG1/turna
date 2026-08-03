// Unit tests for [SrsStateDao]: round-trip of [SrsWord] through the
// `srs_states` table, queue isolation, prefix delete, and clear.

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/data/srs_state_dao.dart';
import 'package:turna/domain/course/srs_word.dart';

import '../helpers/in_memory_course_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SrsStateDao dao;

  setUp(() {
    dao = emptySrsStateDao();
  });

  SrsWord makeWord({
    required String id,
    int interval = 4,
    double ease = 2.4,
    int reps = 2,
    int lapses = 1,
    bool leech = false,
    SrsItemType type = SrsItemType.word,
    DateTime? lastReviewedAt,
    double? stability,
    double? difficulty,
    int fsrsState = 1,
    int? learningStep,
  }) {
    return SrsWord(
      wordId: id,
      dueAt: DateTime(2026, 7, 28, 12),
      intervalDays: interval,
      ease: ease,
      reps: reps,
      lapses: lapses,
      isLeech: leech,
      type: type,
      lastReviewedAt: lastReviewedAt,
      stability: stability,
      difficulty: difficulty,
      fsrsState: fsrsState,
      learningStep: learningStep,
    );
  }

  group('SrsStateDao', () {
    test('loadQueue on an empty table returns an empty map', () async {
      expect(await dao.loadQueue('srs'), isEmpty);
    });

    test('upsert then loadQueue round-trips every field', () async {
      final w = makeWord(
        id: 'w-1',
        interval: 21,
        ease: 2.6,
        reps: 5,
        lapses: 2,
        leech: true,
        type: SrsItemType.expression,
        lastReviewedAt: DateTime(2026, 7, 20, 9, 30),
        stability: 18.5,
        difficulty: 4.2,
        fsrsState: 2,
        learningStep: null,
      );
      await dao.upsert('srs', w);

      final loaded = await dao.loadQueue('srs');
      expect(loaded, hasLength(1));
      final r = loaded['w-1']!;
      expect(r.wordId, 'w-1');
      expect(r.intervalDays, 21);
      expect(r.ease, 2.6);
      expect(r.reps, 5);
      expect(r.lapses, 2);
      expect(r.isLeech, isTrue);
      expect(r.type, SrsItemType.expression);
      expect(r.dueAt, DateTime(2026, 7, 28, 12));
      expect(r.lastReviewedAt, DateTime(2026, 7, 20, 9, 30));
      expect(r.stability, closeTo(18.5, 1e-9));
      expect(r.difficulty, closeTo(4.2, 1e-9));
      expect(r.fsrsState, 2);
      expect(r.learningStep, isNull);
    });

    test('upsert is an update on conflict (same wordId)', () async {
      await dao.upsert('srs', makeWord(id: 'w-1', reps: 1));
      await dao.upsert('srs', makeWord(id: 'w-1', reps: 9, interval: 30));

      final loaded = await dao.loadQueue('srs');
      expect(loaded, hasLength(1));
      expect(loaded['w-1']!.reps, 9);
      expect(loaded['w-1']!.intervalDays, 30);
    });

    test('upsertBatch writes many rows in one call', () async {
      await dao.upsertBatch('srs', [
        makeWord(id: 'w-1'),
        makeWord(id: 'w-2'),
        makeWord(id: 'w-3'),
      ]);
      final loaded = await dao.loadQueue('srs');
      expect(loaded.keys, {'w-1', 'w-2', 'w-3'});
    });

    test('queues are isolated by the queue discriminator', () async {
      await dao.upsert('srs', makeWord(id: 'w-1'));
      await dao.upsert('grammar', makeWord(id: 'gp-1'));

      expect((await dao.loadQueue('srs')).keys, ['w-1']);
      expect((await dao.loadQueue('grammar')).keys, ['gp-1']);
    });

    test('delete removes a single row', () async {
      await dao.upsertBatch('srs', [makeWord(id: 'w-1'), makeWord(id: 'w-2')]);
      await dao.delete('w-1');
      expect((await dao.loadQueue('srs')).keys, ['w-2']);
    });

    test('deleteByPrefix removes only matching ids', () async {
      await dao.upsertBatch('srs', [
        makeWord(id: 'anki-imp1-n1'),
        makeWord(id: 'anki-imp1-n2'),
        makeWord(id: 'anki-imp2-n1'),
        makeWord(id: 'w-builtin'),
      ]);
      await dao.deleteByPrefix('anki-imp1-');
      final loaded = await dao.loadQueue('srs');
      expect(loaded.keys.toSet(), {'anki-imp2-n1', 'w-builtin'});
    });

    test('clearQueue empties only the named queue', () async {
      await dao.upsert('srs', makeWord(id: 'w-1'));
      await dao.upsert('grammar', makeWord(id: 'gp-1'));

      await dao.clearQueue('srs');
      expect(await dao.loadQueue('srs'), isEmpty);
      expect((await dao.loadQueue('grammar')).keys, ['gp-1']);
    });

    test('a never-reviewed card round-trips with null lastReviewedAt',
        () async {
      await dao.upsert('srs', SrsWord.fresh('w-fresh'));
      final r = (await dao.loadQueue('srs'))['w-fresh']!;
      expect(r.lastReviewedAt, isNull);
      expect(r.reps, 0);
    });
  });
}
