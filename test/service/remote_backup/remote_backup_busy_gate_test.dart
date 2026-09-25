// Package imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:turna/service/remote_backup/remote_backup_busy_gate.dart';

void main() {
  late StudyActivityGate gate;

  setUp(() {
    gate = StudyActivityGate();
  });

  test('study scopes count depth and unbalanced ends are ignored', () {
    expect(gate.isStudyActive, isFalse);
    gate.begin('anki_import');
    gate.begin('anki_import'); // nested resume path
    expect(gate.isStudyActive, isTrue);
    gate.end('anki_import');
    expect(gate.isStudyActive, isTrue, reason: 'depth 1 of 2 still held');
    gate.end('anki_import');
    expect(gate.isStudyActive, isFalse);
    gate.end('anki_import'); // late end after release: no-op
    expect(gate.isStudyActive, isFalse);
  });

  test('backup cannot start while a study scope is held', () {
    gate.begin('lesson');
    expect(gate.backupEnter, throwsA(isA<RemoteBackupBusyException>()));
    gate.end('lesson');
    gate.backupEnter();
    gate.backupExit();
  });

  test('study scopes cannot start while a backup snapshot is held', () {
    gate.backupEnter();
    expect(() => gate.begin('lesson'),
        throwsA(isA<RemoteBackupActiveException>()));
    // The mid-snapshot re-check stays green: only backup holders count.
    gate.backupCheck();
    gate.backupExit();
    gate.begin('lesson');
  });

  test('backupCheck aborts while any study scope is active (defense in depth)',
      () {
    // Scopes entered through begin() cannot slip in mid-snapshot (begin
    // throws while the hold is held) — backupCheck exists for writers that
    // bypass the gate entirely, so the snapshot aborts instead of packing
    // an inconsistent archive.
    gate.begin('ungated_writer');
    expect(gate.backupCheck, throwsA(isA<RemoteBackupBusyException>()));
    gate.end('ungated_writer');
    gate.backupEnter();
    gate.backupCheck(); // clean while nothing else writes
    gate.backupExit();
  });

  test('a second concurrent backup is rejected while one holds the gate',
      () {
    gate.backupEnter();
    expect(gate.backupEnter, throwsA(isA<RemoteBackupBusyException>()));
    gate.backupExit();
    gate.backupEnter(); // sequential backups are fine
  });

  test('backupExit without enter is a no-op', () {
    gate.backupExit();
    expect(gate.isBackupActive, isFalse);
  });

  test('runInScope releases the scope when the body throws', () async {
    await expectLater(
      gate.runInScope<void>('anki_import', () async {
        throw StateError('boom');
      }),
      throwsStateError,
    );
    expect(gate.isStudyActive, isFalse);
  });
}
