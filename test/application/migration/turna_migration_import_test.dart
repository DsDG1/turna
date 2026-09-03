// turna-migration-v1 import tests (plan 34 §R7 / OS-22): export → import
// round-trip, checksum tampering, zip-slip, schema-too-new and the
// legacy-ignore disposition — imported Anki rows are ignored entirely
// (v1 retired, Step 6).

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:turna/application/migration/turna_migration_export.dart';
import 'package:turna/application/migration/turna_migration_import.dart';
import 'package:turna/data/course_database.dart';

import '../../helpers/in_memory_course_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqliteLibForTestHost();

  late Directory tmp;
  late CourseDatabase source;
  late CourseDatabase target;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('turna_migration_import');
    source = await seedInMemoryCourseDb();
    target = await seedInMemoryCourseDb();
  });

  tearDown(() async {
    await source.close();
    await target.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<File> buildPackage() async {
    SharedPreferences.setMockInitialValues({
      'game.score': 42,
      'courseScope': '',
    });
    final prefs = await SharedPreferences.getInstance();
    final exporter = TurnaMigrationExporter(
      db: source,
      prefs: prefs,
      appVersion: '0.7.1-test',
    );
    final result = await exporter.exportTo(tmp);
    return result.zipFile;
  }

  test('export → import round-trip restores non-Anki data', () async {
    // Seed one non-Anki SRS row in the source DB.
    await source.customStatement(
      "INSERT INTO srs_states (word_id, queue, due_at, interval_days, ease, "
      "reps, lapses, is_leech, is_suspended, is_buried, type) VALUES "
      "('w-1', 'srs', 10, 3, 2.5, 4, 0, 0, 0, 0, 'word')",
    );
    final zip = await buildPackage();

    final importer = TurnaMigrationImporter(db: target);
    final result = await importer.importFrom(zip);

    expect(result.applied, isTrue, reason: 'a valid package must apply');
    expect(result.restoredSrsStates, 1);
    final restored = await target
        .customSelect(
          "SELECT interval_days FROM srs_states WHERE word_id = 'w-1'",
        )
        .get();
    expect(restored.single.read<int>('interval_days'), 3);
  });

  test('legacy Anki rows are ignored; the rest of the package still applies',
      () async {
    await source.customStatement(
      "INSERT INTO anki_imports (import_id, source_path, source_hash, "
      "imported_at) VALUES ('legacy-imp-1', 'a.apkg', 'hash-1', 1)",
    );
    final zip = await buildPackage();

    final importer = TurnaMigrationImporter(db: target);
    final result = await importer.importFrom(zip);

    expect(result.applied, isTrue);
    expect(result.legacyIgnoredImports, ['legacy-imp-1']);
    // The LIVE legacy tables stay empty — the v1 scheduler is gone and the
    // import must never resurrect it (plan 34 §R7-3 / Step 6).
    // The target had no anki imports before and must still have none.
    final liveImports = await target
        .customSelect(
          'SELECT COUNT(*) AS n FROM anki_imports',
        )
        .get();
    expect(liveImports.single.read<int>('n'), 0,
        reason: 'the imported legacy row must never enter anki_imports');
  });

  test('checksum tampering is rejected with zero writes', () async {
    final zip = await buildPackage();
    final archive = ZipDecoder().decodeBytes(await zip.readAsBytes());
    final tampered = rebuildZip(
      archive,
      'settings.json',
      utf8.encode(
        jsonEncode({
          'schemaVersion': 1,
          'entries': {'tampered': true}
        }),
      ),
      '${tmp.path}/tampered.zip',
    );

    final importer = TurnaMigrationImporter(db: target);
    final result = await importer.importFrom(tampered);

    expect(result.applied, isFalse);
    expect(result.rejection, TurnaMigrationImportRejection.checksumMismatch);
    // Zero partial restore: the round-trip test proves srs rows are written
    // on success, so a zero count here proves nothing was applied.
    final rows = await target
        .customSelect(
          'SELECT COUNT(*) AS n FROM srs_states',
        )
        .get();
    expect(rows.single.read<int>('n'), 0);
  });

  test('zip-slip entries are rejected outright', () async {
    final zip = await buildPackage();
    final archive = ZipDecoder().decodeBytes(await zip.readAsBytes());
    final withEvil = addEntry(
      archive,
      ArchiveFile('../evil.txt', 1, [0]),
      '${tmp.path}/evil.zip',
    );
    final evil = File('${tmp.path}/evil.zip')
      ..writeAsBytesSync(ZipEncoder().encode(withEvil));

    final result = await TurnaMigrationImporter(db: target).importFrom(evil);

    expect(result.applied, isFalse);
    expect(result.rejection, TurnaMigrationImportRejection.zipSlipEntry);
  });

  test('a newer schema version is refused fail-closed', () async {
    final zip = await buildPackage();
    final archive = ZipDecoder().decodeBytes(await zip.readAsBytes());
    final manifest =
        jsonDecode(utf8.decode(entryBytes(archive, 'manifest.json')))
            as Map<String, dynamic>;
    manifest['schemaVersion'] = kTurnaMigrationSchemaVersion + 1;
    final manifestBytes = utf8.encode(jsonEncode(manifest));

    // Rewrite SHA256SUMS to stay internally consistent — the version gate
    // must fire regardless of checksums.
    final manifestSha = _shaOfBytes(manifestBytes);
    final newBody = StringBuffer();
    for (final line
        in utf8.decode(entryBytes(archive, 'SHA256SUMS')).split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed.endsWith('manifest.json')) {
        newBody.writeln('$manifestSha  manifest.json');
      } else {
        newBody.writeln(trimmed);
      }
    }
    // Two-step rebuild: manifest first, then the updated sums.
    final step1 = rebuildZip(
      archive,
      'manifest.json',
      manifestBytes,
      '${tmp.path}/future-step1.zip',
    );
    final future = rebuildZip(
      ZipDecoder().decodeBytes(await step1.readAsBytes()),
      'SHA256SUMS',
      utf8.encode(newBody.toString()),
      '${tmp.path}/future.zip',
    );

    final result = await TurnaMigrationImporter(db: target).importFrom(future);

    expect(result.applied, isFalse);
    expect(result.rejection, TurnaMigrationImportRejection.schemaTooNew);
  });

  test('a non-zip file is rejected', () async {
    final junk = File('${tmp.path}/junk.zip')
      ..writeAsStringSync('this is not a zip');
    final result = await TurnaMigrationImporter(db: target).importFrom(junk);
    expect(result.applied, isFalse);
    expect(result.rejection, TurnaMigrationImportRejection.notAZip);
  });
}

String _shaOfBytes(List<int> bytes) => crypto.sha256.convert(bytes).toString();

/// archive 4.x entries are immutable — rebuild the zip replacing [name].
File rebuildZip(Archive archive, String name, List<int> bytes, String outPath) {
  final rebuilt = Archive();
  for (final entry in archive.files) {
    if (entry.name == name) {
      rebuilt.add(ArchiveFile(name, bytes.length, bytes));
    } else {
      rebuilt.add(ArchiveFile(entry.name, entry.size, entry.content));
    }
  }
  final out = File(outPath);
  out.writeAsBytesSync(ZipEncoder().encode(rebuilt));
  return out;
}

List<int> entryBytes(Archive archive, String name) =>
    archive.files.firstWhere((e) => e.name == name).content as List<int>;

Archive addEntry(Archive archive, ArchiveFile extra, String outPath) {
  final rebuilt = Archive()..add(extra);
  for (final entry in archive.files) {
    rebuilt.add(ArchiveFile(entry.name, entry.size, entry.content));
  }
  return rebuilt;
}
