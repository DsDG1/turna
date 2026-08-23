// Unit tests for the SharedPreferences restore journal (Plan §10.3):
// before-image capture, commit point, and full rollback.

// Flutter imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';

// Project imports:
import 'package:turna/application/backup/backup_manifest_policy.dart';
import 'package:turna/application/backup/backup_restore_journal.dart';
import 'package:turna/service/locator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StreamingSharedPreferences sp;
  late AppPrefs prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    sp = await StreamingSharedPreferences.instance;
    prefs = AppPrefs(sp);
  });

  test('begin arms the journal, commit disarms it', () async {
    await BackupRestoreJournal.begin(prefs, 'r1', {'game.score': 10});
    expect(BackupRestoreJournal.hasPending(prefs), isTrue);

    await BackupRestoreJournal.commit(prefs);
    expect(BackupRestoreJournal.hasPending(prefs), isFalse);
  });

  test('rollback restores the before-image exactly', () async {
    // Pre-restore state.
    await prefs.setInt(LocalStateKeys.score, 10);
    await prefs.setString('theme.key', 'dark');
    await prefs.setBool('bool.key', value: true);
    await prefs.setStringList('list.key', ['a']);

    await BackupRestoreJournal.begin(prefs, 'r2', {
      LocalStateKeys.score: 10,
      'theme.key': 'dark',
      'bool.key': true,
      'list.key': ['a'],
      'brand.new.key': null, // did not exist before the restore
    });

    // A half-applied restore writes whatever it managed before dying.
    await prefs.setInt(LocalStateKeys.score, 999);
    await prefs.setString('theme.key', 'light');
    await prefs.setBool('bool.key', value: false);
    await prefs.setStringList('list.key', ['b', 'c']);
    await prefs.setString('brand.new.key', 'written-by-restore');

    expect(await BackupRestoreJournal.rollbackPending(prefs), isTrue);
    expect(
      prefs.preferences
          .getInt(LocalStateKeys.score, defaultValue: 0)
          .getValue(),
      10,
    );
    expect(
      prefs.preferences.getString('theme.key', defaultValue: '').getValue(),
      'dark',
    );
    expect(
      prefs.preferences.getBool('bool.key', defaultValue: false).getValue(),
      isTrue,
    );
    expect(
      prefs.preferences
          .getStringList('list.key', defaultValue: const []).getValue(),
      ['a'],
    );
    // Keys that did not exist before the restore are removed again.
    expect(
      prefs.preferences
          .getString('brand.new.key', defaultValue: '-')
          .getValue(),
      '-',
    );
    expect(BackupRestoreJournal.hasPending(prefs), isFalse);
  });

  test('rollback without a pending journal is a no-op', () async {
    expect(await BackupRestoreJournal.rollbackPending(prefs), isFalse);
  });

  test('journal marker never travels inside backups (policy exclusion)', () {
    expect(
      BackupManifestPolicy.shouldInclude(BackupRestoreJournal.markerKey),
      isFalse,
    );
  });
}
