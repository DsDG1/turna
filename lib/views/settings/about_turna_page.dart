// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:share_plus/share_plus.dart';

// Project imports:
import 'package:turna/application/anki_official/official_anki_license_notices.dart';
import 'package:turna/application/settings/app_build_info.dart';
import 'package:turna/application/settings/external_link_registry.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/views/settings/changelog_page.dart';
import 'package:turna/core/spacing.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/views/widgets/turna_page_content.dart';
import 'package:turna/views/widgets/turna_snack_bar.dart';

/// Dedicated About page for Turna (Plan 2 §7.1).
///
/// Two tabs only:
///   - **关于** (`_AboutTab`): brand hero, what Turna is, highlights, one
///     integrated links-and-resources card, privacy, credits.
///   - **更新日志** (`ChangelogFromAsset`): offline changelog.
///
/// The former 使用指南 tab was removed with its asset/parser (dead resource
/// per Plan 2 §4.8). All external links resolve through
/// [ExternalLinkRegistry]: unconfigured links render disabled with a reason
/// instead of dead-tapping a guessed legacy URL, and launch failures offer a
/// copy-address fallback.
///
/// The 配套工具 section (desktop GUI editor, content CLI) was removed: those
/// are authoring tools, not app features, and an About page that lists a
/// download the build cannot verify is a promise the app cannot keep. The
/// content-authoring entry point still carries its own GUI link, which is
/// where a creator would look for it.
@RoutePage()
class AboutTurnaPage extends StatelessWidget {
  const AboutTurnaPage({super.key, this.buildInfo});

  /// Test seam; production resolves from PackageInfo.
  final AppBuildInfo? buildInfo;

  Future<void> _shareApp(BuildContext context) async {
    await Share.share(AppStrings.aboutShareText);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: TurnaTheme.scaffoldBg(context),
        appBar: AppBar(
          title: Text(
            AppStrings.aboutTitle,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: Container(
              color: TurnaTheme.scaffoldBg(context),
              child: TabBar(
                indicatorColor: TurnaTheme.brandTeal,
                indicatorWeight: 3,
                labelColor: TurnaTheme.brandTeal,
                unselectedLabelColor: TurnaTheme.textHintColor(context),
                labelStyle: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                tabs: [
                  Tab(text: AppStrings.aboutTabAbout),
                  Tab(text: AppStrings.aboutTabChangelog),
                ],
              ),
            ),
          ),
        ),
        body: Container(
          decoration: BoxDecoration(
            gradient: TurnaTheme.courseTreeGradientFor(context),
          ),
          child: TabBarView(
            children: [
              _AboutTab(
                buildInfo: buildInfo,
                onShare: _shareApp,
              ),
              const ChangelogFromAsset(),
            ],
          ),
        ),
      ),
    );
  }
}

/// "关于"Tab 内容：品牌头、亮点、链接、隐私、致谢。
class _AboutTab extends StatelessWidget {
  const _AboutTab({this.buildInfo, required this.onShare});

  final AppBuildInfo? buildInfo;

  /// Registry injection seam for widget tests (five launch states).
  final ExternalLinkRegistry linkRegistry = const ExternalLinkRegistry();

  final Future<void> Function(BuildContext) onShare;

