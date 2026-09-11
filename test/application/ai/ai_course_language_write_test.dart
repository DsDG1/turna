// Regression tests for multi-language AI write paths:
//
// - `saveSectionJson` / `save` must tag every row with the owning
//   `language_code` (payload `language` field wins, else the active practice
//   language). The composite PK is (language_code, id), so the old 'tr'
//   column default both mislabeled non-Turkish content and forked duplicate
//   rows on update.
// - Writing a section/unit/lesson id that another language already owns
//   must fail loudly — runtime lookups are by bare id, so duplicates throw
//   downstream.
// - `updateLessonInDb` must upsert under the existing row's language, not
//   fork a (tr, id) twin that breaks `lessonById`'s getSingleOrNull.
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:turna/application/ai/ai_course_provider.dart';
import 'package:turna/application/ai/engine/ai_cache.dart';
import 'package:turna/application/ai/engine/ai_engine.dart';
import 'package:turna/application/ai/engine/ai_http_client.dart';
import 'package:turna/courses/languages/language_content_store.dart';
import 'package:turna/data/course_database.dart' as db;
import 'package:turna/data/course_repository.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/repositories/i_course_repository.dart';

import '../../helpers/in_memory_course_db.dart';

Map<String, dynamic> _sectionPayload({
  String id = 'ai-fr-s1',
  String unitId = 'ai-fr-u1',
  String lessonId = 'ai-fr-l1',
  String? language,
}) {
  return <String, dynamic>{
    'id': id,
    'name': 'AI French Section',
    'level': 'A1',
    if (language != null) 'language': language,
    'prerequisiteSectionIds': <String>[],
    'words': [
      {
        'id': 'ai-fr-w1',
        'term': 'bonjour',
        'translation': 'hello',
        'partOfSpeech': 'interjection',
      }
    ],
    'expressions': <Map<String, dynamic>>[],
    'grammarPoints': <Map<String, dynamic>>[],
    'units': [
      {
        'id': unitId,
        'name': 'U1',
        'lessons': [
          {
            'id': lessonId,
            'name': 'L1',
            'type': 'review',
            'template': 'legacy',
            'prerequisiteLessonIds': <String>[],
            'content': {
              'stages': [
                {
                  'id': 'st1',
                  'name': 'S1',
                  'items': [
                    {
                      'id': 'i1',
                      'type': 'multipleChoice',
                      'prompt': 'What does bonjour mean?',
                      'options': ['hello', 'bye', 'thanks'],
                      'correctIndex': 0,
                    }
                  ],
                }
              ],
            },
          },
        ],
      },
    ],
  };
}

AiCourseProvider _provider() => AiCourseProvider.withEngine(
      AiEngine(
        AiHttpClient.withClient(MockClient((_) async => http.Response('', 500))),
        AiCache.forTest(maxEntries: 0, enabled: false),
      ),
    );

Future<List<String>> _languagesOf(
  db.CourseDatabase database,
  String sectionId,
) async {
  final sections = await (database.select(database.sections)
        ..where((t) => t.id.equals(sectionId)))
      .get();
  return [for (final s in sections) s.languageCode];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late db.CourseDatabase database;

  setUp(() async {
    database = await seedInMemoryCourseDb();
    if (getIt.isRegistered<db.CourseDatabase>()) {
      await getIt.unregister<db.CourseDatabase>();
    }
    getIt.registerSingleton<db.CourseDatabase>(database);
    if (getIt.isRegistered<ICourseRepository>()) {
      await getIt.unregister<ICourseRepository>();
    }
    getIt.registerSingleton<ICourseRepository>(CourseRepository(database));
  });

  tearDown(() async {
    if (getIt.isRegistered<ICourseRepository>()) {
      await getIt.unregister<ICourseRepository>();
    }
    if (getIt.isRegistered<db.CourseDatabase>()) {
      await getIt.unregister<db.CourseDatabase>();
    }
    await database.close();
    LanguageContentStore.resetForTest();
  });

  test('saveSectionJson tags rows with the payload language', () async {
    await _provider().saveSectionJson(_sectionPayload(language: 'fr'));

    final repo = CourseRepository(database);
    final fr = await repo.sectionShells(languageCode: 'fr');
    expect(fr.map((s) => s.id), contains('ai-fr-s1'));
    // And it did NOT leak into Turkish.
    final tr = await repo.sectionShells(languageCode: 'tr');
    expect(tr.map((s) => s.id), isNot(contains('ai-fr-s1')));

    final vocab = await repo.vocabulary(languageCode: 'fr');
    expect(vocab.map((w) => w.id), contains('ai-fr-w1'));
  });

  test('saveSectionJson falls back to the active practice language',
      () async {
    await LanguageContentStore.activate('fr');
    await _provider().saveSectionJson(_sectionPayload());

    expect(await _languagesOf(database, 'ai-fr-s1'), ['fr']);
  });

  test('saveSectionJson rejects ids owned by another language', () async {
    // 'section1' is a Turkish builtin section id.
    expect(
      () => _provider().saveSectionJson(
        _sectionPayload(id: 'section1', language: 'fr'),
      ),
      throwsA(isA<StateError>()),
    );
    // Nothing written.
    expect(await _languagesOf(database, 'section1'), ['tr']);
  });

  test('updateLessonInDb upserts under the existing row language', () async {
    final repo = CourseRepository(database);
    final lesson = await repo.lessonById('fr-s1-l1');
    final renamed = lesson.copyWith(name: 'Renamed fr lesson');

    await _provider().updateLessonInDb(renamed);

    final rows = await (database.select(database.lessons)
          ..where((t) => t.id.equals('fr-s1-l1')))
        .get();
    expect(rows, hasLength(1));
    expect(rows.single.languageCode, 'fr');
    expect(rows.single.name, 'Renamed fr lesson');
    // No (tr, fr-s1-l1) twin row.
    expect(
      await (database.select(database.lessonContents)
            ..where((t) => t.lessonId.equals('fr-s1-l1')))
          .get()
          .then((r) => r.map((e) => e.languageCode).toList()),
      ['fr'],
    );
    // And the read path still resolves the lesson unambiguously.
    expect((await repo.lessonById('fr-s1-l1')).name, 'Renamed fr lesson');
  });
}
