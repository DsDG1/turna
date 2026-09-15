// Direct unit tests for the SrsQueueProvider base class (queue building,
// caching and import/remove semantics). srs_provider_test covers the
// concrete provider through its public API; these tests exercise base-class
// seams that previously had zero coverage (leech ordering, excludeAnki, the
// grammar registration branch, due-cache invalidation).

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';

import 'package:turna/application/lesson_link_store.dart';
import 'package:turna/application/srs_queue_provider.dart';
import 'package:turna/core/sm2.dart';
import 'package:turna/domain/course/srs_word.dart';
import 'package:turna/service/locator.dart';

import '../helpers/in_memory_course_db.dart';

/// Exposes the protected base-class seams for testing.
class _TestQueueProvider extends SrsQueueProvider {
  _TestQueueProvider(
    super.appPrefs,
    super.linkStore,
    super.srsDao, {
    this.grammarQueue = false,
  });

  final bool grammarQueue;

  @override
  String get statePrefsKey => LocalStateKeys.srsState;

  @override
  String get queueId => grammarQueue ? 'grammar' : 'test';

  @override
  String get logTag => 'TestQueue';

  List<SrsWord> due({
    SrsItemType? typeFilter,
    DateTime? now,
    bool excludeAnki = false,
  }) =>
      getDueItems(
        typeFilter: typeFilter,
        now: now,
        excludeAnki: excludeAnki,
        usePrimaryCache: false,
      );

  List<SrsWord> cachedDue({DateTime? now}) =>
      getDueItems(now: now, usePrimaryCache: true);

  List<SrsWord> cachedDueArgs({
    SrsItemType? typeFilter,
    DateTime? now,
    bool excludeAnki = false,
  }) =>
      getDueItems(
        typeFilter: typeFilter,
        now: now,
        excludeAnki: excludeAnki,
        usePrimaryCache: true,
      );

  void registerItemPublic(
    String id, {
    SrsItemType type = SrsItemType.word,
    SrsSourceKind sourceKind = SrsSourceKind.builtin,
    String? sourceId,
  }) =>
      registerItem(id, type: type, sourceKind: sourceKind, sourceId: sourceId);

  Future<void> importStatesPublic(Map<String, SrsWord> incoming) =>
      importStates(incoming);

  Future<void> removeImportedItemsPublic(Iterable<String> ids) =>
      removeImportedItems(ids);

  Future<void> removeItemsByPrefixPublic(String prefix) =>
      removeItemsByPrefix(prefix);

  int? get primaryCachedDueCountPublic => primaryCachedDueCount;

  int get primaryDueCountPublic => primaryDueCount;

