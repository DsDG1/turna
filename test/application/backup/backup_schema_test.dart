// Contract tests for the versioned backup envelope and the pre-import
// validator (Plan §8.4 / §10.1): v1 read-compat, v2 write, future-version
// rejection, per-key type checks, integrity digest, size cap.

// Dart imports:
import 'dart:convert';
import 'dart:io';

// Flutter imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:turna/application/backup/backup_schema.dart';
import 'package:turna/application/backup/backup_validator.dart';

void main() {
  const appId = 'me.dsdogs.turna';

  Map<String, dynamic> v2Envelope(Map<String, dynamic> progress) =>
      BackupEnvelopeWriter.build(
        appId: appId,
        appVersion: '0.8.0',
        buildNumber: '9',
        language: 'turkish',
        progress: progress,
      );

  group('LocalBackupDocument', () {
    test('parses the v1 fixture read-only', () {
      final raw =
          File('test/fixtures/backup/v1_local_export.json').readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final doc = LocalBackupDocument.fromMap(decoded);

      expect(doc.schemaVersion, BackupSchemaVersion.v1);
      expect(doc.appId, appId);
      expect(doc.progress, isNotNull);
      expect(doc.progress!['game.score'], 120);
      expect(doc.hasCoursePayload, isTrue);
    });

    test('rejects future schema versions with an upgrade hint', () {
      final raw =
          File('test/fixtures/backup/future_v3_export.json').readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      expect(
        () => LocalBackupDocument.fromMap(decoded),
        throwsA(isA<BackupSchemaException>()
            .having((e) => e.code, 'code', 'backup.futureSchema')),
      );
    });

    test('missing meta is a structured error', () {
      expect(
        () => LocalBackupDocument.fromMap({'progress': {}}),
        throwsA(isA<BackupSchemaException>()),
      );
    });
  });

  group('BackupEnvelopeWriter', () {
    test('v2 envelope has sorted keys and a matching digest', () {
      final envelope = v2Envelope({
        'game.score': 5,
        'settings.ttsSpeed': 1.5,
        'a.before.alphabet': true,
      });
      expect(envelope['meta']['schemaVersion'], BackupSchemaVersion.v2);
      final progressKeys =
          (envelope['progress'] as Map<String, dynamic>).keys.toList();
      expect(progressKeys, equals(progressKeys.toList()..sort()));

      final integrity = envelope['integrity'] as Map<String, dynamic>;
      expect(
        integrity['progressSha256'],
        BackupEnvelopeWriter.progressDigest(
            envelope['progress'] as Map<String, dynamic>),
      );
    });
  });

  group('BackupValidator', () {
    test('accepts a fresh v2 envelope', () {
      final json = jsonEncode(v2Envelope({
        'game.score': 5,
        'settings.ttsSpeed': 1.5,
      }));
      final result = BackupValidator.validateLocalExportJson(
        json,
        expectedAppId: appId,
      );
      expect(result.isValid, isTrue, reason: '${result.issues}');
    });

    test('accepts the v1 fixture', () {
      final raw =
          File('test/fixtures/backup/v1_local_export.json').readAsStringSync();
      final result =
          BackupValidator.validateLocalExportJson(raw, expectedAppId: appId);
      expect(result.isValid, isTrue);
      expect(result.document!.schemaVersion, BackupSchemaVersion.v1);
    });

    test('rejects a foreign app id', () {
      final json = jsonEncode(v2Envelope({'game.score': 1}));
      final result = BackupValidator.validateLocalExportJson(
        json,
        expectedAppId: 'com.other.app',
      );
      expect(result.isValid, isFalse);
      expect(result.issues.first.code, 'backup.foreignApp');
    });

    test('rejects non-JSON payloads', () {
      final result = BackupValidator.validateLocalExportJson('not json {');
      expect(result.issues.first.code, 'backup.notJson');
    });

    test('rejects a non-object root', () {
      final result = BackupValidator.validateLocalExportJson('[1,2,3]');
      expect(result.issues.first.code, 'backup.notObject');
    });

    test('rejects type mismatches before anything is written', () {
      final json = jsonEncode(v2Envelope({
        'game.score': 'one-hundred-twenty',
      }));
      final result = BackupValidator.validateLocalExportJson(json);
      expect(result.isValid, isFalse);
      expect(
        result.issues.any((issue) => issue.code == 'backup.typeMismatch'),
        isTrue,
      );
    });

    test('accepts an int literal for a double-declared key', () {
      final json = jsonEncode(v2Envelope({'settings.ttsSpeed': 1}));
      final result = BackupValidator.validateLocalExportJson(json);
      expect(result.isValid, isTrue);
    });

    test('rejects a tampered progress payload via the integrity digest', () {
      final envelope = v2Envelope({'game.score': 5});
      (envelope['progress'] as Map<String, dynamic>)['game.score'] = 999999;
      final result =
          BackupValidator.validateLocalExportJson(jsonEncode(envelope));
      expect(result.issues.first.code, 'backup.integrityMismatch');
    });

    test('rejects empty files (nothing to import)', () {
      final json = jsonEncode({
        'meta': {
          'schemaVersion': 2,
          'appId': appId,
          'appVersion': '0.8.0',
          'createdAtUtc': '2026-01-01T00:00:00Z',
        },
      });
      final result = BackupValidator.validateLocalExportJson(json);
      expect(result.issues.first.code, 'backup.empty');
    });

    test('range clamps mirror the setters', () {
      expect(BackupValidator.clampValue('settings.ttsSpeed', 9.9), 2.0);
      expect(BackupValidator.clampValue('settings.ttsSpeed', 0.1), 0.5);
      expect(BackupValidator.clampValue('settings.textScale', 500), 200);
      expect(BackupValidator.clampValue('settings.dailyReminderHour', 25), 23);
      expect(BackupValidator.clampValue('settings.dailyReminderMinute', -1), 0);
      expect(BackupValidator.clampValue('srs.desiredRetention', 0.99), 0.95);
      expect(BackupValidator.clampValue('anki.liteThreshold', -5), 0);
      expect(BackupValidator.clampValue('anki.dailyNewLimit', 5000), 999);
    });

    test('oversized files are rejected before parsing', () async {
      final dir = await Directory.systemTemp.createTemp('turna_backup');
      final file = File('${dir.path}/huge.json');
      final sink = file.openWrite();
      sink.write('[');
      for (var i = 0; i < 33 * 1024; i++) {
        sink.write('"${'x' * 1021}",');
      }
      sink.write('0]');
      await sink.close();

      final result = await BackupValidator.validateLocalExportFile(
        file.path,
        expectedAppId: appId,
      );
      expect(result.issues.first.code, 'backup.tooLarge');
      await dir.delete(recursive: true);
    });
  });
}
