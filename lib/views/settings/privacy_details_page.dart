// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';

// Project imports:
import 'package:turna/core/spacing.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/core/turna_icon_id.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/views/widgets/ambient_backdrop.dart';
import 'package:turna/views/widgets/turna_icon.dart';
import 'package:turna/views/widgets/turna_page_content.dart';
import 'package:turna/views/widgets/turna_reading_layout.dart';
import 'package:turna/views/widgets/turna_top_bar.dart';

/// 隐私详情页 — Settings → 关于 → 隐私详情 入口。
///
/// 内容按互联网隐私政策模板组织:
///   1. 概述 + 最后更新时间
///   2. 我们不收集什么
///   3. 数据存储(本地优先)
///   4. 网络访问 — 分两栏突出展示「非 AI 功能」与「AI 功能」，
///      后者明确说明联网行为取决于用户在 AI API 配置里选择的平台
///   5. 可选网络行为:外部链接
///   6. 你的权利与控制
///   7. 政策更新
///   8. 联系方式
///
/// 视觉语言与 `AboutTurnaPage` 一致（R18 长文阅读）:
///   - 纯白画布（ADR 0062：不再铺薄荷渐变，淡彩由卡片自身承载）
///   - [TurnaReadingCard] 纸面卡（`flatPaperDecoration`，长文不铺玻璃）
///   - [TurnaReadingSectionHeader] 走 sectionTitle 版面角色
///   - 网络访问两栏使用不同色温的 callout 区分「离线」与「可选联网」
///
/// 交互:
///   - 滚动超过 [kPillRevealOffset] 后,右下角的「透明度报告」条从底部滑上
///   - 点击跳到 [TransparencyLogPage](Turna 自己的透明日志)
@RoutePage()
class PrivacyDetailsPage extends StatefulWidget {
  const PrivacyDetailsPage({super.key});

  /// 滚动多少像素后浮现入口条。
  static const double kPillRevealOffset = 80;

  @override
  State<PrivacyDetailsPage> createState() => _PrivacyDetailsPageState();
}

class _PrivacyDetailsPageState extends State<PrivacyDetailsPage> {
  /// 入口条是否已浮现(只允许从 false -> true 单向翻,避免来回弹)。
  bool _pillVisible = false;

  bool _onScroll(ScrollNotification notification) {
    if (_pillVisible) return false;
    if (notification.metrics.pixels > PrivacyDetailsPage.kPillRevealOffset) {
      setState(() => _pillVisible = true);
    }
    return false;
  }

