import 'package:turna/application/anki_official/engine/official_anki_engine.dart';
import 'package:turna/application/anki_official/import/official_anki_import_state.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_file_log.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_lifecycle_models.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_maintenance.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/application/anki_official/v2/official_anki_v2_decision_store.dart';
import 'package:turna/application/anki_official/v2/official_anki_v2_view_rebuilder.dart';
import 'package:turna/data/course_database.dart';

/// B5：v2 删除轴 retiring 序列（D6/K6，Step 1 发现 #3 的结构性答复）。
///
/// ① `beginRetire`——账本**单事务**把 source 标 `retiring` 并入队
///   `v2_source_delete` job（用户视角即刻移除：视图重建只含 active）；
/// ② `runRetireJob`——worker 幂等执行引擎删除（op 32 按
///   `anki_source_cards` 所有权清单分批；缺卡无害）；
/// ③ 终删账本行（只删 v2 五表中有行的三张）+ 视图重建；
/// ④ 媒体 GC / VACUUM 走 maintenance job（沿用 doc 41 S5/S7）。
///
/// 任何一段强杀 → 重启 `runPending` 由 job 表驱动续跑，source 停在
/// `retiring` 且修复中心可见——**不产生无主且不可见的卡**。每段幂等。
class OfficialAnkiV2RetireService {
  OfficialAnkiV2RetireService({
    required this.catalog,
    required this.paths,
    required this.course,
    this.engine,
    this.nowMillis,
    this.deleteChunk = defaultDeleteChunk,
  });

  final OfficialAnkiDatabase catalog;
  final OfficialAnkiPaths paths;

  /// 可空：维护 runner 侧 course 可能缺席（极端装配态）。缺席时「即刻
  /// 不可见」退化为账本 state 过滤（读面按 active 供数据），视图行留到
  /// 下次有 course 的重建清掉。
  final CourseDatabase? course;
  final OfficialAnkiEngine? engine;
  final int Function()? nowMillis;

  /// Engine delete batch size (op 32). UI uninstall awaits the engine pass
  /// only when the source fits in one chunk; larger sources detach so the
  /// course tree can disappear without blocking on a 100k-card delete.
  static const int defaultDeleteChunk = 5000;

  final int deleteChunk;

  int get _now =>
      nowMillis?.call() ?? DateTime.now().millisecondsSinceEpoch;

  /// ① 序列入口：账本单事务（CAS active→retiring + 入队删除 job），
  /// 提交后定向删除该 source 的视图行——无需引擎、即刻不可见（K6
  /// 「用户视角即刻移除」）。返回 jobId。source 已 retiring 时幂等返回
  /// 既有 pending job。
  Future<String> beginRetire({required String sourceId}) async {
    final sources = OfficialAnkiSourceDao(catalog);
    final source = sources.findById(sourceId);
    if (source == null) {
      throw StateError('v2 retire: unknown source $sourceId');
    }
    final jobs = OfficialAnkiMaintenanceJobDao(catalog);
    final db = catalog.handle;
    db.execute('BEGIN');
    try {
      if (source.state != OfficialAnkiSourceState.retiring.wire) {
        sources.markRetiring(sourceId: sourceId, nowMillis: _now);
      }
      final jobId = jobs.enqueue(
        profileId: source.profileId,
        kind: OfficialAnkiMaintenanceKind.v2SourceDelete,
        sourceId: sourceId,
        nowMillis: _now,
      );
      db.execute('COMMIT');
      // 即刻不可见：视图定向删行（不等 job、不需引擎）。读面的目录
      // 过滤（catalog active）同时兜底。
      final courseDb = course;
      if (courseDb != null) {
        await courseDb.customStatement(
          'DELETE FROM anki_course_tree_view WHERE source_id = ?',
          [sourceId],
        );
      }
      officialAnkiV2Log('retire begin: $sourceId (job $jobId)');
      return jobId;
    } catch (error) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// ②③④ job 体：幂等执行，任一段可重入。供维护 runner 与修复中心
  /// 手动重试调用。返回 true 表示 source 已彻底终删。
  Future<bool> runRetireJob({required String sourceId}) async {
    final sources = OfficialAnkiSourceDao(catalog);
    final source = sources.findById(sourceId);
    if (source == null) {
      // ③ 已完成（重放）：收敛到视图重建即可。
      await _makeSourceInvisible(sourceId);
      return true;
    }
    if (source.state == OfficialAnkiSourceState.active.wire) {
      // job 先行、CAS 未落（异常时序）：按序列语义补标。
      await beginRetire(sourceId: sourceId);
    }

    // ② 引擎删除：按所有权清单分批；缺卡无害（removeCards 计数语义）。
    final resolved = engine;
    if (resolved != null) {
      var removed = 0;
      var owned = 0;
      var offset = 0;
      while (true) {
        final chunk = sources.listCardIdsPage(
          sourceId,
          offset: offset,
          limit: deleteChunk,
        );
        if (chunk.isEmpty) break;
        owned += chunk.length;
        removed += await resolved.deleteCards(chunk);
        offset += chunk.length;
        await Future<void>.delayed(Duration.zero);
      }
      officialAnkiV2Log(
        'retire engine delete: $sourceId '
        '($owned owned, $removed removed)',
      );
    } else {
      // 引擎不可达：job 留在表里等下次心跳重跑；source 停 retiring、
      // 修复中心可见（K6：绝不静默放弃，也绝不终删未删引擎的 source）。
      officialAnkiV2Log(
        'retire deferred (engine unavailable): $sourceId',
        warning: true,
      );
      return false;
    }

    // ③ 终删账本（v2 五表纪律）+ 清理配置区映射决策 + 视图重建。
    sources.deleteSourceV2(sourceId: sourceId);
    try {
      await OfficialAnkiV2DecisionStore(resolved).deleteImportMapping(sourceId);
    } catch (suppressed) {
      // 配置区清理 best-effort：键残留不影响正确性（source 已无账本行）。
      officialAnkiV2Log('retire mapping cleanup: $suppressed', warning: true);
    }
    await _makeSourceInvisible(sourceId);

    // ④ 字节回收走既有 maintenance job（doc 41 S5/S7 语义）。
    final jobs = OfficialAnkiMaintenanceJobDao(catalog);
    final profileId = source.profileId;
    jobs.enqueue(
      profileId: profileId,
      kind: OfficialAnkiMaintenanceKind.mediaGc,
      nowMillis: _now,
    );
    jobs.enqueue(
      profileId: profileId,
      kind: OfficialAnkiMaintenanceKind.compactCollection,
      nowMillis: _now,
    );
    jobs.enqueue(
      profileId: profileId,
      kind: OfficialAnkiMaintenanceKind.compactCatalog,
      nowMillis: _now,
    );
    officialAnkiV2Log('retire complete: $sourceId');
    return true;
  }

  /// retiring 的 source 必须立刻从课程树不可见（K6）。有引擎 → 整体重建
  /// （active 过滤天然排除 retiring）；无引擎 → 定向删除该 source 的视图
  /// 行，保底「即刻移除」。
  Future<void> _makeSourceInvisible(String sourceId) async {
    final resolved = engine;
    final courseDb = course;
    if (resolved == null || courseDb == null) {
      if (courseDb != null) {
        await courseDb.customStatement(
          'DELETE FROM anki_course_tree_view WHERE source_id = ?',
          [sourceId],
        );
      }
      return;
    }
    await OfficialAnkiV2ViewRebuilder(
      engine: resolved,
      catalog: catalog,
      course: courseDb,
      profileId: paths.profileId,
      nowMillis: nowMillis,
    ).rebuild();
  }
}
