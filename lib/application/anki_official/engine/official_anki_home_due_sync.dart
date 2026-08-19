import 'package:path_provider/path_provider.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_home_due.dart';
import 'package:turna/application/anki_official/engine/official_anki_session.dart';
import 'package:turna/application/anki_official/migration/official_anki_engine_kind.dart';
import 'package:turna/application/anki_official/migration/official_anki_migration_dao.dart';
import 'package:turna/application/anki_official/migration/official_anki_production_router.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';

/// Refreshes official-routed import ids (exclusion) and optional deck counts.
/// Safe to call from Play Hub, Profile, and Anki review hub.
class OfficialAnkiHomeDueSync {
  const OfficialAnkiHomeDueSync();

  static Future<void>? _inFlight;

  Future<void> refresh() async {
    final existing = _inFlight;
    if (existing != null) {
      await existing;
      return;
    }
    final run = _refreshOnce();
    _inFlight = run;
    try {
      await run;
    } finally {
      if (identical(_inFlight, run)) _inFlight = null;
    }
  }

  Future<void> _refreshOnce() async {
    if (!LegacyAnkiMigrationFlags.cutoverEnabled) {
      OfficialAnkiHomeDue.officialImportIds = {};
      OfficialAnkiHomeDue.officialDue = 0;
      OfficialAnkiHomeDue.officialDueByImport = {};
      OfficialAnkiHomeDue.officialDueUnavailable = false;
      return;
    }
    final savedDue = OfficialAnkiHomeDue.officialDue;
    final savedByImport = Map<String, int>.from(
      OfficialAnkiHomeDue.officialDueByImport,
    );
    final savedIds = Set<String>.from(OfficialAnkiHomeDue.officialImportIds);
    final savedUnavailable = OfficialAnkiHomeDue.officialDueUnavailable;
    try {
      final support = await getApplicationSupportDirectory();
      final router = const OfficialAnkiProductionRouter();
      final paths = router.pathsForDefaultProfile(support);
      if (!paths.catalogFile.existsSync()) {
        OfficialAnkiHomeDue.officialImportIds = {};
        OfficialAnkiHomeDue.officialDue = 0;
        OfficialAnkiHomeDue.officialDueByImport = {};
        OfficialAnkiHomeDue.officialDueUnavailable = false;
        return;
      }
      final catalog = OfficialAnkiDatabase.file(paths.catalogFile.path);
      try {
        final dao = OfficialAnkiMigrationDao(catalog);
        OfficialAnkiHomeDue.officialImportIds = router.officialImportIds(
          dao: dao,
        );
        if (!OfficialAnkiFeatureFlags.current.allowsOfficialScheduler) {
          OfficialAnkiHomeDue.officialDue = 0;
          OfficialAnkiHomeDue.officialDueByImport = {};
          OfficialAnkiHomeDue.officialDueUnavailable = false;
          return;
        }
        await OfficialAnkiCompositionRoot.requireImporter(supportDir: support);
        final session = OfficialAnkiCompositionRoot.session;
        if (session is! OfficialAnkiSession) {
          OfficialAnkiHomeDue.officialDueUnavailable = true;
          return;
        }
        var opened = false;
        OfficialAnkiException? lastOpenError;
        for (var attempt = 0; attempt < 6; attempt++) {
          try {
            await session.ensureCollectionOpen();
            opened = true;
            break;
          } on OfficialAnkiException catch (error) {
            lastOpenError = error;
            if (error.code == OfficialAnkiErrorCode.collectionAlreadyOpen) {
              opened = true;
              break;
            }
            if (error.code != OfficialAnkiErrorCode.collectionLocked) {
              rethrow;
            }
            await Future<void>.delayed(
              Duration(milliseconds: 80 * (attempt + 1)),
            );
          }
        }
        if (!opened) {
          if (lastOpenError != null) throw lastOpenError;
          OfficialAnkiHomeDue.officialImportIds = savedIds;
          OfficialAnkiHomeDue.officialDue = savedDue;
          OfficialAnkiHomeDue.officialDueByImport = savedByImport;
          OfficialAnkiHomeDue.officialDueUnavailable = true;
          return;
        }
        await router.refreshHomeDueFromQueue(
          dao: dao,
          sources: OfficialAnkiSourceDao(catalog),
          getReviewQueue: () => session.getReviewQueue(fetchLimit: 50),
        );
      } finally {
        catalog.close();
      }
    } catch (error) {
      final isLock = error is OfficialAnkiException &&
          error.code == OfficialAnkiErrorCode.collectionLocked;
      if (isLock) {
        OfficialAnkiHomeDue.officialImportIds = savedIds;
        OfficialAnkiHomeDue.officialDue = savedDue;
        OfficialAnkiHomeDue.officialDueByImport = savedByImport;
        OfficialAnkiHomeDue.officialDueUnavailable = true;
        return;
      }
      final hasPriorSuccess = savedIds.isNotEmpty || savedDue != 0 || savedUnavailable;
      if (hasPriorSuccess) {
        OfficialAnkiHomeDue.officialImportIds = savedIds;
        OfficialAnkiHomeDue.officialDue = savedDue;
        OfficialAnkiHomeDue.officialDueByImport = savedByImport;
        OfficialAnkiHomeDue.officialDueUnavailable = true;
        return;
      }
      OfficialAnkiHomeDue.officialDueUnavailable = true;
    }
  }
}
