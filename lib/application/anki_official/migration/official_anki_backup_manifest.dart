import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:turna/application/anki_official/migration/official_anki_census.dart';
import 'package:turna/application/anki_official/migration/official_anki_dry_run_matcher.dart';
import 'package:turna/application/anki_official/migration/official_anki_migration_dao.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';

/// Descriptive backup receipt. Does not switch source routes.
class LegacyAnkiBackupManifest {
  const LegacyAnkiBackupManifest({
    required this.legacyRowCount,
    required this.legacyRowHash,
    this.officialBackupId,
    this.projectionFingerprint,
    this.createdAtMillis = 0,
  });

  final int legacyRowCount;
  final String legacyRowHash;
  final String? officialBackupId;
  final String? projectionFingerprint;
  final int createdAtMillis;

  Map<String, Object?> toJson() => <String, Object?>{
        'legacyRowCount': legacyRowCount,
        'legacyRowHash': legacyRowHash,
        'officialBackupId': officialBackupId,
        'projectionFingerprint': projectionFingerprint,
        'createdAtMillis': createdAtMillis,
      };

  factory LegacyAnkiBackupManifest.fromJson(Map<String, Object?> json) {
    return LegacyAnkiBackupManifest(
      legacyRowCount: (json['legacyRowCount'] as num).toInt(),
      legacyRowHash: json['legacyRowHash'] as String,
      officialBackupId: json['officialBackupId'] as String?,
      projectionFingerprint: json['projectionFingerprint'] as String?,
      createdAtMillis: (json['createdAtMillis'] as num?)?.toInt() ?? 0,
    );
  }

  static String hashCounts({
    required int importCount,
    required int noteCount,
    required int cardCount,
    required int srsCount,
  }) {
    return base64Encode(
      utf8.encode('$importCount|$noteCount|$cardCount|$srsCount'),
    );
  }
}

class LegacyAnkiBackupService {
  const LegacyAnkiBackupService();

