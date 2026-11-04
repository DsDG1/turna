// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/accessibility_provider.dart';
import 'package:turna/application/language_provider.dart';
import 'package:turna/application/settings/app_build_info.dart';
import 'package:turna/application/settings/settings_destination.dart';
import 'package:turna/application/theme_provider.dart';
import 'package:turna/core/spacing.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/widgets/directory_rows.dart';

Future<AppBuildInfo>? _settingsLandingBuildInfoFuture;

Future<AppBuildInfo> _loadSettingsLandingBuildInfo() =>
    _settingsLandingBuildInfoFuture ??= AppBuildInfo.load();

/// Settings landing page（「湿地雾光」R16 偏好目录）。
///
/// 落地页 = 三条高频偏好胶囊（语言 / 主题 / 字号，名称 + 当前值）→ 图标
/// 目录行（[DirectoryLinkRow]，图标井取域色相）→ 页脚关于链接。导航身份
/// 仍来自 [SettingsDestination]；昂贵工作（备份发现、存储扫描、诊断）归
/// 各目标页所有。
///
/// 页头为**页内** pageTitle 开篇——Tab 级 `SettingsAppBar` 已退役，外层
/// [HomePage] 的 AppBar 槽位由 `TabBodySpacer` 占住状态栏条。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  static const _experienceDestinations = [
    SettingsDestination.account,
    SettingsDestination.learning,
    SettingsDestination.appearanceAndSound,
    SettingsDestination.accessibility,
  ];

  static const _systemDestinations = [
    SettingsDestination.dataAndBackup,
    SettingsDestination.advanced,
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TurnaTheme.scaffoldBg(context),
      body: CustomScrollView(
        key: const PageStorageKey<String>('settings-landing-list'),
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: AppSpacing.sm + 4),
                    Padding(
                      padding: AppSpacing.pageGutterMist,
                      child: Text(
                        AppStrings.settingsTitle,
                        style: AppTextStyles.pageTitle(context),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    const _QuickPreferenceCapsules(),
                    const SizedBox(height: AppSpacing.xl),
                    _LandingSectionTitle(
                      title: AppStrings.settingsGroupLearning,
                    ),
                    _DestinationRows(destinations: _experienceDestinations),
                    const SizedBox(height: AppSpacing.xl),
                    _LandingSectionTitle(
                      title: AppStrings.settingsGroupDataSystem,
                    ),
                    _DestinationRows(destinations: _systemDestinations),
                    const SizedBox(height: AppSpacing.xl),
                    const _AboutFooterRow(),
                    SizedBox(
                      height: AppSpacing.xl + MediaQuery.paddingOf(context).bottom,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 三条高频偏好胶囊：名称 + 当前值，点击直达对应深页。
class _QuickPreferenceCapsules extends StatelessWidget {
  const _QuickPreferenceCapsules();

  @override
  Widget build(BuildContext context) {
    final language = context.select<LanguageProvider, String>(
      (provider) => provider.displayName,
    );
    final themeMode = context.select<ThemeProvider, ThemeMode>(
      (provider) => provider.themeMode,
    );
    final textScale = context.select<AccessibilityProvider, int>(
      (provider) => provider.textScale,
    );

    final capsules = [
      (
        label: AppStrings.settingsLearningLanguageTitle,
        value: language,
        icon: Icons.language_rounded,
        route: SettingsDestination.learning.route,
      ),
      (
        label: AppStrings.settingsLandingThemeTitle,
        value: _themeLabel(themeMode),
        icon: Icons.contrast_rounded,
        route: SettingsDestination.appearanceAndSound.route,
      ),
      (
        label: AppStrings.settingsTextSizeTitle,
        value: AppStrings.settingsTextSizeValue(textScale),
        icon: Icons.text_fields_rounded,
        route: SettingsDestination.accessibility.route,
      ),
    ];

    return Padding(
      padding: AppSpacing.pageGutterMist,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final textScaleFactor = MediaQuery.textScalerOf(context).scale(1);
          // 200% 字号下纵向堆叠，胶囊结构与分区动作带保持不变。
          final useColumn =
              textScaleFactor > 1.4 || constraints.maxWidth < 320;
          if (useColumn) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < capsules.length; i++) ...[
                  if (i > 0) const SizedBox(height: AppSpacing.sm),
                  _PreferenceCapsule(capsule: capsules[i], expanded: true),
                ],
              ],
            );
          }
          return Row(
            children: [
              for (var i = 0; i < capsules.length; i++) ...[
                if (i > 0) const SizedBox(width: AppSpacing.sm),
                Expanded(child: _PreferenceCapsule(capsule: capsules[i])),
              ],
            ],
          );
        },
      ),
    );
  }

  static String _themeLabel(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.light => AppStrings.settingsThemeLight,
      ThemeMode.dark => AppStrings.settingsThemeDark,
      ThemeMode.system => AppStrings.settingsThemeSystem,
    };
  }
}

