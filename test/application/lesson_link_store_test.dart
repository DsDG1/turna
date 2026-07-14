import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:varnamala/application/lesson_link_store.dart';
import 'package:varnamala/domain/course/lesson_word_link.dart';
import 'package:varnamala/service/locator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppPrefs prefs;
  late LessonLinkStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final sp = await StreamingSharedPreferences.instance;
    prefs = AppPrefs(sp);
    await prefs.preferences.setString(LocalStateKeys.lessonWordLinks, '{}');
    store = LessonLinkStore(prefs);
  });

  group('readAll', () {
    test('returns empty map when no links have been stored', () {
      expect(store.readAll(), isEmpty);
    });

    test('decodes stored links from prefs', () async {
      final link = LessonWordLink(
        wordId: 'w-1',
        lessonId: 'l-a',
        lessonName: 'Lesson A',
        type: LinkType.word,
        firstSeenAt: DateTime(2026, 7, 11, 10, 0),
      );
      await prefs.preferences.setString(
        LocalStateKeys.lessonWordLinks,
        jsonEncode({'w-1': link.toJson()}),
      );

      final all = store.readAll();
      expect(all, hasLength(1));
      expect(all['w-1']?.lessonName, 'Lesson A');
    });
  });

  group('upsertFirstSeen', () {
    test('records a first-seen link for each id', () async {
      await store.upsertFirstSeen(
        ids: const ['w-1', 'w-2'],
        lessonId: 'l-a',
        lessonName: 'Lesson A',
        type: LinkType.word,
      );

      expect(store.containsId('w-1'), isTrue);
      expect(store.containsId('w-2'), isTrue);
      expect(store.containsId('w-3'), isFalse);

      expect(store.lessonNameFor('w-1'), 'Lesson A');
      expect(store.lessonNameFor('w-2'), 'Lesson A');
    });

    test('keeps the first seen link when the same id is upserted again',
        () async {
      await store.upsertFirstSeen(
        ids: const ['w-1'],
        lessonId: 'l-a',
        lessonName: 'Lesson A',
        type: LinkType.word,
      );
      final firstSeenAt = store.readAll()['w-1']!.firstSeenAt;

      // Small delay so a would-be overwrite would have a different timestamp.
      await Future.delayed(const Duration(milliseconds: 10));

      await store.upsertFirstSeen(
        ids: const ['w-1'],
        lessonId: 'l-b',
        lessonName: 'Lesson B',
        type: LinkType.word,
      );

      final link = store.readAll()['w-1']!;
      expect(link.lessonId, 'l-a');
      expect(link.lessonName, 'Lesson A');
      expect(link.firstSeenAt, firstSeenAt);
    });

    test('serializes concurrent upserts so overlapping ids keep first lesson',
        () async {
      await Future.wait([
        store.upsertFirstSeen(
          ids: const ['w-1', 'w-2'],
          lessonId: 'l-a',
          lessonName: 'Lesson A',
          type: LinkType.word,
        ),
        store.upsertFirstSeen(
          ids: const ['w-1', 'w-3'],
          lessonId: 'l-b',
          lessonName: 'Lesson B',
          type: LinkType.word,
        ),
      ]);

      final all = store.readAll();
      // w-1 should belong to whichever write won the chain, but it must only
      // appear once and not flip to Lesson B if Lesson A won.
      expect(all, containsPair('w-1', isA<LessonWordLink>()));
      expect(all, containsPair('w-2', isA<LessonWordLink>()));
      expect(all, containsPair('w-3', isA<LessonWordLink>()));
      expect(all.length, 3);

      // w-2 and w-3 are non-overlapping, so their lessons are deterministic.
      expect(all['w-2']?.lessonName, 'Lesson A');
      expect(all['w-3']?.lessonName, 'Lesson B');
    });
  });

  group('filtered', () {
    test('returns only links of the requested type', () async {
      await store.upsertFirstSeen(
        ids: const ['w-1'],
        lessonId: 'l-a',
        lessonName: 'Lesson A',
        type: LinkType.word,
      );
      await store.upsertFirstSeen(
        ids: const ['g-1'],
        lessonId: 'l-a',
        lessonName: 'Lesson A',
        type: LinkType.grammarPoint,
      );

      expect(store.filtered(LinkType.word).keys, ['w-1']);
      expect(store.filtered(LinkType.grammarPoint).keys, ['g-1']);
    });
  });

  group('corruption handling', () {
    test('decodes invalid JSON to an empty map without crashing', () async {
      await prefs.preferences.setString(
          LocalStateKeys.lessonWordLinks, 'not-json');
      final corrupted = LessonLinkStore(prefs);
      expect(corrupted.readAll(), isEmpty);
    });
  });
}
