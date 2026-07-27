// Dart imports:
import 'dart:convert';

// Package imports:
import 'package:file_picker/file_picker.dart';

// Package imports:
import 'package:drift/drift.dart' show Value;

// Project imports:
import 'package:varnamala/data/course_database.dart' as db;
import 'package:varnamala/data/course_repository.dart';
import 'package:varnamala/di/injection.dart';
import 'package:varnamala/domain/course/word_entry.dart';

/// Service for importing vocabulary from Anki CSV exports.
///
/// Anki can export notes as CSV (File → Export → "Notes in Plain Text (.csv)").
/// The expected format is: `front,back` (two columns) or `front,back,hint,...`
/// (extra columns are ignored). The first row may be a header and is skipped
/// if it looks like one (i.e. contains common header words).
///
/// Imported words are tagged with `anki:<importId>` so they can be identified
/// and removed later via [CourseRepository.deleteByTag].
class AnkiImportService {
  final CourseRepository _repo;

  AnkiImportService() : _repo = getIt<CourseRepository>();

  /// Pick a CSV file and import its words into the current language course.
  ///
  /// Returns the number of words successfully imported. Throws if the user
  /// cancels the file picker or the file cannot be parsed.
  Future<int> importFromCsv() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'txt'],
    );

    if (result == null || result.files.single.path == null) {
      throw ImportCancelledException();
    }

    final path = result.files.single.path!;
    final bytes = result.files.single.bytes!;
    final content = utf8.decode(bytes, allowMalformed: true);

    return _parseAndInsert(content, path);
  }

  /// Import from a raw CSV string (useful for paste/drag-drop flows).
  Future<int> importFromString(String csv, {String sourceLabel = 'pasted'}) async {
    return _parseAndInsert(csv, sourceLabel);
  }

  Future<int> _parseAndInsert(String content, String sourceLabel) async {
    final lines = content
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    if (lines.isEmpty) {
      throw ImportEmptyException();
    }

    // Detect delimiter: tab is common in Anki exports, then comma.
    final delimiter = lines.first.contains('\t') ? '\t' : ',';

    // Skip header row if it looks like one.
    int startIdx = 0;
    if (_isHeaderRow(lines.first, delimiter)) {
      startIdx = 1;
    }

    final importId = DateTime.now().millisecondsSinceEpoch.toString();
    final words = <WordEntry>[];
    final seenTerms = <String>{};

    for (var i = startIdx; i < lines.length; i++) {
      final cols = _splitCsvLine(lines[i], delimiter);
      if (cols.length < 2) continue;

      final term = cols[0].trim();
      final translation = cols[1].trim();
      if (term.isEmpty || translation.isEmpty) continue;

      // Deduplicate within the same import.
      final key = term.toLowerCase();
      if (seenTerms.contains(key)) continue;
      seenTerms.add(key);

      // Pronunciation may be in column 3 if present.
      final pronunciation = cols.length > 2 ? cols[2].trim() : null;

      words.add(WordEntry(
        id: 'anki-$importId-${words.length}',
        term: term,
        translation: translation,
        pronunciation: pronunciation?.isNotEmpty == true ? pronunciation : null,
        tags: ['anki:$importId'],
      ));
    }

    if (words.isEmpty) {
      throw ImportEmptyException();
    }

    await _repo.bulkInsertVocabulary(words);

    // Record the import metadata.
    await _repo.recordAnkiImport(
      db.AnkiImportsCompanion(
        importId: Value(importId),
        sourcePath: Value(sourceLabel),
        sourceHash: Value('csv-$importId'),
        importedAt: Value(DateTime.now().millisecondsSinceEpoch ~/ 1000),
        noteCount: Value(words.length),
        deckCount: Value(1),
        cardCount: Value(words.length),
      ),
    );

    return words.length;
  }

  /// Split a CSV line respecting quoted fields (simple RFC 4180 handling).
  List<String> _splitCsvLine(String line, String delimiter) {
    // If no quotes, simple split.
    if (!line.contains('"')) {
      return line.split(delimiter);
    }

    final result = <String>[];
    final buf = StringBuffer();
    var inQuotes = false;

    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (inQuotes) {
        if (c == '"') {
          if (i + 1 < line.length && line[i + 1] == '"') {
            buf.write('"');
            i++; // skip escaped quote
          } else {
            inQuotes = false;
          }
        } else {
          buf.write(c);
        }
      } else {
        if (c == '"') {
          inQuotes = true;
        } else if (c == delimiter) {
          result.add(buf.toString());
          buf.clear();
        } else {
          buf.write(c);
        }
      }
    }
    result.add(buf.toString());

    return result;
  }

  bool _isHeaderRow(String line, String delimiter) {
    final cols = line.split(delimiter).map((c) => c.trim().toLowerCase()).toList();
    if (cols.isEmpty) return false;
    final first = cols.first;
    // Common Anki header words across languages.
    return first == 'front' ||
        first == '正面' ||
        first == 'term' ||
        first == '単語' ||
        first == 'word' ||
        first == 'expression';
  }
}

class ImportCancelledException implements Exception {
  @override
  String toString() => 'Import cancelled by user';
}

class ImportEmptyException implements Exception {
  @override
  String toString() => 'No valid word pairs found in the file';
}
