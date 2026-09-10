// Regression tests for the seeder's multi-language fault tolerance:
//
// - one builtin language whose unit/lesson ids collide with another
//   language's must not take the whole startup down — seedIfNeeded skips it
//   (clear validation log) and keeps seeding the rest;
// - the explicit reinstall path (seedLanguage) still throws so a
//   user-triggered restore surfaces the collision.
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/language_registry.dart';
import 'package:turna/courses/course_validator.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/data/course_database_seeder.dart';
import 'package:turna/data/course_repository.dart';

import '../helpers/in_memory_course_db.dart';

class _MapBundle extends CachingAssetBundle {
  _MapBundle(this.files);
  final Map<String, String> files;

  @override
  Future<ByteData> load(String key) async {
    final text = files[key];
    if (text == null) {
      throw FlutterError('Unable to load asset: $key');
    }
    return ByteData.view(Uint8List.fromList(utf8.encode(text)).buffer);
  }
}

const _manifestPath = 'assets/courses/manifest.json';

/// Two synthetic languages whose section trees share the SAME unit/lesson
/// ids (both reuse the French fixture verbatim): the second language's seed
/// must trip the cross-language id validation.
_MapBundle _collidingBundle() {
  final frenchVocab =
      File('assets/courses/french/vocab.json').readAsStringSync();
  final frenchSection =
      File('assets/courses/french/sections/fr-section1.json').readAsStringSync();

  String indexFor(String code) => jsonEncode({
        'language': code,
        'version': '1',
        'sections': [
          {'file': 'sections/s1.json'},
        ],
      });

  return _MapBundle({
    _manifestPath: jsonEncode({
      'languages': [
        {'code': 'xx', 'displayName': 'Xx', 'ttsLocale': 'xx-XX', 'dir': 'xx'},
        {'code': 'yy', 'displayName': 'Yy', 'ttsLocale': 'yy-YY', 'dir': 'yy'},
      ],
    }),
    'assets/courses/xx/index.json': indexFor('xx'),
    'assets/courses/xx/vocab.json': frenchVocab,
    'assets/courses/xx/sections/s1.json': frenchSection,
    'assets/courses/yy/index.json': indexFor('yy'),
    'assets/courses/yy/vocab.json': frenchVocab,
    'assets/courses/yy/sections/s1.json': frenchSection,
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqliteLibForTestHost();

  setUp(() {
    LanguageRegistry.instance.resetForTest();
  });

  tearDown(() {
    LanguageRegistry.instance.resetForTest();
  });

  test('seedIfNeeded skips a colliding language and keeps the other',
      () async {
    final bundle = _collidingBundle();
    final db = CourseDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final wrote = await DatabaseSeeder(db, bundle: bundle).seedIfNeeded();

    // The first language seeded; the second collided and was skipped —
    // no throw, and the survivor is fully present.
    expect(wrote, isTrue);
    final repo = CourseRepository(db);
    expect(await repo.sectionShells(languageCode: 'xx'), isNotEmpty);
    expect(await repo.sectionShells(languageCode: 'yy'), isEmpty);
  });

  test('seedLanguage still throws on a cross-language id collision',
      () async {
    final bundle = _collidingBundle();
    final db = CourseDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final seeder = DatabaseSeeder(db, bundle: bundle);
    expect(await seeder.seedLanguage('xx'), isTrue);
    expect(
      () => seeder.seedLanguage('yy'),
      throwsA(isA<CourseValidationException>()),
    );
  });
}
