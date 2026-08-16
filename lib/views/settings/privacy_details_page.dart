// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/settings/transparency_log_page.dart';
import 'package:turna/views/theme.dart';

/// 隐私详情页 — Settings → 关于 → 隐私详情 入口。
///
/// 内容按互联网隐私政策模板组织:
///   1. 概述 + 最后更新时间
///   2. 我们不收集什么
///   3. 数据存储(本地优先)
///   4. 网络访问 ⭐ — 分两栏突出展示「非 AI 功能」与「AI 功能」,
///      后者明确说明联网行为取决于用户在 AI API 配置里选择的平台
///   5. 可选网络行为:外部链接
///   6. 你的权利与控制
///   7. 政策更新
///   8. 联系方式
///
/// 视觉语言与 `AboutTurnaPage` 一致:
///   - `courseTreeGradientFor` 薄荷渐变背景
///   - `_AboutCard` 圆角白卡 + 1px 边框 + `softShadow`
///   - `_SectionHeader` 短 teal 横条 + 小标题
///   - 网络访问两栏使用不同色温的 callout 区分「离线」与「可选联网」
///
/// 交互:
///   - 滚动超过 [kPillRevealOffset] 后,右下角的「透明度报告」药丸从底部滑上
///   - 点击药丸跳到 [TransparencyLogPage](Turna 自己的透明日志)
class PrivacyDetailsPage extends StatefulWidget {
  const PrivacyDetailsPage({super.key});

  /// 滚动多少像素后浮现药丸。
  static const double kPillRevealOffset = 80;

  @override
  State<PrivacyDetailsPage> createState() => _PrivacyDetailsPageState();
}

class _PrivacyDetailsPageState extends State<PrivacyDetailsPage> {
  /// 药丸是否已浮现(只允许从 false -> true 单向翻,避免来回弹)。
  bool _pillVisible = false;

  bool _onScroll(ScrollNotification notification) {
    if (_pillVisible) return false;
    if (notification.metrics.pixels > PrivacyDetailsPage.kPillRevealOffset) {
      setState(() => _pillVisible = true);
    }
    return false;
  }

