import 'dart:io';

import 'package:turna/application/anki_official/migration/official_anki_backup_manifest.dart';
import 'package:turna/application/anki_official/migration/official_anki_census.dart';
import 'package:turna/application/anki_official/migration/official_anki_dry_run_matcher.dart';
import 'package:turna/application/anki_official/migration/official_anki_dry_run_saga.dart';
import 'package:turna/application/anki_official/migration/official_anki_engine_kind.dart';
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
    this.selectedImport,
    this.backupFile,
  });

  final LegacyAnkiCensusReport census;
  final LegacyAnkiDryRunResult dryRun;
  final int diskFreeBytes;
  final String displayName;
  final LegacyAnkiImportCensus? selectedImport;
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
        final target =
            selectLegacyAnkiPilotImport(census.imports) ?? census.imports.first;
        final existing = dao.findByLegacyImport(
          profileId: paths.profileId,
          legacyImportId: target.importId,
        );
        final migrationId = existing?.migrationId ?? 'mig-${target.importId}';
        if (existing == null) {
          dao.insertDetected(
            migrationId: migrationId,
            profileId: paths.profileId,
            legacyImportId: target.importId,
            policy: LegacyAnkiSchedulingPolicy.preservePackageScheduling,
            nowMillis: now,
            sourceHash: target.sourceHash,
            legacyCardCount: target.cardCount,
          );
        }
        final legacy = identityReader == null
            ? const <LegacyAnkiCardIdentity>[]
            : await identityReader.loadCardIdentities(target.importId);
        dao.replaceDryRunMap(
          migrationId: migrationId,
          result: const LegacyAnkiDryRunResult(rows: []),
        );
        dao.setCursor(
          migrationId: migrationId,
          cursorLegacyCardId: 0,
          nowMillis: now,
        );
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
    final selected = selectLegacyAnkiPilotImport(census.imports);
    return OfficialAnkiMigrationPreviewModel(
      census: census,
      dryRun: dryRun,
      diskFreeBytes: paths.diskFreeBytes(),
      displayName: selected != null
          ? 'Legacy (${selected.importId})'
          : census.imports.isNotEmpty
              ? 'Legacy (${census.imports.first.importId})'
              : 'Legacy source (0 detected)',
      selectedImport: selected,
      backupFile: backupFile,
    );
  }
}

class OfficialAnkiFixtureReviewTarget {
  const OfficialAnkiFixtureReviewTarget({
    required this.sourceId,
    required this.deckId,
    required this.cardIds,
  });

  final String sourceId;
  final int deckId;
  final Set<int> cardIds;
}

OfficialAnkiFixtureReviewTarget? officialAnkiObservingFixtureReviewTarget({
  required OfficialAnkiMigrationDao dao,
  required OfficialAnkiSourceDao sources,
  required String profileId,
}) {
  final row = dao.findObservingFixture(profileId: profileId);
  final sourceId = row?.officialSourceId;
  if (sourceId == null || sourceId.isEmpty) return null;
  final cards = sources.listCards(sourceId);
  if (cards.isEmpty) return null;
  return OfficialAnkiFixtureReviewTarget(
    sourceId: sourceId,
    deckId: cards.first.deckId,
    cardIds: {for (final card in cards) card.cardId},
  );
}

int? officialAnkiObservingFixtureDeckId({
  required OfficialAnkiMigrationDao dao,
  required OfficialAnkiSourceDao sources,
  required String profileId,
}) {
  return officialAnkiObservingFixtureReviewTarget(
    dao: dao,
    sources: sources,
    profileId: profileId,
  )?.deckId;
}

LegacyAnkiImportCensus? selectLegacyAnkiPilotImport(
  List<LegacyAnkiImportCensus> imports,
) {
  for (final row in imports) {
    if (isFixturePilotSource(
      importId: row.importId,
      sourceHash: row.sourceHash,
    )) {
      return row;
    }
  }
  return null;
}
