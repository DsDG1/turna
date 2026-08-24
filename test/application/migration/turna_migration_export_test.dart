import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:turna/application/backup/backup_manifest_policy.dart';
import 'package:turna/application/migration/turna_migration_export.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/service/locator.dart';

import '../../helpers/in_memory_course_db.dart';

void main() {
  late CourseDatabase db;
  late Directory tempRoot;

  setUp(() async {
    ensureSqliteLibForTestHost();
    SharedPreferences.setMockInitialValues({
      LocalStateKeys.score: 42,
      LocalStateKeys.streak: 3,
      LocalStateKeys.gems: 7,
      LocalStateKeys.completedLessonIds: <String>['lesson-a', 'lesson-b'],
      LocalStateKeys.perfectLessonIds: <String>['lesson-a'],
      LocalStateKeys.mistakeLog: jsonEncode([
        {
          'id': 'm1',
          'prompt': 'merhaba',
          'answer': 'hello',
          'userAnswer': 'hi',
        },
      ]),
      LocalStateKeys.aiEngineConfig: jsonEncode({
        'preset': 'openai',
        'apiKey': 'sk-secret-must-not-export',
        'model': 'gpt-test',
      }),
      'remoteBackup.config': 'should-never-appear',
    });
    db = CourseDatabase(NativeDatabase.memory());
    await db.customStatement('''
      INSERT INTO srs_states (
        word_id, queue, due_at, interval_days, ease, reps, lapses,
        is_leech, is_suspended, is_buried, type, fsrs_state
      ) VALUES (
        'w1', 'srs', 1000, 1, 2.5, 1, 0,
        0, 0, 0, 'word', 1
      )
    ''');
    await db.customStatement('''
      INSERT INTO review_events (
        card_id, queue, reviewed_at, quality,
        prev_interval_days, next_interval_days, prev_ease, next_ease,
        reps, lapses, type
      ) VALUES (
        'w1', 'srs', 2000, 4,
        1, 3, 2.5, 2.6,
        1, 0, 'word'
      )
    ''');
    await db.customStatement('''
      INSERT INTO anki_imports (
        import_id, source_path, source_hash, imported_at,
        deck_count, note_count, card_count, media_count
      ) VALUES (
        'imp1', '/tmp/deck.apkg', 'hash1', 3000,
        1, 1, 1, 0
      )
    ''');
    await db.customStatement('''
      INSERT INTO anki_notes (
        import_id, note_id, mid, tags, fields_json, sfld
      ) VALUES (
        'imp1', 1, 1, '', '["Q","A"]', 'Q'
      )
    ''');
    await db.customStatement('''
      INSERT INTO anki_cards_meta (
        import_id, card_id, note_id, ord, did, word_id, render_mode
      ) VALUES (
        'imp1', 10, 1, 0, 1, 'anki-imp1-c10', 'hybrid'
      )
    ''');
    tempRoot = await Directory.systemTemp.createTemp('turna-mig-');
  });

  tearDown(() async {
    await db.close();
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  test('exports turna-migration-v1 zip with required members and no secrets',
      () async {
    final mediaRoot = Directory('${tempRoot.path}/anki_media')..createSync();
    final mediaFile = File('${mediaRoot.path}/front.png')
      ..writeAsBytesSync(const [1, 2, 3, 4, 5]);

    final prefs = await SharedPreferences.getInstance();
    final exporter = TurnaMigrationExporter(
      db: db,
      legacyMediaRoot: mediaRoot,
      prefs: prefs,
      appVersion: '0.7.1-test',
      buildNumber: '2',
      platform: 'test',
    );
    final result = await exporter.exportTo(tempRoot);

    expect(result.zipFile.existsSync(), isTrue);
    expect(result.manifest['format'], kTurnaMigrationFormat);
    expect(result.manifest['legacyAnkiDisposition'], 'legacyPendingMigration');
    expect(result.manifest['counts']['srsStates'], 1);
    expect(result.manifest['counts']['ankiSources'], 1);
    expect(result.manifest['counts']['mediaObjects'], 1);

    final bytes = await result.zipFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final names = archive.map((f) => f.name).toSet();
    for (final required in [
      'manifest.json',
      'profile.json',
      'settings.json',
      'course_progress.jsonl',
      'srs_states.jsonl',
      'review_history.jsonl',
      'mistakes.jsonl',
      'anki_sources.jsonl',
      'anki_notes.jsonl',
      'anki_cards.jsonl',
      'introductions.jsonl',
      'media_manifest.json',
      'SHA256SUMS',
    ]) {
      expect(names.contains(required), isTrue, reason: required);
    }
    expect(names.any((n) => n.startsWith('media/')), isTrue);

    final settingsFile =
        archive.firstWhere((f) => f.name == 'settings.json');
    final settingsJson =
        jsonDecode(utf8.decode(settingsFile.content as List<int>))
            as Map<String, dynamic>;
    final entries = settingsJson['entries'] as Map<String, dynamic>;
    expect(entries.containsKey('remoteBackup.config'), isFalse);
    final ai = entries[LocalStateKeys.aiEngineConfig];
    expect(ai, isA<String>());
    expect(ai as String, isNot(contains('sk-secret-must-not-export')));
    expect(
      BackupManifestPolicy.stripApiKeyFromEngineConfig(ai),
      isNot(contains('sk-secret')),
    );

    final progress = utf8.decode(
      archive.firstWhere((f) => f.name == 'course_progress.jsonl').content
          as List<int>,
    );
    expect(progress, contains('lesson-a'));
    expect(progress, contains('lesson-b'));

    final srs = utf8.decode(
      archive.firstWhere((f) => f.name == 'srs_states.jsonl').content
          as List<int>,
    );
    expect(srs, contains('w1'));

    final mediaSha = result.sha256Sums.keys
        .firstWhere((k) => k.startsWith('media/'))
        .split('/')
        .last;
    expect(mediaFile.existsSync(), isTrue);
    expect(
      archive.any((f) => f.name == 'media/$mediaSha'),
      isTrue,
    );
  });

  test('export is repeatable and does not mutate source db rows', () async {
    final prefs = await SharedPreferences.getInstance();
    final exporter = TurnaMigrationExporter(
      db: db,
      prefs: prefs,
      platform: 'test',
    );
    final first = await exporter.exportTo(tempRoot);
    final before = await db.customSelect('SELECT COUNT(*) AS c FROM srs_states').get();
    final secondDir = Directory('${tempRoot.path}/second')..createSync();
    final second = await exporter.exportTo(secondDir);
    final after = await db.customSelect('SELECT COUNT(*) AS c FROM srs_states').get();

    expect(before.single.read<int>('c'), after.single.read<int>('c'));
    expect(first.manifest['format'], second.manifest['format']);
    expect(second.zipFile.existsSync(), isTrue);
  });
}
