import 'dart:io';

import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_import_attempt_dao.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';

/// B4（K1）：v2 待完成导入分级。
///
/// staging 目录即证据（一次性资产，继承 ADR 0042）：重启 census 发现未
/// 完成 v2 导入 → 按 staging 完整性分流——`resumable`（collection 完整，
/// 直接进 preview）或 `rebuildStaging`（staging 损坏/缺失，重建后再进）。
/// live 零写入不变式不变（staging-first）。纯读模型，不改 v1 行为
/// （v1 的 `official_anki_pending_imports.dart` 原样保留）。
enum OfficialAnkiV2PendingImportVerdict { resumable, rebuildStaging, gone }

class OfficialAnkiV2PendingImport {
  const OfficialAnkiV2PendingImport({
    required this.sourceId,
    required this.attemptId,
    required this.displayName,
    required this.phase,
    required this.verdict,
    this.stagingPath,
    this.cardCount = 0,
  });

  final String sourceId;
  final String attemptId;
  final String displayName;
  final String phase;
  final OfficialAnkiV2PendingImportVerdict verdict;
  final String? stagingPath;
  final int cardCount;
}

abstract final class OfficialAnkiV2PendingImports {
  /// 未完成的 v2 导入（chain='v2'，phase 非 terminal）。
  static List<OfficialAnkiV2PendingImport> list(OfficialAnkiDatabase catalog) {
    final sources = OfficialAnkiSourceDao(catalog);
    final attempts = OfficialAnkiImportAttemptDao(catalog);
    final v2Sources = {
      for (final source in sources.listV2Sources(
        _profileIdOf(catalog),
      ))
        source.sourceId: source,
    };
    if (v2Sources.isEmpty) return const [];
    final out = <OfficialAnkiV2PendingImport>[];
    for (final attempt in attempts.unfinished()) {
      final source = v2Sources[attempt.sourceId];
      if (source == null) continue;
      out.add(OfficialAnkiV2PendingImport(
        sourceId: attempt.sourceId,
        attemptId: attempt.attemptId,
        displayName: source.displayName,
        phase: attempt.phase.isEmpty ? attempt.state : attempt.phase,
        verdict: _verdictOf(attempt),
        stagingPath: attempt.stagingPath,
        cardCount: sources.cardCount(attempt.sourceId),
      ));
    }
    return out;
  }

  /// K1 分级：staging 目录在且 collection.anki2 存在 → resumable；
  /// 目录在但库缺/损坏标记缺失 → rebuildStaging；目录没了 → gone
  /// （重启向用户提供重新选择包的入口，账本行由 census 按意图清理）。
  static OfficialAnkiV2PendingImportVerdict _verdictOf(
    OfficialAnkiAttemptRow attempt,
  ) {
    final stagingPath = attempt.stagingPath;
    if (stagingPath == null || stagingPath.isEmpty) {
      return OfficialAnkiV2PendingImportVerdict.rebuildStaging;
    }
    final root = Directory(stagingPath);
    if (!root.existsSync()) {
      return OfficialAnkiV2PendingImportVerdict.gone;
    }
    final collection = File(
      '${root.path}/collection.anki2',
    );
    return collection.existsSync()
        ? OfficialAnkiV2PendingImportVerdict.resumable
        : OfficialAnkiV2PendingImportVerdict.rebuildStaging;
  }

  static String _profileIdOf(OfficialAnkiDatabase catalog) {
    final row = catalog.handle.select(
      'SELECT profile_id FROM anki_sources LIMIT 1',
    );
    return row.isEmpty ? 'profile-default-01' : row.first['profile_id'] as String;
  }
}
