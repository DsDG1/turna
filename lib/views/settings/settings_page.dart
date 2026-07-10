// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/annotations.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';

// Project imports:
import 'package:words625/application/audio_controller.dart';
import 'package:words625/application/game_provider.dart';
import 'package:words625/application/language_provider.dart';
import 'package:words625/application/mistake_provider.dart';
import 'package:words625/application/settings_provider.dart';
import 'package:words625/application/theme_provider.dart';
import 'package:words625/core/enums.dart';
import 'package:words625/core/extensions.dart';
import 'package:words625/di/injection.dart';
import 'package:words625/domain/auth/local_user.dart';
import 'package:words625/service/locator.dart';
import 'package:words625/views/settings/about_varnamala_page.dart';
import 'package:words625/views/theme.dart';

@RoutePage()
class SettingsPage extends StatelessWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VarnamalaTheme.scaffoldBg(context),
      appBar: AppBar(
        title: Text(
          'Settings',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionTitle(title: 'Account', icon: Icons.person_rounded),
            const _AccountTile(),
            const SizedBox(height: 16),
            const _SectionTitle(title: 'Learning', icon:Icons.menu_book_rounded),
            _SettingsCard(
              children: [
                const _LanguageSelectorTile(),
                _tileDivider(context),
                const _TtsSpeedTile(),
              ],
            ),
            const SizedBox(height: 16),
            const _SectionTitle(
                title: 'Sound & Haptics', icon: Icons.volume_up_rounded),
            _SettingsCard(
              children: [
                _ToggleTile(
                  icon: Icons.music_note_rounded,
                  title: 'Sound effects',
                  subtitle: 'Play sounds for errors and level-ups',
                  valueSelector: (p) => p.soundEffectsEnabled,
                  onChanged: (p, value) => p.setSoundEffects(value),
                ),
                _tileDivider(context),
                _ToggleTile(
                  icon: Icons.vibration_rounded,
                  title: 'Haptic feedback',
                  subtitle: 'Vibrate on key interactions',
                  valueSelector: (p) => p.hapticFeedbackEnabled,
                  onChanged: (p, value) => p.setHapticFeedback(value),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const _SectionTitle(
                title: 'Appearance', icon: Icons.palette_rounded),
            const _ThemeSelector(),
            const SizedBox(height: 16),
            const _SectionTitle(title: 'Data', icon: Icons.storage_rounded),
            _SettingsCard(
              children: [
                _ActionTile(
                  icon: Icons.delete_sweep_rounded,
                  title: 'Clear mistake log',
                  subtitle: 'Remove all saved mistakes',
                  onTap: (context) => _confirmClearMistakes(context),
                ),
                _tileDivider(context),
                _ActionTile(
                  icon: Icons.restart_alt_rounded,
                  title: 'Reset lesson progress',
                  subtitle: 'Mark all lessons as not completed',
                  onTap: (context) => _confirmResetProgress(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const _SectionTitle(title: 'About', icon: Icons.info_rounded),
            _SettingsCard(
              children: [
                _NavigationTile(
                  icon: Icons.school_rounded,
                  title: 'About Varnamala',
                  onTap: (context) => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AboutVarnamalaPage(),
                    ),
                  ),
                ),
                _tileDivider(context),
                _NavigationTile(
                  icon: Icons.code_rounded,
                  title: 'Open source licenses',
                  onTap: (context) => _showLicenses(context),
                ),
                _tileDivider(context),
                const _VersionFooter(),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _tileDivider(BuildContext context) => Divider(
        height: 1,
        indent: 56,
        endIndent: 16,
        color: VarnamalaTheme.dividerBg(context),
      );

  Future<void> _confirmClearMistakes(BuildContext context) async {
    final mistakeProvider = context.read<MistakeProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const _ConfirmDialog(
        title: 'Clear mistake log?',
        message: 'This will permanently delete all saved mistakes.',
        confirmText: 'Clear',
      ),
    );
    if (confirmed == true) {
      await mistakeProvider.clear();
      if (context.mounted) {
        _showSnack(context, 'Mistake log cleared');
      }
    }
  }

  Future<void> _confirmResetProgress(BuildContext context) async {
    final gameProvider = context.read<GameProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const _ConfirmDialog(
        title: 'Reset lesson progress?',
        message: 'All lesson completion and perfect-lesson records will be '
            'cleared. This cannot be undone.',
        confirmText: 'Reset',
      ),
    );
    if (confirmed == true) {
      await gameProvider.resetLessonProgress();
      if (context.mounted) {
        _showSnack(context, 'Lesson progress reset');
      }
    }
  }

  void _showLicenses(BuildContext context) {
    showLicensePage(
      context: context,
      applicationName: 'Varnamala',
      applicationVersion: '1.0.0',
    );
  }

  void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionTitle({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: VarnamalaTheme.peacockTeal, size: 20),
          const SizedBox(width: 8),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: VarnamalaTheme.textSecondary,
                ),
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;

  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: VarnamalaTheme.cardBg(context),
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusLarge),
        border: Border.all(color: VarnamalaTheme.statCardBorder(context)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: VarnamalaTheme.peacockTeal.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(VarnamalaTheme.radiusMedium),
            ),
            child: Icon(
              icon,
              color: VarnamalaTheme.peacockTeal,
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
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: VarnamalaTheme.textHintColor(context),
                        ),
                  ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );

    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(VarnamalaTheme.radiusLarge),
      child: InkWell(
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusLarge),
        onTap: onTap,
        child: content,
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile();

  @override
  Widget build(BuildContext context) {
    return PreferenceBuilder<SerializableFirebaseUser>(
      preference: getIt<AppPrefs>().authUser,
      builder: (context, user) {
        final displayName = user.displayName ?? 'Learner';
        final email = user.email ?? '';
        final languageProvider = context.watch<LanguageProvider>();

        return _SettingsCard(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
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
                        if (email.isNotEmpty)
                          Text(
                            email,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: VarnamalaTheme.textHintColor(context),
                                ),
                          ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: VarnamalaTheme.peacockTeal
                                .withValues(alpha: 0.08),
                            borderRadius:
                                BorderRadius.circular(VarnamalaTheme.radiusRound),
                          ),
                          child: Text(
                            languageProvider.selectedLanguage.name.toTitleCase,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: VarnamalaTheme.peacockTeal,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _LanguageSelectorTile extends StatelessWidget {
  const _LanguageSelectorTile();

  @override
  Widget build(BuildContext context) {
    final languageProvider = context.watch<LanguageProvider>();
    final current = languageProvider.selectedLanguage;

    return PopupMenuButton<TargetLanguage>(
      initialValue: current,
      onSelected: (value) {
        languageProvider.setLanguage(value);
        languageProvider.cacheLanguage();
      },
      itemBuilder: (context) => TargetLanguage.values
          .map(
            (lang) => PopupMenuItem(
              value: lang,
              child: Row(
                children: [
                  Icon(
                    Icons.language_rounded,
                    size: 18,
                    color: lang == current
                        ? VarnamalaTheme.peacockTeal
                        : VarnamalaTheme.textHint,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    lang.name.toTitleCase,
                    style: TextStyle(
                      fontWeight:
                          lang == current ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
      child: _SettingsTile(
        icon: Icons.language_rounded,
        title: 'Learning Language',
        subtitle: 'Choose the language you are learning',
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              current.name.toTitleCase,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: VarnamalaTheme.peacockTeal,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.chevron_right_rounded,
              color: VarnamalaTheme.textHint,
            ),
          ],
        ),
      ),
    );
  }
}

class _TtsSpeedTile extends StatelessWidget {
  const _TtsSpeedTile();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: VarnamalaTheme.peacockTeal.withValues(alpha: 0.08),
                  borderRadius:
                      BorderRadius.circular(VarnamalaTheme.radiusMedium),
                ),
                child: const Icon(
                  Icons.record_voice_over_rounded,
                  color: VarnamalaTheme.peacockTeal,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TTS Speed',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    Text(
                      'Adjust voice playback speed',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: VarnamalaTheme.textHintColor(context),
                          ),
                    ),
                  ],
                ),
              ),
              Text(
                '${settings.ttsSpeed.toStringAsFixed(1)}x',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: VarnamalaTheme.peacockTeal,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 52),
            child: Slider.adaptive(
              value: settings.ttsSpeed,
              min: 0.5,
              max: 2.0,
              divisions: 15,
              activeColor: VarnamalaTheme.peacockTeal,
              inactiveColor: VarnamalaTheme.dividerBg(context),
              onChanged: (value) {
                settings.setTtsSpeed(value);
                getIt<AudioController>().setTtsSpeed(value);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ToggleTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool Function(SettingsProvider) valueSelector;
  final void Function(SettingsProvider, bool) onChanged;

  const _ToggleTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.valueSelector,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final value = valueSelector(settings);

    return _SettingsTile(
      icon: icon,
      title: title,
      subtitle: subtitle,
      trailing: Switch.adaptive(
        value: value,
        activeTrackColor: VarnamalaTheme.peacockTeal,
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return VarnamalaTheme.peacockTeal;
          }
          return null;
        }),
        onChanged: (newValue) => onChanged(settings, newValue),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final void Function(BuildContext) onTap;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _SettingsTile(
      icon: icon,
      title: title,
      subtitle: subtitle,
      onTap: () => onTap(context),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: VarnamalaTheme.textHint,
      ),
    );
  }
}

class _NavigationTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final void Function(BuildContext) onTap;

  const _NavigationTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _SettingsTile(
      icon: icon,
      title: title,
      onTap: () => onTap(context),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: VarnamalaTheme.textHint,
      ),
    );
  }
}

class _ThemeSelector extends StatelessWidget {
  const _ThemeSelector();

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final current = themeProvider.themeMode;

    return _SettingsCard(
      children: [
        _ThemeOption(
          icon: Icons.light_mode_rounded,
          label: 'Light',
          value: ThemeMode.light,
          isSelected: current == ThemeMode.light,
          onTap: () => themeProvider.setThemeMode(ThemeMode.light),
        ),
        Divider(
          height: 1,
          indent: 56,
          endIndent: 16,
          color: VarnamalaTheme.dividerBg(context),
        ),
        _ThemeOption(
          icon: Icons.dark_mode_rounded,
          label: 'Dark',
          value: ThemeMode.dark,
          isSelected: current == ThemeMode.dark,
          onTap: () => themeProvider.setThemeMode(ThemeMode.dark),
        ),
        Divider(
          height: 1,
          indent: 56,
          endIndent: 16,
          color: VarnamalaTheme.dividerBg(context),
        ),
        _ThemeOption(
          icon: Icons.settings_suggest_rounded,
          label: 'System',
          value: ThemeMode.system,
          isSelected: current == ThemeMode.system,
          onTap: () => themeProvider.setThemeMode(ThemeMode.system),
        ),
      ],
    );
  }
}

class _ThemeOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final ThemeMode value;
  final bool isSelected;
  final VoidCallback onTap;

  const _ThemeOption({
    required this.icon,
    required this.label,
    required this.value,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(VarnamalaTheme.radiusLarge),
      child: InkWell(
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusLarge),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: VarnamalaTheme.peacockTeal.withValues(alpha: 0.08),
                  borderRadius:
                      BorderRadius.circular(VarnamalaTheme.radiusMedium),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: isSelected
                      ? VarnamalaTheme.peacockTeal
                      : VarnamalaTheme.textHint,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
              ),
              const Spacer(),
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected
                        ? VarnamalaTheme.peacockTeal
                        : VarnamalaTheme.textHint,
                    width: 2,
                  ),
                ),
                child: isSelected
                    ? Center(
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: VarnamalaTheme.peacockTeal,
                          ),
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VersionFooter extends StatelessWidget {
  const _VersionFooter();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final version = snapshot.data?.version ?? '1.0.0';
        final build = snapshot.data?.buildNumber ?? '';
        final label = build.isEmpty ? 'Version $version' : 'Version $version ($build)';
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: VarnamalaTheme.peacockTeal.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(VarnamalaTheme.radiusMedium),
                ),
                child: const Icon(
                  Icons.info_outline_rounded,
                  color: VarnamalaTheme.peacockTeal,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: VarnamalaTheme.textHintColor(context),
                      ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ConfirmDialog extends StatelessWidget {
  final String title;
  final String message;
  final String confirmText;

  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmText,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusLarge),
      ),
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            confirmText,
            style: const TextStyle(color: VarnamalaTheme.error),
          ),
        ),
      ],
    );
  }
}
