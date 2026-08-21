// Integration tests for the isolate-backed [AnkiImporter.parse] worker.
//
// Builds minimal but real `.apkg` fixtures (a zip wrapping a legacy-schema
// SQLite `collection.anki2` plus a `media` manifest) and exercises the full
// pipeline: streaming extraction, chunked hashing, paginated sqlite reads,
// progress port messages, cancellation, and error mapping.

// Dart imports:
import 'dart:convert';
import 'dart:io';

// Package imports:
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sql;

// Project imports:
import 'package:turna/application/anki/anki_importer.dart';

// Test imports:
import '../helpers/in_memory_course_db.dart';

const String _modelsJson = '''
{
  "1607392314938": {
    "id": 1607392314938,
    "name": "Basic",
    "type": 0,
    "flds": [{"name": "Front"}, {"name": "Back"}],
    "tmpls": [{"name": "Card 1", "qfmt": "{{Front}}", "afmt": "{{Back}}"}],
    "css": ""
  }
}
''';

const String _decksJson = '''
{"1": {"id": 1, "name": "Test Deck"}}
''';

/// Builds an `.apkg` at [apkgPath] with [noteCount] notes (one card each)
/// and a `media` manifest mapping `0` -> `audio.mp3`.
void _buildApkg(
  String apkgPath, {
  int noteCount = 3,
  bool includeDatabase = true,
}) {
  final dir = p.dirname(apkgPath);
  final dbPath = p.join(dir, 'collection.anki2');

  if (includeDatabase) {
    final db = sql.sqlite3.open(dbPath);
    try {
      db.execute('''
        CREATE TABLE col (
          id INTEGER PRIMARY KEY,
          crt INTEGER NOT NULL,
          decks TEXT NOT NULL,
          models TEXT NOT NULL,
          dconf TEXT NOT NULL
        )
      ''');
      db.execute('''
        CREATE TABLE notes (
          id INTEGER PRIMARY KEY,
          guid TEXT NOT NULL,
          mid INTEGER NOT NULL,
          mod INTEGER NOT NULL,
          usn INTEGER NOT NULL DEFAULT 0,
          tags TEXT NOT NULL DEFAULT '',
          flds TEXT NOT NULL,
          sfld TEXT NOT NULL DEFAULT '',
          csum INTEGER NOT NULL DEFAULT 0,
          flags INTEGER NOT NULL DEFAULT 0,
          data TEXT NOT NULL DEFAULT ''
        )
      ''');
      db.execute('''
        CREATE TABLE cards (
          id INTEGER PRIMARY KEY,
          nid INTEGER NOT NULL,
          did INTEGER NOT NULL,
          ord INTEGER NOT NULL DEFAULT 0,
          type INTEGER NOT NULL DEFAULT 0,
          queue INTEGER NOT NULL DEFAULT 0,
          due INTEGER NOT NULL DEFAULT 0,
          ivl INTEGER NOT NULL DEFAULT 0,
          factor INTEGER NOT NULL DEFAULT 0,
          reps INTEGER NOT NULL DEFAULT 0,
          lapses INTEGER NOT NULL DEFAULT 0,
          left INTEGER NOT NULL DEFAULT 0,
          odue INTEGER NOT NULL DEFAULT 0,
          odid INTEGER NOT NULL DEFAULT 0,
          flags INTEGER NOT NULL DEFAULT 0,
          data TEXT NOT NULL DEFAULT ''
        )
      ''');
      db.execute('''
        CREATE TABLE revlog (
          id INTEGER PRIMARY KEY,
          cid INTEGER NOT NULL,
          usn INTEGER NOT NULL DEFAULT 0,
          ease INTEGER NOT NULL DEFAULT 0,
          ivl INTEGER NOT NULL DEFAULT 0,
          lastIvl INTEGER NOT NULL DEFAULT 0,
          factor INTEGER NOT NULL DEFAULT 0,
          time INTEGER NOT NULL DEFAULT 0,
          type INTEGER NOT NULL DEFAULT 0
        )
      ''');
      db.execute('''
        INSERT INTO col (id, crt, decks, models, dconf)
        VALUES (1, 1415180000, '$_decksJson', '$_modelsJson', '{}')
      ''');

      const insertChunk = 500;
      for (var start = 0; start < noteCount; start += insertChunk) {
        final remaining = noteCount - start;
        final count = remaining < insertChunk ? remaining : insertChunk;
        final noteValues = List.generate(
          count,
          (i) {
            final n = start + i;
            final front = 'merhaba $n';
            final back = 'hello $n';
            return '(${n + 1}, '
                "'guid$n', 1607392314938, 1607392314, 0, 'tag1', "
                "'$front\x1f$back', '$front', 0, 0, '')";
          },
        ).join(', ');
        db.execute('''
          INSERT INTO notes (id, guid, mid, mod, usn, tags, flds, sfld, csum,
                             flags, data)
          VALUES $noteValues
        ''');
        final cardValues = List.generate(
          count,
          (i) {
            final n = start + i;
            return '(${n + 1}, ${n + 1}, 1, 0, 2, 0, '
                '${100000 + n}, 4, 2500, 3, 1, 0, 0, 0, 0, \'\')';
          },
        ).join(', ');
        db.execute('INSERT INTO cards VALUES $cardValues');
      }
      if (noteCount > 0) {
        db.execute('''
          INSERT INTO revlog (id, cid, usn, ease, ivl, lastIvl, factor, time,
                              type)
          VALUES (1, 1, 0, 3, 4, 0, 2500, 120, 2)
        ''');
      }
    } finally {
      db.dispose();
    }
  }

  final archive = Archive();
  if (includeDatabase) {
    final dbBytes = File(dbPath).readAsBytesSync();
    archive.addFile(
      ArchiveFile('collection.anki2', dbBytes.length, dbBytes),
    );
  }
  final mediaJson = utf8.encode('{"0": "audio.mp3"}');
  archive.addFile(ArchiveFile('media', mediaJson.length, mediaJson));
  final mediaBody = utf8.encode('fake-audio-bytes');
  archive.addFile(ArchiveFile('0', mediaBody.length, mediaBody));

  final zipBytes = ZipEncoder().encode(archive);
  File(apkgPath).writeAsBytesSync(zipBytes);
  if (includeDatabase) {
    File(dbPath).deleteSync();
  }
}

