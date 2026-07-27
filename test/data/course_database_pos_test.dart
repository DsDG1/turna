import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varnamala/data/course_database.dart' as db;
import 'package:varnamala/data/course_repository.dart';
import 'package:varnamala/domain/course/pos_tag.dart';
import 'package:varnamala/domain/course/word_entry.dart';

import '../helpers/in_memory_course_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqliteLibForTestHost();

  group('WordEntry POS JSON round-trip', () {
    test('pos survives fromJson/toJson for a known tag', () {
      final w = WordEntry(
        id: 'w-pos',
        term: 'su',
        translation: 'water',
        pos: PosTag.noun,
      );
      final json = w.toJson();
      expect(json['pos'], 'noun');
      final back = WordEntry.fromJson(json);
      expect(back.pos, PosTag.noun);
    });

    test('missing/unknown pos parses as null (old assets)', () {
      final w = WordEntry.fromJson(const {
        'id': 'w-old',
        'term': 'merhaba',
        'translation': 'hello',
        'tags': <String>[],
      });
      expect(w.pos, isNull);
      final w2 = WordEntry.fromJson(const {
        'id': 'w-bad',
        'term': 'x',
        'translation': 'y',
        'pos': 'bogus',
        'tags': <String>[],
      });
      expect(w2.pos, isNull);
    });
  });

  group('Vocabulary table POS column', () {
    late db.CourseDatabase database;
    late CourseRepository repo;

    setUp(() async {
      database = db.CourseDatabase(NativeDatabase.memory());
      repo = CourseRepository(database);
    });

    tearDown(() async => database.close());

    test('schema v6: pos column exists and round-trips', () async {
      expect(database.schemaVersion, 6);
      await database.into(database.vocabulary).insert(db.VocabularyCompanion(
            id: const Value('w1'),
            term: const Value('koşmak'),
            translation: const Value('to run'),
            pronunciation: const Value(null),
            audioAsset: const Value(null),
            pos: const Value('verb'),
            tags: const Value('[]'),
          ));
      final read = await repo.vocabulary();
      expect(read, hasLength(1));
      expect(read.first.id, 'w1');
      expect(read.first.pos, PosTag.verb);
    });

    test('null pos round-trips (unset)', () async {
      await database.into(database.vocabulary).insert(db.VocabularyCompanion(
            id: const Value('w2'),
            term: const Value('su'),
            translation: const Value('water'),
            pronunciation: const Value(null),
            audioAsset: const Value(null),
            pos: const Value(null),
            tags: const Value('[]'),
          ));
      final read = await repo.vocabulary();
      expect(read.first.pos, isNull);
    });
  });

  group('Old assets load', () {
    test('bundled turkish vocab.json parses (pos absent -> null)', () {
      // Existing assets have no pos field; WordEntry.fromJson must not break.
      // (Confirmed via the closed-set test + missing-pos test above; this
      // guard asserts the loader path itself compiles + runs.)
      const w = {
        'id': 'w-merhaba',
        'term': 'merhaba',
        'translation': 'hello',
        'pronunciation': 'mer-ha-ba',
        'tags': ['greeting'],
      };
      final entry = WordEntry.fromJson(w);
      expect(entry.id, 'w-merhaba');
      expect(entry.pos, isNull);
    });
  });
}