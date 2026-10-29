import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_file_log.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_import/adaptation/card_presentation_resolver.dart';
import 'package:turna/application/anki_import/recognition/recognize/result.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/projection/official_anki_mapping_suggestion.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_paging.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_payloads.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/application/anki_official/v2/official_anki_adaptation_store.dart';
import 'package:turna/application/anki_official/v2/official_anki_v2_decision_store.dart';
import 'package:turna/application/anki_official/v2/official_anki_v2_view_store.dart';
import 'package:turna/courses/course_loader.dart';
import 'package:turna/data/course_database.dart'
    hide Section, Unit, Lesson, LessonContent;
import 'package:turna/domain/anki/adaptation/presentation_decision.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/domain/course/lesson.dart';
import 'package:turna/domain/course/lesson_content.dart';
import 'package:turna/domain/course/stage.dart';

/// Why a v2 lesson existed but its content could not be derived. The caller
/// can tell "not a v2 lesson" (null failure) apart from "v2, but broken"
/// (non-null failure), so the user-visible error stops being a generic
/// "cannot load course" (ADR 0057 §6 fail-closed + B1).
enum OfficialAnkiV2LessonDeriveFailure {
  /// The config-area mapping decision JSON is corrupt — the whole source
  /// degrades to needsMapping. Reconfirming the mapping in the import flow
  /// fixes it.
  mappingDecisionCorrupt,

  /// No card in this lesson had a mapping decision (v1 needsMapping
  /// semantics) — the user skipped every notetype this lesson depends on.
  mappingDecisionMissing,

  /// Cards existed and were mapped, but every derivation failed (render or
  /// payload errors). Not a single interaction survived.
  derivationFailed,
}

/// v2 课时派生结果：`lesson == null && failure == null` 是正常 miss（非 v2
/// 课时 / 引擎缺席）；`failure != null` 说明这确实是 v2 课时但派生失败。
typedef OfficialAnkiV2LessonOutcome =
    ({Lesson? lesson, OfficialAnkiV2LessonDeriveFailure? failure});

/// B6 第 5 读挂点（真机首夜 F6，ADR 0043）：v2 课时正文派生自卡（D3）。
///
/// v2 课时壳的 `content` 恒空（课程树只有结构事实），drift `lessons`/
/// `lesson_contents` 又按零写入纪律不落 v2 行——`LessonViewModel.loadLesson`
/// 的既有装载管线对 v2 课时必然 miss（「无法加载课程」）。本类在装载
/// 管线之前供给：视图行（课时→卡，含 presentation_kind）+ 配置区映射
/// 决策 + 引擎投影读面（op 25/26 卡字段）→ 复用 v1 的 payload 编码器
/// 现场合成 `LessonContent`。零新存储：卡变了重进课时即得新正文。
///
/// 卡面判定全权在 `OfficialCardPresentationResolver.resolveCard`（ADR
/// 0057 §1）：本类只取数据（视图行 / 映射决策 / 生效方案）与编码 payload，
/// 不再自持方案→映射的拼装规则。单卡派生失败退原卡引用，不拖垮整课；
/// 整课无一张可渲染时带 [OfficialAnkiV2LessonDeriveFailure] 返回，调用方
/// 可以区分「重新确认映射」与「无法加载」。
class OfficialAnkiV2LessonContent {
  OfficialAnkiV2LessonContent._();

  /// v2 课时 → 带正文的完整 [Lesson]；非 v2 课时或派生不可用 → lesson 为
  /// null（failure 说明是不是 v2 课时本身坏了）。
  static Future<OfficialAnkiV2LessonOutcome> lessonFor(String lessonId) async {
    final course = _courseOrNull();
    final catalog = OfficialAnkiCompositionRoot.readOnlyCatalog;
    if (course == null || catalog == null) {
      return (lesson: null, failure: null);
    }

    final rows = await OfficialAnkiV2ViewStore(course).rowsForLesson(lessonId);
    if (rows.isEmpty) {
      return (lesson: null, failure: null); // 非 v2 课时（v1 数据或未知 id）
    }
    final active = _activeV2SourceIds(catalog);
    final viewRows = [
      for (final row in rows)
        if (active.contains(row.sourceId)) row,
    ];
    if (viewRows.isEmpty) {
      return (lesson: null, failure: null); // retiring 源即刻不可见
    }

    final engine = await _engineOrNull();
    if (engine == null) return (lesson: null, failure: null);
    try {
      return await _derive(
        engine: engine,
        catalog: catalog,
        lessonId: lessonId,
        rows: viewRows,
      );
    } catch (error) {
      officialAnkiV2Log('lesson content derive failed: $error', warning: true);
      return (
        lesson: null,
        failure: OfficialAnkiV2LessonDeriveFailure.derivationFailed,
      );
    }
  }

