// 「拔掉 turkish 资产、只留法语」启动链路测试。法语课程是多语言并存
// 机制的验收 fixture，不是真的课程，不在开发计划内；本测试借它验证
// manifest 缺失语言时的注册表、AI 上下文与 seeder 行为。
import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/ai/learner_ai_context_assembler.dart';
import 'package:turna/application/language_registry.dart';
import 'package:turna/courses/course_loader.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/data/course_database_seeder.dart';
import 'package:turna/data/course_repository.dart';
import 'package:turna/domain/course/language_codes.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqliteLibForTestHost();

  test('seed and registry work when turkish assets are omitted', () async {
    final frenchIndex = File('assets/courses/french/index.json').readAsStringSync();
    final frenchVocab = File('assets/courses/french/vocab.json').readAsStringSync();
    final frenchGrammar =
        File('assets/courses/french/grammar_points.json').readAsStringSync();
    final frenchExpr =
        File('assets/courses/french/expressions.json').readAsStringSync();
    final frenchSection =
        File('assets/courses/french/sections/fr-section1.json').readAsStringSync();

    final bundle = _MapBundle({
      languageManifestPath: jsonEncode({
        'languages': [
          {
            'code': 'fr',
            'displayName': 'French',
            'ttsLocale': 'fr-FR',
            'dir': 'french',
          },
        ],
      }),
      'assets/courses/french/index.json': frenchIndex,
      'assets/courses/french/vocab.json': frenchVocab,
      'assets/courses/french/grammar_points.json': frenchGrammar,
      'assets/courses/french/expressions.json': frenchExpr,
      'assets/courses/french/sections/fr-section1.json': frenchSection,
    });

    LanguageRegistry.instance.resetForTest();
    addTearDown(LanguageRegistry.instance.resetForTest);
    await LanguageRegistry.instance.load(bundle: bundle);
    expect(LanguageRegistry.instance.defaultCode, LanguageCodes.french);
    expect(LanguageRegistry.instance.displayName('fr'), 'French');
    expect(LanguageRegistry.instance.ttsLocale('fr'), 'fr-FR');

    final ctx = await LearnerAiContextAssembler.assemble();
    expect(ctx.languageName, 'French');

    expect(CourseLoader.baseDirFor('fr'), 'assets/courses/french');
    expect(CourseLoader.indexAssetFor('fr'), isNot(contains('turkish')));

    final db = CourseDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final wrote = await DatabaseSeeder(db, bundle: bundle).seedIfNeeded();
    expect(wrote, isTrue);

    final repo = CourseRepository(db);
    expect(await repo.sectionShells(languageCode: LanguageCodes.turkish), isEmpty);
    final french = await repo.sectionShells(languageCode: LanguageCodes.french);
    expect(french, isNotEmpty);
    expect(french.single.id, 'fr-section1');
    final vocab = await repo.vocabulary(languageCode: LanguageCodes.french);
    expect(vocab.map((w) => w.id), contains('fr-w-bonjour'));
  });
}

const languageManifestPath = 'assets/courses/manifest.json';