  void invalidateDueCachesPublic() => invalidateDueCaches();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppPrefs prefs;
  late LessonLinkStore linkStore;
  late _TestQueueProvider queue;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final sp = await StreamingSharedPreferences.instance;
    prefs = AppPrefs(sp);
    await prefs.preferences.setString(LocalStateKeys.srsState, '{}');
    linkStore = LessonLinkStore(prefs);
    queue = _TestQueueProvider(prefs, linkStore, emptySrsStateDao());
    queue.setSchedulerForTesting(const Sm2Engine());
  });

  SrsWord word(String id, {DateTime? dueAt}) =>
      SrsWord.fresh(id).copyWith(dueAt: dueAt ?? DateTime(2024, 1, 1));

  group('getDueItems ordering and filtering', () {
    test('leeches sink to the end even when due earlier', () async {
      await queue.importStatesPublic({
        'leech-1': word('leech-1').copyWith(isLeech: true),
        'normal-1': word('normal-1', dueAt: DateTime(2024, 1, 5)),
        'normal-2': word('normal-2', dueAt: DateTime(2024, 1, 3)),
      });
      final due = queue.due(now: DateTime(2024, 1, 10));
      expect(due.map((w) => w.wordId), ['normal-2', 'normal-1', 'leech-1']);
    });

    test('excludeAnki drops both anki id prefixes, keeps course words',
        () async {
      await queue.importStatesPublic({
        'anki-imp1-c11': word('anki-imp1-c11'),
        'official-anki-src1-c22': word('official-anki-src1-c22'),
        'course-word': word('course-word'),
      });
      final due = queue.due(now: DateTime(2024, 1, 10), excludeAnki: true);
      expect(due.map((w) => w.wordId), ['course-word']);
    });

    test('suspended and buried never surface in the due queue', () async {
      await queue.importStatesPublic({
        's': word('s').copyWith(isSuspended: true),
        'b': word('b').copyWith(isBuried: true),
        'ok': word('ok'),
      });
      final due = queue.due(now: DateTime(2024, 1, 10));
      expect(due.map((w) => w.wordId), ['ok']);
    });

    test('typeFilter restricts to one item type', () async {
      await queue.importStatesPublic({
        'w': word('w'),
        'e': word('e').copyWith(type: SrsItemType.expression),
      });
      final due = queue.due(
        now: DateTime(2024, 1, 10),
        typeFilter: SrsItemType.expression,
      );
      expect(due.map((w) => w.wordId), ['e']);
    });
  });

  group('due cache', () {
    test('same cutoff returns the cached instance', () async {
      await queue.importStatesPublic({'a': word('a')});
      final cutoff = DateTime(2024, 1, 10);
      final first = queue.cachedDue(now: cutoff);
      final second = queue.cachedDue(now: cutoff);
      expect(identical(first, second), isTrue);
    });

    test('invalidateDueCaches rebuilds the primary cache', () async {
      await queue.importStatesPublic({'a': word('a')});
      final cutoff = DateTime(2024, 1, 10);
      queue.cachedDue(now: cutoff);
      expect(queue.primaryCachedDueCountPublic, 1);
      await queue.importStatesPublic({'b': word('b')});
      queue.invalidateDueCachesPublic();
      expect(queue.primaryCachedDueCountPublic, isNull);
      expect(queue.primaryDueCountPublic, 2);
    });

    test('cache refreshes once the earliest future dueAt passes', () async {
      final cutoff = DateTime(2024, 1, 10, 12);
      await queue.importStatesPublic({
        'due-now': word('due-now'),
        'due-later':
            word('due-later', dueAt: cutoff.add(const Duration(hours: 1))),
      });
      expect(queue.cachedDue(now: cutoff).map((w) => w.wordId), ['due-now']);
      // Before the next dueAt the due set cannot change — cache may serve.
      expect(
        queue
            .cachedDue(now: cutoff.add(const Duration(minutes: 30)))
            .map((w) => w.wordId),
        ['due-now'],
      );
      // Past it, a stale cache would hide the newly due card — must recompute.
      expect(
        queue
            .cachedDue(now: cutoff.add(const Duration(hours: 2)))
            .map((w) => w.wordId),
        ['due-now', 'due-later'],
      );
    });

    test('an earlier cutoff recomputes instead of reusing a later cache',
        () async {
      final t0 = DateTime(2024, 1, 10, 12);
      await queue.importStatesPublic({
        'w': word('w', dueAt: t0.add(const Duration(hours: 1))),
      });
      expect(
          queue.cachedDue(now: t0.add(const Duration(hours: 2))), hasLength(1));
      expect(queue.cachedDue(now: t0), isEmpty);
    });

    test('different filter args never share the primary cache', () async {
      await queue.importStatesPublic({
        'word-1': word('word-1'),
        'anki-imp1-c1': word('anki-imp1-c1'),
      });
      final cutoff = DateTime(2024, 1, 10);
      // Unfiltered pass caches both; the excludeAnki caller must not be
      // served that polluted list (and vice versa).
      expect(queue.cachedDue(now: cutoff), hasLength(2));
      expect(
        queue
            .cachedDueArgs(now: cutoff, excludeAnki: true)
            .map((w) => w.wordId),
        ['word-1'],
      );
      expect(queue.cachedDue(now: cutoff), hasLength(2));
    });
  });

  group('grammar queue registration branch', () {
    test('grammar queue rewrites sourceKind/sourceId to grammar', () {
      final grammar = _TestQueueProvider(prefs, linkStore, emptySrsStateDao(),
          grammarQueue: true)
        ..setSchedulerForTesting(const Sm2Engine());
      grammar.registerItemPublic('g-1');
      final entry = grammar.state['g-1']!;
      expect(entry.sourceKind, SrsSourceKind.grammar);
      expect(entry.sourceId, 'grammar');
    });

    test('non-grammar queue keeps the caller-supplied source', () {
      queue.registerItemPublic('w-1', sourceId: 'tr');
      final entry = queue.state['w-1']!;
      expect(entry.sourceKind, SrsSourceKind.builtin);
      expect(entry.sourceId, 'tr');
    });
  });

  group('import/remove semantics', () {
    test('importStates is idempotent — existing ids are never overwritten',
        () async {
      final evolved = word('a').copyWith(reps: 7, intervalDays: 30);
      await queue.importStatesPublic({'a': evolved});
      // A later import of the same id (e.g. re-import) must not reset it.
      await queue.importStatesPublic({'a': word('a')});
      final entry = queue.state['a']!;
      expect(entry.reps, 7);
      expect(entry.intervalDays, 30);
    });

    test('removeImportedItems removes exactly the listed ids, not the prefix',
        () async {
      await queue.importStatesPublic({
        'anki-imp1-c1': word('anki-imp1-c1'),
        'anki-imp1-c2': word('anki-imp1-c2'),
      });
      await queue.removeImportedItemsPublic(['anki-imp1-c1']);
      expect(queue.state.containsKey('anki-imp1-c1'), isFalse);
      expect(queue.state.containsKey('anki-imp1-c2'), isTrue);
    });

    test('removeItemsByPrefix removes the whole deck', () async {
      await queue.importStatesPublic({
        'anki-imp1-c1': word('anki-imp1-c1'),
        'anki-imp2-c9': word('anki-imp2-c9'),
      });
      await queue.removeItemsByPrefixPublic('anki-imp1-');
      expect(queue.state.containsKey('anki-imp1-c1'), isFalse);
      expect(queue.state.containsKey('anki-imp2-c9'), isTrue);
    });
  });

  group('engine parameters', () {
    test('setDesiredRetention is a no-op on the injected Sm2 engine', () {
      queue.setDesiredRetention(0.9);
      expect(queue.engine, isA<Sm2Engine>());
    });

    test('setFsrsParameters persists and clears via prefs', () async {
      final params = List<double>.generate(21, (i) => 1.0 + i / 100);
      await queue.setFsrsParameters(params);
      expect(queue.hasCustomFsrsParameters, isTrue);
      await queue.setFsrsParameters(null);
      expect(queue.hasCustomFsrsParameters, isFalse);
    });
  });
}
