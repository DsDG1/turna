import 'dart:io';

import 'package:turna/application/anki_official/migration/official_anki_dry_run_matcher.dart';
import 'package:turna/data/course_database.dart';

/// Read-only Legacy Anki census. Never includes card text or media bytes.
class LegacyAnkiImportCensusSeed {
  const LegacyAnkiImportCensusSeed({
    required this.importId,
    required this.sourceHash,
    required this.noteCount,
    required this.cardCount,
    required this.mediaCount,
    required this.deckCount,
    required this.importedScheduling,
    required this.status,
    required this.sourceFilePresent,
    this.noteGuids = const <String>[],
    this.srsRowCount = 0,
    this.reviewEventCount = 0,
  });

  final String importId;
  final String sourceHash;
  final int noteCount;
  final int cardCount;
  final int mediaCount;
  final int deckCount;
  final bool importedScheduling;
  final String status;
  final bool sourceFilePresent;
  final List<String> noteGuids;
  final int srsRowCount;
  final int reviewEventCount;
}

class LegacyAnkiImportCensus {
  const LegacyAnkiImportCensus({
    required this.importId,
    required this.sourceHash,
    required this.noteCount,
    required this.cardCount,
    required this.mediaCount,
    required this.deckCount,
    required this.importedScheduling,
    required this.status,
    required this.sourceFilePresent,
    required this.srsRowCount,
    required this.reviewEventCount,
    required this.duplicateGuidCount,
    required this.missingGuidCount,
  });

  final String importId;
  final String sourceHash;
  final int noteCount;
  final int cardCount;
  final int mediaCount;
  final int deckCount;
  final bool importedScheduling;
  final String status;
  final bool sourceFilePresent;
  final int srsRowCount;
  final int reviewEventCount;
  final int duplicateGuidCount;
  final int missingGuidCount;

  Map<String, Object?> toJson() => <String, Object?>{
        'importId': importId,
        'sourceHash': sourceHash,
        'noteCount': noteCount,
        'cardCount': cardCount,
        'mediaCount': mediaCount,
        'deckCount': deckCount,
        'importedScheduling': importedScheduling,
        'status': status,
        'sourceFilePresent': sourceFilePresent,
        'srsRowCount': srsRowCount,
        'reviewEventCount': reviewEventCount,
        'duplicateGuidCount': duplicateGuidCount,
        'missingGuidCount': missingGuidCount,
      };
}

class LegacyAnkiCensusReport {
  const LegacyAnkiCensusReport({
    required this.generatedAtMillis,
    required this.platform,
    required this.imports,
  });

  static const schemaVersion = 1;

  final int generatedAtMillis;
  final String platform;
  final List<LegacyAnkiImportCensus> imports;

  int get sourceCount => imports.length;
  int get cardCount => imports.fold(0, (sum, row) => sum + row.cardCount);
  int get noteCount => imports.fold(0, (sum, row) => sum + row.noteCount);

  Map<String, Object?> toJson() => <String, Object?>{
        'schemaVersion': schemaVersion,
        'generatedAtMillis': generatedAtMillis,
        'platform': platform,
        'totals': <String, Object?>{
          'sourceCount': sourceCount,
          'noteCount': noteCount,
          'cardCount': cardCount,
          'srsRowCount':
              imports.fold<int>(0, (sum, row) => sum + row.srsRowCount),
          'reviewEventCount':
              imports.fold<int>(0, (sum, row) => sum + row.reviewEventCount),
          'missingSourceFiles':
              imports.where((row) => !row.sourceFilePresent).length,
        },
        'imports': [for (final row in imports) row.toJson()],
      };
}

abstract class LegacyAnkiCensusReader {
  Future<List<LegacyAnkiImportCensusSeed>> loadSeeds();
}

class DatabaseLegacyAnkiCensusReader implements LegacyAnkiCensusReader {
  const DatabaseLegacyAnkiCensusReader(this._db);

  final CourseDatabase _db;

  @override
  Future<List<LegacyAnkiImportCensusSeed>> loadSeeds() async {
    final imports = await _db.select(_db.ankiImports).get();
    final seeds = <LegacyAnkiImportCensusSeed>[];
    for (final imp in imports) {
      final notes = await (_db.select(_db.ankiNotes)
            ..where((t) => t.importId.equals(imp.importId)))
          .get();
      final cards = await (_db.select(_db.ankiCardsMeta)
            ..where((t) => t.importId.equals(imp.importId)))
          .get();

      final wordIds = cards.map((c) => c.wordId).toList();
      final srsCount = wordIds.isEmpty
          ? 0
          : (await (_db.select(_db.srsStates)
                    ..where((t) => t.wordId.isIn(wordIds)))
                  .get())
              .length;
      final reviewCount = wordIds.isEmpty
          ? 0
          : (await (_db.select(_db.reviewEvents)
                    ..where((t) => t.cardId.isIn(wordIds)))
                  .get())
              .length;

      final sourceFilePresent = File(imp.sourcePath).existsSync();

      seeds.add(
        LegacyAnkiImportCensusSeed(
          importId: imp.importId,
          sourceHash: imp.sourceHash,
          noteCount: notes.length,
          cardCount: cards.length,
          mediaCount: imp.mediaCount,
          deckCount: imp.deckCount,
          importedScheduling: true,
          status: 'ready',
          sourceFilePresent: sourceFilePresent,
          noteGuids: notes.map((n) => n.guid).toList(),
          srsRowCount: srsCount,
          reviewEventCount: reviewCount,
        ),
      );
    }
    return seeds;
  }

  Future<List<LegacyAnkiCardIdentity>> loadCardIdentities(
      String importId) async {
    final notes = await (_db.select(_db.ankiNotes)
          ..where((t) => t.importId.equals(importId)))
        .get();
    final guidByNoteId = <int, String>{
      for (final note in notes) note.noteId: note.guid,
    };
    final cards = await (_db.select(_db.ankiCardsMeta)
          ..where((t) => t.importId.equals(importId)))
        .get();
    return [
      for (final card in cards)
        LegacyAnkiCardIdentity(
          legacyCardId: card.cardId,
          legacyWordId: card.wordId,
          templateOrd: card.ord,
          legacyNoteId: card.noteId,
          noteGuid: guidByNoteId[card.noteId],
        ),
    ];
  }
}
