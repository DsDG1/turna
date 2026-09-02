import 'package:turna/application/anki_official/engine/official_anki_engine.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_file_log.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_lifecycle_models.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_maintenance.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';

/// K2：live `importPackage` 已写入共享 collection，但 source 从未
/// `active`、视图表没有行 → 课程树不可见、文件体积仍在。
///
/// 无主卡 = collection 里有、且不属于任何 `active`/`retiring` 源的
/// `anki_source_cards` 行。v1 回滚靠 checkpoint（已废）；v2 用这个差集
/// 回收。删除后入队 mediaGc + compact，否则 sqlite 文件不会缩小。
class OfficialAnkiV2UnownedCardReclaimer {
  OfficialAnkiV2UnownedCardReclaimer({
    required this.catalog,
    required this.paths,
    this.engine,
    this.nowMillis,
  });

  final OfficialAnkiDatabase catalog;
  final OfficialAnkiPaths paths;
  final OfficialAnkiEngine? engine;
  final int Function()? nowMillis;

  static const _deleteChunk = 5000;
  static const _searchPage = 500;

  int get _now => nowMillis?.call() ?? DateTime.now().millisecondsSinceEpoch;

  Future<int> purge() async {
    var resolved = engine ?? OfficialAnkiCompositionRoot.engine;
    if (resolved == null) {
      try {
        await OfficialAnkiCompositionRoot.requireImporter();
      } catch (error) {
        officialAnkiV2Log('unowned purge: engine bootstrap $error', warning: true);
        return 0;
      }
      resolved = OfficialAnkiCompositionRoot.engine;
    }
    if (resolved == null) {
      officialAnkiV2Log('unowned purge skipped: no engine', warning: true);
      return 0;
    }
    try {
      await resolved.openProfile(paths);
    } catch (error) {
      officialAnkiV2Log('unowned purge open: $error', warning: true);
      return 0;
    }

    final owned = _ownedCardIds();
    final all = await _allCardIds(resolved);
    final ghosts = all.difference(owned).toList()..sort();
    if (ghosts.isEmpty) {
      officialAnkiV2Log('unowned purge: none');
      return 0;
    }

    var deleted = 0;
    for (var start = 0; start < ghosts.length; start += _deleteChunk) {
      final chunk = ghosts.sublist(
        start,
        start + _deleteChunk > ghosts.length
            ? ghosts.length
            : start + _deleteChunk,
      );
      deleted += await resolved.deleteCards(chunk);
    }
    officialAnkiV2Log(
      'unowned purge: deleted $deleted cards '
      '(ghosts=${ghosts.length}, owned=${owned.length})',
    );

    final jobs = OfficialAnkiMaintenanceJobDao(catalog);
    jobs.enqueue(
      profileId: paths.profileId,
      kind: OfficialAnkiMaintenanceKind.mediaGc,
      nowMillis: _now,
    );
    jobs.enqueue(
      profileId: paths.profileId,
      kind: OfficialAnkiMaintenanceKind.compactCollection,
      nowMillis: _now,
    );
    return deleted;
  }

  Set<int> _ownedCardIds() {
    final rows = catalog.handle.select(
      'SELECT c.card_id FROM anki_source_cards c '
      'INNER JOIN anki_sources s ON s.source_id = c.source_id '
      "WHERE s.state IN ('active', 'retiring')",
    );
    return {
      for (final row in rows) (row['card_id'] as num).toInt(),
    };
  }

  Future<Set<int>> _allCardIds(OfficialAnkiEngine resolved) async {
    final ids = <int>{};
    String? token;
    do {
      final page = await resolved.searchCardsPage(
        search: '',
        pageSize: _searchPage,
        pageToken: token,
      );
      ids.addAll(page.cardIds);
      token = page.nextPageToken;
    } while (token != null && token.isNotEmpty);
    return ids;
  }
}
