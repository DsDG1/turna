// Dart imports:
import 'dart:convert';

// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

// Project imports:
import 'package:turna/application/anki/anki_models.dart';
import 'package:turna/core/logger.dart';

// Platform imports:
import 'anki_import_platform_stub.dart'
    if (dart.library.io) 'anki_import_platform_io.dart' as platform;

/// Parses Anki `.apkg` / `.colpkg` files into an [AnkiCollection]
/// intermediate representation. Pure parsing — does not touch the Turna
/// database.
///
/// Implementation notes:
/// - Uses `archive` package for ZIP extraction
/// - Uses `sqlite3` (ffi) for reading legacy-compatible
///   `collection.anki2` / `collection.anki21` exports
/// - Large collections are read in pages (LIMIT/OFFSET) to avoid memory spikes
class AnkiImporter {
  static const int _pageSize = 500;
  static const String _fieldSeparator = '\x1f';

  /// Safety limits for untrusted ZIP input. They are deliberately generous
  /// for real language decks while preventing accidental or malicious
  /// expansion from exhausting the app process.
  static const int maxArchiveBytes = 512 * 1024 * 1024;
  static const int maxEntries = 100000;
  static const int maxUncompressedBytes = 2 * 1024 * 1024 * 1024;
  static const int maxEntryBytes = 256 * 1024 * 1024;

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
    if (defaultTargetPlatform.name == 'ohos') {
      throw UnsupportedError(
        'Anki import is not available on HarmonyOS yet. '
        'Anki `.apkg` files are SQLite databases read via sqlite3 FFI, '
        'which has no HarmonyOS build.',
      );
    }
    if (!platform.ankiFileExists(apkgPath)) {
      throw AnkiImportException('File not found: $apkgPath');
    }

    // Extract ZIP archive. The default directory belongs to this import and
    // is removed on every failure/cancellation. A caller-supplied directory
    // remains caller-owned, but [cleanupExtractedDir] can be used after a
    // successful import.
    final extractDir = tempDir ??
        p.join(platform.ankiSystemTempPath,
            'anki_import_${DateTime.now().millisecondsSinceEpoch}');
    final ownsExtractDir = tempDir == null;
    platform.ankiCreateDirectory(extractDir);

    platform.AnkiSqlDatabase? db;
    var parseSucceeded = false;
    try {
      final archiveBytes = platform.ankiFileLength(apkgPath);
      if (archiveBytes > maxArchiveBytes) {
        throw AnkiImportException(
          'Archive is too large (${archiveBytes ~/ (1024 * 1024)} MiB; '
          'limit ${maxArchiveBytes ~/ (1024 * 1024)} MiB)',
        );
      }

      final bytes = platform.ankiReadBytes(apkgPath);
      // Hash the source bytes once here - they are already in memory for ZIP
      // extraction - so callers can detect re-imports without a second full
      // synchronous read of a potentially huge file on the main isolate.
      final sourceHash = sha256.convert(bytes).toString();
      final archive = platform.decodeAnkiArchive(bytes);
      if (archive.length > maxEntries) {
        throw AnkiImportException(
          'Archive contains too many files (${archive.length}; limit $maxEntries)',
        );
      }

      var uncompressedBytes = 0;
      for (final entry in archive) {
        if (!entry.isFile) continue;
        final safeName = _safeArchiveEntryName(entry.name);
        final content = List<int>.from(entry.content);
        if (content.length > maxEntryBytes) {
          throw AnkiImportException(
            'Archive entry is too large: ${entry.name}',
          );
        }
        uncompressedBytes += content.length;
        if (uncompressedBytes > maxUncompressedBytes) {
          throw AnkiImportException(
            'Archive expands beyond the ${maxUncompressedBytes ~/ (1024 * 1024)} MiB limit',
          );
        }
        final outputPath = p.join(extractDir, safeName);
        platform.ankiCreateDirectory(p.dirname(outputPath));
        platform.ankiWriteBytes(outputPath, content);
      }

      // Determine database file
      final dbFile = _findDatabaseFile(extractDir);
      if (dbFile == null) {
        // Current Anki exports use a zstd-compressed schema-v18 database named
        // `collection.anki21b`. It is not byte-compatible with the legacy
        // SQLite schema parsed below. Detect it explicitly instead of
        // reporting a misleading "no collection" error (or, worse, importing
        // an empty course). Anki can still produce the supported schema via
        // the "Support older Anki versions" export option.
        final modernCollection = p.join(extractDir, 'collection.anki21b');
        if (platform.ankiFileExists(modernCollection)) {
          throw const AnkiImportException(
            '该文件使用 Anki 最新版牌组格式（collection.anki21b），当前版本尚不能安全解析。'
            '请在 Anki 导出时勾选“支持旧版 Anki / Support older Anki versions”后重新导入。',
            code: 'PACKAGE_VERSION_UNSUPPORTED',
          );
        }
        throw AnkiImportException(
          '压缩包中没有找到可识别的 Anki 数据库（collection.anki2 或 collection.anki21）。',
          code: 'COLLECTION_DATABASE_MISSING',
        );
      }

      // Parse media mapping
      final media = _parseMediaMapping(extractDir);

      // Open SQLite database (read-only)
      db = platform.openAnkiDatabase(dbFile);

      // Parse collection metadata (decks + notetypes)
      final colRow = db.select('SELECT * FROM col LIMIT 1');
      if (colRow.isEmpty) {
        throw AnkiImportException('Empty collection table');
      }

      final col = colRow.first;
      final decksJson = col['decks']?.toString() ?? '{}';
      final modelsJson = col['models']?.toString() ?? '{}';
      final collectionCreationTime = _asInt(col['crt']);
      final deckConfigs = _asJsonMap(col['dconf']);

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

      // Parse review log (paginated). Optional - some packages may lack the
      // table; a missing table degrades to an empty list (no history migration).
      final revlog = _parseRevlog(
        db,
        onProgress: onProgress,
        isCancelled: isCancelled,
        label: 'revlog',
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

      final collection = AnkiCollection(
        notetypes: notetypes,
        decks: decksWithCounts,
        notes: notes,
        cards: cards,
        media: media,
        mediaDir: extractDir,
        sourceHash: sourceHash,
        revlog: revlog,
        collectionCreationTime: collectionCreationTime,
        deckConfigs: deckConfigs,
      );
      parseSucceeded = true;
      return collection;
    } finally {
      db?.dispose();
      if (ownsExtractDir && !parseSucceeded) cleanupExtractedDir(extractDir);
    }
  }

