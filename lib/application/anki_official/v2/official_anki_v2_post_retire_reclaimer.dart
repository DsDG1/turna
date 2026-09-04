import 'package:flutter/foundation.dart' show debugPrint;

import 'package:turna/application/anki_official/engine/official_anki_engine.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_file_log.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_maintenance.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/application/maintenance/official_anki_ghost_purge_service.dart';
import 'package:turna/data/course_database.dart';

/// B5 收尾（Step 1 发现 #3 的补漏）：retire 序列第④步只把字节回收
/// *入队*（media_gc / compact_collection / compact_catalog），消费时机
/// 原本只剩下次启动——用户视角就是「删了但没删」。本回收器在引擎删除
/// 完成后立即接管：
///
/// ① 用 `forceCompact: true` drain 维护队列（绕过 16MB/20% 阈值——用户
///   刚删了数据，空间就该拿回来；VACUUM/媒体 GC 全部走引擎）；
/// ② 若账本已空（最后一个 source 也删了），执行 ghost purge——
///   backups/checkpoints/WAL 这些任何 job 都不碰的目录，等价于自动按下
///   存储页的「强制清空残留」（服务自身 fail-closed 复验 attempts）。
///
/// 全程 best-effort：任何一段失败只记日志，不影响已成功的 retire；
/// 未消费的 job 留队，由下次启动的 drain 收敛。
class OfficialAnkiV2PostRetireReclaimer {
  const OfficialAnkiV2PostRetireReclaimer({
    required this.catalog,
    required this.paths,
    required this.engine,
    this.course,
    this.leaseOwnerToken,
  });

  final OfficialAnkiDatabase catalog;
  final OfficialAnkiPaths paths;

  /// 引擎缺席时直接返回：无引擎的 drain 只会把 media_gc 等抛错留队，
  /// 白耗 attempt_count——job 留给启动恢复（引擎在场）的那次运行。
  final OfficialAnkiEngine? engine;
  final CourseDatabase? course;

  /// 调用方已持有维护 lease 时透传（启动恢复路径），使 drain 能在同一
  /// 把 lease 下运行而不是被自己的 lease 拒之门外。
  final String? leaseOwnerToken;

  Future<void> run() async {
    final engine = this.engine;
    if (engine == null) return;
    var drained = 0;
    try {
      drained = await OfficialAnkiMaintenanceRunner(
        catalog: catalog,
        paths: paths,
        engine: engine,
        course: course,
        forceCompact: true,
      ).runPending(
        profileId: paths.profileId,
        leaseOwnerToken: leaseOwnerToken,
      );
    } catch (error) {
      debugPrint('[PostRetireReclaimer] drain failed: $error');
    }
    try {
      // 账本空才动 ghost 文件：retire 被打断（source 仍在 retiring）时
      // listSources 非空，自然不触发——无需在此复验失败态。
      if (OfficialAnkiSourceDao(catalog).listSources(paths.profileId).isEmpty) {
        final purge = await const OfficialAnkiGhostPurgeService()
            .run(catalog: catalog, paths: paths, engine: engine);
        officialAnkiV2Log(
          'post-retire reclaim: drained $drained job(s), '
          'ghost purge ok=${purge.ok} '
          '(${purge.errorCode ?? '${purge.deletedEntries} entries'})',
          warning: !purge.ok && purge.errorCode != 'sources_present',
        );
      }
    } catch (error) {
      debugPrint('[PostRetireReclaimer] ghost purge failed: $error');
    }
  }
}