  static Future<OfficialAnkiV2LessonOutcome> _derive({
    required OfficialAnkiEngine engine,
    required OfficialAnkiDatabase catalog,
    required String lessonId,
    required List<OfficialAnkiV2ViewRow> rows,
  }) async {
    final sourceId = rows.first.sourceId;
    final decision =
        await OfficialAnkiV2DecisionStore(engine).readImportMapping(sourceId);
    final decoded = _decodeSuggestions(decision?.suggestionsJson);
    final suggestions = decoded.suggestions;
    // 适配方案读一次（manifest + 单卡覆盖），逐卡只按需读修订体（ADR 0057 §6）。
    final adaptation = await OfficialAnkiAdaptationStore(engine).snapshot(sourceId);

    final cardIds = [for (final row in rows) row.cardId];
    final snapshot = await engine.beginProjectionRead(
      cardSetFingerprint: _cardSetFingerprint(cardIds),
      mappingVersion: rows.first.mappingVersion,
    );
    final projectionRows =
        await _projectionRowsByCard(engine, cardIds, snapshot.snapshotToken);

    const resolver = OfficialCardPresentationResolver();
    const payloads = OfficialAnkiProjectionPayloads();
    final interactions = <Interaction>[];
    var overflowFallbacks = 0;
    var unavailable = 0;
    var planFallbacks = 0;
    var deriveFailures = 0;
    var mappedCards = 0;
    var missingCards = 0;
    final variantCounts = <CardContentVariant, int>{};
    final reasonCounts = <PresentationReason, int>{};
    for (final row in rows) {
      final projectionRow = projectionRows[row.cardId];
      if (projectionRow == null) {
        missingCards++; // 引擎侧已删（缺卡无害）
        continue;
      }
      final mapping = suggestions[projectionRow.notetypeId];
      if (mapping == null) continue; // 无映射决策 = v1 needsMapping 同语义
      mappedCards++;
      // ADR 0057 §3：Cloze 的 card ordinal 是挖空编号，不是模板索引。查方案
      // 用「模板序号 0 + 挖空目标」：带挖空目标的方案命中精确挖空，模板级
      // 方案按 nt:0 命中全部挖空。非 Cloze 牌型的 ordinal 就是模板索引。
      final isCloze = mapping.cardArchetype == CardArchetype.cloze;
      final applied = await adaptation.lookup(
        notetypeId: projectionRow.notetypeId,
        templateOrdinal: isCloze ? 0 : projectionRow.templateOrdinal,
        cardId: row.cardId,
        clozeTarget: isCloze ? projectionRow.templateOrdinal : null,
      );
      var resolved = _resolveCard(
        resolver: resolver,
        payloads: payloads,
        projectionRow: projectionRow,
        mapping: mapping,
        applied: applied,
        row: row,
      );
      if (resolved == null) {
        // 单卡派生失败不拖垮整课：退到轻量的原卡引用（B1），失败本身已记日志。
        deriveFailures++;
        resolved = const OfficialCardPlanResolution(
          kind: OfficialAnkiProjectionKind.canonicalLink,
          decision: OriginalCardDecision(reasons: []),
          values: OfficialAnkiRoleValues.empty,
        );
      }
      final values = resolved.values;
      var kind = resolved.kind;
      if (values.variant != CardContentVariant.none) {
        variantCounts[values.variant] = (variantCounts[values.variant] ?? 0) + 1;
      }
      if (applied is! AdaptationNoPlan && resolved.decision.isOriginalCard) {
        planFallbacks++;
        kind = OfficialAnkiProjectionKind.canonicalLink;
      }
      _countReasons(reasonCounts, resolved.decision.reasons);
      final item = OfficialAnkiProjectedItem(
        kind: kind,
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
        // 超限不静默跳卡：退到轻量的原卡引用（ADR 0057 §1）。原卡引用本身
        // 也放不下才是真的不可用——记下来，不假装这张卡存在。
        try {
          final fallback = payloads.interactionJson(
            kind: OfficialAnkiProjectionKind.canonicalLink,
            item: item,
            values: values,
            sourceId: sourceId,
          );
          interactions
              .add(Interaction.fromJson(Map<String, dynamic>.from(fallback)));
          overflowFallbacks++;
        } on OfficialAnkiPayloadOverflow {
          unavailable++;
          officialAnkiV2Log(
            'lesson card ${row.cardId} unavailable: payload overflow',
            warning: true,
          );
        }
      }
    }
    if (interactions.isEmpty) {
      // 整课没有一张可渲染的卡。带原因返回，让调用方能区分「重新确认映射」
      // 与「无法加载」，而不是笼统回落 v1 管线（B1）。
      final failure = decoded.corrupt
          ? OfficialAnkiV2LessonDeriveFailure.mappingDecisionCorrupt
          : (mappedCards == 0 && missingCards > 0
              ? OfficialAnkiV2LessonDeriveFailure.derivationFailed
              : (mappedCards == 0
                  ? OfficialAnkiV2LessonDeriveFailure.mappingDecisionMissing
                  : OfficialAnkiV2LessonDeriveFailure.derivationFailed));
      officialAnkiV2Log(
        'lesson $lessonId produced no interactions (${failure.name})',
        warning: true,
      );
      return (lesson: null, failure: failure);
    }
    if (deriveFailures > 0) {
      officialAnkiV2Log(
        'lesson $lessonId: $deriveFailures card(s) fell back to the original '
        'card after a derive error',
        warning: true,
      );
    }
    if (planFallbacks > 0) {
      // 方案明确回原卡 / manifest 指向的修订缺失：这是设计内的结果，不是
      // 故障，但必须能从日志里区分于「本来就没有方案」。
      officialAnkiV2Log(
        'lesson $lessonId: $planFallbacks card(s) pinned to the original card '
        'by an adaptation decision',
      );
    }
    if (reasonCounts.isNotEmpty) {
      // 可解释性（ADR 0057 §9）：整课按原因聚合一次，出问题时不用逐卡翻。
      officialAnkiV2Log(
        'lesson $lessonId reasons: '
        '${reasonCounts.entries.map((e) => '${e.key.name}=${e.value}').join(', ')}',
      );
    }
    if (variantCounts.isNotEmpty) {
      // 受约束变体显式记账（plan §3.2）：basic 组里的挖空/选择/听力卡不再
      // 只是一次静默的 archetype 覆写，日志里能看出这一课到底发生了什么。
      officialAnkiV2Log(
        'lesson $lessonId variants: '
        '${variantCounts.entries.map((e) => '${e.key.name}=${e.value}').join(', ')}',
      );
    }
    if (overflowFallbacks > 0 || unavailable > 0) {
      officialAnkiV2Log(
        'lesson $lessonId: $overflowFallbacks card(s) fell back to the '
        'original card, $unavailable card(s) unavailable',
        warning: unavailable > 0,
      );
    }

    final lessonKey = rows.first.lessonKey;
    return (
      lesson: Lesson(
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
      ),
      failure: null,
    );
  }

