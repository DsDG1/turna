// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/ai/engine/ai_engine_config_holder.dart';
import 'package:turna/core/spacing.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/core/turna_icon_id.dart';
import 'package:turna/domain/ai/ai_course.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/views/ai/components/ai_practice_generate_sheet.dart';
import 'package:turna/views/lesson/components/ai_depth_tutor_sheet.dart';
import 'package:turna/views/widgets/turna_icon.dart';
import 'package:turna/views/widgets/turna_reading_layout.dart';
import 'package:turna/views/widgets/turna_sheet.dart';
import 'package:turna/views/widgets/turna_top_bar.dart';

/// AI 助手功能介绍页 — 常驻手册。
///
/// 从 AI Hub 顶栏右上角的帮助图标进入。一页讲清楚 6 个主推功能（伴学 4 + 复习 2）
/// 是干嘛的、什么时候用、怎么操作、有啥小贴士。每张功能卡可直接点开对应功能。
///
/// 文案集中在 AppStrings 的 `aiGuide*` 分组；[_FeatureSpec] 的 5 个 String
/// 字段直接绑 AppStrings getter，上 i18n 时只需替换取值。
@RoutePage()
class AiFeatureGuidePage extends StatelessWidget {
  const AiFeatureGuidePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TurnaTheme.surfaceColor(context),
      appBar: TurnaTopBar(
        centerTitle: true,
        showDivider: true,
        title: AppStrings.aiFeatureGuideTitle,
      ),
      body: const _FeatureGuideContent(),
    );
  }
}

class _FeatureGuideContent extends StatelessWidget {
  const _FeatureGuideContent();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
          const SliverToBoxAdapter(child: _HeroCard()),
          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.pageMargin,
              ),
              child: TurnaReadingSectionHeader(
                indexLabel: '01',
                title: AppStrings.aiGuideSectionCompanion,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.pageMargin,
            ),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => Padding(
                  padding: EdgeInsets.only(bottom: i < 3 ? AppSpacing.md : 0),
                  child: _FeatureCard(spec: _kFeatures[i]),
                ),
                childCount: 4,
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.pageMargin,
              ),
              child: TurnaReadingSectionHeader(
                indexLabel: '02',
                title: AppStrings.aiGuideSectionReview,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.pageMargin,
            ),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => Padding(
                  padding: EdgeInsets.only(bottom: i < 1 ? AppSpacing.md : 0),
                  child: _FeatureCard(spec: _kFeatures[4 + i]),
                ),
                childCount: 2,
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxl)),
        ],
      ),
    );
  }
}

// ─── Hero（引擎状态一行 + 隐私说明，R14：不再是渐变大卡）──────────────────

class _HeroCard extends StatelessWidget {
  const _HeroCard();