  @override
  Widget build(BuildContext context) {
    final year = DateTime.now().year;
    return TurnaPageContent(
      maxWidth: AppSpacing.formColumnMaxWidth,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.pageMargin, 12, AppSpacing.pageMargin, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _HeroCard(buildInfo: buildInfo),
            const SizedBox(height: 20),
            _SectionHeader(text: AppStrings.aboutWhatIsTitle),
            const SizedBox(height: 10),
            _AboutCard(
              child: Text(
                AppStrings.aboutWhatIsBody,
                style: AppTextStyles.bodyText(context).copyWith(
                  color: TurnaTheme.textSecondaryColor(context),
                ),
              ),
            ),
            const SizedBox(height: 20),
            _SectionHeader(text: AppStrings.aboutHighlightsTitle),
            const SizedBox(height: 10),
            const _HighlightsCard(),
            const SizedBox(height: 20),
            _SectionHeader(text: AppStrings.aboutLinksTitle),
            const SizedBox(height: 10),
            _AboutCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _LinkTile(
                    icon: Icons.code_rounded,
                    title: AppStrings.settingsOpenSourceLicenses,
                    onTap: () => showTurnaLicensePage(
                      context: context,
                      applicationVersion: AppBuildInfo.unknownVersion,
                    ),
                  ),
                  _LinkDivider(),
                  _ExternalLinkTile(
                    registry: linkRegistry,
                    id: ExternalLinkId.projectHome,
                    icon: Icons.open_in_new_rounded,
                    title: AppStrings.aboutUpstreamTitle,
                    configuredSubtitle: AppStrings.aboutUpstreamSubtitle,
                  ),
                  _LinkDivider(),
                  _ExternalLinkTile(
                    registry: linkRegistry,
                    id: ExternalLinkId.issueTracker,
                    icon: Icons.bug_report_rounded,
                    title: AppStrings.aboutReportIssueTitle,
                    configuredSubtitle: AppStrings.aboutReportIssueSubtitle,
                  ),
                  _LinkDivider(),
                  _ExternalLinkTile(
                    registry: linkRegistry,
                    id: ExternalLinkId.releaseNotes,
                    icon: Icons.new_releases_rounded,
                    title: AppStrings.aboutViewReleasesTitle,
                    configuredSubtitle: AppStrings.aboutViewReleasesSubtitle,
                  ),
                  _LinkDivider(),
                  _LinkTile(
                    icon: Icons.share_rounded,
                    title: AppStrings.aboutShareTitle,
                    onTap: () => onShare(context),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                AppStrings.aboutLinksNotConfiguredNote,
                style: AppTextStyles.captionSm(context).copyWith(
                  color: TurnaTheme.textHintColor(context),
                ),
              ),
            ),
            const SizedBox(height: 20),
            _SectionHeader(text: AppStrings.aboutPrivacyTitle),
            const SizedBox(height: 10),
            _PrivacyTile(),
            const SizedBox(height: 20),
            _SectionHeader(text: AppStrings.aboutCreditsTitle),
            const SizedBox(height: 10),
            _AboutCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppStrings.aboutCreditsOriginal,
                    style: AppTextStyles.bodyText(context).copyWith(
                      color: TurnaTheme.textSecondaryColor(context),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    AppStrings.aboutCreditsFork,
                    style: AppTextStyles.bodyText(context).copyWith(
                      color: TurnaTheme.textSecondaryColor(context),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    AppStrings.aboutLicense,
                    style: AppTextStyles.captionSm(context).copyWith(
                      color: TurnaTheme.textHintColor(context),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            Center(
              child: Text(
                AppStrings.aboutCopyright(year.toString()),
                style: AppTextStyles.captionSm(context).copyWith(
                  color: TurnaTheme.textHintColor(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 区块标题：与隐私长文页共用同一个 sectionTitle 角色（R18 阅读语）。
class _SectionHeader extends StatelessWidget {
  final String text;

  const _SectionHeader({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(text, style: AppTextStyles.sectionTitle(context));
  }
}

/// Brand hero: the identity strip and the three facts worth reading first.
///
/// The version moved out of its own section and into the hero chip — the page
/// used to repeat it in the header *and* in a dedicated card two screens down,
/// which made a build number the most redundant thing on an About page.
class _HeroCard extends StatelessWidget {
  const _HeroCard({this.buildInfo});

  final AppBuildInfo? buildInfo;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppBuildInfo>(
      future: buildInfo != null ? Future.value(buildInfo) : AppBuildInfo.load(),
      builder: (context, snapshot) {
        // No hardcoded fallback number: unknown stays "未知版本".
        final info = snapshot.data ??
            const AppBuildInfo(
              versionName: AppBuildInfo.unknownVersion,
              buildNumber: '',
            );
        final displayVersion = info.buildNumber.isEmpty
            ? info.versionName
            : '${info.versionName} (${info.buildNumber})';

        return Container(
          width: double.infinity,
          // R18 阅读语：品牌开篇也走纸面；身份感由 clay+sand 色带与
          // 图标井承担，不靠玻璃浮起。
          decoration: TurnaTheme.flatPaperDecoration(context),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              // Decorative bloom, sized off the card so it never drives layout.
              Positioned(
                right: -28,
                top: -34,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: TurnaTheme.brandTeal.withValues(alpha: 0.10),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Clay + sand brand strip: the one piece of the old header
                    // that is worth keeping — it is the app's identity pair,
                    // and the palette contract pins it here.
                    Container(
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        gradient: LinearGradient(
                          colors: [
                            TurnaTheme.anatolianClay,
                            TurnaTheme.warmSand.withValues(alpha: 0.95),
                          ],
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: TurnaTheme.brandTeal.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(
                              TurnaTheme.radiusMedium,
                            ),
                          ),
                          child: const Icon(
                            Icons.school_rounded,
                            color: TurnaTheme.anatolianClay,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                AppStrings.aboutBrandName,
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.2,
                                  color: TurnaTheme.textPrimaryColor(context),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                AppStrings.aboutTagline,
                                style: AppTextStyles.captionSm(context),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: TurnaTheme.brandTeal,
                            borderRadius:
                                BorderRadius.circular(TurnaTheme.radiusRound),
                          ),
                          child: Text(
                            displayVersion,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: TurnaTheme.textOnPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Divider(
                      height: 1,
                      color: TurnaTheme.dividerBg(context),
                    ),
                    const SizedBox(height: 12),
                    const Wrap(
                      spacing: 16,
                      runSpacing: 8,
                      children: [
                        _HeroFact(
                          icon: Icons.wifi_off_rounded,
                          label: '离线可用',
                        ),
                        _HeroFact(
                          icon: Icons.phonelink_lock_rounded,
                          label: '数据不出本机',
                        ),
                        _HeroFact(
                          icon: Icons.volunteer_activism_rounded,
                          label: '开源免费',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HeroFact extends StatelessWidget {
  final IconData icon;
  final String label;

  const _HeroFact({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: TurnaTheme.brandTeal),
        const SizedBox(width: 5),
        Text(label, style: AppTextStyles.captionSm(context)),
      ],
    );
  }
}

/// The three highlights in one card rather than three floating chips: the
/// page already has a card per section, and three separate bordered boxes at
/// the same weight as the surrounding content read as three more sections.
class _HighlightsCard extends StatelessWidget {
  const _HighlightsCard();

  static final _highlights = [
    (
      icon: Icons.cloud_off_rounded,
      title: AppStrings.aboutHighlightOfflineTitle,
      subtitle: AppStrings.aboutHighlightOfflineSubtitle,
    ),
    (
      icon: Icons.psychology_rounded,
      title: AppStrings.aboutHighlightSrsTitle,
      subtitle: AppStrings.aboutHighlightSrsSubtitle,
    ),
    (
      icon: Icons.quiz_rounded,
      title: AppStrings.aboutHighlightInteractionsTitle,
      subtitle: AppStrings.aboutHighlightInteractionsSubtitle,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return _AboutCard(
      child: Builder(builder: (context) {
        // Wrap instead of a fixed 3-column Row: at 200% text scale or on
        // narrow screens the items flow onto extra lines instead of
        // overflowing (Plan §14.4).
        final screenWidth = MediaQuery.sizeOf(context).width;
        final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
        final singleColumn = screenWidth < 520 || largeText;
        final itemWidth =
            singleColumn ? double.infinity : (screenWidth - 32 - 32 - 20) / 3;
        return Wrap(
          spacing: 10,
          runSpacing: 14,
          children: [
            for (final highlight in _highlights)
              SizedBox(
                width: itemWidth,
                child: _HighlightItem(
                  icon: highlight.icon,
                  title: highlight.title,
                  subtitle: highlight.subtitle,
                  centered: !singleColumn,
                ),
              ),
          ],
        );
      }),
    );
  }
}

class _HighlightItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool centered;

  const _HighlightItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.centered,
  });

  @override
  Widget build(BuildContext context) {
    final textAlign = centered ? TextAlign.center : TextAlign.start;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: TurnaTheme.brandTeal.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
          ),
          child: Icon(icon, color: TurnaTheme.brandTeal, size: 21),
        ),
        const SizedBox(height: 8),
        Text(
          title,
          textAlign: textAlign,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.cardTitle(context),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          textAlign: textAlign,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.captionSm(context).copyWith(
            color: TurnaTheme.textHintColor(context),
          ),
        ),
      ],
    );
  }
}

/// Privacy as an entry point, not a wall of text: the summary is one line and
/// the detail lives on the page that exists for it.
class _PrivacyTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _AboutCard(
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
        child: InkWell(
          borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
          onTap: () => context.router.push(const PrivacyDetailsRoute()),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: TurnaTheme.brandTeal.withValues(alpha: 0.08),
                    borderRadius:
                        BorderRadius.circular(TurnaTheme.radiusMedium),
                  ),
                  child: const Icon(
                    Icons.shield_outlined,
                    color: TurnaTheme.brandTeal,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppStrings.aboutPrivacySummary,
                        style: AppTextStyles.cardTitle(context),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        AppStrings.aboutPrivacyOpenDetails,
                        style: AppTextStyles.captionSm(context).copyWith(
                          color: TurnaTheme.brandTeal,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: TurnaTheme.textHint.withValues(alpha: 0.6),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 通用内容卡片（R18 长文阅读）：纸面（实色 + 中性细边），长文不铺玻璃。
class _AboutCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _AboutCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: TurnaTheme.flatPaperDecoration(context),
      child: child,
    );
  }
}

/// Registry-driven external link row: disabled with a visible reason when the
/// URL is unconfigured (never a fake clickable link), otherwise launches via
/// [openExternalLink] which surfaces failures with a copy-address fallback.
class _ExternalLinkTile extends StatelessWidget {
  const _ExternalLinkTile({
    required this.registry,
    required this.id,
    required this.icon,
    required this.title,
    required this.configuredSubtitle,
  });

  final ExternalLinkRegistry registry;
  final ExternalLinkId id;
  final IconData icon;
  final String title;

  /// Subtitle shown when the link is configured.
  final String configuredSubtitle;

  @override
  Widget build(BuildContext context) {
    final descriptor = registry.describe(id);
    final subtitle =
        descriptor.enabled ? configuredSubtitle : descriptor.unavailableReason;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
      child: InkWell(
        borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
        onTap: descriptor.enabled
            ? () => openExternalLink(context, id, registry: registry)
            // Disabled links still explain themselves on tap instead of
            // silently doing nothing.
            : () => TurnaSnackBar.show(
                  context,
                  descriptor.unavailableReason,
                ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: TurnaTheme.brandTeal.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
                ),
                child: Icon(
                  icon,
                  color: descriptor.enabled
                      ? TurnaTheme.brandTeal
                      : TurnaTheme.textHintColor(context),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.cardTitle(context).copyWith(
                        color: descriptor.enabled
                            ? TurnaTheme.textPrimaryColor(context)
                            : TurnaTheme.textHintColor(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.captionSm(context).copyWith(
                        color: TurnaTheme.textHintColor(context),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                descriptor.enabled
                    ? Icons.chevron_right_rounded
                    : Icons.lock_outline_rounded,
                size: 20,
                color: TurnaTheme.textHint.withValues(alpha: 0.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LinkTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback? onTap;

  const _LinkTile({
    required this.icon,
    required this.title,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
      child: InkWell(
        borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: TurnaTheme.brandTeal.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
                ),
                child: Icon(
                  icon,
                  color: TurnaTheme.brandTeal,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.cardTitle(context),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: TurnaTheme.textHint.withValues(alpha: 0.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LinkDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      indent: 64,
      endIndent: 16,
      color: TurnaTheme.dividerBg(context),
    );
  }
}
