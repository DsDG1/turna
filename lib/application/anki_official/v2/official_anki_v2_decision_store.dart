import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_file_log.dart';
import 'package:turna/application/anki_official/v2/official_anki_v2_config_keys.dart';

/// D2 消费者：决策进配置区（op 41/42，step4.md B1）。
///
/// 每个写都是 Collection 内**单事务**（op 42 内部 `set_config_json`），
/// 杀进程即回滚，无半写（K10）；同值重放结果相同（幂等）；值损坏读取
/// 按 missing 处理，识别器可重建议（决策丢失 ≠ 数据丢失）。
class OfficialAnkiV2DecisionStore {
  const OfficialAnkiV2DecisionStore(this._engine);

  final OfficialAnkiEngine _engine;

  /// 写映射晋升决策。返回 true 表示配置区已持有该决策（写成功或同值
  /// 重放的 no-op）。
  Future<bool> writeImportMapping({
    required String sourceId,
    required OfficialAnkiV2MappingDecision decision,
  }) async {
    final result = await _engine.setConfig(
      OfficialAnkiV2ConfigKeys.importMapping(sourceId),
      decision.toJson(),
    );
    if (!result.ok) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.invalidState,
        messageKey: 'official_anki.invalid_state',
        debugDetails: 'v2_mapping_config_write_failed',
      );
    }
    return true;
  }

  Future<OfficialAnkiV2MappingDecision?> readImportMapping(
    String sourceId,
  ) async {
    final value = await _engine.getConfig(
      OfficialAnkiV2ConfigKeys.importMapping(sourceId),
    );
    if (!value.found) return null;
    return OfficialAnkiV2MappingDecision.decode(value.value);
  }

  /// 删除映射决策（source 卸载终删时清理命名空间）。
  Future<void> deleteImportMapping(String sourceId) async {
    await _engine.setConfig(OfficialAnkiV2ConfigKeys.importMapping(sourceId), null);
  }

  Future<bool> writeDeckPlacement({
    required int deckId,
    required OfficialAnkiV2PlacementDecision decision,
  }) async {
    final result = await _engine.setConfig(
      OfficialAnkiV2ConfigKeys.coursePlacement(deckId),
      decision.toJson(),
    );
    return result.ok;
  }

  Future<OfficialAnkiV2PlacementDecision?> readDeckPlacement(int deckId) async {
    final value = await _engine.getConfig(
      OfficialAnkiV2ConfigKeys.coursePlacement(deckId),
    );
    if (!value.found) return null;
    return OfficialAnkiV2PlacementDecision.decode(value.value);
  }

  /// 读取全部放置决策。deck ids 由调用方给出（来自 Collection 牌组树），
  /// 每个键一次 GET_CONFIG——决策数量 = 顶层牌组数，量级很小。
  Future<Map<int, OfficialAnkiV2PlacementDecision>> readDeckPlacements(
    Iterable<int> deckIds,
  ) async {
    final out = <int, OfficialAnkiV2PlacementDecision>{};
    for (final deckId in deckIds) {
      final decision = await readDeckPlacement(deckId);
      if (decision != null) out[deckId] = decision;
    }
    return out;
  }

  Future<void> deleteDeckPlacement(int deckId) async {
    await _engine.setConfig(OfficialAnkiV2ConfigKeys.coursePlacement(deckId), null);
  }

  /// B6：课程切换 = 改一个配置区决策键。best-effort —— 引擎不可用时
  /// 只记录告警，不阻塞切换（prefs 侧的兼容写由 CourseProvider 负责）。
  Future<void> writeCourseScope(String wireKey) async {
    try {
      await _engine.setConfig(
        OfficialAnkiV2ConfigKeys.courseScope,
        {'wireKey': wireKey, 'schema': 1},
      );
    } catch (error) {
      officialAnkiV2Log('course scope decision write failed: $error',
          warning: true);
    }
  }

  Future<String?> readCourseScope() async {
    try {
      final value = await _engine.getConfig(OfficialAnkiV2ConfigKeys.courseScope);
      if (!value.found || value.value is! Map) return null;
      return (value.value as Map)['wireKey'] as String?;
    } catch (_) {
      return null;
    }
  }
}
