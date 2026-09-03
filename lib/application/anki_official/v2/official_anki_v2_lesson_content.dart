import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_file_log.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/projection/official_anki_mapping_suggestion.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_paging.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_payloads.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/application/anki_official/v2/official_anki_v2_decision_store.dart';
import 'package:turna/application/anki_official/v2/official_anki_v2_view_store.dart';
import 'package:turna/courses/course_loader.dart';
import 'package:turna/data/course_database.dart'
    hide Section, Unit, Lesson, LessonContent;
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/domain/course/lesson.dart';
import 'package:turna/domain/course/lesson_content.dart';
import 'package:turna/domain/course/stage.dart';

/// B6 第 5 读挂点（真机首夜 F6，step4.md）：v2 课时正文派生自卡（D3）。
///
/// v2 课时壳的 `content` 恒空（课程树只有结构事实），drift `lessons`/
/// `lesson_contents` 又按零写入纪律不落 v2 行——`LessonViewModel.loadLesson`
/// 的既有装载管线对 v2 课时必然 miss（「无法加载课程」）。本类在装载
/// 管线之前供给：视图行（课时→卡，含 presentation_kind）+ 配置区映射
/// 决策 + 引擎投影读面（op 25/26 卡字段）→ 复用 v1 的 payload 编码器
/// 现场合成 `LessonContent`。零新存储：卡变了重进课时即得新正文。
///
/// interaction id 由视图行的 wordId 铸造（`officialAnkiItemId`），与
/// `OfficialAnkiLessonCardIndex` v2 分支的 wordId 前缀匹配天然对上——
/// 播放器答题能解析回正确的卡（复习链联动）。
///
/// miss / 任何一步不可用都返回 null：调用方回落 v1 装载管线，用户可见
/// 行为与接线前一致（fail-closed，不把半截正文交给播放器）。
class OfficialAnkiV2LessonContent {
  OfficialAnkiV2LessonContent._();

  /// Test seam（与 `OfficialAnkiV2CourseRead.flagsOf` 同款）。
  static OfficialAnkiFeatureFlags Function() flagsOf =
      () => OfficialAnkiFeatureFlags.current;

  /// v2 课时 → 带正文的完整 [Lesson]；非 v2 课时或派生不可用 → null。
  static Future<Lesson?> lessonFor(String lessonId) async {
    if (!flagsOf().allowsV2ImportChain) return null;
    final course = _courseOrNull();
    final catalog = OfficialAnkiCompositionRoot.readOnlyCatalog;
    if (course == null || catalog == null) return null;

    final rows = await OfficialAnkiV2ViewStore(course).rowsForLesson(lessonId);
    if (rows.isEmpty) return null; // 非 v2 课时（v1 数据或未知 id）
    final active = _activeV2SourceIds(catalog);
    final viewRows = [
      for (final row in rows)
        if (active.contains(row.sourceId)) row,
    ];
    if (viewRows.isEmpty) return null; // retiring 源即刻不可见

    final engine = await _engineOrNull();
    if (engine == null) return null;
    try {
      return await _derive(
        engine: engine,
        catalog: catalog,
        lessonId: lessonId,
        rows: viewRows,
      );
    } catch (error) {
      officialAnkiV2Log('lesson content derive failed: $error', warning: true);
      return null;
    }
  }

