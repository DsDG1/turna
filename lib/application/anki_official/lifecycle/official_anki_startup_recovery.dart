import 'package:turna/application/anki_official/anki_deck_manager.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_file_log.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_lifecycle_models.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_maintenance.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_repair_executor.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/storage/official_anki_import_attempt_dao.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/application/anki_official/v2/official_anki_v2_unowned_card_reclaimer.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/di/injection.dart';

/// Single Official startup entry (doc 42 P3): lease → repair/census →
/// re-anchor → pending cleanup. Achievements and orphan media stay separate.
class OfficialAnkiStartupRecovery {
  const OfficialAnkiStartupRecovery({this.ensureEngine});

  static const ownerToken = 'startup-recovery';

  /// Opens the engine session when startup work exists. Production default
  /// is [OfficialAnkiCompositionRoot.requireImporter] — the same road the
  /// home due sync takes. Injectable for tests.
  final Future<void> Function()? ensureEngine;

  Future<void> run() async {
    final catalog = OfficialAnkiCompositionRoot.readOnlyCatalog;
    if (catalog == null) return;
    final paths = OfficialAnkiCompositionRoot.locatorPaths;
    final profileId = paths?.profileId ?? 'profile-default-01';
    final lease = OfficialAnkiMaintenanceLease(catalog);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!lease.tryAcquire(
      profileId: profileId,
      ownerToken: ownerToken,
      operationKind: 'startup_recovery',
      nowMillis: now,
    )) {
      return;
    }
    try {
      var engine = OfficialAnkiCompositionRoot.engine;
      // Step1 task C: cold start only opened the read-only catalog, so the
      // engine is null here and the repair executor below (census, import
      // recovery, pending cleanup, maintenance runPending) used to be
      // skipped entirely. Open the engine only when the catalog says there
      // is work — users without anki pay nothing at startup.
      if (engine == null && paths != null) {
        final hasMaintenanceWork =
            OfficialAnkiMaintenanceJobDao(catalog).pending(profileId: profileId)
                .isNotEmpty ||
            OfficialAnkiSourceDao(catalog)
                .listSources(profileId)
                .any((row) => row.state == 'pending_cleanup') ||
            OfficialAnkiSourceDao(catalog)
                .listV2Sources(profileId)
                .isNotEmpty ||
            OfficialAnkiImportAttemptDao(catalog).unfinished().isNotEmpty;
        if (hasMaintenanceWork) {
          try {
            await (ensureEngine ??
                OfficialAnkiCompositionRoot.requireImporter)();
            engine = OfficialAnkiCompositionRoot.engine;
          } catch (error) {
            officialAnkiStartupLog('startup engine open failed: $error', warning: true);
          }
        }
      }
      // K3（step4.md B3）：v2 有活跃 source → 入队整视图重建（无状态、
      // 幂等）。engine null（无 v2 数据）时自然跳过。
      if (engine != null && paths != null) {
        try {
          final v2Sources = OfficialAnkiSourceDao(catalog)
              .listV2Sources(profileId, states: {'active'});
          if (v2Sources.isNotEmpty) {
            OfficialAnkiMaintenanceJobDao(catalog).enqueue(
              profileId: profileId,
              kind: OfficialAnkiMaintenanceKind.v2ViewRebuild,
              nowMillis: DateTime.now().millisecondsSinceEpoch,
            );
          }
        } catch (error) {
          officialAnkiStartupLog('v2 view rebuild enqueue: $error', warning: true);
        }
      }
      if (engine != null && paths != null) {
        await const OfficialAnkiRepairExecutor().run(
          course: getIt<CourseDatabase>(),
          catalog: catalog,
          engine: engine,
          sources: OfficialAnkiSourceDao(catalog),
          paths: paths,
          profileId: profileId,
          maintenanceLeaseOwnerToken: ownerToken,
        );
        // Ledger 已空、但 collection 里仍有无主卡（用户放弃过中断导入，
        // 或旧包只删了账本）：差集回收。有未完成 attempt 时不跑，以免
        // 吃掉 receipt_committed 尚未写完的所有权行。
        if (OfficialAnkiImportAttemptDao(catalog).unfinished().isEmpty) {
          try {
            await OfficialAnkiV2UnownedCardReclaimer(
              catalog: catalog,
              paths: paths,
              engine: engine,
            ).purge();
          } catch (error) {
            officialAnkiStartupLog('unowned purge: $error', warning: true);
          }
        }
      }
      try {
        final resumed =
            await getIt<AnkiDeckManager>().retryPendingOfficialCleanups();
        if (resumed > 0) {
          officialAnkiStartupLog('resumed $resumed pending cleanups');
        }
      } catch (e) {
        officialAnkiStartupLog('pending cleanup retry skipped: $e', warning: true);
      }
    } finally {
      lease.release(profileId: profileId, ownerToken: ownerToken);
    }
  }
}
