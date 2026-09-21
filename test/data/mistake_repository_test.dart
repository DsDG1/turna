// Regression tests for the incremental MistakeRepository write paths
// (insertEntry / updateEntry / deleteEntriesByIds). These used to be one
// DELETE-all + rebuild-everything `replaceAll` per wrong answer; the tests
// pin the incremental contracts: FIFO order survives gaps, updates never
// clobber sort order, deletes stay scoped to the given ids + language.

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/data/mistake_repository.dart';
import 'package:turna/domain/course/mistake_entry.dart';

import '../helpers/in_memory_course_db.dart';

MistakeEntry _entry(String id, {int rewriteCount = 0}) {
  return MistakeEntry(
    id: id,
    lessonId: 'lesson-1',
    stageId: 'stage-1',
    interactionId: 'interaction-$id',
    timestamp: DateTime.fromMillisecondsSinceEpoch(1700000000000),
    rewriteCount: rewriteCount,
  );
}

void main() {
  late CourseDatabase db;
  late MistakeRepository repo;

  setUp(() {
    db = emptyInMemoryCourseDatabase();
    repo = MistakeRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('insertEntry appends in FIFO order across a delete gap', () async {
    await repo.insertEntry(
      languageCode: 'tr',
      entry: _entry('a'),
      dailyCounts: const {},
      masteredTotal: 0,
    );
    await repo.insertEntry(
      languageCode: 'tr',
      entry: _entry('b'),
      dailyCounts: const {},
      masteredTotal: 0,
    );
    // Gap: delete the middle entry, then append — order must stay a, c.
    await repo.deleteEntriesByIds(
      languageCode: 'tr',
      ids: const {'b'},
      dailyCounts: const {},
      masteredTotal: 0,
    );
    await repo.insertEntry(
      languageCode: 'tr',
      entry: _entry('c'),
      dailyCounts: const {},
      masteredTotal: 0,
    );

    final loaded = await repo.load('tr');
    expect(loaded.map((e) => e.id).toList(), ['a', 'c']);
  });

  test('insertEntry evictOldest drops only the head row', () async {
    for (final id in ['a', 'b', 'c']) {
      await repo.insertEntry(
        languageCode: 'tr',
        entry: _entry(id),
        dailyCounts: const {},
        masteredTotal: 0,
      );
    }
    await repo.insertEntry(
      languageCode: 'tr',
      entry: _entry('d'),
      dailyCounts: const {},
      masteredTotal: 0,
      evictOldest: true,
    );

    final loaded = await repo.load('tr');
    expect(loaded.map((e) => e.id).toList(), ['b', 'c', 'd']);
  });

  test('updateEntry bumps rewriteCount without reordering', () async {
    for (final id in ['a', 'b']) {
      await repo.insertEntry(
        languageCode: 'tr',
        entry: _entry(id),
        dailyCounts: const {},
        masteredTotal: 0,
      );
    }

    await repo.updateEntry(
      languageCode: 'tr',
      entry: _entry('a', rewriteCount: 1),
    );

    final loaded = await repo.load('tr');
    expect(loaded.map((e) => e.id).toList(), ['a', 'b']);
    expect(loaded.first.rewriteCount, 1);
    expect(loaded.last.rewriteCount, 0);
  });

  test('deleteEntriesByIds removes only matching ids and writes aggregates',
      () async {
    for (final id in ['a', 'b', 'c']) {
      await repo.insertEntry(
        languageCode: 'tr',
        entry: _entry(id),
        dailyCounts: const {},
        masteredTotal: 0,
      );
    }

    await repo.deleteEntriesByIds(
      languageCode: 'tr',
      ids: const {'a', 'c', 'not-stored'},
      dailyCounts: const {'2026-09-21': 1},
      masteredTotal: 7,
    );

    final loaded = await repo.load('tr');
    expect(loaded.map((e) => e.id).toList(), ['b']);
    expect(await repo.loadDailyCounts('tr'), {'2026-09-21': 1});
    expect(await repo.loadMasteredTotal('tr'), 7);
  });

  test('incremental writes converge with replaceAll for the same data',
      () async {
    final entries = [for (var i = 0; i < 5; i++) _entry('e$i')];

    for (final e in entries) {
      await repo.insertEntry(
        languageCode: 'tr',
        entry: e,
        dailyCounts: const {'2026-09-21': 5},
        masteredTotal: 3,
      );
    }

    final incrementalDb = emptyInMemoryCourseDatabase();
    final incrementalRepo = MistakeRepository(incrementalDb);
    addTearDown(() async {
      await incrementalDb.close();
      await db.close();
    });
    await incrementalRepo.replaceAll(
      languageCode: 'tr',
      entries: entries,
      dailyCounts: const {'2026-09-21': 5},
      masteredTotal: 3,
    );

    final viaIncremental = await repo.load('tr');
    final viaReplaceAll = await incrementalRepo.load('tr');
    expect(
      viaIncremental.map((e) => e.id).toList(),
      viaReplaceAll.map((e) => e.id).toList(),
    );
    expect(
      await repo.loadDailyCounts('tr'),
      await incrementalRepo.loadDailyCounts('tr'),
    );
    expect(
      await repo.loadMasteredTotal('tr'),
      await incrementalRepo.loadMasteredTotal('tr'),
    );
  });

  test('incremental writes are scoped to their language', () async {
    await repo.insertEntry(
      languageCode: 'tr',
      entry: _entry('tr-a'),
      dailyCounts: const {},
      masteredTotal: 0,
    );
    await repo.insertEntry(
      languageCode: 'fr',
      entry: _entry('fr-a'),
      dailyCounts: const {},
      masteredTotal: 0,
    );

    await repo.deleteEntriesByIds(
      languageCode: 'fr',
      ids: const {'fr-a'},
      dailyCounts: const {},
      masteredTotal: 0,
    );

    expect((await repo.load('tr')).map((e) => e.id).toList(), ['tr-a']);
    expect(await repo.load('fr'), isEmpty);
  });
}