void main() {
  setUpAll(() {
    ensureSqliteLibForTestHost();
  });

  late Directory tempDir;

  setUp(() {
    // Fast hosts parse a 20k-note fixture in well under the production
    // 100ms poll interval; shrink it so the cancel test is deterministic.
    AnkiImporter.cancelPollInterval = const Duration(milliseconds: 1);
    tempDir = Directory.systemTemp.createTempSync('anki_importer_test');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('parses a minimal apkg on the worker isolate', () async {
    final apkgPath = p.join(tempDir.path, 'deck.apkg');
    _buildApkg(apkgPath);
    final extractDir = p.join(tempDir.path, 'extract');
    Directory(extractDir).createSync();

    final progressMessages = <String>[];
    final collection = await AnkiImporter().parse(
      apkgPath,
      tempDir: extractDir,
      onProgress: (progress, message) => progressMessages.add(message),
    );

    expect(collection.notes, hasLength(3));
    expect(collection.cards, hasLength(3));
    expect(collection.revlog, hasLength(1));
    expect(collection.decks[1]?.name, 'Test Deck');
    expect(collection.decks[1]?.cardCount, 3);
    expect(collection.notetypes.values.single.fieldNames,
        ['Front', 'Back']);
    expect(collection.media, {'0': 'audio.mp3'});
    expect(collection.notes.first.fields, ['merhaba 0', 'hello 0']);

    // Chunked hashing in the worker must equal a plain one-shot hash.
    final expectedHash =
        crypto.sha256.convert(File(apkgPath).readAsBytesSync()).toString();
    expect(collection.sourceHash, expectedHash);

    // Extraction streamed to disk and stays available after success.
    expect(File(p.join(extractDir, 'collection.anki2')).existsSync(), isTrue);
    expect(File(p.join(extractDir, '0')).existsSync(), isTrue);

    // Progress crossed the isolate boundary.
    expect(progressMessages, isNotEmpty);
    expect(progressMessages.any((m) => m.startsWith('Parsing notes')), isTrue);
    expect(progressMessages.any((m) => m.startsWith('Parsing cards')), isTrue);
  });

  test('cancellation aborts with AnkiImportCancelled and cleans up', () async {
    final apkgPath = p.join(tempDir.path, 'big.apkg');
    _buildApkg(apkgPath, noteCount: 20000);

    final preExistingAnkiDirs = Directory.systemTemp
        .listSync()
        .whereType<Directory>()
        .where((d) => p.basename(d.path).startsWith('anki_import_'))
        .map((d) => d.path)
        .toSet();

    var cancelRequested = false;
    await expectLater(
      AnkiImporter().parse(
        apkgPath,
        onProgress: (_, __) => cancelRequested = true,
        isCancelled: () => cancelRequested,
      ),
      throwsA(isA<AnkiImportCancelled>()),
    );

    // The default extraction directory (owned by the importer) was removed.
    final leftover = Directory.systemTemp
        .listSync()
        .whereType<Directory>()
        .map((d) => d.path)
        .where((path) =>
            p.basename(path).startsWith('anki_import_') &&
            !preExistingAnkiDirs.contains(path))
        .toList();
    expect(leftover, isEmpty);
  });

  test('missing file fails fast', () async {
    await expectLater(
      AnkiImporter().parse(p.join(tempDir.path, 'nope.apkg')),
      throwsA(isA<AnkiImportException>()),
    );
  });

  test('archive without a collection database maps to a typed error',
      () async {
    final apkgPath = p.join(tempDir.path, 'empty.apkg');
    _buildApkg(apkgPath, includeDatabase: false);

    try {
      await AnkiImporter().parse(apkgPath);
      fail('parse should have thrown');
    } on AnkiImportException catch (e) {
      expect(e.code, 'COLLECTION_DATABASE_MISSING');
    }
  });

  test('modern collection.anki21b package maps to a typed error', () async {
    final archive = Archive()
      ..addFile(ArchiveFile('collection.anki21b', 4, [1, 2, 3, 4]));
    final apkgPath = p.join(tempDir.path, 'modern.apkg');
    File(apkgPath).writeAsBytesSync(ZipEncoder().encode(archive));

    try {
      await AnkiImporter().parse(apkgPath);
      fail('parse should have thrown');
    } on AnkiImportException catch (e) {
      expect(e.code, 'PACKAGE_VERSION_UNSUPPORTED');
    }
  });

  test('unsafe zip entry names are rejected', () async {
    final evil = utf8.encode('evil');
    final archive = Archive()
      ..addFile(ArchiveFile('../evil.txt', evil.length, evil))
      ..addFile(ArchiveFile('collection.anki2', 4, [1, 2, 3, 4]));
    final apkgPath = p.join(tempDir.path, 'evil.apkg');
    File(apkgPath).writeAsBytesSync(ZipEncoder().encode(archive));

    await expectLater(
      AnkiImporter().parse(apkgPath),
      throwsA(isA<AnkiImportException>()),
    );
  });
}