  /// 单卡走解析器；失败（数据损坏 / 未预期的异常）记日志并返回 null，
  /// 调用方退原卡引用（B1）。解析器内部不再抛出后，这里兜的是编码前
  /// 任何一步的意外。
  static OfficialCardPlanResolution? _resolveCard({
    required OfficialCardPresentationResolver resolver,
    required OfficialAnkiProjectionPayloads payloads,
    required OfficialAnkiProjectionRow projectionRow,
    required OfficialAnkiMappingSuggestion mapping,
    required AdaptationLookup applied,
    required OfficialAnkiV2ViewRow row,
  }) {
    try {
      return resolver.resolveCard(
        row: projectionRow,
        mapping: mapping,
        applied: applied,
        storedKindName: row.presentationKind,
        payloads: payloads,
      );
    } catch (error, stackTrace) {
      officialAnkiV2Log(
        'lesson card ${row.cardId} resolve failed: $error\n$stackTrace',
        warning: true,
      );
      return null;
    }
  }

  /// 按原因聚合（ADR 0057 §9）。日志只记枚举名与次数，不记字段内容。
  static void _countReasons(
    Map<PresentationReason, int> counts,
    List<PresentationReason> reasons,
  ) {
    for (final reason in reasons) {
      counts[reason] = (counts[reason] ?? 0) + 1;
    }
  }

  /// `<notetypeId, suggestion>` 解码（导入侧 `_encodeSuggestions` 的逆）。
  ///
  /// 决策损坏按 missing 处理（配置区读语义先例），识别器可重建议——但
  /// `corrupt` 必须置位并留痕：这份 JSON 是整组映射的唯一来源，静默吞掉
  /// 会让「为什么全部退回 needsMapping」无从查起（AGENTS.md §4）。
  static ({Map<int, OfficialAnkiMappingSuggestion> suggestions, bool corrupt})
      _decodeSuggestions(String? json) {
    if (json == null || json.isEmpty) {
      return (suggestions: const {}, corrupt: false);
    }
    try {
      final decoded = jsonDecode(json);
      if (decoded is! Map) {
        officialAnkiV2Log(
          'import mapping decision JSON is not an object; '
          'treating every notetype as needsMapping',
          warning: true,
        );
        return (suggestions: const {}, corrupt: true);
      }
      final out = <int, OfficialAnkiMappingSuggestion>{};
      for (final entry in decoded.entries) {
        final id = int.tryParse(entry.key.toString());
        if (id == null || entry.value is! Map) continue;
        out[id] = OfficialAnkiMappingSuggestion.fromJson(
          Map<String, Object?>.from(entry.value as Map),
        );
      }
      return (suggestions: out, corrupt: false);
    } catch (error) {
      officialAnkiV2Log(
        'import mapping decision JSON corrupt: $error; '
        'treating every notetype as needsMapping',
        warning: true,
      );
      return (suggestions: const {}, corrupt: true);
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
      // best-effort 探测：课程库尚未初始化属于正常冷启动路径。
      return null;
    }
  }

  static Set<String> _activeV2SourceIds(OfficialAnkiDatabase catalog) {
    final profileId = OfficialAnkiCompositionRoot.locatorPaths?.profileId ??
        OfficialAnkiPaths.defaultProfileId;
    return {
      for (final source in OfficialAnkiSourceDao(catalog)
          .listV2Sources(profileId, states: {'active'}))
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
