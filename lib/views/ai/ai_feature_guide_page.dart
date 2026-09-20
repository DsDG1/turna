// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/ai/engine/ai_engine_config_holder.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/views/lesson/components/ai_depth_tutor_sheet.dart';
import 'package:turna/views/lesson/tutor_launch_sheet.dart';
import 'package:turna/views/play/components/play_tiles.dart';
import 'package:turna/core/theme.dart';

/// AI 助手功能介绍页 — 常驻手册。
///
/// 从 AI Hub AppBar 右上角 ❓ 进入。一页讲清楚 6 个主推功能（伴学 4 + 复习 2）
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
      appBar: AppBar(
        centerTitle: true,
        title: Text(AppStrings.aiFeatureGuideTitle),
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
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
          const SliverToBoxAdapter(child: _HeroCard()),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SectionTitle(title: AppStrings.aiGuideSectionCompanion),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => Padding(
                  padding: EdgeInsets.only(bottom: i < 3 ? 12 : 0),
                  child: _FeatureCard(spec: _kFeatures[i]),
                ),
                childCount: 4,
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SectionTitle(title: AppStrings.aiGuideSectionReview),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => Padding(
                  padding: EdgeInsets.only(bottom: i < 1 ? 12 : 0),
                  child: _FeatureCard(spec: _kFeatures[4 + i]),
                ),
                childCount: 2,
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }
}

// ─── Hero ─────────────────────────────────────────────────────────────────

class _HeroCard extends StatelessWidget {
  const _HeroCard();

  @override
  Widget build(BuildContext context) {
    return Selector<AiEngineConfigHolder, _HeroSnapshot>(
      selector: (_, h) => _HeroSnapshot(
        preset: h.config.preset.label,
        complete: h.config.isComplete,
      ),
      builder: (context, snap, _) {
        const radius =
            BorderRadius.all(Radius.circular(TurnaTheme.radiusXLarge));

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  TurnaTheme.amethystLeague,
                  TurnaTheme.brandTeal,
                ],
              ),
              borderRadius: radius,
              boxShadow: [
                BoxShadow(
                  color: TurnaTheme.amethystLeague.withValues(alpha: 0.25),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppStrings.aiGuideHeroTitle,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  AppStrings.aiGuideHeroSubtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.88),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _HeroChip(
                      icon: snap.complete
                          ? Icons.check_circle_rounded
                          : Icons.warning_amber_rounded,
                      label: snap.complete
                          ? AppStrings.aiGuideEngineConfigured(snap.preset)
                          : AppStrings.aiGuideEngineMissing,
                      warning: !snap.complete,
                    ),
                    _HeroChip(
                      icon: Icons.lock_outline_rounded,
                      label: AppStrings.aiGuidePrivacyChip,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HeroSnapshot {
  const _HeroSnapshot({required this.preset, required this.complete});
  final String preset;
  final bool complete;

  @override
  bool operator ==(Object other) =>
      other is _HeroSnapshot &&
      other.preset == preset &&
      other.complete == complete;

  @override
  int get hashCode => Object.hash(preset, complete);
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({
    required this.icon,
    required this.label,
    this.warning = false,
  });
  final IconData icon;
  final String label;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color:
            warning ? TurnaTheme.warning : Colors.white.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
        border: Border.all(
          color: Colors.white.withValues(alpha: warning ? 0.0 : 0.35),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
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

  final IconData icon;
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
    icon: Icons.chat_bubble_outline_rounded,
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
    icon: Icons.analytics_outlined,
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
    icon: Icons.bookmark_outline_rounded,
    accent: TurnaTheme.amethystLeague,
    title: AppStrings.aiGuideSavedTitle,
    purpose: AppStrings.aiGuideSavedPurpose,
    scenarios: AppStrings.aiGuideSavedScenarios,
    steps: AppStrings.aiGuideSavedSteps,
    tip: AppStrings.aiGuideSavedTip,
    open: _openSaved,
  ),
  // 4. 深度讲解
  _FeatureSpec(
    icon: Icons.account_tree_outlined,
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
    icon: Icons.history_toggle_off_rounded,
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
    icon: Icons.quiz_rounded,
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
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: TurnaTheme.cardBg(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(TurnaTheme.radiusXLarge),
      ),
    ),
    builder: (_) => const AiDepthTutorSheet(),
  );
}

void _openTutorMistakes(BuildContext context) {
  // TutorLaunchSheet 内部自带 mistakes/weakWords 切换；此处打开后用户
  // 默认进 mistakes。需要从 mistakes 直进时再补 initial 参数。
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: TurnaTheme.cardBg(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(TurnaTheme.radiusXLarge),
      ),
    ),
    builder: (_) => const TutorLaunchSheet(),
  );
}

void _openTutorWeak(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: TurnaTheme.cardBg(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(TurnaTheme.radiusXLarge),
      ),
    ),
    builder: (_) => const TutorLaunchSheet(),
  );
}

// ─── Feature card ─────────────────────────────────────────────────────────

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({required this.spec});
  final _FeatureSpec spec;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      accentColor: spec.accent,
      onTap: () => spec.open(context),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题行
            Row(
              children: [
                AccentIconChip(
                  icon: spec.icon,
                  color: spec.accent,
                  size: 22,
                  padding: 9,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    spec.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: spec.accent,
                        ),
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: TurnaTheme.brandTeal,
                ),
              ],
            ),
            const SizedBox(height: 14),
            // 作用
            _SectionLabel(
                label: AppStrings.aiGuideLabelPurpose, color: spec.accent),
            const SizedBox(height: 4),
            Text(
              spec.purpose,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: TurnaTheme.textPrimaryColor(context),
                    height: 1.55,
                  ),
            ),
            const SizedBox(height: 12),
            // 适用场景
            _SectionLabel(
                label: AppStrings.aiGuideLabelScenarios, color: spec.accent),
            const SizedBox(height: 4),
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
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: TurnaTheme.textSecondaryColor(context),
                              height: 1.5,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            // 操作流程
            _SectionLabel(
                label: AppStrings.aiGuideLabelSteps, color: spec.accent),
            const SizedBox(height: 4),
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
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: spec.accent,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        spec.steps[i],
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: TurnaTheme.textSecondaryColor(context),
                              height: 1.5,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            // 小贴士
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: spec.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.lightbulb_outline_rounded,
                    size: 16,
                    color: spec.accent,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      spec.tip,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3,
          ),
    );
  }
}
