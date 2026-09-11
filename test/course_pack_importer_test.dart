import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:turna/application/course_catalog.dart';
import 'package:turna/application/course_pack/course_pack.dart';
import 'package:turna/application/course_pack/course_pack_importer.dart';
import 'package:turna/application/course_pack/course_pack_media.dart';
import 'package:turna/application/course_pack/imported_languages.dart';
import 'package:turna/application/language_registry.dart';
import 'package:turna/courses/course_loader.dart';
import 'package:turna/courses/language_manifest.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/domain/course/course_scope.dart';

import 'helpers/in_memory_course_db.dart';

Map<String, dynamic> _miniPack({
  String code = 'es',
  String unitId = 'll-es-u-1',
  String lessonId = 'll-es-l-1',
  String wordId = 'll-es-w-hola',
  String format = 'turnapack/1',
  String? imageAsset,
  String? audioAsset,
}) {
  final sectionId = 'll-$code-s-1';
  final sectionFile = 'sections/$sectionId.json';
  return {
    'format': format,
    'packVersion': 1,
    'language': {
      'code': code,
      'displayName': 'Spanish',
      'ttsLocale': 'es-ES',
      'nativeLabel': 'Aprende español',
      'signatureChars': 'ñÑáéíóúüÜ¿¡',
    },
    'license': {
      'name': 'CC BY-SA 4.0',
      'attribution': 'LibreLingo community',
      'link': 'https://creativecommons.org/licenses/by-sa/4.0/',
    },
    'files': {
      'index.json': {
        'version': 1,
        'language': code,
        'displayName': 'Spanish',
        'sections': [
          {
            'id': sectionId,
            'name': 'Basics',
            'description': 'Basics',
            'level': 'A1',
            'prerequisiteSectionIds': <String>[],
            'file': sectionFile,
          }
        ],
      },
      'vocab.json': {
        'version': 1,
        'language': code,
        'words': [
          {
            'id': wordId,
            'term': 'hola',
            'translation': 'hello',
            'tags': ['noun'],
            if (audioAsset != null) 'audioAsset': audioAsset,
          }
        ],
      },
      'expressions.json': {
        'version': 4,
        'language': code,
        'expressions': <Map<String, dynamic>>[],
      },
      'grammar_points.json': {'grammarPoints': <Map<String, dynamic>>[]},
      sectionFile: {
        'id': sectionId,
        'name': 'Basics',
        'description': 'Basics',
        'units': [
          {
            'id': unitId,
            'name': 'Basics',
            'description': 'Basics',
            'prerequisiteUnitIds': <String>[],
            'lessons': [
              {
                'id': lessonId,
                'name': 'Hola',
                'description': '',
                'type': 'normal',
                'template': 'intro',
                'prerequisiteLessonIds': <String>[],
                'content': {
                  'subLessons': [
                    {
                      'id': 'll-$code-sl-hola',
                      'name': 'hola',
                      'stages': [
                        {
                          'id': 'll-$code-st-hola',
                          'name': 'Learn',
                          'items': [
                            {
                              'runtimeType': 'showWord',
                              'id': 'll-$code-i-sw-1',
                              'wordId': wordId,
                              'context': 'hola — hello',
                              if (imageAsset != null) 'imageAsset': imageAsset,
                            },
                            {
                              'runtimeType': 'fillBlank',
                              'id': 'll-$code-i-fb-1',
                              'sentence': '_____.',
                              'answer': 'hola',
                              'hint': 'hello',
                            },
                          ],
                        }
                      ],
                    }
                  ],
                },
              }
            ],
          }
        ],
      },
    },
  };
}

