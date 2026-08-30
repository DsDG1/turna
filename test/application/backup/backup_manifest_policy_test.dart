// Contract tests for the single backup manifest policy (Plan §8.5):
// * one key set shared by the local export and the remote snapshot;
// * secrets and device-local keys are structurally excluded;
// * dynamic prefix settings are eligible;
// * serialization-boundary sanitization strips embedded API keys.

// Dart imports:
import 'dart:convert';

// Flutter imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:turna/application/backup/backup_manifest_policy.dart';
import 'package:turna/service/locator.dart';

void main() {
  test('sensitive and device-local keys are never included', () {
    const never = [
      LocalStateKeys.remoteBackupConfig,
      LocalStateKeys.remoteBackupDeviceId,
      LocalStateKeys.remoteBackupLastInfo,
      'remoteBackup.anything.else',
      LocalStateKeys.systemHealthEvent,
      'anki.deck.someDeck.counter',
      'anki.newDoneToday',
      'anki.reviewDoneToday',
      'anki.limitsDate',
      'restore.inProgress',
      'ai.credentialMigrated',
      'flutter.someFrameworkKey',
    ];
    for (final key in never) {
      expect(
        BackupManifestPolicy.shouldInclude(key),
        isFalse,
        reason: '$key must never travel in a backup',
      );
    }
  });

  test('every key the plan calls out is covered by the policy', () {
    const must = [
      LocalStateKeys.srsDesiredRetention,
      LocalStateKeys.srsFsrsParameters,
      LocalStateKeys.srsFsrsOptimizedAt,
      LocalStateKeys.srsFsrsOptimizedReviews,
      'anki.dailyNewLimit',
      'anki.dailyReviewLimit',
      'anki.dailyChallengeIncludesAnki',
      LocalStateKeys.ankiForceDisableJs,
      PrefsConstants.courseScope,
      PrefsConstants.courseOrder,
      'settings.autoReadOnTap.builtin',
      'settings.autoReadOnTap.anki:someDeck',
      'settings.nativeLang.builtin',
      LocalStateKeys.aiEngineConfig,
      'ai.replyLanguage',
      LocalStateKeys.funAutoAnswer,
      LocalStateKeys.gems,
      PrefsConstants.authUser,
    ];
    for (final key in must) {
      expect(
        BackupManifestPolicy.shouldInclude(key),
        isTrue,
        reason: '$key must round-trip through every backup path',
      );
    }
  });

  test('exact entries carry the type the setters persist', () {
    final entry = BackupManifestPolicy.entryFor(LocalStateKeys.ttsSpeed);
    expect(entry, isNotNull);
    expect(entry!.type, BackupPrefType.double_);

    final listEntry =
        BackupManifestPolicy.entryFor(LocalStateKeys.completedLessonIds);
    expect(listEntry!.type, BackupPrefType.stringList);
  });

  test('prefix entries only accept their declared scalar types', () {
    final autoRead =
        BackupManifestPolicy.entryFor('settings.autoReadOnTap.builtin')!;
    expect(autoRead.isPrefix, isTrue);
    expect(autoRead.acceptsType(BackupPrefType.bool_), isTrue);
    expect(autoRead.acceptsType(BackupPrefType.string), isFalse);

    final nativeLang =
        BackupManifestPolicy.entryFor('settings.nativeLang.builtin')!;
    expect(nativeLang.acceptsType(BackupPrefType.string), isTrue);
    expect(nativeLang.acceptsType(BackupPrefType.bool_), isFalse);
  });

  test('sanitization strips the API key at the serialization boundary', () {
    final config = jsonEncode({
      'preset': 'openai',
      'apiKey': 'sk-super-secret-value',
      'model': 'gpt-x',
    });
    final sanitized = BackupManifestPolicy.sanitizeForSerialization(
        LocalStateKeys.aiEngineConfig, config);
    expect(sanitized, isA<String>());
    expect(sanitized.toString(), contains('"apiKey":""'));
    expect(sanitized.toString().contains('sk-super-secret-value'), isFalse);
    expect(sanitized.toString(), contains('gpt-x'));
  });

  test('sanitization drops non-eligible keys entirely', () {
    expect(
      BackupManifestPolicy.sanitizeForSerialization(
          LocalStateKeys.remoteBackupConfig, '{"password":"x"}'),
      isNull,
    );
  });

  test('corrupt AI config sanitizes to an empty string, not an opaque blob',
      () {
    expect(
      BackupManifestPolicy.stripApiKeyFromEngineConfig('not-json'),
      '',
    );
  });

  test('no exact key is shadowed by an exclusion rule', () {
    for (final entry in BackupManifestPolicy.typedEntries) {
      final key = entry.key!;
      expect(
        BackupManifestPolicy.shouldInclude(key),
        isTrue,
        reason: 'exclusion rules must not shadow the exact key $key',
      );
    }
  });
}
