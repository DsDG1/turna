import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine.dart';
import 'package:turna/application/anki_official/v2/official_anki_adaptation_promoter.dart';
import 'package:turna/application/anki_official/v2/official_anki_adaptation_store.dart';
import 'package:turna/core/logger.dart';
import 'package:turna/domain/anki/adaptation/card_adaptation_plan.dart';

/// 把向导里确认过的适配草稿落到 live（ADR 0057 §6，plan §12.3）。
///
/// best-effort：任何失败只记日志并返回空报告——导入本身已经提交成功，用户
/// 仍然拿到本地识别结果与原卡。live 模板序号现场从 projection schemas 读，
/// 不用 staging 的序号，因为合并后它们不保证一致。
Future<AdaptationPromotionReport> promoteAdaptationDrafts({
  required OfficialAnkiEngine? live,
  required String sourceId,
  required Map<String, CardAdaptationPlan> plans,
}) async {
  if (plans.isEmpty) return AdaptationPromotionReport.empty;
  if (live == null) {
    logger.w('[AnkiImport] adaptation promote skipped: no live engine');
    return AdaptationPromotionReport.empty;
  }
  try {
    final notetypeIds = <int>{
      for (final key in plans.keys)
        if (parseAdaptationScopeKey(key) case final scope?) scope.notetypeId,
    };
    final schemas = await live.getProjectionSchemas(
      notetypeIds: notetypeIds.toList(),
    );
    final ordinals = <int, Set<int>>{
      for (final schema in schemas)
        schema.notetypeId: <int>{
          for (final template in schema.templateFacts?.templates ??
              const <OfficialAnkiTemplateFact>[])
            template.ord,
        },
    };
    final report = await const OfficialAnkiAdaptationPromoter().promotePlans(
      live: live,
      sourceId: sourceId,
      plans: plans,
      liveTemplateOrdinals: ordinals,
    );
    logger.w(
      '[AnkiImport] adaptation promoted=${report.promoted} '
      'skipped=${report.skippedCount} cards=${report.cardsCopied}',
    );
    return report;
  } catch (error) {
    logger.w('[AnkiImport] adaptation promote failed: $error');
    return AdaptationPromotionReport.empty;
  }
}
