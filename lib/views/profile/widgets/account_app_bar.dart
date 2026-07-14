// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:provider/provider.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';

// Project imports:
import 'package:varnamala/application/theme_provider.dart';
import 'package:varnamala/di/injection.dart';
import 'package:varnamala/domain/auth/local_user.dart';
import 'package:varnamala/service/locator.dart';
import 'package:varnamala/views/theme.dart';

class AccountAppBar extends StatelessWidget implements PreferredSizeWidget {
  const AccountAppBar({Key? key}) : super(key: key);

  @override
  Size get preferredSize => const Size.fromHeight(0);

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

class AccountWidget extends StatelessWidget {
  const AccountWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return PreferenceBuilder<LocalUser>(
      preference: getIt<AppPrefs>().authUser,
      builder: (BuildContext context, LocalUser user) {
        final displayName = user.displayName ?? 'Learner';
        final email = user.email ?? '';

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: VarnamalaTheme.cardBg(context),
            borderRadius: BorderRadius.circular(VarnamalaTheme.radiusLarge),
            border: Border.all(color: VarnamalaTheme.statCardBorder(context)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor:
                    VarnamalaTheme.peacockTeal.withValues(alpha: 0.1),
                child: const Icon(
                  Icons.person_rounded,
                  size: 28,
                  color: VarnamalaTheme.peacockTeal,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style:
                          Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                    ),
                    const SizedBox(height: 2),
                    if (email.isNotEmpty)
                      Text(
                        email,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: VarnamalaTheme.textHint,
                            ),
                      ),
                  ],
                ),
              ),
              _ThemeToggle(),
            ],
          ),
        );
      },
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
                color: current == ThemeMode.light
                    ? VarnamalaTheme.peacockTeal
                    : null,
              ),
              const SizedBox(width: 8),
              Text(
                'Light',
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
                color: current == ThemeMode.dark
                    ? VarnamalaTheme.peacockTeal
                    : null,
              ),
              const SizedBox(width: 8),
              Text(
                'Dark',
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
                color: current == ThemeMode.system
                    ? VarnamalaTheme.peacockTeal
                    : null,
              ),
              const SizedBox(width: 8),
              Text(
                'System',
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: VarnamalaTheme.peacockTeal.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(VarnamalaTheme.radiusRound),
        ),
        child: Icon(
          current == ThemeMode.dark
              ? Icons.dark_mode_rounded
              : current == ThemeMode.light
                  ? Icons.light_mode_rounded
                  : Icons.settings_suggest_rounded,
          size: 20,
          color: VarnamalaTheme.peacockTeal,
        ),
      ),
    );
  }
}