  void _openTransparencyLog() {
    context.router.push(const TransparencyLogRoute());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TurnaTheme.scaffoldBg(context),
      appBar: TurnaTopBar(title: AppStrings.privacyDetailsTitle),
      body: AmbientBackdrop(
        child: Stack(
          children: [
            Positioned.fill(
              child: NotificationListener<ScrollNotification>(
                onNotification: _onScroll,
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.pageMargin,
                    8,
                    AppSpacing.pageMargin,
                    24,
                  ),
                  child: TurnaPageContent(
                    maxWidth: AppSpacing.formColumnMaxWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _PrivacyHero(),
                        const SizedBox(height: 20),
                        TurnaReadingSectionHeader(
                          title: AppStrings.privacyDetailsOverviewTitle,
                        ),
                        TurnaReadingCard(
                          child: _SectionBody(
                            intro: AppStrings.privacyDetailsOverviewIntro,
                            body: AppStrings.privacyDetailsOverviewBody,
                          ),
                        ),
                        const SizedBox(height: 20),
                        TurnaReadingSectionHeader(
                          title: AppStrings.privacyDetailsNotCollectTitle,
                        ),
                        TurnaReadingCard(
                          child: _SectionBody(
                            intro: AppStrings.privacyDetailsNotCollectIntro,
                            body: AppStrings.privacyDetailsNotCollectBody,
                          ),
                        ),
                        const SizedBox(height: 20),
                        TurnaReadingSectionHeader(
                          title: AppStrings.privacyDetailsStorageTitle,
                        ),
                        TurnaReadingCard(
                          child: _SectionBody(
                            intro: AppStrings.privacyDetailsStorageIntro,
                            body: AppStrings.privacyDetailsStorageBody,
                          ),
                        ),
                        const SizedBox(height: 20),
                        TurnaReadingSectionHeader(
                          title: AppStrings.privacyDetailsNetworkTitle,
                        ),
                        _SectionIntro(
                          text: AppStrings.privacyDetailsNetworkIntro,
                        ),
                        const SizedBox(height: 10),
                        const _NetworkCalloutRow(),
                        const SizedBox(height: 20),
                        TurnaReadingSectionHeader(
                          title: AppStrings.privacyDetailsExternalLinksTitle,
                        ),
                        TurnaReadingCard(
                          child: _SectionBody(
                            intro: AppStrings.privacyDetailsExternalLinksIntro,
                            body: AppStrings.privacyDetailsExternalLinksBody,
                          ),
                        ),
                        const SizedBox(height: 20),
                        TurnaReadingSectionHeader(
                          title: AppStrings.privacyDetailsYourRightsTitle,
                        ),
                        TurnaReadingCard(
                          child: _SectionBody(
                            intro: AppStrings.privacyDetailsYourRightsIntro,
                            body: AppStrings.privacyDetailsYourRightsBody,
                          ),
                        ),
                        const SizedBox(height: 20),
                        TurnaReadingSectionHeader(
                          title: AppStrings.privacyDetailsUpdatesTitle,
                        ),
                        TurnaReadingCard(
                          child: _SectionBody(
                            intro: AppStrings.privacyDetailsUpdatesIntro,
                            body: AppStrings.privacyDetailsUpdatesBody,
                          ),
                        ),
                        const SizedBox(height: 20),
                        TurnaReadingSectionHeader(
                          title: AppStrings.privacyDetailsContactTitle,
                        ),
                        TurnaReadingCard(
                          child: _SectionBody(
                            intro: AppStrings.privacyDetailsContactIntro,
                            body: AppStrings.privacyDetailsContactBody,
                          ),
                        ),
                        // 给入口条留底部空间,避免覆盖最后一张卡片。
                        const SizedBox(height: 80),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: IgnorePointer(
                ignoring: !_pillVisible,
                child: AnimatedSlide(
                  offset: _pillVisible ? Offset.zero : const Offset(0, 1.6),
                  duration: const Duration(milliseconds: 360),
                  curve: Curves.easeOutCubic,
                  child: AnimatedOpacity(
                    opacity: _pillVisible ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 220),
                    child: _TransparencyHintPill(onTap: _openTransparencyLog),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 顶部 hero:盾牌图标 + 标题 + 一行导语 + 「最后更新」角标。
class _PrivacyHero extends StatelessWidget {
  const _PrivacyHero();

  @override
  Widget build(BuildContext context) {
    return TurnaReadingCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: TurnaTheme.brandTeal.withValues(alpha: 0.1),
              borderRadius: TurnaTheme.borderRadius,
            ),
            child: const TurnaIcon(
              TurnaIconId.shield,
              color: TurnaTheme.brandTeal,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppStrings.privacyDetailsTitle,
                  style: AppTextStyles.sectionTitle(context),
                ),
                const SizedBox(height: 2),
                Text(
                  AppStrings.privacyDetailsEntrySubtitle,
                  style: AppTextStyles.captionSm(context)
                      .copyWith(color: TurnaTheme.textSecondaryColor(context)),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TurnaReadingBadge(label: AppStrings.privacyDetailsLastUpdated),
        ],
      ),
    );
  }
}

/// 网络访问两栏:左侧「非 AI = 完全离线」,右侧「AI = 取决于平台」。
/// 视觉上用不同色温区分离线与免联网的可选联网。
class _NetworkCalloutRow extends StatelessWidget {
  const _NetworkCalloutRow();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 窄屏(手机)上下堆叠,宽屏(平板/桌面)左右并排
        final isWide = constraints.maxWidth >= 520;
        final left = _NetworkCallout(
          icon: TurnaIconId.cloudOff,
          tintColor: TurnaTheme.brandTeal,
          title: AppStrings.privacyDetailsNonAiTitle,
          intro: AppStrings.privacyDetailsNonAiIntro,
          body: AppStrings.privacyDetailsNonAiBody,
        );
        final right = _NetworkCallout(
          icon: TurnaIconId.spark,
          tintColor: TurnaTheme.brandSky,
          title: AppStrings.privacyDetailsAiTitle,
          intro: AppStrings.privacyDetailsAiIntro,
          body: AppStrings.privacyDetailsAiBody,
        );
        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: left),
              const SizedBox(width: 10),
              Expanded(child: right),
            ],
          );
        }
        return Column(children: [left, const SizedBox(height: 10), right]);
      },
    );
  }
}

