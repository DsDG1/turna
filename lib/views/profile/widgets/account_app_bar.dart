// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:provider/provider.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';

// Project imports:
import 'package:turna/application/language_provider.dart';
import 'package:turna/application/theme_provider.dart';
import 'package:turna/core/extensions.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/auth/local_user.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/service/locator.dart';
import 'package:turna/views/theme.dart';

class AccountAppBar extends StatelessWidget implements PreferredSizeWidget {
  const AccountAppBar({Key? key}) : super(key: key);

  @override
  Size get preferredSize => const Size.fromHeight(0);

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

/// Hero-style profile header: avatar, name, language chip, theme + share actions.
class AccountWidget extends StatelessWidget {
  final VoidCallback? onShare;

  const AccountWidget({Key? key, this.onShare}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final languageName = context
        .select((LanguageProvider p) => p.selectedLanguage.displayName)
        .toTitleCase;

    return PreferenceBuilder<LocalUser>(
      preference: getIt<AppPrefs>().authUser,
      builder: (BuildContext context, LocalUser user) {
        final displayName =
            user.displayName ?? AppStrings.profileLearnerFallback;
        final email = user.email ?? '';
        final bio = user.bio?.trim() ?? '';

        return Container(
          padding: const EdgeInsets.fromLTRB(18, 18, 14, 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(TurnaTheme.radiusXLarge),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [
                      TurnaTheme.peacockTeal.withValues(alpha: 0.35),
                      TurnaTheme.peacockDeep.withValues(alpha: 0.45),
                    ]
                  : [
                      TurnaTheme.peacockTeal.withValues(alpha: 0.12),
                      TurnaTheme.peacockCyan.withValues(alpha: 0.18),
                    ],
            ),
            border: Border.all(
              color: TurnaTheme.peacockTeal.withValues(alpha: 0.18),
            ),
            boxShadow: [
              BoxShadow(
                color: TurnaTheme.peacockTeal.withValues(alpha: 0.08),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: TurnaTheme.peacockTeal.withValues(alpha: 0.15),
                  border: Border.all(
                    color: TurnaTheme.peacockTeal.withValues(alpha: 0.35),
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.person_rounded,
                  size: 32,
                  color: TurnaTheme.peacockTeal,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    if (email.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        email,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: TurnaTheme.textHintColor(context),
                            ),
                      ),
                    ],
                    if (bio.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        bio,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: TurnaTheme.textSecondaryColor(context),
                            ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: TurnaTheme.cardBg(context).withValues(
                          alpha: isDark ? 0.35 : 0.85,
                        ),
                        borderRadius:
                            BorderRadius.circular(TurnaTheme.radiusRound),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.language_rounded,
                            size: 14,
                            color: TurnaTheme.peacockTeal,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            languageName,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: TurnaTheme.peacockTeal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                children: [
                  _ThemeToggle(),
                  if (onShare != null) ...[
                    const SizedBox(height: 8),
                    _HeroIconButton(
                      icon: Icons.share_rounded,
                      tooltip: AppStrings.profileShare,
                      onTap: onShare!,
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HeroIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _HeroIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: TurnaTheme.cardBg(context).withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusRound),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(TurnaTheme.radiusRound),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, size: 20, color: TurnaTheme.peacockTeal),
          ),
        ),
      ),
    );
  }
}

class _ThemeToggle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final current = themeProvider.themeMode;

    return PopupMenuButton<ThemeMode>(
      initialValue: current,
      onSelected: (mode) => themeProvider.setThemeMode(mode),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: ThemeMode.light,
          child: Row(
            children: [
              Icon(
                Icons.light_mode_rounded,
                size: 18,
                color:
                    current == ThemeMode.light ? TurnaTheme.peacockTeal : null,
              ),
              const SizedBox(width: 8),
              Text(
                AppStrings.settingsThemeLight,
                style: TextStyle(
                  fontWeight: current == ThemeMode.light
                      ? FontWeight.w700
                      : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: ThemeMode.dark,
          child: Row(
            children: [
              Icon(
                Icons.dark_mode_rounded,
                size: 18,
                color:
                    current == ThemeMode.dark ? TurnaTheme.peacockTeal : null,
              ),
              const SizedBox(width: 8),
              Text(
                AppStrings.settingsThemeDark,
                style: TextStyle(
                  fontWeight: current == ThemeMode.dark
                      ? FontWeight.w700
                      : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: ThemeMode.system,
          child: Row(
            children: [
              Icon(
                Icons.settings_suggest_rounded,
                size: 18,
                color:
                    current == ThemeMode.system ? TurnaTheme.peacockTeal : null,
              ),
              const SizedBox(width: 8),
              Text(
                AppStrings.settingsThemeSystem,
                style: TextStyle(
                  fontWeight: current == ThemeMode.system
                      ? FontWeight.w700
                      : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: TurnaTheme.cardBg(context).withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(TurnaTheme.radiusRound),
        ),
        child: Icon(
          current == ThemeMode.dark
              ? Icons.dark_mode_rounded
              : current == ThemeMode.light
                  ? Icons.light_mode_rounded
                  : Icons.settings_suggest_rounded,
          size: 20,
          color: TurnaTheme.peacockTeal,
        ),
      ),
    );
  }
}
