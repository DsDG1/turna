// Round-trip and failure-path tests for the unified local export/import
// pipeline (Plan §10.6): progress round-trips with clamping, unknown keys
// are ignored, v1 course-only files report honestly, secrets never enter
// the file, and a mid-import crash rolls back via the journal.

// Dart imports:
import 'dart:convert';
import 'dart:io';

// Flutter imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';

// Package imports:
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

// Project imports:
import 'package:turna/application/backup/backup_restore_journal.dart';
import 'package:turna/application/backup/backup_schema.dart';
import 'package:turna/service/export_service.dart';
import 'package:turna/service/locator.dart';

/// path_provider stub: export() writes into a real temp directory.
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.dir);

  final Directory dir;

  @override
  Future<String?> getTemporaryPath() async => dir.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late AppPrefs prefs;
  late ExportService service;

  setUp(() async {
    PackageInfo.setMockInitialValues(
      appName: 'turna',
      packageName: 'me.dsdogs.turna',
      version: '0.8.0',
      buildNumber: '9',
      buildSignature: '',
    );
    SharedPreferences.setMockInitialValues({});
    final sp = await StreamingSharedPreferences.instance;
    await sp.remove('restore.inProgress');
    for (final key in sp.getKeys().getValue().toList()) {
      await sp.remove(key);
    }
    prefs = AppPrefs(sp);
    tmp = await Directory.systemTemp.createTemp('turna_export');
    PathProviderPlatform.instance = _FakePathProvider(tmp);
    service = ExportService(prefs);
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  Future<File> writeBackup(Map<String, dynamic> doc) async {
    final file = File('${tmp.path}/backup.json');
    await file.writeAsString(jsonEncode(doc));
    return file;
  }

  test('v2 export -> wipe -> import restores every covered key', () async {
    await prefs.setInt(LocalStateKeys.score, 320);
    await prefs.setInt(LocalStateKeys.streak, 9);
    await prefs.setDouble(LocalStateKeys.ttsSpeed, 1.25);
    await prefs.setInt(LocalStateKeys.textScale, 130);
    await prefs.setDouble(LocalStateKeys.srsDesiredRetention, 0.88);
    await prefs.setString(LocalStateKeys.srsFsrsParameters, '[0.1, 0.2]');
    await prefs.setInt('anki.dailyNewLimit', 12);
    await prefs.setBool('anki.dailyChallengeIncludesAnki', value: false);
    await prefs.setBool('settings.autoReadOnTap.builtin', value: false);
    await prefs.setString('settings.nativeLang.builtin', 'zh');
    await prefs.setStringList(
        LocalStateKeys.streakProtectedDays, ['2026-08-01', '2026-08-02']);

    final exported = await service.export();
    final raw = await exported.readAsString();

    // Secrets never enter the file even though aiEngineConfig is covered.
    expect(raw.contains('password'), isFalse);
    expect(raw.contains('remoteBackup.'), isFalse);

    // Wipe some covered keys, then import.
    await prefs.preferences.remove(LocalStateKeys.score);
    await prefs.preferences.remove(LocalStateKeys.srsFsrsParameters);
    await prefs.preferences.remove('anki.dailyNewLimit');
    await prefs.preferences.remove('settings.autoReadOnTap.builtin');

    final outcome = await service.importFromFile(exported.path);
    expect(outcome.progressRestored, isTrue);
    expect(outcome.legacyCoursePayloadIgnored, isFalse);

    expect(
      prefs.preferences
          .getInt(LocalStateKeys.score, defaultValue: -1)
          .getValue(),
      320,
    );
    expect(
      prefs.preferences
          .getString(LocalStateKeys.srsFsrsParameters, defaultValue: '')
          .getValue(),
      '[0.1, 0.2]',
    );
    expect(
      prefs.preferences
          .getInt('anki.dailyNewLimit', defaultValue: -1)
          .getValue(),
      12,
    );
    expect(
      prefs.preferences
          .getBool('settings.autoReadOnTap.builtin', defaultValue: true)
          .getValue(),
      isFalse,
    );
    // The journal committed - no pending marker left behind.
    expect(
      prefs.preferences
          .getString('restore.inProgress', defaultValue: '')
          .getValue(),
      isEmpty,
    );
  });

  test('out-of-range values are clamped on import, never enter live state',
      () async {
    final doc = BackupEnvelopeWriter.build(
      appId: 'me.dsdogs.turna',
      appVersion: '0.8.0',
      buildNumber: '9',
      language: 'turkish',
      progress: {
        'settings.ttsSpeed': 42.0,
        'settings.textScale': 400,
        'settings.dailyReminderHour': 99,
        'srs.desiredRetention': 0.1,
      },
    );
    final file = await writeBackup(doc);
    final outcome = await service.importFromFile(file.path);
    expect(outcome.progressRestored, isTrue);

    expect(
      prefs.preferences
          .getDouble(LocalStateKeys.ttsSpeed, defaultValue: -1)
          .getValue(),
      2.0,
    );
    expect(
      prefs.preferences
          .getInt(LocalStateKeys.textScale, defaultValue: -1)
          .getValue(),
      200,
    );
    expect(
      prefs.preferences
          .getInt(LocalStateKeys.dailyReminderHour, defaultValue: -1)
          .getValue(),
      23,
    );
    expect(
      prefs.preferences
          .getDouble(LocalStateKeys.srsDesiredRetention, defaultValue: -1)
          .getValue(),
      0.8,
    );
  });

  test('unknown keys in the file are ignored, not written', () async {
    final doc = BackupEnvelopeWriter.build(
      appId: 'me.dsdogs.turna',
      appVersion: '0.8.0',
      buildNumber: '9',
      language: 'turkish',
      progress: {'malicious.unknown.key': 'nope'},
    );
    final file = await writeBackup(doc);
    final outcome = await service.importFromFile(file.path);
    expect(outcome.progressRestored, isTrue);
    expect(
      prefs.preferences
          .getString('malicious.unknown.key', defaultValue: '')
          .getValue(),
      isEmpty,
    );
  });

  test('v1 fixture with course payload reports it honestly as ignored',
      () async {
    final file = File('test/fixtures/backup/v1_local_export.json');
    final outcome = await service.importFromFile(file.path);

    expect(outcome.progressRestored, isTrue);
    expect(
      prefs.preferences
          .getInt(LocalStateKeys.score, defaultValue: -1)
          .getValue(),
      120,
    );
    expect(outcome.legacyCoursePayloadIgnored, isTrue);
  });

  test('future schema file is rejected before any write', () async {
    final file = File('test/fixtures/backup/future_v3_export.json');
    await expectLater(
      service.importFromFile(file.path),
      throwsA(isA<BackupSchemaException>()
          .having((e) => e.code, 'code', 'backup.futureSchema')),
    );
    expect(
      prefs.preferences
          .getString('restore.inProgress', defaultValue: '')
          .getValue(),
      isEmpty,
      reason: 'rejected files must not even arm the journal',
    );
  });

  test('type-mismatched file is rejected before any write', () async {
    final doc = BackupEnvelopeWriter.build(
      appId: 'me.dsdogs.turna',
      appVersion: '0.8.0',
      buildNumber: '9',
      language: 'turkish',
      progress: {'game.score': 'not-an-int'},
    );
    final file = await writeBackup(doc);
    await expectLater(
      service.importFromFile(file.path),
      throwsA(isA<BackupSchemaException>()),
    );
  });

  test('a mid-import crash rolls every touched key back via the journal',
      () async {
    // Seed before-state.
    await prefs.setInt(LocalStateKeys.score, 7);
    await prefs.setString(LocalStateKeys.themeMode, 'dark');

    final doc = BackupEnvelopeWriter.build(
      appId: 'me.dsdogs.turna',
      appVersion: '0.8.0',
      buildNumber: '9',
      language: 'turkish',
      progress: {
        'game.score': 777,
        'settings.themeMode': 'light',
      },
    );
    final file = await writeBackup(doc);
    final outcome = await service.importFromFile(file.path);
    expect(outcome.progressRestored, isTrue);
    expect(
      prefs.preferences
          .getInt(LocalStateKeys.score, defaultValue: -1)
          .getValue(),
      777,
    );

    // Simulate the crash window: journal armed with the before-image while
    // the new values are already half-applied. The boot-time rollback (what
    // a crash mid-import triggers on next start) must restore them.
    await prefs.preferences.setString(
      'restore.inProgress',
      jsonEncode({
        'id': 'crashed',
        'startedAtUtc': '2026-08-24T00:00:00Z',
        'beforeImage': {
          'game.score': 7,
          'settings.themeMode': 'dark',
        },
      }),
    );

    final rolledBack = await BackupRestoreJournal.rollbackPending(prefs);
    expect(rolledBack, isTrue);
    expect(
      prefs.preferences
          .getInt(LocalStateKeys.score, defaultValue: -1)
          .getValue(),
      7,
      reason: 'score must return to the pre-import value',
    );
    expect(
      prefs.preferences
          .getString(LocalStateKeys.themeMode, defaultValue: '')
          .getValue(),
      'dark',
    );
  });
}