/// 单个网络 callout:左侧色条 + 顶部 icon + 标题 + 简短导语 + 段落。
class _NetworkCallout extends StatelessWidget {
  final TurnaIconId icon;
  final Color tintColor;
  final String title;
  final String intro;
  final String body;

  const _NetworkCallout({
    required this.icon,
    required this.tintColor,
    required this.title,
    required this.intro,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    // Lift the accent toward white on dark surfaces — the raw deep green /
    // deep blue tints are near-invisible against the dark card fill.
    final accent = TurnaTheme.accentOnCard(context, tintColor);
    return Container(
      decoration: TurnaTheme.flatPaperDecoration(context),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: accent),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.12),
                            borderRadius: TurnaTheme.borderRadius,
                          ),
                          child: TurnaIcon(icon, color: accent, size: 20),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            title,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: TurnaTheme.textPrimaryColor(context),
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      intro,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        height: 1.5,
                        color: accent,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      body,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        height: 1.55,
                        color: TurnaTheme.textSecondaryColor(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 章节正文卡片的标准布局:导语(粗体强调一行)+ 详细正文。
/// 把「这一节在讲什么」前置,方便快速扫读。
class _SectionBody extends StatelessWidget {
  final String intro;
  final String body;

  const _SectionBody({required this.intro, required this.body});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionIntro(text: intro),
        const SizedBox(height: 8),
        _BodyText(text: body),
      ],
    );
  }
}

/// 1 行简短导语。放在章节正文顶部,稍粗、稍大,作为「这一节在讲什么」的快速入口。
class _SectionIntro extends StatelessWidget {
  final String text;

  const _SectionIntro({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTextStyles.cardTitle(context).copyWith(height: 1.5),
    );
  }
}

/// 标准段落文本。统一 1.55 行高,便于长文本阅读。
class _BodyText extends StatelessWidget {
  final String text;

  const _BodyText({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTextStyles.bodyText(context)
          .copyWith(color: TurnaTheme.textSecondaryColor(context)),
    );
  }
}

/// 滚动后从底部浮出的「透明度报告」入口条（4px Bauhaus 几何块）。
class _TransparencyHintPill extends StatelessWidget {
  final VoidCallback onTap;

  const _TransparencyHintPill({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: TurnaTheme.borderRadius,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: TurnaTheme.brandTeal,
            borderRadius: TurnaTheme.borderRadius,
            border: Border.all(
              color: TurnaTheme.textOnPrimary.withValues(alpha: 0.16),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: TurnaTheme.textOnPrimary.withValues(alpha: 0.18),
                  borderRadius: TurnaTheme.borderRadius,
                ),
                child: const TurnaIcon(
                  TurnaIconId.eye,
                  color: TurnaTheme.textOnPrimary,
                  size: 16,
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  AppStrings.transparencyPillHint,
                  style: AppTextStyles.captionSm(context).copyWith(
                    color: TurnaTheme.textOnPrimary,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              const TurnaIcon(
                TurnaIconId.arrowForward,
                color: TurnaTheme.textOnPrimary,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
