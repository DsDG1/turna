// Dart imports:
import 'dart:async';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/application/anki_official/introduction/card_introduction_eligibility.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/application/anki_official/v2/official_anki_v2_post_retire_reclaimer.dart';
import 'package:turna/application/anki_official/v2/official_anki_v2_retire_service.dart';
import 'package:turna/core/logger.dart';
import 'package:turna/domain/repositories/i_anki_import_store.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/repositories/i_course_repository.dart';
import 'package:turna/service/locator.dart';

/// Centralized Anki deck management: uninstall, incremental update detection,
/// review limits, and SRS key partitioning.
///
/// Phase 3 features:
/// - Deck uninstall (by tag batch delete + media cleanup)
/// - Incremental update detection (source_hash comparison)
/// - Review limits (daily new/review caps)
/// - SRS state partitioning (per-import prefs keys)
@lazySingleton
class AnkiDeckManager {
  final ICourseRepository _repo;
  final IAnkiImportStore _importDao;
  final AppPrefs _appPrefs;

  AnkiDeckManager({
    required ICourseRepository repo,
    required IAnkiImportStore importDao,
    required AppPrefs appPrefs,
  })  : _repo = repo,
        _importDao = importDao,
        _appPrefs = appPrefs;

  // ─── Review Limits ──────────────────────────────────────────────────

  /// Default daily new card limit.
  static const int defaultDailyNewLimit = 20;

  /// Default daily review card limit.
  static const int defaultDailyReviewLimit = 200;

  static const String _dailyNewLimitKey = 'anki.dailyNewLimit';
  static const String _dailyReviewLimitKey = 'anki.dailyReviewLimit';

  int get dailyNewLimit {
    return _appPrefs.preferences
        .getInt(_dailyNewLimitKey, defaultValue: defaultDailyNewLimit)
        .getValue();
  }

  int get dailyReviewLimit {
    return _appPrefs.preferences
        .getInt(_dailyReviewLimitKey, defaultValue: defaultDailyReviewLimit)
        .getValue();
  }

  Future<void> setDailyNewLimit(int limit) async {
    await _appPrefs.preferences.setInt(_dailyNewLimitKey, limit);
  }

  Future<void> setDailyReviewLimit(int limit) async {
    await _appPrefs.preferences.setInt(_dailyReviewLimitKey, limit);
  }

  // ─── Daily Challenge Toggle ─────────────────────────────────────────

  static const String _dailyChallengeAnkiKey =
      'anki.dailyChallengeIncludesAnki';

  /// Whether Anki-imported cards may appear in the daily challenge pool.
  /// Defaults to `true`; the settings page exposes a toggle to turn this off.
  bool get dailyChallengeIncludesAnki {
    return _appPrefs.preferences
        .getBool(_dailyChallengeAnkiKey, defaultValue: true)
        .getValue();
  }

  Future<void> setDailyChallengeIncludesAnki(bool value) async {
    await _appPrefs.preferences.setBool(_dailyChallengeAnkiKey, value);
  }

  /// Restore Anki learning prefs to factory defaults (new/review limits +
  /// daily-challenge inclusion). Does not uninstall decks or clear SRS.
  Future<void> resetLearningDefaults() async {
    await setDailyNewLimit(defaultDailyNewLimit);
    await setDailyReviewLimit(defaultDailyReviewLimit);
    await setDailyChallengeIncludesAnki(true);
  }

  // ─── Deck Uninstall ─────────────────────────────────────────────────

  /// Route an uninstall through the resolved owner. CourseDatabase authority
  /// identifies Official ids; the course-tree prefix is only a recovery
  /// hint. Ids that resolve to neither are already gone (or predate the
  /// Official cutover — the Legacy cleanup path is retired, plan P1) and
  /// report as removed. Returns false when Official cleanup is safely
  /// deferred for a later retry.
  Future<bool> uninstall(String importId) async {
    final owner = await _resolveDeletionOwner(importId);
    final officialSourceId = owner.officialSourceId;
    if (officialSourceId != null) {
      return _uninstallV2Source(officialSourceId);
    }
    return true;
  }

  CourseDatabase? _courseDatabase() {
    try {
      return getIt.isRegistered<CourseDatabase>()
          ? getIt<CourseDatabase>()
          : null;
    } catch (_) {
      return null;
    }
  }