  /// Remove an extracted import directory after the caller has copied the
  /// persistent media it needs. Safe to call for an empty/non-existent path.
  static void cleanupExtractedDir(String path) {
    if (path.isEmpty) return;
    if (platform.ankiDirectoryExists(path)) {
      try {
        platform.ankiDeleteDirectory(path);
      } catch (e) {
        logger.w('Failed to clean Anki temporary directory $path: $e');
      }
    }
  }

  String _safeArchiveEntryName(String rawName) {
    final name = rawName.replaceAll('\\', '/');
    if (name.isEmpty ||
        name.startsWith('/') ||
        RegExp(r'^[A-Za-z]:').hasMatch(name)) {
      throw AnkiImportException('Unsafe ZIP entry path: $rawName');
    }
    final parts = name.split('/');
    if (parts.any((part) => part.isEmpty || part == '..')) {
      throw AnkiImportException('Unsafe ZIP entry path: $rawName');
    }
    return parts.join(p.separator);
  }

  static int _asInt(Object? value) =>
      value is int ? value : int.tryParse(value?.toString() ?? '') ?? 0;

  static int _requiredPositiveInt(
    Map<String, Object?> row,
    String column,
  ) {
    final value = row[column];
    final parsed = value is int ? value : int.tryParse(value?.toString() ?? '');
    if (parsed == null || parsed <= 0) {
      throw AnkiImportException(
        'cards.$column must be a positive integer (got $value)',
      );
    }
    return parsed;
  }

  static int _requiredNonNegativeInt(
    Map<String, Object?> row,
    String column,
  ) {
    final value = row[column];
    final parsed = value is int ? value : int.tryParse(value?.toString() ?? '');
    if (parsed == null || parsed < 0) {
      throw AnkiImportException(
        'cards.$column must be a non-negative integer (got $value)',
      );
    }
    return parsed;
  }