List<int> _zipOf(Map<String, dynamic> pack, Map<String, List<int>> media) {
  final archive = Archive();
  final packBytes = utf8.encode(jsonEncode(pack));
  archive.addFile(ArchiveFile('pack.json', packBytes.length, packBytes));
  media.forEach((name, bytes) {
    archive.addFile(ArchiveFile('media/$name', bytes.length, bytes));
  });
  return ZipEncoder().encode(archive);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqliteLibForTestHost();
  ensurePathProviderMockForTest();

  late CourseDatabase db;
  late Directory persistDir;

  setUp(() async {
    ImportedLanguageRegistry.instance.resetForTest();
    LanguageRegistry.instance.replaceForTest(LanguageManifest.packedFallback);
    db = CourseDatabase(NativeDatabase.memory());
    CourseLoader.overrideDatabase(() => db);
    persistDir = await Directory.systemTemp.createTemp('turnapack-');
  });

  tearDown(() async {
    CourseLoader.clearDatabaseOverride();
    ImportedLanguageRegistry.instance.resetForTest();
    LanguageRegistry.instance.resetForTest();
    await db.close();
    if (persistDir.existsSync()) {
      persistDir.deleteSync(recursive: true);
    }
  });

  CoursePackImporter importer({Future<void> Function()? fail}) =>
      CoursePackImporter(
        db,
        persistDirectory: persistDir,
        afterTablesCleared: fail,
      );

  test('imports a valid pack into the catalog overlay', () async {
    final result = await importer().importFromString(jsonEncode(_miniPack()));
    expect(result.displayName, 'Spanish');
    expect(result.sectionCount, 1);
    expect(result.wordCount, 1);
    final entries = await CourseCatalog.load(courseDb: db);
    expect(
      entries.any((e) =>
          e.displayName == 'Spanish' &&
          e.scope == const BuiltinCourseScope('es')),
      isTrue,
    );
    expect(
      ImportedLanguageRegistry.instance.ttsLocaleOrNull('es'),
      'es-ES',
    );
    expect(
      File('${persistDir.path}/es.turnapack').existsSync(),
      isTrue,
    );
    final version = await (db.select(db.courseMeta)
          ..where((t) => t.key.equals('contentVersion:es')))
        .getSingle();
    expect(version.value, '1+4');
  });

  test('rejects unsupported format', () async {
    expect(
      () => importer().importFromString(jsonEncode({'format': 'turnapack/9'})),
      throwsA(isA<CoursePackImportException>()),
    );
  });

  test('rejects reserved and builtin codes', () async {
    expect(
      () => importer()
          .importFromString(jsonEncode(_miniPack(code: 'anki'))),
      throwsA(isA<CoursePackImportException>()),
    );
    expect(
      () =>
          importer().importFromString(jsonEncode(_miniPack(code: 'tr'))),
      throwsA(isA<CoursePackImportException>()),
    );
  });

  test('rejects ids without ll-<code>- prefix', () async {
    expect(
      () => importer().importFromString(
        jsonEncode(_miniPack(wordId: 'w-hola')),
      ),
      throwsA(isA<CoursePackImportException>()),
    );
  });

  test('rejects colliding unit ids from another language', () async {
    await db.into(db.units).insert(
          UnitsCompanion.insert(
            id: 'll-es-u-1',
            languageCode: const Value('de'),
            sectionId: 'other',
            name: 'x',
          ),
        );
    expect(
      () => importer().importFromString(jsonEncode(_miniPack())),
      throwsA(isA<CoursePackImportException>()),
    );
    final rows = await (db.select(db.sections)
          ..where((t) => t.languageCode.equals('es')))
        .get();
    expect(rows, isEmpty);
  });

  test('reimport rewrites contentVersion', () async {
    await importer().importFromString(jsonEncode(_miniPack()));
    await importer().importFromString(jsonEncode(_miniPack()));
    final words = await (db.select(db.vocabulary)
          ..where((t) => t.languageCode.equals('es')))
        .get();
    expect(words, hasLength(1));
  });

  test('mid-write failure leaves zero residue', () async {
    expect(
      () => importer(fail: () async => throw StateError('boom'))
          .importFromString(jsonEncode(_miniPack())),
      throwsA(anything),
    );
    final sections = await (db.select(db.sections)
          ..where((t) => t.languageCode.equals('es')))
        .get();
    expect(sections, isEmpty);
    final vocab = await (db.select(db.vocabulary)
          ..where((t) => t.languageCode.equals('es')))
        .get();
    expect(vocab, isEmpty);
    final meta = await (db.select(db.courseMeta)
          ..where((t) => t.key.equals('contentVersion:es')))
        .get();
    expect(meta, isEmpty);
  });

  test('uninstall marker then reimport from persisted pack', () async {
    await importer().importFromString(jsonEncode(_miniPack()));
    await db.transaction(() async {
      await (db.delete(db.sections)..where((t) => t.languageCode.equals('es')))
          .go();
      await (db.delete(db.units)..where((t) => t.languageCode.equals('es')))
          .go();
      await (db.delete(db.lessons)..where((t) => t.languageCode.equals('es')))
          .go();
      await (db.delete(db.lessonContents)
            ..where((t) => t.languageCode.equals('es')))
          .go();
      await (db.delete(db.vocabulary)..where((t) => t.languageCode.equals('es')))
          .go();
    });
    final packFile = File('${persistDir.path}/es.turnapack');
    expect(packFile.existsSync(), isTrue);
    await importer().importFromFile(packFile.path);
    final sections = await (db.select(db.sections)
          ..where((t) => t.languageCode.equals('es')))
        .get();
    expect(sections, isNotEmpty);
  });

  test('fixture mini.turnapack imports', () async {
    final fixture = File('test/fixtures/mini.turnapack');
    expect(fixture.existsSync(), isTrue);
    final result = await importer().importFromFile(fixture.path);
    expect(result.code, 'es');
    expect(result.wordCount, greaterThan(0));
    expect(result.sectionCount, greaterThan(0));
  });

  test('real LibreLingo ES pack imports when present', () async {
    // Built by: python tool/librelingo_import.py --course-dir
    // ../LibreLingo-ES-from-EN/course --code es ... --out ../dist/es.turnapack
    final pack = File('../dist/es.turnapack');
    if (!pack.existsSync()) {
      markTestSkipped('real course pack ../dist/es.turnapack not built');
      return;
    }
    final result = await importer().importFromBytes(pack.readAsBytesSync());
    expect(result.code, 'es');
    expect(result.sectionCount, greaterThanOrEqualTo(3));
    expect(result.wordCount, greaterThanOrEqualTo(100));
    final entries = await CourseCatalog.load(courseDb: db);
    expect(
      entries.any((e) => e.scope == const BuiltinCourseScope('es')),
      isTrue,
    );
  });

  test('zip pack extracts media and rewrites refs', () async {
    final jpeg = [0xFF, 0xD8, 0xFF, 0xD9];
    final zip = _zipOf(
      _miniPack(
        format: 'turnapack/2',
        imageAsset: 'media/dog1.jpg',
        audioAsset: 'media/hola.mp3',
      ),
      {
        'dog1.jpg': jpeg,
        'hola.mp3': utf8.encode('ID3'),
      },
    );
    await importer().importFromBytes(zip);
    final contents = await (db.select(db.lessonContents)
          ..where((t) => t.languageCode.equals('es')))
        .get();
    expect(contents.single.contentJson, contains('turnapack://es/dog1.jpg'));
    final words = await (db.select(db.vocabulary)
          ..where((t) => t.languageCode.equals('es')))
        .get();
    expect(words.single.audioAsset, 'turnapack://es/hola.mp3');
    expect(File(p.join(persistDir.path, 'es', 'media', 'dog1.jpg')).existsSync(), isTrue);
    expect(File(p.join(persistDir.path, 'es', 'media', 'hola.mp3')).existsSync(), isTrue);
    expect(
      await CoursePackMedia.resolveFile(
        'turnapack://es/dog1.jpg',
        persist: persistDir,
      ),
      File(p.join(persistDir.path, 'es', 'media', 'dog1.jpg')).path,
    );
  });

  test('json pack that references media/ is rejected', () async {
    expect(
      () => importer().importFromString(
        jsonEncode(_miniPack(imageAsset: 'media/dog1.jpg')),
      ),
      throwsA(isA<CoursePackImportException>()),
    );
  });

  test('zip-slip media entries are rejected', () async {
    final zip = _zipOf(_miniPack(format: 'turnapack/2'), const {});
    final archive = ZipDecoder().decodeBytes(zip);
    archive.addFile(ArchiveFile('../evil.jpg', 4, [1, 2, 3, 4]));
    expect(
      () => importer().importFromBytes(ZipEncoder().encode(archive)),
      throwsA(isA<CoursePackImportException>()),
    );
  });

  test('nested media/ paths are rejected', () async {
    // `media/media/x.jpg` would write under media/media/ on disk while
    // turnapack:// resolution strips one level — the ref could never
    // resolve, so the pack is refused up front.
    final zip = _zipOf(
      _miniPack(format: 'turnapack/2', imageAsset: 'media/media/x.jpg'),
      {'media/x.jpg': const [0xFF, 0xD8, 0xFF, 0xD9]},
    );
    expect(
      () => importer().importFromBytes(zip),
      throwsA(isA<CoursePackImportException>()),
    );
  });

  test('index sections[].id must match the section file id', () async {
    final pack = _miniPack();
    final index = pack['files']['index.json'] as Map<String, dynamic>;
    (index['sections'] as List).first['id'] = 'll-es-s-9';
    expect(
      () => importer().importFromString(jsonEncode(pack)),
      throwsA(isA<CoursePackImportException>()),
    );
  });

  test('non-UTF8 bytes surface a clean import error', () async {
    expect(
      () => importer().importFromBytes(const [0xFF, 0xFE, 0x00, 0x01]),
      throwsA(isA<CoursePackImportException>()),
    );
  });

  test('reimport replaces extracted media', () async {
    final jpeg = [0xFF, 0xD8, 0xFF, 0xD9];
    await importer().importFromBytes(
      _zipOf(_miniPack(format: 'turnapack/2', imageAsset: 'media/a.jpg'),
          {'a.jpg': jpeg}),
    );
    await importer().importFromBytes(
      _zipOf(_miniPack(format: 'turnapack/2', imageAsset: 'media/b.jpg'),
          {'b.jpg': jpeg}),
    );
    final mediaDir = Directory(p.join(persistDir.path, 'es', 'media'));
    expect(File(p.join(mediaDir.path, 'a.jpg')).existsSync(), isFalse);
    expect(File(p.join(mediaDir.path, 'b.jpg')).existsSync(), isTrue);
    expect(
      Directory('${mediaDir.path}.staging').existsSync(),
      isFalse,
      reason: 'staging dir must be consumed by the rename',
    );
  });

  test('failed reimport of an uninstalled language keeps its marker',
      () async {
    await importer().importFromString(jsonEncode(_miniPack()));
    await db.into(db.courseMeta).insertOnConflictUpdate(
          CourseMetaCompanion.insert(
            key: 'uninstalled:es',
            value: '1',
          ),
        );
    expect(
      () => importer(fail: () async => throw StateError('boom'))
          .importFromString(jsonEncode(_miniPack())),
      throwsA(anything),
    );
    final markers = await (db.select(db.courseMeta)
          ..where((t) => t.key.equals('uninstalled:es')))
        .get();
    expect(markers, hasLength(1),
        reason: 'marker must survive so the language stays restorable');
  });

  test('successful reimport clears a stale uninstall marker', () async {
    await importer().importFromString(jsonEncode(_miniPack()));
    await db.into(db.courseMeta).insertOnConflictUpdate(
          CourseMetaCompanion.insert(
            key: 'uninstalled:es',
            value: '1',
          ),
        );
    await importer().importFromString(jsonEncode(_miniPack()));
    final markers = await (db.select(db.courseMeta)
          ..where((t) => t.key.equals('uninstalled:es')))
        .get();
    expect(markers, isEmpty);
  });
}
