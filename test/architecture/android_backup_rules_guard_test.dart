// `core/log_capture.dart` writes the transparency log into
// `getApplicationDocumentsDirectory()`, which on Android is
// `<dataDir>/app_flutter/` — inside the platform auto-backup tree. That log
// is the one artifact the app actively encourages users to export and share,
// so it must be excluded from platform backup.
//
// The risk here is silent: Android backup rules support no wildcards, so if
// the log file is ever renamed the rules keep matching the old name, the
// build stays green, and the log quietly resumes riding along to the cloud.
// This guard ties the rules to `LogCapture.persistedFileNames()` so the
// mismatch fails a test instead.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/core/log_capture.dart';

void main() {
  const manifest = 'android/app/src/main/AndroidManifest.xml';
  const backupRules = 'android/app/src/main/res/xml/backup_rules.xml';
  const extractionRules =
      'android/app/src/main/res/xml/data_extraction_rules.xml';

  // Every log file the capture can write, in the `root`-domain form the
  // rules use. The documents dir is `<dataDir>/app_flutter/`, a sibling of
  // `files/`, so the rules must use the `root` domain — `file` maps to
  // getFilesDir() and would silently match nothing.
  const documentsDir = 'app_flutter';

  /// Drop `<!-- … -->` blocks. The rules files carry a long comment
  /// explaining what is deliberately NOT excluded, and a raw substring check
  /// would flag that prose instead of an actual rule.
  String rulesBody(String path) =>
      File(path).readAsStringSync().replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');

  test('the manifest wires both backup-rule attributes', () {
    final xml = File(manifest).readAsStringSync();

    expect(xml, contains('android:fullBackupContent="@xml/backup_rules"'),
        reason: 'API 23-30 ignores the 31+ rules file entirely');
    expect(xml,
        contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
        reason: 'API 31+ ignores fullBackupContent entirely');
  });

  test('pre-31 rules exclude every transparency log file', () {
    final xml = File(backupRules).readAsStringSync();

    for (final name in LogCapture.persistedFileNames()) {
      expect(
        xml,
        contains('<exclude domain="root" path="$documentsDir/$name" />'),
        reason: '$name would be uploaded to the cloud backup. Android backup '
            'rules have no wildcard, so each name needs its own entry.',
      );
    }
  });

  test('API 31+ rules exclude every log file from cloud AND transfer', () {
    final xml = File(extractionRules).readAsStringSync();

    for (final section in ['cloud-backup', 'device-transfer']) {
      final start = xml.indexOf('<$section>');
      final end = xml.indexOf('</$section>');
      expect(start, isNot(lessThan(0)), reason: 'missing <$section> section');
      expect(end, greaterThan(start));
      final body = xml.substring(start, end);

      for (final name in LogCapture.persistedFileNames()) {
        expect(
          body,
          contains('<exclude domain="root" path="$documentsDir/$name" />'),
          reason: '$name must leave the backup set in the $section leg too. '
              'Android 12+ runs device-transfer even when the cloud leg is '
              'disabled, so excluding only one of them leaks by cable.',
        );
      }
    }
  });

  test('learning data is not collateral damage', () {
    // Excluding these would restore cards with dead media, or discard the
    // only copy of downgraded SRS history.
    for (final rules in [backupRules, extractionRules]) {
      final xml = rulesBody(rules);
      expect(xml, isNot(contains('course.db')),
          reason: '$rules excludes the learning database');
      expect(xml, isNot(contains('anki_media')),
          reason: '$rules excludes deck media the database references by path');
    }
  });

  test('the rules stay an exclusion list, not an allowlist', () {
    // An <include> in a full-backup-content file turns it into an
    // allowlist: everything unlisted silently stops being backed up.
    expect(rulesBody(backupRules), isNot(contains('<include ')));
  });
}