  static Map<String, dynamic> _asJsonMap(Object? value) {
    if (value is! String || value.isEmpty) return const {};
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map<String, dynamic>) return decoded;
      return const {};
    } catch (_) {
      return const {};
    }
  }

  /// Find the SQLite database file in the extracted directory.
  String? _findDatabaseFile(String extractDir) {
    // Anki 2.1+ uses collection.anki21, older uses collection.anki2
    final anki21 = p.join(extractDir, 'collection.anki21');
    if (platform.ankiFileExists(anki21)) return anki21;

    final anki2 = p.join(extractDir, 'collection.anki2');
    if (platform.ankiFileExists(anki2)) return anki2;

    return null;
  }

  /// Parse the `media` JSON file (maps numeric filenames to original names).
  Map<String, String> _parseMediaMapping(String extractDir) {
    final mediaPath = p.join(extractDir, 'media');
    if (!platform.ankiFileExists(mediaPath)) return {};

    try {
      final content = platform.ankiReadString(mediaPath);
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
      final raw = jsonDecode(decksJson);
      if (raw is! Map) {
        throw const AnkiImportException('col.decks is not a JSON object');
      }
      final decoded = Map<String, dynamic>.from(raw);
      // Build the complete name/id map first. Anki's JSON order is not a
      // parent-before-child guarantee, so resolving parents while iterating
      // made multi-level decks depend on export ordering.
      for (final entry in decoded.entries) {
        try {
          final did = int.parse(entry.key);
          if (did <= 0 || entry.value is! Map) {
            throw const FormatException('invalid deck id or body');
          }
          final deckData = Map<String, dynamic>.from(entry.value as Map);
          final name = deckData['name']?.toString().trim();
          result[did] = AnkiDeckInfo(
            id: did,
            name: name == null || name.isEmpty ? 'Deck $did' : name,
          );
        } catch (e) {
          logger.w('Skipping malformed deck ${entry.key}: $e');
        }
      }

      final idsByName = <String, int>{
        for (final deck in result.values) deck.name: deck.id,
      };
      for (final entry in result.entries.toList()) {
        final name = entry.value.name;
        final separator = name.lastIndexOf('::');
        final parentName = separator < 0 ? '' : name.substring(0, separator);
        final parentId = parentName.isEmpty ? 0 : (idsByName[parentName] ?? 0);
        result[entry.key] = entry.value.copyWith(parentId: parentId);
      }
    } on AnkiImportException {
      rethrow;
    } catch (e) {
      throw AnkiImportException('Failed to parse col.decks: $e');
    }
    return result;
  }

  /// Parse notetypes (models) JSON from the `col.models` column.
  Map<int, AnkiNotetype> _parseNotetypes(String modelsJson) {
    final result = <int, AnkiNotetype>{};
    try {
      final raw = jsonDecode(modelsJson);
      if (raw is! Map) {
        throw const AnkiImportException('col.models is not a JSON object');
      }
      final decoded = Map<String, dynamic>.from(raw);
      for (final entry in decoded.entries) {
        try {
          final mid = int.parse(entry.key);
          if (mid <= 0 || entry.value is! Map) {
            throw const FormatException('invalid notetype id or body');
          }
          final modelData = Map<String, dynamic>.from(entry.value as Map);
          final name = modelData['name']?.toString() ?? 'Model $mid';

          // Parse field names. A single malformed field used to be
          // skipped-with-warning while the rest of the notetype was kept —
          // but that left `fieldNames[i] == ''` and shifted every later
          // field by one when the renderer indexed `note.fields[i]` against
          // `fieldNames[i]`. Reject the entire notetype instead so a
          // malformed export produces zero notetypes rather than silently
          // mis-indexed ones. Skipping the notetype leaves the deck
          // un-importable but at least the user sees a clear diagnostic.
          final flds = modelData['flds'] is List
              ? modelData['flds'] as List<dynamic>
              : const <dynamic>[];
          if (flds.isEmpty) {
            logger.w('Notetype $mid has no fields; skipping entire notetype');
            continue;
          }
          final fieldNames = <String>[];
          var fieldsOk = true;
          for (final field in flds) {
            if (field is! Map || field['name'] == null) {
              logger.w(
                'Notetype $mid has a malformed field; skipping entire notetype',
              );
              fieldsOk = false;
              break;
            }
            fieldNames.add(field['name'].toString());
          }
          if (!fieldsOk) continue;

          // Parse template names + question/answer bodies (qfmt/afmt). The
          // bodies drive direction-correct rendering (e.g. "Basic (and
          // reversed)") and per-card question-type detection in the adapter.
          final tmpls = modelData['tmpls'] is List
              ? modelData['tmpls'] as List<dynamic>
              : const <dynamic>[];
          final templateNames = <String>[];
          final templates = <AnkiTemplate>[];
          for (final template in tmpls) {
            if (template is! Map) {
              logger.w('Skipping malformed template in notetype $mid');
              continue;
            }
            final td = Map<String, dynamic>.from(template);
            final tName = td['name']?.toString() ?? '';
            templateNames.add(tName);
            templates.add(AnkiTemplate(
              name: tName,
              qfmt: td['qfmt']?.toString() ?? '',
              afmt: td['afmt']?.toString() ?? '',
            ));
          }

          // Detect Cloze type (type == 1 in Anki)
          final isCloze = _asInt(modelData['type']) == 1;

          result[mid] = AnkiNotetype(
            id: mid,
            name: name,
            fieldNames: fieldNames,
            templateNames: templateNames,
            templates: templates,
            isCloze: isCloze,
            css: modelData['css']?.toString() ?? '',
          );
        } catch (e) {
          logger.w('Skipping malformed notetype ${entry.key}: $e');
        }
      }
    } on AnkiImportException {
      rethrow;
    } catch (e) {
      throw AnkiImportException('Failed to parse col.models: $e');
    }
    return result;
  }

  /// Test-only entry point: parse [modelsJson] (the value of `col.models`)
  /// into the same shape [_parseNotetypes] produces. Lets unit tests
  /// exercise notetype parsing without an `.apkg` fixture.
  @visibleForTesting
  static Map<int, AnkiNotetype> parseNotetypesForTest(String modelsJson) {
    return AnkiImporter._parseNotetypesShared(modelsJson);
  }

  /// Shared static entry for [_parseNotetypes] — keeps the test seam and
  /// the production path reading the same JSON-to-notetypes code without
  /// leaking instance state.
  static Map<int, AnkiNotetype> _parseNotetypesShared(String modelsJson) {
    return AnkiImporter()._parseNotetypes(modelsJson);
  }

  /// Parse notes table with pagination.
  List<AnkiNote> _parseNotes(
    platform.AnkiSqlDatabase db, {
    void Function(double, String)? onProgress,
    bool Function()? isCancelled,
    String label = 'notes',
  }) {
    final total =
        db.select('SELECT COUNT(*) AS c FROM notes').first['c'] as int;
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
    platform.AnkiSqlDatabase db, {
    void Function(double, String)? onProgress,
    bool Function()? isCancelled,
    String label = 'cards',
  }) {
    final total =
        db.select('SELECT COUNT(*) AS c FROM cards').first['c'] as int;
    final cards = <AnkiCardData>[];
    var offset = 0;

    while (true) {
      if (isCancelled != null && isCancelled()) {
        throw const AnkiImportCancelled();
      }
      final rows = db.select(
        'SELECT id, nid, did, ord, type, queue, due, ivl, factor, reps, lapses, '
        'left, odue, odid, flags, data '
        'FROM cards ORDER BY id LIMIT $_pageSize OFFSET $offset',
      );

      if (rows.isEmpty) break;

      for (final row in rows) {
        cards.add(AnkiCardData(
          id: _requiredPositiveInt(row, 'id'),
          nid: _requiredPositiveInt(row, 'nid'),
          did: _requiredPositiveInt(row, 'did'),
          ord: _requiredNonNegativeInt(row, 'ord'),
          type: _asInt(row['type']),
          queue: _asInt(row['queue']),
          due: _asInt(row['due']),
          ivl: _asInt(row['ivl']),
          factor: row['factor'] == null ? 2500 : _asInt(row['factor']),
          reps: _asInt(row['reps']),
          lapses: _asInt(row['lapses']),
          left: _asInt(row['left']),
          odue: _asInt(row['odue']),
          odid: _asInt(row['odid']),
          flags: _asInt(row['flags']),
          data: row['data']?.toString() ?? '',
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

  /// Parse the `revlog` (review log) table with pagination. Returns an empty
  /// list when the table is absent (older/trimmed packages) so revlog migration
  /// is best-effort and never blocks import.
  List<AnkiRevlogEntry> _parseRevlog(
    platform.AnkiSqlDatabase db, {
    void Function(double, String)? onProgress,
    bool Function()? isCancelled,
    String label = 'revlog',
  }) {
    final total = (() {
      try {
        return db.select('SELECT COUNT(*) AS c FROM revlog').first['c'] as int;
      } catch (_) {
        return 0; // table missing
      }
    })();
    if (total == 0) return const [];

    final entries = <AnkiRevlogEntry>[];
    var offset = 0;

    while (true) {
      if (isCancelled != null && isCancelled()) {
        throw const AnkiImportCancelled();
      }
      final rows = db.select(
        'SELECT id, cid, usn, ease, ivl, lastIvl, factor, time, type '
        'FROM revlog ORDER BY id LIMIT $_pageSize OFFSET $offset',
      );

      if (rows.isEmpty) break;

      for (final row in rows) {
        entries.add(AnkiRevlogEntry(
          id: row['id'] as int,
          cid: row['cid'] as int,
          usn: row['usn'] as int? ?? 0,
          ease: row['ease'] as int? ?? 0,
          ivl: row['ivl'] as int? ?? 0,
          lastIvl: row['lastIvl'] as int? ?? 0,
          factor: row['factor'] as int? ?? 0,
          time: row['time'] as int? ?? 0,
          type: row['type'] as int? ?? 0,
        ));
      }

      offset += _pageSize;
      if (onProgress != null && total > 0) {
        final p = (offset / total).clamp(0.0, 1.0);
        onProgress(p, 'Parsing $label… $offset / $total');
      }
      if (rows.length < _pageSize) break;
    }

    return entries;
  }
}

/// Exception thrown when Anki import fails.
class AnkiImportException implements Exception {
  final String message;
  final String? code;

  const AnkiImportException(this.message, {this.code});

  @override
  String toString() => code == null ? message : '[$code] $message';
}

/// Thrown when the user cancels an in-progress parse/assemble.
class AnkiImportCancelled implements Exception {
  const AnkiImportCancelled();

  @override
  String toString() => 'AnkiImportCancelled';
}
