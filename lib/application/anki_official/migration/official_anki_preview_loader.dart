import 'dart:io';

import 'package:turna/application/anki_official/migration/official_anki_backup_manifest.dart';
import 'package:turna/application/anki_official/migration/official_anki_census.dart';
import 'package:turna/application/anki_official/migration/official_anki_dry_run_matcher.dart';
import 'package:turna/application/anki_official/migration/official_anki_dry_run_saga.dart';
import 'package:turna/application/anki_official/migration/official_anki_migration_dao.dart';
import 'package:turna/application/anki_official/migration/official_anki_migration_state.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';

class OfficialAnkiMigrationPreviewModel {
  const OfficialAnkiMigrationPreviewModel({
    required this.census,
    required this.dryRun,
    required this.diskFreeBytes,
    required this.displayName,
    this.backupFile,
  });

  final LegacyAnkiCensusReport census;
  final LegacyAnkiDryRunResult dryRun;
  final int diskFreeBytes;
  final String displayName;
  final File? backupFile;
}

/// Builds preview input. Never switches routes or writes scheduling.
class OfficialAnkiMigrationPreviewLoader {
  const OfficialAnkiMigrationPreviewLoader();

  Future<OfficialAnkiMigrationPreviewModel> load({
    required OfficialAnkiPaths paths,
    required LegacyAnkiCensusReport census,
    DatabaseLegacyAnkiCensusReader? identityReader,
    int? nowMillis,
  }) async {
    await paths.ensureLayout();
    final now = nowMillis ?? DateTime.now().millisecondsSinceEpoch;
    var dryRun = const LegacyAnkiDryRunResult(rows: []);
    File? backupFile;
    if (census.imports.isNotEmpty) {
      final catalog = OfficialAnkiDatabase.file(paths.catalogFile.path);
      try {
        final dao = OfficialAnkiMigrationDao(catalog);
        final sources = OfficialAnkiSourceDao(catalog);
        final official = [
          for (final source in sources.listSources(paths.profileId))
            for (final card in sources.listCards(source.sourceId))
              OfficialAnkiCardIdentity(
                officialCardId: card.cardId,
                templateOrd: card.templateOrd,
                officialNoteId: card.noteId,
                noteGuid: card.noteGuid,
              ),
        ];
        final first = census.imports.first;
        final existing = dao.findByLegacyImport(
          profileId: paths.profileId,
          legacyImportId: first.importId,
        );
        final migrationId = existing?.migrationId ?? 'mig-${first.importId}';
        if (existing == null) {
          dao.insertDetected(
            migrationId: migrationId,
            profileId: paths.profileId,
            legacyImportId: first.importId,
            policy: LegacyAnkiSchedulingPolicy.preservePackageScheduling,
            nowMillis: now,
            sourceHash: first.sourceHash,
            legacyCardCount: first.cardCount,
          );
        }
        final legacy = identityReader == null
            ? const <LegacyAnkiCardIdentity>[]
            : await identityReader.loadCardIdentities(first.importId);
        dryRun = await const LegacyAnkiDryRunSaga().run(
          dao: dao,
          migrationId: migrationId,
          legacyCards: legacy,
          officialCards: official,
          nowMillis: now,
        );
        const service = LegacyAnkiBackupService();
        final manifest = service.generateFromCensus(census: census);
        backupFile = await service.persist(
          manifest: manifest,
          targetFile: File(
            '${paths.backups.path}/legacy-manifest-$migrationId.json',
          ),
        );
        service.recordInDao(
          dao: dao,
          migrationId: migrationId,
          manifest: manifest,
          nowMillis: now,
        );
      } finally {
        catalog.close();
      }
    }
    return OfficialAnkiMigrationPreviewModel(
      census: census,
      dryRun: dryRun,
      diskFreeBytes: paths.diskFreeBytes(),
      displayName: census.imports.isNotEmpty
          ? 'Legacy (${census.imports.first.importId})'
          : 'Legacy source (0 detected)',
      backupFile: backupFile,
    );
  }
}
