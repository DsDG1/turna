// Integration test for the fidelity review path (deep-adaptation plan §3.4):
// a due card whose `anki_cards_meta.render_mode` is `fidelity` is rendered on
// demand from the NoteStore into an [AnkiHtmlCard], bypassing lesson-body
// loading.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:varnamala/application/anki/anki_models.dart';
import 'package:varnamala/application/anki/anki_review_assembler.dart';
import 'package:varnamala/application/course_provider.dart';
import 'package:varnamala/application/lesson_link_store.dart';
import 'package:varnamala/application/srs_provider.dart';
import 'package:varnamala/data/anki_import_dao.dart';
import 'package:varnamala/data/anki_note_dao.dart';
import 'package:varnamala/domain/course/interaction.dart';
import 'package:varnamala/service/locator.dart';

import '../../helpers/in_memory_course_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(ensurePathProviderMockForTest);

  test('fidelity card is rendered from NoteStore as ankiHtmlCard', () async {
    final db = await seedInMemoryCourseDb();
    final importDao = AnkiImportDao(db);
    final noteDao = AnkiNoteDao(db);
    await importDao.upsert(const AnkiImportRecord(
      importId: 'imp',
      sourcePath: '/x.apkg',
      sourceHash: 'h',
      importedAt: 1,
    ));
    await noteDao.upsertNotetype(AnkiNotetypeRecord(
      importId: 'imp',
      mid: 1,
      name: 'Basic',
      fieldNames: const ['Front', 'Back'],
      templates: const [
        AnkiTemplate(
          name: 'Card 1',
          qfmt: '{{Front}}',
          afmt: '{{FrontSide}}<hr id="answer">{{Back}}',
        ),
      ],
      css: '.card{color:red}',
    ));
    await noteDao.upsertNote(AnkiNoteRecord(
      importId: 'imp',
      noteId: 100,
      mid: 1,
      fields: const [
        'What is 2+2? [sound:prompt%20one.mp3]',
        '<audio src="answer.ogg"></audio>4',
      ],
    ));
    await noteDao.upsertCardMeta(AnkiCardMetaRecord(
      importId: 'imp',
      cardId: 1,
      noteId: 100,
      ord: 0,
      did: 1,
      wordId: 'anki-imp-c1',
      renderMode: 'fidelity',
    ));

    SharedPreferences.setMockInitialValues({});
    final sp = await StreamingSharedPreferences.instance;
    final prefs = AppPrefs(sp);
    await prefs.setString(PrefsConstants.courseScope, '');
    await prefs.preferences.setString(LocalStateKeys.srsState, '{}');
    final srs = SrsProvider(prefs, LessonLinkStore(prefs), emptySrsStateDao());
    srs.registerWord('anki-imp-c1');

    final courseProvider = CourseProvider(prefs);
    await courseProvider.load();

    final assembler =
        AnkiReviewAssembler(srs, courseProvider, noteDao: noteDao);
    final lesson = await assembler.assembleBatchAsync();

    expect(lesson, isNotNull);
    final items = lesson!.flattenedStages.expand((s) => s.items).toList();
    expect(items, hasLength(1));
    expect(items.single, isA<AnkiHtmlCard>());
    final html = items.single as AnkiHtmlCard;
    expect(html.frontHtml, contains('What is 2+2?'));
    expect(html.backHtml, contains('4'));
    expect(html.css, '.card{color:red}');
    expect(html.wordId, 'anki-imp-c1');
    expect(html.audioAssets, [
      'anki://imp/prompt one.mp3',
      'anki://imp/answer.ogg',
    ]);
  });

  test('structured projection still uses canonical card in primary review',
      () async {
    final db = await seedInMemoryCourseDb();
    final noteDao = AnkiNoteDao(db);
    final importDao = AnkiImportDao(db);
    await importDao.upsert(const AnkiImportRecord(
        importId: 'imp2', sourcePath: '/y', sourceHash: 'h2', importedAt: 2));
    await noteDao.upsertCardMeta(AnkiCardMetaRecord(
      importId: 'imp2',
      cardId: 9,
      noteId: 99,
      wordId: 'anki-imp2-c9',
      renderMode: 'structured',
    ));
    await noteDao.upsertNotetype(const AnkiNotetypeRecord(
      importId: 'imp2',
      mid: 7,
      name: 'Choice projection source',
      fieldNames: ['Front', 'Back'],
      templates: [
        AnkiTemplate(
          name: 'Card 1',
          qfmt: '{{Front}}',
          afmt: '{{FrontSide}}<hr>{{Back}}',
        ),
      ],
    ));
    await noteDao.upsertNote(const AnkiNoteRecord(
      importId: 'imp2',
      noteId: 99,
      mid: 7,
      fields: ['Question source', 'Answer source'],
    ));

    SharedPreferences.setMockInitialValues({});
    final sp = await StreamingSharedPreferences.instance;
    final prefs = AppPrefs(sp);
    await prefs.setString(PrefsConstants.courseScope, '');
    await prefs.preferences.setString(LocalStateKeys.srsState, '{}');
    final srs = SrsProvider(prefs, LessonLinkStore(prefs), emptySrsStateDao());
    srs.registerWord('anki-imp2-c9');

    final courseProvider = CourseProvider(prefs);
    await courseProvider.load();

    final assembler =
        AnkiReviewAssembler(srs, courseProvider, noteDao: noteDao);
    final lesson = await assembler.assembleBatchAsync();
    final item = lesson!.flattenedStages.single.items.single;
    expect(item, isA<AnkiHtmlCard>());
    expect((item as AnkiHtmlCard).frontHtml, contains('Question source'));
  });

  test('cached prerendered HTML is served with JS disabled (no re-decrypt)',
      () async {
    final db = await seedInMemoryCourseDb();
    final noteDao = AnkiNoteDao(db);
    final importDao = AnkiImportDao(db);
    await importDao.upsert(const AnkiImportRecord(
        importId: 'imp', sourcePath: '/x', sourceHash: 'h', importedAt: 1));
    // JS notetype (allowJs=true) - would normally need the WebView to decrypt.
    await noteDao.upsertNotetype(AnkiNotetypeRecord(
      importId: 'imp',
      mid: 1,
      name: 'Encrypted',
      allowJs: true,
      fieldNames: const ['Front', 'Back'],
      templates: const [
        AnkiTemplate(
            name: 'C', qfmt: '{{Front}}<script>d()</script>', afmt: '{{Back}}'),
      ],
      css: '.card{}',
    ));
    await noteDao.upsertNote(AnkiNoteRecord(
        importId: 'imp',
        noteId: 1,
        mid: 1,
        fields: const ['cipher', 'cipher']));
    await noteDao.upsertCardMeta(AnkiCardMetaRecord(
      importId: 'imp',
      cardId: 1,
      noteId: 1,
      wordId: 'anki-imp-c1',
      renderMode: 'fidelity',
    ));
    // Pre-populate the cache (simulating a prior capture after JS decryption).
    await noteDao.upsertPrerenderedFace('anki-imp-c1',
        front: '<p>解密题目</p>', back: '<p>解密答案</p>');

    SharedPreferences.setMockInitialValues({});
    final sp = await StreamingSharedPreferences.instance;
    final prefs = AppPrefs(sp);
    await prefs.setString(PrefsConstants.courseScope, '');
    await prefs.preferences.setString(LocalStateKeys.srsState, '{}');
    final srs = SrsProvider(prefs, LessonLinkStore(prefs), emptySrsStateDao());
    srs.registerWord('anki-imp-c1');
    final courseProvider = CourseProvider(prefs);
    await courseProvider.load();

    final assembler =
        AnkiReviewAssembler(srs, courseProvider, noteDao: noteDao);
    final lesson = await assembler.assembleBatchAsync();
    expect(lesson, isNotNull);
    final item = lesson!.flattenedStages.expand((s) => s.items).single;
    expect(item, isA<AnkiHtmlCard>());
    final html = item as AnkiHtmlCard;
    expect(html.allowJs, isFalse); // cached -> no JS, no re-decrypt
    expect(html.frontHtml, contains('解密题目'));
    expect(html.backHtml, contains('解密答案'));
  });
}
