import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_session.dart';

import 'package:turna/application/anki_official/migration/official_anki_engine_kind.dart';
import 'package:turna/application/anki_official/migration/official_anki_migration_dao.dart';
import 'package:turna/application/anki_official/migration/official_anki_production_router.dart';
import 'package:turna/application/anki_official/migration/official_anki_review_gate_decision.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';

import 'package:turna/application/anki_official/official_anki_ids.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/views/anki_official/official_anki_reviewer_error_view.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/courses/course_loader.dart';
import 'package:turna/data/anki_import_dao.dart';

/// Capability gate for official-routed sources. Fail-closed if cutover says
/// official but the collection is not ready. Never opens a different-semantics
/// review page — production always continues on the shared session host.
class AnkiOfficialReviewGate {
  const AnkiOfficialReviewGate({
    this.catalogExists,
    this.routerOverride,
    this.catalogOverride,
    this.navigatorOverride,
    this.ensureCollectionReadyOverride,
    this.routerCanOpenOfficialReviewOverride,
  });

  final bool Function(OfficialAnkiPaths paths)? catalogExists;
  final OfficialAnkiProductionRouter? routerOverride;
  final OfficialAnkiDatabase Function(String path)? catalogOverride;
  final Future<void> Function(
    BuildContext context,
    OfficialAnkiProductionRouter router,
    OfficialAnkiPaths paths,
    OfficialAnkiSession session,
    OfficialAnkiRoutedSource target,
  )? navigatorOverride;
  final Future<bool> Function(OfficialAnkiSession session)?
      ensureCollectionReadyOverride;
  final bool Function(OfficialAnkiProductionRouter router)?
      routerCanOpenOfficialReviewOverride;

  Future<bool> openInsteadOfLegacy(
    BuildContext context, {
    required String? sectionId,
    bool? cutoverEnabledOverride,
  }) async {
    final importId =
        LegacyAnkiIdentifiers.importIdFromSectionId(sectionId ?? '');
    if (importId.isEmpty) return false;
    final cutoverEnabled =
        cutoverEnabledOverride ?? LegacyAnkiMigrationFlags.cutoverEnabled;

    final support = await getApplicationSupportDirectory();
    if (!context.mounted) return false;
    final router = routerOverride ?? const OfficialAnkiProductionRouter();
    final paths = router.pathsForDefaultProfile(support);
    final catalogPresent = catalogExists != null
        ? catalogExists!(paths)
        : paths.catalogFile.existsSync();
    if (!catalogPresent) {
      return _failClosedIfOfficialWithoutCatalog(
        context,
        importId,
        cutoverEnabledOverride: cutoverEnabled,
      );
    }

    final catalog = catalogOverride != null
        ? catalogOverride!(paths.catalogFile.path)
        : OfficialAnkiDatabase.file(paths.catalogFile.path);
    try {
      final dao = OfficialAnkiMigrationDao(catalog);
      final sources = OfficialAnkiSourceDao(catalog);
      final sourceHash = await _sourceHashForImport(importId);
      if (!context.mounted) return true;
      if (sourceHash != null && sourceHash.isNotEmpty) {
        router.adoptExistingIfCatalogMatches(
          dao: dao,
          sources: sources,
          importId: importId,
          sourceHash: sourceHash,
        );
      }
      final routed = router.engineForImport(
        importId: importId,
        dao: dao,
        sources: sources,
        cutoverEnabled: cutoverEnabled,
        sourceHash: sourceHash,
      );
      final target = router.reviewTargetForImport(
        dao: dao,
        sources: sources,
        importId: importId,
        cutoverEnabled: cutoverEnabled,
        sourceHash: sourceHash,
      );
      final canOpen = routerCanOpenOfficialReviewOverride != null
          ? routerCanOpenOfficialReviewOverride!(router)
          : router.canOpenOfficialReview();
      final decision = decideOfficialReviewGate(
        cutoverEnabled: cutoverEnabled,
        routedEngine: routed,
        catalogPresent: true,
        hasReviewTarget: target != null,
        canOpenOfficialReview: canOpen,
      );
      if (decision == OfficialAnkiReviewGateDecision.useLegacy) {
        return false;
      }
      if (decision == OfficialAnkiReviewGateDecision.failClosed) {
        _snackFailClosed(context);
        return true;
      }
      await OfficialAnkiCompositionRoot.requireImporter(supportDir: support);
      if (!context.mounted) return true;
      final session = OfficialAnkiCompositionRoot.session;
      if (session is! OfficialAnkiSession) {
        _snackFailClosed(context);
        return true;
      }
      final opened = ensureCollectionReadyOverride != null
          ? await ensureCollectionReadyOverride!(session)
          : await _ensureCollectionReady(session);
      if (!context.mounted) return true;
      if (!opened) {
        _snackFailClosed(context);
        return true;
      }
      if (navigatorOverride != null) {
        await navigatorOverride!(
          context,
          router,
          paths,
          session,
          target!,
        );
        // Tests may still intercept; production stays on the shared session.
        return false;
      }
      // Official-capable: stay on the shared AnkiReviewSessionRoute host.
      return false;
    } finally {
      catalog.close();
    }
  }

  bool _failClosedIfOfficialWithoutCatalog(
    BuildContext context,
    String importId, {
    bool? cutoverEnabledOverride,
  }) {
    final routed = const OfficialAnkiProductionRouter().engineForImport(
      importId: importId,
      cutoverEnabled: cutoverEnabledOverride,
    );
    if (routed != AnkiEngineKind.official) return false;
    _snackFailClosed(context);
    return true;
  }

  Future<String?> _sourceHashForImport(String importId) async {
    try {
      final course = CourseLoader.databaseOrNull();
      if (course == null) return null;
      return (await AnkiImportDao(course).getById(importId))?.sourceHash;
    } catch (suppressed) {
      debugPrint('[AnkiOfficialReviewGate] suppressed error: $suppressed');
      return null;
    }
  }

  Future<bool> _ensureCollectionReady(OfficialAnkiSession session) async {
    for (var attempt = 0; attempt < 6; attempt++) {
      try {
        await session.ensureCollectionOpen();
        return true;
      } on OfficialAnkiException catch (error) {
        if (error.code == OfficialAnkiErrorCode.collectionAlreadyOpen) {
          return true;
        }
        if (error.code != OfficialAnkiErrorCode.collectionLocked) {
          return false;
        }
        await Future<void>.delayed(Duration(milliseconds: 80 * (attempt + 1)));
      }
    }
    return false;
  }

  void _snackFailClosed(BuildContext context) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          OfficialAnkiReviewerErrorView.localize(
              'official_anki.review_fail_closed'),
        ),
      ),
    );
  }
}