typedef _CapsuleData = ({
  String label,
  String value,
  IconData icon,
  PageRouteInfo route,
});

class _PreferenceCapsule extends StatelessWidget {
  const _PreferenceCapsule({required this.capsule, this.expanded = false});

  final _CapsuleData capsule;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    return Material(
      // 偏好胶囊走纸面（ADR 0065）：实色 + 中性细边，不铺玻璃。
      color: TurnaTheme.cardBg(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(TurnaTheme.cardRadius),
        side: BorderSide(color: TurnaTheme.dividerBg(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('settings-quick-${capsule.label}'),
        onTap: () => context.router.push(capsule.route),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm + 2,
          ),
          child: Row(
            mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
            children: [
              Icon(
                capsule.icon,
                size: 16,
                color: TurnaTheme.textSecondaryColor(context),
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      capsule.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.captionSm(context).copyWith(
                        color: TurnaTheme.textSecondaryColor(context),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs - 2),
                    Text(
                      capsule.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyText(context).copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: TurnaTheme.brandTealDark,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LandingSectionTitle extends StatelessWidget {
  const _LandingSectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pageMargin,
        0,
        AppSpacing.pageMargin,
        AppSpacing.md,
      ),
      child: Text(title, style: AppTextStyles.sectionTitle(context)),
    );
  }
}

/// 图标目录行组：图标井取域色相（R16 偏好目录）。
class _DestinationRows extends StatelessWidget {
  const _DestinationRows({required this.destinations});

  final List<SettingsDestination> destinations;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: AppSpacing.pageGutterMist,
      child: Column(
        children: [
          for (final destination in destinations)
            DirectoryLinkRow(
              key: ValueKey(destination.name),
              icon: destination.icon,
              iconTone: _toneFor(destination),
              title: destination.title,
              description: destination.subtitle,
              onTap: () => context.router.push(destination.route),
            ),
        ],
      ),
    );
  }

  static Color _toneFor(SettingsDestination destination) {
    return switch (destination) {
      SettingsDestination.account => TurnaTheme.brandTeal,
      SettingsDestination.learning => TurnaTheme.brandTeal,
      SettingsDestination.appearanceAndSound => TurnaTheme.anatolianClay,
      SettingsDestination.accessibility => TurnaTheme.brandSky,
      SettingsDestination.dataAndBackup => TurnaTheme.brandNavy,
      SettingsDestination.advanced => TurnaTheme.textSecondary,
      SettingsDestination.about => TurnaTheme.brandTeal,
    };
  }
}

/// 页脚关于链接：值右对齐显示版本号。
class _AboutFooterRow extends StatelessWidget {
  const _AboutFooterRow();

  @override
  Widget build(BuildContext context) {
    const destination = SettingsDestination.about;
    final showVersion = MediaQuery.textScalerOf(context).scale(1) <= 1.3;
    return Padding(
      padding: AppSpacing.pageGutterMist,
      child: FutureBuilder<AppBuildInfo>(
        future: showVersion ? _loadSettingsLandingBuildInfo() : null,
        builder: (context, snapshot) => DirectoryValueRow(
          key: const ValueKey('settings-about-footer'),
          label: destination.title,
          value: showVersion
              ? (snapshot.data?.versionName ?? AppBuildInfo.unknownVersion)
              : null,
          onTap: () => context.router.push(destination.route),
        ),
      ),
    );
  }
}