  @override
  Widget build(BuildContext context) {
    return Selector<AiEngineConfigHolder, (bool, String)>(
      selector: (_, h) => (h.config.isComplete, h.config.preset.label),
      builder: (context, snap, _) {
        final (complete, preset) = snap;
        return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.pageMargin,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppStrings.aiGuideHeroTitle,
                style: AppTextStyles.pageTitle(context),
              ),
              const SizedBox(height: AppSpacing.xs + 2),
              Text(
                AppStrings.aiGuideHeroSubtitle,
                style: AppTextStyles.captionSm(context).copyWith(height: 1.5),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: complete ? TurnaTheme.brandTeal : null,
                      border: complete
                          ? null
                          : Border.all(color: TurnaTheme.warning, width: 2),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm + 2),
                  Expanded(
                    child: Text(
                      complete
                          ? AppStrings.aiGuideEngineConfigured(preset)
                          : AppStrings.aiGuideEngineMissing,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.captionSm(context).copyWith(
                        color: complete
                            ? TurnaTheme.textSecondaryColor(context)
                            : TurnaTheme.warning,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  TurnaIcon(
                    TurnaIconId.lock,
                    size: 14,
                    color: TurnaTheme.textHintColor(context),
                  ),
                  const SizedBox(width: AppSpacing.xs + 2),
                  Flexible(
                    child: Text(
                      AppStrings.aiGuidePrivacyChip,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.captionSm(context)
                          .copyWith(color: TurnaTheme.textHintColor(context)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Feature data ─────────────────────────────────────────────────────────

class _FeatureSpec {
  const _FeatureSpec({
    required this.icon,
    required this.accent,
    required this.title,
    required this.purpose,
    required this.scenarios,
    required this.steps,
    required this.tip,
    required this.open,
  });

  final TurnaIconId icon;
  final Color accent;
  final String title;
  final String purpose;
  final List<String> scenarios;
  final List<String> steps;
  final String tip;
  final void Function(BuildContext) open;
}

final List<_FeatureSpec> _kFeatures = [
  // 1. 自由问答
  _FeatureSpec(
    icon: TurnaIconId.chat,
    accent: TurnaTheme.brandTeal,
    title: AppStrings.aiGuideFreeChatTitle,
    purpose: AppStrings.aiGuideFreeChatPurpose,
    scenarios: AppStrings.aiGuideFreeChatScenarios,
    steps: AppStrings.aiGuideFreeChatSteps,
    tip: AppStrings.aiGuideFreeChatTip,
    open: _openTutorChat,
  ),
  // 2. 学习诊断
  _FeatureSpec(
    icon: TurnaIconId.insights,
    accent: TurnaTheme.brandSky,
    title: AppStrings.aiGuideDiagnosisTitle,
    purpose: AppStrings.aiGuideDiagnosisPurpose,
    scenarios: AppStrings.aiGuideDiagnosisScenarios,
    steps: AppStrings.aiGuideDiagnosisSteps,
    tip: AppStrings.aiGuideDiagnosisTip,
    open: _openDiagnosis,
  ),
  // 3. 收藏的回答
  _FeatureSpec(
    icon: TurnaIconId.bookmark,
    accent: TurnaTheme.anatolianClay,
    title: AppStrings.aiGuideSavedTitle,
    purpose: AppStrings.aiGuideSavedPurpose,
    scenarios: AppStrings.aiGuideSavedScenarios,
    steps: AppStrings.aiGuideSavedSteps,
    tip: AppStrings.aiGuideSavedTip,
    open: _openSaved,
  ),
  // 4. 深度讲解
  _FeatureSpec(
    icon: TurnaIconId.tree,
    accent: TurnaTheme.brandReed,
    title: AppStrings.aiGuideDepthTitle,
    purpose: AppStrings.aiGuideDepthPurpose,
    scenarios: AppStrings.aiGuideDepthScenarios,
    steps: AppStrings.aiGuideDepthSteps,
    tip: AppStrings.aiGuideDepthTip,
    open: _openDepthTutor,
  ),
  // 5. 按错题练习
  _FeatureSpec(
    icon: TurnaIconId.repeat,
    accent: TurnaTheme.brandTeal,
    title: AppStrings.aiGuideMistakesTitle,
    purpose: AppStrings.aiGuideMistakesPurpose,
    scenarios: AppStrings.aiGuideMistakesScenarios,
    steps: AppStrings.aiGuideMistakesSteps,
    tip: AppStrings.aiGuideMistakesTip,
    open: _openTutorMistakes,
  ),
  // 6. 按弱词练习
  _FeatureSpec(
    icon: TurnaIconId.target,
    accent: TurnaTheme.brandReed,
    title: AppStrings.aiGuideWeakTitle,
    purpose: AppStrings.aiGuideWeakPurpose,
    scenarios: AppStrings.aiGuideWeakScenarios,
    steps: AppStrings.aiGuideWeakSteps,
    tip: AppStrings.aiGuideWeakTip,
    open: _openTutorWeak,
  ),
];

// ─── Open helpers ─────────────────────────────────────────────────────────

void _openTutorChat(BuildContext context) =>
    context.router.push(AiTutorChatRoute());

void _openDiagnosis(BuildContext context) =>
    context.router.push(const AiDiagnosisRoute());

void _openSaved(BuildContext context) =>
    context.router.push(const AiSavedListRoute());

void _openDepthTutor(BuildContext context) {
  showTurnaSheet(
    context: context,
    title: AppStrings.aiDepthTutorTitle,
    subtitle: AppStrings.aiDepthTutorSubtitle,
    body: const AiDepthTutorSheet(),
  );
}

void _openTutorMistakes(BuildContext context) {
  showAiPracticeGenerateSheet(context, source: AiPracticeSource.mistakes);
}

void _openTutorWeak(BuildContext context) {
  showAiPracticeGenerateSheet(context, source: AiPracticeSource.weakWords);
}

// ─── Feature card ─────────────────────────────────────────────────────────

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({required this.spec});
  final _FeatureSpec spec;

  @override
  Widget build(BuildContext context) {
    return TurnaReadingCard(
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => spec.open(context),
          borderRadius: TurnaTheme.borderRadius,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 标题行
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: TurnaTheme.softTint(
                          context,
                          spec.accent,
                          alpha: 0.12,
                        ),
                        borderRadius: TurnaTheme.borderRadius,
                      ),
                      child: TurnaIcon(
                        spec.icon,
                        size: 18,
                        color: TurnaTheme.accentOnCard(context, spec.accent),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        spec.title,
                        style: AppTextStyles.cardTitle(context)
                            .copyWith(color: spec.accent),
                      ),
                    ),
                    TurnaIcon(
                      TurnaIconId.chevronRight,
                      size: 18,
                      color: TurnaTheme.textSecondaryColor(context),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md + 2),
                // 作用
                _SectionLabel(
                  label: AppStrings.aiGuideLabelPurpose,
                  color: spec.accent,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  spec.purpose,
                  style: AppTextStyles.bodyText(context).copyWith(height: 1.55),
                ),
                const SizedBox(height: AppSpacing.md),
                // 适用场景
                _SectionLabel(
                  label: AppStrings.aiGuideLabelScenarios,
                  color: spec.accent,
                ),
                const SizedBox(height: AppSpacing.xs),
                for (final s in spec.scenarios)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 7, right: 6),
                          child: Container(
                            width: 4,
                            height: 4,
                            decoration: BoxDecoration(
                              color: spec.accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            s,
                            style: AppTextStyles.captionSm(context)
                                .copyWith(height: 1.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: AppSpacing.md),
                // 操作流程
                _SectionLabel(
                  label: AppStrings.aiGuideLabelSteps,
                  color: spec.accent,
                ),
                const SizedBox(height: AppSpacing.xs),
                for (var i = 0; i < spec.steps.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 20,
                          child: Text(
                            '${i + 1}.',
                            style: AppTextStyles.captionSm(context).copyWith(
                              color: spec.accent,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            spec.steps[i],
                            style: AppTextStyles.captionSm(context)
                                .copyWith(height: 1.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: AppSpacing.md),
                // 小贴士
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: TurnaTheme.softTint(
                      context,
                      spec.accent,
                      alpha: 0.08,
                    ),
                    borderRadius: TurnaTheme.borderRadius,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TurnaIcon(
                        TurnaIconId.lightbulb,
                        size: 16,
                        color: spec.accent,
                      ),
                      const SizedBox(width: AppSpacing.xs + 2),
                      Expanded(
                        child: Text(
                          spec.tip,
                          style: AppTextStyles.captionSm(context).copyWith(
                            color: TurnaTheme.textPrimaryColor(context),
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: AppTextStyles.caption(
        context,
      ).copyWith(color: color, fontWeight: FontWeight.w800, letterSpacing: 0.3),
    );
  }
}