  /// v2 retiring 序列入口（B5）：①账本单事务即刻移除（含视图定向删行）
  /// → ②③④同步推进一遍（引擎在场时一次走完）；引擎缺席时 job 留队，
  /// 下次启动 `runPending` 续跑——两种情况都返回 true（用户视角已移除，
  /// 与 v1「deferred 返回 false」的差别在于 v2 的收敛由 job 表保证）。
  ///
  /// [leaseOwnerToken] 由启动恢复路径透传，使删除后的字节回收 drain 能
  /// 复用已持有的维护 lease；UI 删除不传，drain 自行获取。
  Future<bool> _uninstallV2Source(
    String sourceId, {
    String? leaseOwnerToken,
  }) async {
    await OfficialAnkiCompositionRoot.initializeReadOnlyLocator();
    final catalog = OfficialAnkiCompositionRoot.readOnlyCatalog;
    final paths = OfficialAnkiCompositionRoot.locatorPaths;
    if (catalog == null || paths == null) {
      return false;
    }
    // 账本行已不存在 = 该源此前已完成终删（retire ③ 跑完、账本五表已
    // 清）。当次调用无事可做，按「已移除」汇报——否则课程列表已隐藏
    // 该源、消息却说移除未完成，两态矛盾。
    final sources = OfficialAnkiSourceDao(catalog);
    if (sources.findById(sourceId) == null) {
      return true;
    }
    // B5 契约：引擎缺席（含解析抛错）不得阻塞 ①账本单事务（job 留队
    // 续跑）。用户可见的「移除失败」只剩两处来源：locator 未就绪的
    // 早退 return false，或 beginRetire 自身抛错（DB）。
    OfficialAnkiEngine? engine;
    try {
      engine = await _resolveOfficialEngine();
    } catch (error) {
      logger.w('[AnkiDeckManager] v2 retire engine absent: $error');
    }
    final service = OfficialAnkiV2RetireService(
      catalog: catalog,
      paths: paths,
      course: _courseDatabase(),
      engine: engine,
    );
    await service.beginRetire(sourceId: sourceId);
    Future<void> enginePass() async {
      try {
        await service.runRetireJob(sourceId: sourceId);
      } catch (error) {
        logger.w('[AnkiDeckManager] v2 retire deferred: $error');
      }
    }

    // 字节回收必须排在引擎删除之后（媒体 GC 依赖卡已删完才能识别无主
    // 文件），所以回收器链在 enginePass 完成之处，而不是删除当刻。
    Future<void> reclaimPass() => OfficialAnkiV2PostRetireReclaimer(
          catalog: catalog,
          paths: paths,
          engine: engine,
          course: _courseDatabase(),
          leaseOwnerToken: leaseOwnerToken,
        ).run();

    // 小源：同步走完引擎删除（F4 测试与日常小包）。大源（含 10 万卡
    // 夹具）：beginRetire 已让课程树即刻不可见，引擎分批删卡不挡 UI，
    // 否则确认删除会卡死，表现就是「删不掉」。两种体量都不在 UI 等待
    // 字节回收——drain 分离执行，失败留队由下次启动收敛。计数读失败
    // 时按大源处理（后台续跑），绝不让 post-commit 的读取异常把已提交
    // 的移除报成「未完成」。
    final owned = _retireCardCount(sources, sourceId);
    if (owned <= OfficialAnkiV2RetireService.defaultDeleteChunk) {
      await enginePass();
      unawaited(reclaimPass());
    } else {
      logger.d(
        '[AnkiDeckManager] v2 retire engine pass detached: '
        '$sourceId ($owned cards)',
      );
      unawaited(enginePass().then((_) => reclaimPass()));
    }
    return true;
  }

  /// 体量探测（决定引擎删除走同步还是后台）。账本已提交 retiring 后
  /// 此读仍可能瞬时失败（busy/locked）；失败按「体量未知=大源」处理。
  int _retireCardCount(OfficialAnkiSourceDao sources, String sourceId) {
    try {
      return sources.cardCount(sourceId);
    } catch (error) {
      logger.w('[AnkiDeckManager] v2 retire card count failed: $error');
      return OfficialAnkiV2RetireService.defaultDeleteChunk + 1;
    }
  }

  /// Resolve which persisted owner an uninstall id belongs to.
  Future<AnkiDeletionOwner> _resolveDeletionOwner(String importId) async {
    try {
      await OfficialAnkiCompositionRoot.initializeReadOnlyLocator();
      final ledgerCatalog = OfficialAnkiCompositionRoot.readOnlyCatalog;
      if (ledgerCatalog != null &&
          OfficialAnkiSourceDao(ledgerCatalog).findById(importId) != null) {
        return AnkiDeletionOwner(
          importId: importId,
          officialSourceId: importId,
        );
      }
    } catch (e) {
      logger.w(
        '[AnkiDeckManager] ledger owner lookup failed for $importId: $e',
      );
    }
    if (await _isOfficialSource(importId)) {
      return AnkiDeletionOwner(importId: importId, officialSourceId: importId);
    }
    return AnkiDeletionOwner(importId: importId);
  }

