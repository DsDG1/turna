import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:turna/application/anki/anki_deck_assembler.dart';
import 'package:turna/application/anki/anki_importer.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/migration/official_anki_migration_dao.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/official_anki_ids.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/courses/course_loader.dart';
import 'package:turna/data/anki_import_dao.dart';
import 'package:turna/data/anki_note_dao.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/repositories/i_course_repository.dart';

/// After a G1+ official new import, publish a reviewable official-owned source.
///
/// Official import itself only writes catalog sources. Production Review
/// needs a course section + migration row with [recordedKind]=official.
class OfficialAnkiNewImportCutover {
  const OfficialAnkiNewImportCutover();

  static String importIdForSourceHash(String sourceHash) {
    final hex = sourceHash.toLowerCase().replaceAll(RegExp(r'[^0-9a-f]'), '');
    final take = hex.length >= 10 ? hex.substring(0, 10) : hex.padRight(10, '0');
    return 'g1$take';
  }

  Future<String> attach({
    required String packagePath,
    required String sourceId,
    required OfficialAnkiMigrationDao dao,
    required OfficialAnkiSourceDao sources,
    required OfficialAnkiPaths paths,
    required CourseDatabase course,
    required ICourseRepository repo,
    CourseProvider? courseProvider,
    AnkiImporter? importer,
    int? nowMillis,
  }) async {
    final source = sources.findById(sourceId);
    if (source == null || source.sourceHash.isEmpty) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.invalidArgument,
        messageKey: 'official_anki.source_missing',
        debugDetails: 'new import cutover needs catalog source',
      );
    }
    final importId = importIdForSourceHash(source.sourceHash);
    final now = nowMillis ?? DateTime.now().millisecondsSinceEpoch;
    final existing = dao.findByLegacyImport(
      profileId: paths.profileId,
      legacyImportId: importId,
    );
    if (existing?.recordedKind == 'official' &&
        existing?.officialSourceId == sourceId) {
      return importId;
    }

    final collection = await (importer ?? AnkiImporter()).parse(packagePath);
    final importDao = AnkiImportDao(course);
    final noteDao = AnkiNoteDao(course);
    await noteDao.deleteByImport(importId);
    await importDao.upsert(
      AnkiImportRecord(
        importId: importId,
        sourcePath: packagePath,
        sourceHash: source.sourceHash,
        importedAt: now ~/ 1000,
        deckCount: collection.decks.length,
        noteCount: collection.notes.length,
        cardCount: collection.cards.length,
        status: 'complete',
        sourceCardCount: collection.cards.length,
        storedCardCount: collection.cards.length,
        indexedCardCount: collection.cards.length,
      ),
    );
    // Batched inserts instead of per-row awaits: a multi-thousand-card deck
    // would otherwise issue one auto-committing round-trip per note/card.
    const batchChunk = 500;
    final noteRecords = [
      for (final note in collection.notes)
        AnkiNoteRecord(
          importId: importId,
          noteId: note.id,
          mid: note.mid,
          tags: note.tags,
          fields: note.fields,
          sfld: note.sortField,
          guid: note.guid,
          mod: note.mod,
        ),
    ];
    for (var i = 0; i < noteRecords.length; i += batchChunk) {
      await noteDao.upsertNoteBatch(
        noteRecords.skip(i).take(batchChunk).toList(),
      );
    }
    final cardRecords = [
      for (final card in collection.cards)
        AnkiCardMetaRecord(
          importId: importId,
          cardId: card.id,
          noteId: card.nid,
          ord: card.ord,
          did: card.did,
          wordId: 'anki-$importId-c${card.id}',
        ),
    ];
    for (var i = 0; i < cardRecords.length; i += batchChunk) {
      await noteDao.upsertCardMetaBatch(
        cardRecords.skip(i).take(batchChunk).toList(),
      );
    }
    await AnkiDeckAssembler().assemble(
      collection: collection,
      importId: importId,
      repo: repo,
      noteDao: noteDao,
      smartGrouping: false,
    );
    try {
      await courseProvider?.reloadCourse();
    } catch (_) {}
    final after = dao.findByLegacyImport(
      profileId: paths.profileId,
      legacyImportId: importId,
    );
    if (after == null) {
      dao.insertObservingOfficial(
        migrationId: newOfficialAnkiId('mig'),
        profileId: paths.profileId,
        legacyImportId: importId,
        officialSourceId: sourceId,
        sourceHash: source.sourceHash,
        nowMillis: now,
        cardCount: collection.cards.length,
      );
    } else if (after.recordedKind != 'official' ||
        after.officialSourceId != sourceId) {
      dao.setOfficialSourceAndRecordedKind(
        migrationId: after.migrationId,
        officialSourceId: sourceId,
        recordedKind: 'official',
        nowMillis: now,
      );
    }
    return importId;
  }

  Future<String> attachFromApp({
    required String packagePath,
    required String sourceId,
  }) async {
    CourseDatabase? course;
    try {
      course = CourseLoader.databaseOrNull() ??
          (getIt.isRegistered<CourseDatabase>()
              ? getIt<CourseDatabase>()
              : null);
    } catch (_) {
      course = null;
    }
    if (course == null || !getIt.isRegistered<ICourseRepository>()) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.capabilityMissing,
        messageKey: 'official_anki.course_unavailable',
      );
    }
    CourseProvider? courseProvider;
    try {
      courseProvider = getIt.isRegistered<CourseProvider>()
          ? getIt<CourseProvider>()
          : null;
    } catch (_) {
      courseProvider = null;
    }
    final support = await getApplicationSupportDirectory();
    final paths = OfficialAnkiPaths(
      profileId: 'profile-default-01',
      profileRoot: Directory('${support.path}/official_anki/default'),
    );
    final shared = OfficialAnkiCompositionRoot.readOnlyCatalog;
    final catalog = shared ?? OfficialAnkiDatabase.file(paths.catalogFile.path);
    try {
      return attach(
        packagePath: packagePath,
        sourceId: sourceId,
        dao: OfficialAnkiMigrationDao(catalog),
        sources: OfficialAnkiSourceDao(catalog),
        paths: paths,
        course: course,
        repo: getIt<ICourseRepository>(),
        courseProvider: courseProvider,
      );
    } finally {
      if (shared == null) {
        catalog.close();
      }
    }
  }
}
