// Dart imports:
import 'dart:convert';
import 'dart:io';

// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sql;

// Project imports:
import 'package:varnamala/application/anki/anki_models.dart';
import 'package:varnamala/core/logger.dart';

/// Parses Anki `.apkg` / `.colpkg` files into an [AnkiCollection]
/// intermediate representation. Pure parsing — does not touch the Varnamala
/// database.
///
/// Implementation notes:
/// - Uses `archive` package for ZIP extraction
/// - Uses `sqlite3` (ffi) for reading `collection.anki2` / `collection.anki21`
/// - Large collections are read in pages (LIMIT/OFFSET) to avoid memory spikes
class AnkiImporter {
  static const int _pageSize = 500;
  static const String _fieldSeparator = '\x1f';

  /// Parse an .apkg file and return the intermediate representation.
  ///
  /// [apkgPath] is the absolute path to the .apkg/.colpkg file.
  /// [tempDir] is where the archive will be extracted (defaults to system temp).
  ///
  /// [onProgress] receives (0..1, message) during paginated note/card reads.
  /// [isCancelled] is polled between pages; returning true aborts parsing with
  /// an [AnkiImportCancelled] exception.
  ///
  /// **Not available on HarmonyOS** — Anki `.apkg` files are SQLite databases
  /// read via `sqlite3` FFI, which has no HarmonyOS build. Callers on OHos
  /// should check [defaultTargetPlatform] before invoking.
  Future<AnkiCollection> parse(
    String apkgPath, {
    String? tempDir,
    void Function(double progress, String message)? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (defaultTargetPlatform == TargetPlatform.ohos) {
      throw UnsupportedError(
        'Anki import is not available on HarmonyOS yet. '
        'Anki `.apkg` files are SQLite databases read via sqlite3 FFI, '
        'which has no HarmonyOS build.',
      );
    }
    final file = File(apkgPath);
    if (!file.existsSync()) {
      throw AnkiImportException('File not found: $apkgPath');
    }

    // Extract ZIP archive
    final extractDir = tempDir ??
        p.join(Directory.systemTemp.path, 'anki_import_${DateTime.now().millisecondsSinceEpoch}');
    final dir = Directory(extractDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final bytes = file.readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);

    for (final entry in archive) {
      final outputPath = p.join(extractDir, entry.name);
      if (entry.isFile) {
        final outFile = File(outputPath);
        outFile.parent.createSync(recursive: true);
        outFile.writeAsBytesSync(entry.content as List<int>);
      }
    }

    // Determine database file
    final dbFile = _findDatabaseFile(extractDir);
    if (dbFile == null) {
      throw AnkiImportException(
        'No collection.anki2 or collection.anki21 found in archive',
      );
    }

    // Parse media mapping
    final media = _parseMediaMapping(extractDir);

    // Open SQLite database (read-only)
    final db = sql.sqlite3.open(dbFile, mode: sql.OpenMode.readOnly);

    try {
      // Parse collection metadata (decks + notetypes)
      final colRow = db.select('SELECT decks, models FROM col LIMIT 1');
      if (colRow.isEmpty) {
        throw AnkiImportException('Empty collection table');
      }

      final decksJson = colRow.first['decks'] as String;
      final modelsJson = colRow.first['models'] as String;

      final decks = _parseDecks(decksJson);
      final notetypes = _parseNotetypes(modelsJson);

      // Parse notes (paginated)
      final notes = _parseNotes(
        db,
        onProgress: onProgress,
        isCancelled: isCancelled,
        label: 'notes',
      );

      // Parse cards (paginated)
      final cards = _parseCards(
        db,
        onProgress: onProgress,
        isCancelled: isCancelled,
        label: 'cards',
      );

      // Compute deck card counts
      final deckCounts = <int, int>{};
      for (final card in cards) {
        deckCounts[card.did] = (deckCounts[card.did] ?? 0) + 1;
      }
      final decksWithCounts = decks.map((key, value) => MapEntry(
            key,
            value.copyWith(cardCount: deckCounts[key] ?? 0),
          ));

      return AnkiCollection(
        notetypes: notetypes,
        decks: decksWithCounts,
        notes: notes,
        cards: cards,
        media: media,
        mediaDir: extractDir,
      );
    } finally {
      db.dispose();
    }
  }

  /// Find the SQLite database file in the extracted directory.
  String? _findDatabaseFile(String extractDir) {
    // Anki 2.1+ uses collection.anki21, older uses collection.anki2
    final anki21 = File(p.join(extractDir, 'collection.anki21'));
    if (anki21.existsSync()) return anki21.path;

    final anki2 = File(p.join(extractDir, 'collection.anki2'));
    if (anki2.existsSync()) return anki2.path;

    return null;
  }

  /// Parse the `media` JSON file (maps numeric filenames to original names).
  Map<String, String> _parseMediaMapping(String extractDir) {
    final mediaFile = File(p.join(extractDir, 'media'));
    if (!mediaFile.existsSync()) return {};

    try {
      final content = mediaFile.readAsStringSync();
      final decoded = jsonDecode(content) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, v.toString()));
    } catch (e) {
      logger.w('Failed to parse media mapping: $e');
      return {};
    }
  }

  /// Parse decks JSON from the `col.decks` column.
  Map<int, AnkiDeckInfo> _parseDecks(String decksJson) {
    final result = <int, AnkiDeckInfo>{};
    try {
      final decoded = jsonDecode(decksJson) as Map<String, dynamic>;
      for (final entry in decoded.entries) {
        final did = int.tryParse(entry.key) ?? 0;
        final deckData = entry.value as Map<String, dynamic>;
        final name = deckData['name']?.toString() ?? 'Deck $did';
        // Skip the default deck (id=1) if it has no cards
        if (did == 1 && name == 'Default') continue;

        // Determine parent from name hierarchy (e.g. "Parent::Child")
        final parentId = _findParentDeckId(name, result);

        result[did] = AnkiDeckInfo(
          id: did,
          name: name,
          parentId: parentId,
        );
      }
    } catch (e) {
      logger.w('Failed to parse decks: $e');
    }
    return result;
  }

  /// Find parent deck id by name hierarchy ("Parent::Child" → parent's id).
  int _findParentDeckId(String name, Map<int, AnkiDeckInfo> existing) {
    if (!name.contains('::')) return 0;
    final parentName = name.substring(0, name.lastIndexOf('::'));
    for (final deck in existing.values) {
      if (deck.name == parentName) return deck.id;
    }
    return 0;
  }

  /// Parse notetypes (models) JSON from the `col.models` column.
  Map<int, AnkiNotetype> _parseNotetypes(String modelsJson) {
    final result = <int, AnkiNotetype>{};
    try {
      final decoded = jsonDecode(modelsJson) as Map<String, dynamic>;
      for (final entry in decoded.entries) {
        final mid = int.tryParse(entry.key) ?? 0;
        final modelData = entry.value as Map<String, dynamic>;
        final name = modelData['name']?.toString() ?? 'Model $mid';

        // Parse field names
        final flds = modelData['flds'] as List<dynamic>? ?? [];
        final fieldNames = flds
            .map((f) => (f as Map<String, dynamic>)['name']?.toString() ?? '')
            .toList();

        // Parse template names
        final tmpls = modelData['tmpls'] as List<dynamic>? ?? [];
        final templateNames = tmpls
            .map((t) => (t as Map<String, dynamic>)['name']?.toString() ?? '')
            .toList();

        // Detect Cloze type (type == 1 in Anki)
        final isCloze = (modelData['type'] as int? ?? 0) == 1;

        result[mid] = AnkiNotetype(
          id: mid,
          name: name,
          fieldNames: fieldNames,
          templateNames: templateNames,
          isCloze: isCloze,
        );
      }
    } catch (e) {
      logger.w('Failed to parse notetypes: $e');
    }
    return result;
  }

  /// Parse notes table with pagination.
  List<AnkiNote> _parseNotes(
    sql.Database db, {
    void Function(double, String)? onProgress,
    bool Function()? isCancelled,
    String label = 'notes',
  }) {
    final total = db.select('SELECT COUNT(*) AS c FROM notes').first['c'] as int;
    final notes = <AnkiNote>[];
    var offset = 0;

    while (true) {
      if (isCancelled != null && isCancelled()) {
        throw const AnkiImportCancelled();
      }
      final rows = db.select(
        'SELECT id, guid, mid, mod, tags, flds, sfld FROM notes '
        'ORDER BY id LIMIT $_pageSize OFFSET $offset',
      );

      if (rows.isEmpty) break;

      for (final row in rows) {
        final flds = row['flds'] as String? ?? '';
        final fields = flds.split(_fieldSeparator);

        notes.add(AnkiNote(
          id: row['id'] as int,
          guid: row['guid']?.toString() ?? '',
          mid: row['mid'] as int,
          mod: row['mod'] as int? ?? 0,
          tags: row['tags']?.toString().trim() ?? '',
          fields: fields,
          sortField: row['sfld']?.toString() ?? '',
        ));
      }

      offset += _pageSize;
      if (onProgress != null && total > 0) {
        final p = (offset / total).clamp(0.0, 1.0);
        onProgress(p, 'Parsing $label… $offset / $total');
      }
      if (rows.length < _pageSize) break;
    }

    return notes;
  }

  /// Parse cards table with pagination.
  List<AnkiCardData> _parseCards(
    sql.Database db, {
    void Function(double, String)? onProgress,
    bool Function()? isCancelled,
    String label = 'cards',
  }) {
    final total = db.select('SELECT COUNT(*) AS c FROM cards').first['c'] as int;
    final cards = <AnkiCardData>[];
    var offset = 0;

    while (true) {
      if (isCancelled != null && isCancelled()) {
        throw const AnkiImportCancelled();
      }
      final rows = db.select(
        'SELECT id, nid, did, ord, type, queue, due, ivl, factor, reps, lapses '
        'FROM cards ORDER BY id LIMIT $_pageSize OFFSET $offset',
      );

      if (rows.isEmpty) break;

      for (final row in rows) {
        cards.add(AnkiCardData(
          id: row['id'] as int,
          nid: row['nid'] as int,
          did: row['did'] as int,
          ord: row['ord'] as int? ?? 0,
          type: row['type'] as int? ?? 0,
          queue: row['queue'] as int? ?? 0,
          due: row['due'] as int? ?? 0,
          ivl: row['ivl'] as int? ?? 0,
          factor: row['factor'] as int? ?? 2500,
          reps: row['reps'] as int? ?? 0,
          lapses: row['lapses'] as int? ?? 0,
        ));
      }

      offset += _pageSize;
      if (onProgress != null && total > 0) {
        final p = (offset / total).clamp(0.0, 1.0);
        onProgress(p, 'Parsing $label… $offset / $total');
      }
      if (rows.length < _pageSize) break;
    }

    return cards;
  }
}

/// Exception thrown when Anki import fails.
class AnkiImportException implements Exception {
  final String message;
  const AnkiImportException(this.message);

  @override
  String toString() => 'AnkiImportException: $message';
}

/// Thrown when the user cancels an in-progress parse/assemble.
class AnkiImportCancelled implements Exception {
  const AnkiImportCancelled();

  @override
  String toString() => 'AnkiImportCancelled';
}
