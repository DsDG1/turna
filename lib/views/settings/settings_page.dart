// Flutter imports:
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';

// Project imports:
import 'package:turna/application/accessibility_provider.dart';
import 'package:turna/application/language_provider.dart';
import 'package:turna/application/settings/app_build_info.dart';
import 'package:turna/application/settings/settings_destination.dart';
import 'package:turna/application/settings_provider.dart';
import 'package:turna/application/theme_provider.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/auth/local_user.dart';
import 'package:turna/domain/cosmetics/avatar.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/service/locator.dart';
import 'package:turna/views/settings/widgets/settings_common.dart';
import 'package:turna/views/theme.dart';
import 'package:turna/views/widgets/avatar_with_ring.dart';

Future<AppBuildInfo>? _settingsLandingBuildInfoFuture;

Future<AppBuildInfo> _loadSettingsLandingBuildInfo() =>
    _settingsLandingBuildInfoFuture ??= AppBuildInfo.load();

/// Settings landing page.
///
/// The landing surface deliberately shows navigation and lightweight current
/// values only. Expensive work (backup discovery, storage scans, diagnostics)
/// remains owned by the destination pages. Formal navigation identity still
/// comes from [SettingsDestination]; the visual hierarchy here can evolve
/// without breaking deep links.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  static const _experienceDestinations = [
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
      appBar: AppBar(
        backgroundColor: TurnaTheme.scaffoldBg(context),
        elevation: 0,
        centerTitle: false,
        titleSpacing: 16,
        title: Text(
          AppStrings.settingsTitle,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
      ),
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
                    const SizedBox(height: 4),
                    const _PersonalSummaryCard(),
                    const SizedBox(height: 24),
                    _LandingSectionTitle(
                      title: AppStrings.settingsLandingQuickTitle,
                    ),
                    const SizedBox(height: 10),
                    const _QuickSettingsGrid(),
                    const SizedBox(height: 24),
                    _LandingSectionTitle(
                      title: AppStrings.settingsGroupLearning,
                    ),
                    const SizedBox(height: 10),
                    _DestinationCard(destinations: _experienceDestinations),
                    const SizedBox(height: 24),
                    _LandingSectionTitle(
                      title: AppStrings.settingsGroupDataSystem,
                    ),
                    const SizedBox(height: 10),
                    _DestinationCard(destinations: _systemDestinations),
                    const SizedBox(height: 16),
                    const _AboutLandingCard(),
                    if (kDebugMode) ...[
                      const SizedBox(height: 24),
                      _LandingSectionTitle(
                        title: AppStrings.settingsCategoryFunLab,
                      ),
                      const SizedBox(height: 10),
                      const _DestinationCard(
                        destinations: [SettingsDestination.developer],
                      ),
                    ],
                    SizedBox(
                      height: 20 + MediaQuery.paddingOf(context).bottom,
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

class _PersonalSummaryCard extends StatelessWidget {
  const _PersonalSummaryCard();

  @override
  Widget build(BuildContext context) {
    return PreferenceBuilder<LocalUser>(
      preference: getIt<AppPrefs>().authUser,
      builder: (context, user) {
        final avatar = AvatarCatalog.resolve(user.avatarId);
        final displayName = user.displayName?.trim().isNotEmpty == true
            ? user.displayName!.trim()
            : AppStrings.profileLearnerFallback;
        final subtitle = AppStrings.settingsLandingPersonalSummary(
          displayName: displayName,
          dailyXp: user.dailyXpGoal ?? 100,
          studyMinutes: user.dailyStudyMinutesGoal ?? 30,
        );
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final radius = BorderRadius.circular(TurnaTheme.radiusLarge);

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Material(
            color: Colors.transparent,
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: radius,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? [
                          TurnaTheme.brandTeal.withValues(alpha: 0.28),
                          TurnaTheme.brandNavy.withValues(alpha: 0.38),
                        ]
                      : [
                          TurnaTheme.brandTeal.withValues(alpha: 0.10),
                          TurnaTheme.brandSky.withValues(alpha: 0.15),
                        ],
                ),
                border: Border.all(
                  color: TurnaTheme.brandTeal.withValues(alpha: 0.22),
                ),
              ),
              child: InkWell(
                key: const Key('settings-personal-summary'),
                borderRadius: radius,
                onTap: () => context.router.push(
                  SettingsDestination.account.route,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      AvatarWithRing(
                        radius: 27,
                        gapColor: TurnaTheme.cardBg(context),
                        backgroundColor:
                            avatar.background.withValues(alpha: 0.18),
                        child: Text(
                          avatar.emoji,
                          style: const TextStyle(fontSize: 26),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              SettingsDestination.account.title,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              subtitle,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: TurnaTheme.textSecondaryColor(
                                      context,
                                    ),
                                    height: 1.35,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: TurnaTheme.textHintColor(context),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _QuickSettingsGrid extends StatelessWidget {
  const _QuickSettingsGrid();

  @override
  Widget build(BuildContext context) {
    final language = context.select<LanguageProvider, String>(
      (provider) => provider.selectedLanguage.displayName,
    );
    final themeMode = context.select<ThemeProvider, ThemeMode>(
      (provider) => provider.themeMode,
    );
    final reminder = context
        .select<SettingsProvider, ({bool enabled, int hour, int minute})>(
      (provider) => (
        enabled: provider.dailyReminderEnabled,
        hour: provider.dailyReminderHour,
        minute: provider.dailyReminderMinute,
      ),
    );
    final textScale = context.select<AccessibilityProvider, int>(
      (provider) => provider.textScale,
    );
    final textScaleFactor = MediaQuery.textScalerOf(context).scale(1);

    final items = [
      _QuickSettingData(
        icon: Icons.language_rounded,
        title: AppStrings.settingsLearningLanguageTitle,
        value: language,
        color: TurnaTheme.brandTeal,
        destination: SettingsDestination.learning,
      ),
      _QuickSettingData(
        icon: Icons.contrast_rounded,
        title: AppStrings.settingsLandingThemeTitle,
        value: _themeLabel(themeMode),
        color: TurnaTheme.anatolianClay,
        destination: SettingsDestination.appearanceAndSound,
      ),
      _QuickSettingData(
        icon: Icons.notifications_active_outlined,
        title: AppStrings.settingsDailyReminderTitle,
        value: reminder.enabled
            ? '${reminder.hour.toString().padLeft(2, '0')}:'
                '${reminder.minute.toString().padLeft(2, '0')}'
            : AppStrings.settingsLandingReminderOff,
        color: TurnaTheme.brandSky,
        destination: SettingsDestination.learning,
      ),
      _QuickSettingData(
        icon: Icons.text_fields_rounded,
        title: AppStrings.settingsTextSizeTitle,
        value: AppStrings.settingsTextSizeValue(textScale),
        color: TurnaTheme.brandNavy,
        destination: SettingsDestination.accessibility,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = textScaleFactor > 1.3
            ? 1
            : constraints.maxWidth >= 620
                ? 4
                : constraints.maxWidth >= 360
                    ? 2
                    : 1;
        const gap = 10.0;
        final available = constraints.maxWidth - 32;
        final width = (available - gap * (columns - 1)) / columns;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final item in items)
                SizedBox(
                  width: width,
                  child: _QuickSettingTile(data: item),
                ),
            ],
          ),
        );
      },
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

class _QuickSettingData {
  const _QuickSettingData({
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
    required this.destination,
  });

  final IconData icon;
  final String title;
  final String value;
  final Color color;
  final SettingsDestination destination;
}

class _QuickSettingTile extends StatelessWidget {
  const _QuickSettingTile({required this.data});

  final _QuickSettingData data;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(TurnaTheme.radiusLarge);
    return Material(
      color: TurnaTheme.cardBg(context),
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: TurnaTheme.statCardBorder(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: radius,
        onTap: () => context.router.push(data.destination.route),
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: data.color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
                ),
                child: Icon(data.icon, color: data.color, size: 19),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: TurnaTheme.textSecondaryColor(context),
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      data.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
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
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: TurnaTheme.textSecondaryColor(context),
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

class _DestinationCard extends StatelessWidget {
  const _DestinationCard({required this.destinations});

  final List<SettingsDestination> destinations;

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
      children: [
        for (int index = 0; index < destinations.length; index++) ...[
          if (index > 0) settingsTileDivider(context),
          _destinationTile(destinations[index]),
        ],
      ],
    );
  }

  Widget _destinationTile(SettingsDestination destination) {
    final color = switch (destination) {
      SettingsDestination.learning => TurnaTheme.brandTeal,
      SettingsDestination.appearanceAndSound => TurnaTheme.anatolianClay,
      SettingsDestination.accessibility => TurnaTheme.brandSky,
      SettingsDestination.dataAndBackup => TurnaTheme.brandNavy,
      SettingsDestination.advanced => TurnaTheme.textSecondary,
      SettingsDestination.about => TurnaTheme.brandTeal,
      SettingsDestination.account => TurnaTheme.brandTeal,
      SettingsDestination.developer => TurnaTheme.amethystLeague,
    };
    return SettingsNavigationTile(
      key: ValueKey(destination.name),
      icon: destination.icon,
      iconColor: color,
      iconBackground: color.withValues(alpha: 0.09),
      title: destination.title,
      subtitle: destination.subtitle,
      onTap: (context) => context.router.push(destination.route),
    );
  }
}

class _AboutLandingCard extends StatelessWidget {
  const _AboutLandingCard();

  @override
  Widget build(BuildContext context) {
    const destination = SettingsDestination.about;
    final showVersion = MediaQuery.textScalerOf(context).scale(1) <= 1.3;
    return SettingsCard(
      children: [
        SettingsTile(
          key: ValueKey(destination.name),
          icon: destination.icon,
          title: destination.title,
          subtitle: destination.subtitle,
          onTap: () => context.router.push(destination.route),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showVersion)
                FutureBuilder<AppBuildInfo>(
                  future: _loadSettingsLandingBuildInfo(),
                  builder: (context, snapshot) => Text(
                    snapshot.data?.versionName ?? AppBuildInfo.unknownVersion,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: TurnaTheme.textHintColor(context),
                        ),
                  ),
                ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                color: TurnaTheme.textHintColor(context),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