  /// Per-deck daily new-card limit override, or `null` for the global limit.
  Future<int?> dailyNewLimitFor(String importId) =>
      _importDao.dailyNewLimitFor(importId);

  /// Per-deck daily review limit override, or `null` for the global limit.
  Future<int?> dailyReviewLimitFor(String importId) =>
      _importDao.dailyReviewLimitFor(importId);

  /// Persist per-deck daily limit overrides (`null` clears the override).
  Future<void> setDailyLimits(
    String importId, {
    int? newLimit,
    int? reviewLimit,
  }) =>
      _importDao.setDailyLimits(
        importId,
        newLimit: newLimit,
        reviewLimit: reviewLimit,
      );

  /// Official sources own `official-anki-<sourceId>-…` tree ids.
  Future<bool> _isOfficialSource(String importId) async {
    final prefix = 'official-anki-$importId-';
    final sections = await _repo.sectionShells();
    return sections.any((section) => section.id.startsWith(prefix));
  }

  /// Hard-uninstall an official source. Unlike the historical soft uninstall,
  /// the official Anki collection also loses the source's notes and cards —
  /// deleting a deck deletes everything. The projection, vocabulary rows
  /// (P5F-33 channel), unification bookkeeping, catalog rows, review history,
  /// and mistake-log entries are dropped in the same pass.
  ///
  /// The collection delete is a structured step, not best-effort: when the
  /// engine is unavailable or `deleteNotes` fails, the source is marked
  /// `pending_cleanup`, its catalog/migration rows are kept (they are the
  /// only way to find those notes again), and `false` is returned so the
  /// caller knows the removal is deferred. Retrying [uninstall] — or
  /// [retryPendingOfficialCleanups] on the next start — resumes the saga.
  /// Hard-uninstall an official source using the v2 retire service.
  Future<bool> uninstallOfficialSource(
    String sourceId, {
    String? leaseOwnerToken,
  }) =>
      _uninstallV2Source(sourceId, leaseOwnerToken: leaseOwnerToken);

  /// Retry every `pending_cleanup` or `retiring` source whose cleanup was interrupted.
  Future<int> retryPendingOfficialCleanups({String? leaseOwnerToken}) async {
    final pendingSourceIds = <String>{};
    try {
      await OfficialAnkiCompositionRoot.initializeReadOnlyLocator();
      final catalog = OfficialAnkiCompositionRoot.readOnlyCatalog;
      if (catalog != null) {
        pendingSourceIds.addAll(
          OfficialAnkiSourceDao(catalog)
              .listSources(CardIntroductionEligibility.defaultProfileId)
              .where((source) =>
                  source.state == 'pending_cleanup' ||
                  source.state == 'retiring')
              .map((source) => source.sourceId),
        );
      }
    } catch (e) {
      logger.w('[AnkiDeckManager] pending catalog lookup failed: $e');
    }

    var resumed = 0;
    for (final sourceId in pendingSourceIds) {
      try {
        if (await uninstallOfficialSource(
          sourceId,
          leaseOwnerToken: leaseOwnerToken,
        )) {
          resumed++;
        }
      } catch (e) {
        logger.w(
          '[AnkiDeckManager] pending cleanup retry failed for $sourceId: $e',
        );
      }
    }
    return resumed;
  }

  /// Engine for collection writes: the live session's engine when one is
  /// open, otherwise open (or fall back to) the shared importer session.
  /// Null when official anki is unavailable (flags off / worker failed).
  Future<OfficialAnkiEngine?> _resolveOfficialEngine() async {
    final existing = OfficialAnkiCompositionRoot.engine;
    if (existing != null) return existing;
    await OfficialAnkiCompositionRoot.requireImporter();
    return OfficialAnkiCompositionRoot.engine;
  }
}

/// The persisted owner an uninstall id resolves to. [officialSourceId] is
/// null for ids that predate the Official cutover (no-op uninstall).
class AnkiDeletionOwner {
  const AnkiDeletionOwner({required this.importId, this.officialSourceId});

  final String importId;
  final String? officialSourceId;
}