  void _openTransparencyLog() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const TransparencyLogPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TurnaTheme.scaffoldBg(context),
      appBar: AppBar(
        title: Text(
          AppStrings.privacyDetailsTitle,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: TurnaTheme.courseTreeGradientFor(context),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: NotificationListener<ScrollNotification>(
                onNotification: _onScroll,
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _PrivacyHero(),
                      const SizedBox(height: 20),
                      _SectionHeader(
                          text: AppStrings.privacyDetailsOverviewTitle),
                      const SizedBox(height: 10),
                      _AboutCard(
                        child: _SectionBody(
                          intro: AppStrings.privacyDetailsOverviewIntro,
                          body: AppStrings.privacyDetailsOverviewBody,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _SectionHeader(
                          text: AppStrings.privacyDetailsNotCollectTitle),
                      const SizedBox(height: 10),
                      _AboutCard(
                        child: _SectionBody(
                          intro: AppStrings.privacyDetailsNotCollectIntro,
                          body: AppStrings.privacyDetailsNotCollectBody,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _SectionHeader(
                          text: AppStrings.privacyDetailsStorageTitle),
                      const SizedBox(height: 10),
                      _AboutCard(
                        child: _SectionBody(
                          intro: AppStrings.privacyDetailsStorageIntro,
                          body: AppStrings.privacyDetailsStorageBody,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _SectionHeader(
                          text: AppStrings.privacyDetailsNetworkTitle),
                      const SizedBox(height: 4),
                      _SectionIntro(
                          text: AppStrings.privacyDetailsNetworkIntro),
                      const SizedBox(height: 10),
                      const _NetworkCalloutRow(),
                      const SizedBox(height: 20),
                      _SectionHeader(
                          text: AppStrings
                              .privacyDetailsExternalLinksTitle),
                      const SizedBox(height: 10),
                      _AboutCard(
                        child: _SectionBody(
                          intro: AppStrings.privacyDetailsExternalLinksIntro,
                          body: AppStrings.privacyDetailsExternalLinksBody,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _SectionHeader(
                          text: AppStrings.privacyDetailsYourRightsTitle),
                      const SizedBox(height: 10),
                      _AboutCard(
                        child: _SectionBody(
                          intro: AppStrings.privacyDetailsYourRightsIntro,
                          body: AppStrings.privacyDetailsYourRightsBody,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _SectionHeader(
                          text: AppStrings.privacyDetailsUpdatesTitle),
                      const SizedBox(height: 10),
                      _AboutCard(
                        child: _SectionBody(
                          intro: AppStrings.privacyDetailsUpdatesIntro,
                          body: AppStrings.privacyDetailsUpdatesBody,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _SectionHeader(
                          text: AppStrings.privacyDetailsContactTitle),
                      const SizedBox(height: 10),
                      _AboutCard(
                        child: _SectionBody(
                          intro: AppStrings.privacyDetailsContactIntro,
                          body: AppStrings.privacyDetailsContactBody,
                        ),
                      ),
                      // 给药丸留底部空间,避免覆盖最后一张卡片。
                      const SizedBox(height: 80),
                    ],
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
                  offset:
                      _pillVisible ? Offset.zero : const Offset(0, 1.6),
                  duration: const Duration(milliseconds: 360),
                  curve: Curves.easeOutCubic,
                  child: AnimatedOpacity(
                    opacity: _pillVisible ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 220),
                    child: _TransparencyHintPill(
                      onTap: _openTransparencyLog,
                    ),
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
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: TurnaTheme.cardBg(context),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
        border: Border.all(color: TurnaTheme.statCardBorder(context)),
        boxShadow: TurnaTheme.softShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 顶部 teal 装饰条,与品牌色一致
          Container(
            height: 4,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  TurnaTheme.brandTeal,
                  TurnaTheme.brandTeal.withValues(alpha: 0.6),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: TurnaTheme.brandTeal.withValues(alpha: 0.1),
                    borderRadius:
                        BorderRadius.circular(TurnaTheme.radiusMedium),
                  ),
                  child: const Icon(
                    Icons.shield_outlined,
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
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: TurnaTheme.textPrimaryColor(context),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        AppStrings.privacyDetailsEntrySubtitle,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: TurnaTheme.textSecondaryColor(context),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // 最后更新角标
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: TurnaTheme.brandTeal.withValues(alpha: 0.1),
                    borderRadius:
                        BorderRadius.circular(TurnaTheme.radiusRound),
                  ),
                  child: Text(
                    AppStrings.privacyDetailsLastUpdated,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: TurnaTheme.brandTeal,
                    ),
                  ),
                ),
              ],
            ),
          ),
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
          icon: Icons.cloud_off_rounded,
          tintColor: const Color(0xFF2E7D32), // 深绿
          title: AppStrings.privacyDetailsNonAiTitle,
          intro: AppStrings.privacyDetailsNonAiIntro,
          body: AppStrings.privacyDetailsNonAiBody,
        );
        final right = _NetworkCallout(
          icon: Icons.hub_outlined,
          tintColor: const Color(0xFF1565C0), // 深蓝
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
        return Column(
          children: [
            left,
            const SizedBox(height: 10),
            right,
          ],
        );
      },
    );
  }
}

/// 单个网络 callout:左侧色条 + 顶部 icon + 标题 + 简短导语 + 段落。
class _NetworkCallout extends StatelessWidget {
  final IconData icon;
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
    return Container(
      decoration: BoxDecoration(
        color: TurnaTheme.cardBg(context),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
        border: Border.all(color: TurnaTheme.statCardBorder(context)),
        boxShadow: TurnaTheme.softShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: tintColor),
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
                            color: tintColor.withValues(alpha: 0.12),
                            borderRadius:
                                BorderRadius.circular(TurnaTheme.radiusMedium),
                          ),
                          child: Icon(icon, color: tintColor, size: 20),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            title,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
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
                            color: tintColor,
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
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            height: 1.5,
            color: TurnaTheme.textPrimaryColor(context),
          ),
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
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            height: 1.55,
            color: TurnaTheme.textSecondaryColor(context),
          ),
    );
  }
}

/// 短 teal 横条 + 小标题 — 与 About / 新手页面保持节奏一致。
class _SectionHeader extends StatelessWidget {
  final String text;

  const _SectionHeader({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 18,
            decoration: BoxDecoration(
              color: TurnaTheme.brandTeal.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            text,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: TurnaTheme.textSecondaryColor(context),
                ),
          ),
        ],
      ),
    );
  }
}

/// 通用内容卡片:cardBg + 1px 边框 + softShadow + 16 圆角。
class _AboutCard extends StatelessWidget {
  final Widget child;

  const _AboutCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TurnaTheme.cardBg(context),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
        border: Border.all(color: TurnaTheme.statCardBorder(context)),
        boxShadow: TurnaTheme.softShadow,
      ),
      child: child,
    );
  }
}

/// 滚动后从底部浮出的「透明度报告」药丸。
///
/// 视觉:teal 主色 + 白字 + 圆角药丸,带 visibility 图标与简短的引导文字。
/// 点击进入 [TransparencyLogPage]。
class _TransparencyHintPill extends StatelessWidget {
  final VoidCallback onTap;

  const _TransparencyHintPill({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(TurnaTheme.radiusRound),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: TurnaTheme.brandTeal,
            borderRadius: BorderRadius.circular(TurnaTheme.radiusRound),
            boxShadow: [
              BoxShadow(
                color: TurnaTheme.brandTeal.withValues(alpha: 0.32),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius:
                      BorderRadius.circular(TurnaTheme.radiusMedium),
                ),
                child: const Icon(
                  Icons.visibility_outlined,
                  color: Colors.white,
                  size: 16,
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  AppStrings.transparencyPillHint,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.arrow_forward_rounded,
                color: Colors.white,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
