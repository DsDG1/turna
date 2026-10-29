import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:turna/application/ai/engine/ai_engine.dart';
import 'package:turna/application/ai/engine/ai_engine_config_holder.dart';
import 'package:turna/application/anki_import/adaptation/adaptation_plan_validator.dart';
import 'package:turna/application/anki_import/adaptation/ai_card_adaptation_service.dart';
import 'package:turna/application/anki_import/adaptation/notetype_presentation_preview.dart';
import 'package:turna/application/anki_import/anki_import_controller.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/projection/official_anki_mapping_suggestion.dart';
import 'package:turna/application/anki_official/v2/official_anki_adaptation_store.dart';
import 'package:turna/core/ohos_target.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/anki/adaptation/card_adaptation_plan.dart';
import 'package:turna/views/anki/import_wizard/components/smart_adaptation_panel.dart';

/// 把「智能适配」接在预览页上的宿主（ADR 0057 §7）。
///
/// 页面只负责摆放；事实构造、AI 调用、二次本地校验、样本级验证、暂存与
/// 恢复都在这里，这样预览页不必为了一个可选功能变胖（同目录的 size
/// ratchet 会拦住），也方便在没有引擎/网络的测试里单独验证。
class SmartAdaptationHost extends StatelessWidget {
  const SmartAdaptationHost({
    super.key,
    required this.sourceId,
    required this.schemas,
    required this.controller,
    this.suggestions = const <int, OfficialAnkiMappingSuggestion>{},
  });

  final String sourceId;
  final List<OfficialAnkiProjectionSchema> schemas;
  final AnkiImportController controller;

  /// 预览当前的建议表（用户可能已改过）。样本级验证用「此刻展示的组」
  /// 解析，避免「展示的组」与「验证的组」不是同一份映射。
  final Map<int, OfficialAnkiMappingSuggestion> suggestions;

  @override
  Widget build(BuildContext context) {
    // ADR 0056：不随包 AI 的构建上，入口是隐藏而不是置灰。
    if (isDegraded(OhosDegradation.aiGeneration)) {
      return const SizedBox.shrink();
    }
    final holder = _configHolderOrNull(context);
    // 控制器是 ChangeNotifier：暂存/恢复后面板要立刻反映「已暂存」。
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => SmartAdaptationPanel(
        schemas: schemas,
        aiConfigured: holder?.config.isComplete ?? false,
        hasPlan: controller.adaptationDrafts.hasNotetype,
        onGenerate: (schema) => _generate(context, holder, schema),
        onApply: _apply,
        onRestore: (schema) =>
            controller.adaptationDrafts.clearNotetype(schema.notetypeId),
      ),
    );
  }

  /// 根级 Provider 在场时用它的配置；测试或未来的其它宿主可能没有这个
  /// Provider——缺配置只会让「生成」按钮禁用，不会让页面崩。
  AiEngineConfigHolder? _configHolderOrNull(BuildContext context) {
    try {
      return Provider.of<AiEngineConfigHolder>(context, listen: false);
    } catch (_) {
      // Provider 不在场是测试宿主的正常路径，不是错误。
      return null;
    }
  }

  AdaptationFacts _factsFor(OfficialAnkiProjectionSchema schema) {
    final templates =
        schema.templateFacts?.templates ?? const <OfficialAnkiTemplateFact>[];
    return AdaptationFacts(
      sourceId: sourceId,
      notetypeId: schema.notetypeId,
      fieldCount: schema.fieldNames.length,
      templateOrdinals: [for (final template in templates) template.ord],
      frontFieldOrds: {
        for (final template in templates) ...template.frontFields,
      },
      backFieldOrds: {
        for (final template in templates) ...template.backFields,
      },
    );
  }

  OfficialAnkiMappingSuggestion _suggestionFor(
    OfficialAnkiProjectionSchema schema,
  ) {
    return suggestions[schema.notetypeId] ??
        officialAnkiSuggestMapping(schema);
  }

  Future<CardAdaptationResult> _generate(
    BuildContext context,
    AiEngineConfigHolder? holder,
    OfficialAnkiProjectionSchema schema,
  ) async {
    final config = holder?.config;
    if (config == null ||
        !config.isComplete ||
        !getIt.isRegistered<AiEngine>()) {
      return const CardAdaptationUnavailable('ai_unavailable');
    }
    final facts = _factsFor(schema);
    final result = await AiCardAdaptationService.viaEngine(
      engine: getIt<AiEngine>(),
      config: config,
    ).generate(schema: schema, facts: facts);
    if (result is CardAdaptationAccepted) {
      // 服务已校验过一次；这里用页面此刻的同一份事实再核一遍，避免「展示的
      // 组」与「校验的组」不是同一份 schema。
      final validation =
          AdaptationPlanValidator.validate(result.plan, facts: facts);
      if (!validation.ok) {
        return CardAdaptationRejected(
          code: 'invalid_plan',
          issues: validation.issues,
        );
      }
      // 样本级验证（ADR 0057 §7 的本地全组验证在 Dart 侧的可达部分）：
      // 把方案套到本组每张样本上走完整解析链。全部样本都落回原卡说明
      // 方案在这个组上什么都渲染不了——暂存它只会骗用户「已适配」。
      final sampleSummary = resolvePlanSampleSummary(
        schema: schema,
        suggestion: _suggestionFor(schema),
        plan: result.plan,
      );
      if (sampleSummary.total > 0 && sampleSummary.structured == 0) {
        return const CardAdaptationRejected(
          code: 'invalid_plan',
          issues: [AdaptationIssue.allSamplesUnsupported],
        );
      }
    }
    return result;
  }

  Future<bool> _apply(
    OfficialAnkiProjectionSchema schema,
    CardAdaptationPlan plan,
  ) async {
    controller.adaptationDrafts.stage(
      // 方案自己的作用域决定暂存键：带挖空目标的方案存成精确挖空键，
      // 模板级方案存成模板键——课时侧按同一规则查（ADR 0057 §3）。
      adaptationScopeKey(
        schema.notetypeId,
        plan.scope.templateOrdinal,
        clozeTarget: plan.scope.clozeTarget,
      ),
      plan,
    );
    return true;
  }
}