  static Future<Lesson?> _derive({
    required OfficialAnkiEngine engine,
    required OfficialAnkiDatabase catalog,
    required String lessonId,
    required List<OfficialAnkiV2ViewRow> rows,
  }) async {
    final sourceId = rows.first.sourceId;
    final decision =
        await OfficialAnkiV2DecisionStore(engine).readImportMapping(sourceId);
    final suggestions = _decodeSuggestions(decision?.suggestionsJson);

    final cardIds = [for (final row in rows) row.cardId];
    final snapshot = await engine.beginProjectionRead(
      cardSetFingerprint: _cardSetFingerprint(cardIds),
      mappingVersion: rows.first.mappingVersion,
    );
    final projectionRows =
        await _projectionRowsByCard(engine, cardIds, snapshot.snapshotToken);

    final payloads = OfficialAnkiProjectionPayloads();
    final interactions = <Interaction>[];
    for (final row in rows) {
      final projectionRow = projectionRows[row.cardId];
      if (projectionRow == null) continue; // 引擎侧已删（缺卡无害）
      final mapping = suggestions[projectionRow.notetypeId];
      if (mapping == null) continue; // 无映射决策 = v1 needsMapping 同语义
      final values = payloads.values(projectionRow, mapping);
      final item = OfficialAnkiProjectedItem(
        kind: _kindFor(row.presentationKind),
        cardId: row.cardId,
        wordId: row.wordId,
        sectionId: row.sectionId,
        unitId: row.unitId,
        lessonId: row.lessonId,
        sectionName: row.sectionKey,
        unitName: row.sectionKey,
        lessonName: row.lessonKey,
        payload: const <String, Object?>{},
        sourceFingerprint: projectionRow.sourceFingerprint,
      );
      try {
        final payload = payloads.interactionJson(
          kind: item.kind,
          item: item,
          values: values,
          sourceId: sourceId,
        );
        interactions
            .add(Interaction.fromJson(Map<String, dynamic>.from(payload)));
      } on OfficialAnkiPayloadOverflow {
        continue; // 单卡超限跳过该卡，不拖垮整课时
      }
    }
    if (interactions.isEmpty) return null;

    final lessonKey = rows.first.lessonKey;
    return Lesson(
      id: lessonId,
      name: lessonKey,
      content: LessonContent(
        stages: [
          Stage(
            id: 'official-stage-0',
            name: lessonKey,
            items: interactions,
          ),
        ],
      ),
    );
  }

  /// kind 用视图行存储值（单一事实源）；损坏/未知名降 showWord。
  static OfficialAnkiProjectionKind _kindFor(String name) {
    for (final kind in OfficialAnkiProjectionKind.values) {
      if (kind.name == name) return kind;
    }
    return OfficialAnkiProjectionKind.showWord;
  }

  /// `<notetypeId, suggestion>` 解码（导入侧 `_encodeSuggestions` 的逆）。
  /// 决策损坏按 missing（配置区读语义先例），识别器可重建议。
  static Map<int, OfficialAnkiMappingSuggestion> _decodeSuggestions(
    String? json,
  ) {
    if (json == null || json.isEmpty) return const {};
    try {
      final decoded = jsonDecode(json);
      if (decoded is! Map) return const {};
      final out = <int, OfficialAnkiMappingSuggestion>{};
      for (final entry in decoded.entries) {
        final id = int.tryParse(entry.key.toString());
        if (id == null || entry.value is! Map) continue;
        out[id] = OfficialAnkiMappingSuggestion.fromJson(
          Map<String, Object?>.from(entry.value as Map),
        );
      }
      return out;
    } catch (_) {
      return const {};
    }
  }

  static Future<Map<int, OfficialAnkiProjectionRow>> _projectionRowsByCard(
    OfficialAnkiEngine engine,
    List<int> cardIds,
    String snapshotToken,
  ) async {
    final out = <int, OfficialAnkiProjectionRow>{};
    for (var start = 0;
        start < cardIds.length;
        start += officialAnkiProjectionPageDefault) {
      final page = await engine.getProjectionRowsBatch(
        cardIds: cardIds
            .skip(start)
            .take(officialAnkiProjectionPageDefault)
            .toList(),
        snapshotToken: snapshotToken,
      );
      for (final row in page.rows) {
        out[row.cardId] = row;
      }
    }
    return out;
  }

  static String _cardSetFingerprint(List<int> cardIds) {
    return sha256.convert(utf8.encode(cardIds.join(','))).toString();
  }

  static CourseDatabase? _courseOrNull() {
    try {
      return CourseLoader.databaseOrNull();
    } catch (_) {
      return null;
    }
  }

  static Set<String> _activeV2SourceIds(OfficialAnkiDatabase catalog) {
    final profileId =
        OfficialAnkiCompositionRoot.locatorPaths?.profileId ??
            'profile-default-01';
    return {
      for (final source
          in OfficialAnkiSourceDao(catalog).listV2Sources(profileId, states: {'active'}))
        source.sourceId,
    };
  }

  /// 引擎在场直接用；缺席照抄 v2 commit 模式 bootstrap 一次（课时播放
  /// = 复习面，答题本就需要引擎）。bootstrap 失败 fail-closed 返 null。
  static Future<OfficialAnkiEngine?> _engineOrNull() async {
    final existing = OfficialAnkiCompositionRoot.engine;
    if (existing != null) return existing;
    try {
      await OfficialAnkiCompositionRoot.requireImporter();
    } catch (error) {
      officialAnkiV2Log('lesson content engine bootstrap: $error',
          warning: true);
      return null;
    }
    return OfficialAnkiCompositionRoot.engine;
  }
}