  LegacyAnkiBackupManifest generate({
    required int importCount,
    required int noteCount,
    required int cardCount,
    required int srsCount,
    String? officialBackupId,
    String? projectionFingerprint,
    int? createdAtMillis,
  }) {
    final totalRowCount = importCount + noteCount + cardCount + srsCount;
    return LegacyAnkiBackupManifest(
      legacyRowCount: totalRowCount,
      legacyRowHash: LegacyAnkiBackupManifest.hashCounts(
        importCount: importCount,
        noteCount: noteCount,
        cardCount: cardCount,
        srsCount: srsCount,
      ),
      officialBackupId: officialBackupId,
      projectionFingerprint: projectionFingerprint,
      createdAtMillis: createdAtMillis ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  LegacyAnkiBackupManifest generateFromCensus({
    required LegacyAnkiCensusReport census,
    String? officialBackupId,
    String? projectionFingerprint,
    int? createdAtMillis,
  }) {
    final srsCount = census.imports.fold<int>(
      0,
      (sum, row) => sum + row.srsRowCount,
    );
    return generate(
      importCount: census.imports.length,
      noteCount: census.noteCount,
      cardCount: census.cardCount,
      srsCount: srsCount,
      officialBackupId: officialBackupId,
      projectionFingerprint: projectionFingerprint,
      createdAtMillis: createdAtMillis,
    );
  }

  Future<File> persist({
    required LegacyAnkiBackupManifest manifest,
    required File targetFile,
  }) async {
    if (!targetFile.parent.existsSync()) {
      targetFile.parent.createSync(recursive: true);
    }
    final content = const JsonEncoder.withIndent('  ').convert(manifest.toJson());
    await targetFile.writeAsString(content, flush: true);
    return targetFile;
  }

  void recordInDao({
    required OfficialAnkiMigrationDao dao,
    required String migrationId,
    required LegacyAnkiBackupManifest manifest,
    int? nowMillis,
  }) {
    final now = nowMillis ?? DateTime.now().millisecondsSinceEpoch;
    dao.setBackupInfo(
      migrationId: migrationId,
      backupId: manifest.officialBackupId ?? 'local-backup',
      backupManifestHash: manifest.legacyRowHash,
      nowMillis: now,
    );
  }

  Future<Directory> createPhysicalBackup({
    required OfficialAnkiPaths paths,
    required String migrationId,
    required LegacyAnkiBackupManifest manifest,
    List<LegacyAnkiCardIdentity>? legacyCards,
  }) async {
    final backupDir = Directory('${paths.backups.path}/p5c/$migrationId');
    if (!backupDir.existsSync()) {
      backupDir.createSync(recursive: true);
    }

    // 1. legacy-manifest.json (desensitized receipt, no card text)
    final manifestFile = File('${backupDir.path}/legacy-manifest.json');
    await persist(manifest: manifest, targetFile: manifestFile);

    // 2. legacy-subset.sqlite (CourseDatabase subset: only IDs, GUIDs, ordinals, counts)
    final subsetDbFile = File('${backupDir.path}/legacy-subset.sqlite');
    if (subsetDbFile.existsSync()) {
      subsetDbFile.deleteSync();
    }
    final db = sqlite3.open(subsetDbFile.path);
    try {
      db.execute('''
CREATE TABLE legacy_cards_subset (
  legacy_card_id INTEGER PRIMARY KEY,
  legacy_word_id TEXT NOT NULL,
  legacy_note_id INTEGER,
  template_ord INTEGER NOT NULL,
  note_guid TEXT,
  content_fingerprint TEXT
);
CREATE TABLE legacy_backup_metadata (
  migration_id TEXT PRIMARY KEY,
  legacy_row_count INTEGER NOT NULL,
  legacy_row_hash TEXT NOT NULL,
  created_at_millis INTEGER NOT NULL
);
''');
      db.execute(
        'INSERT INTO legacy_backup_metadata '
        '(migration_id, legacy_row_count, legacy_row_hash, created_at_millis) '
        'VALUES (?, ?, ?, ?)',
        [
          migrationId,
          manifest.legacyRowCount,
          manifest.legacyRowHash,
          manifest.createdAtMillis,
        ],
      );

      if (legacyCards != null && legacyCards.isNotEmpty) {
        final stmt = db.prepare(
          'INSERT OR IGNORE INTO legacy_cards_subset '
          '(legacy_card_id, legacy_word_id, legacy_note_id, template_ord, note_guid, content_fingerprint) '
          'VALUES (?, ?, ?, ?, ?, ?)',
        );
        for (final card in legacyCards) {
          stmt.execute([
            card.legacyCardId,
            card.legacyWordId,
            card.legacyNoteId,
            card.templateOrd,
            card.noteGuid,
            card.contentFingerprint,
          ]);
        }
        stmt.dispose();
      }
    } finally {
      db.dispose();
    }

    // 3. collection.anki2 (Official Collection copy)
    final colCopy = File('${backupDir.path}/collection.anki2');
    if (paths.collectionFile.existsSync()) {
      paths.collectionFile.copySync(colCopy.path);
    } else {
      colCopy.writeAsStringSync('');
    }

    // 4. collection.media/ (Media directory copy)
    final mediaCopy = Directory('${backupDir.path}/collection.media');
    if (!mediaCopy.existsSync()) {
      mediaCopy.createSync(recursive: true);
    }
    if (paths.mediaFolder.existsSync()) {
      for (final entity in paths.mediaFolder.listSync()) {
        if (entity is File) {
          final dest = '${mediaCopy.path}/${entity.uri.pathSegments.last}';
          try {
            Link(dest).createSync(entity.path);
          } catch (_) {
            entity.copySync(dest);
          }
        }
      }
    }

    // 5. official_catalog.sqlite (Catalog database copy)
    final catalogCopy = File('${backupDir.path}/official_catalog.sqlite');
    if (paths.catalogFile.existsSync()) {
      paths.catalogFile.copySync(catalogCopy.path);
    } else {
      catalogCopy.writeAsStringSync('');
    }

    // 6. SHA256SUMS (All backup files sha256)
    final sumsFile = File('${backupDir.path}/SHA256SUMS');
    final lines = <String>[];
    for (final file in [manifestFile, subsetDbFile, colCopy, catalogCopy]) {
      if (file.existsSync()) {
        final bytes = file.readAsBytesSync();
        final digest = sha256.convert(bytes).toString();
        lines.add('$digest  ${file.uri.pathSegments.last}');
      }
    }
    await sumsFile.writeAsString('${lines.join('\n')}\n', flush: true);

    return backupDir;
  }
}
