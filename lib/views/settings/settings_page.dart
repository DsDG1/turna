// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/annotations.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:words625/application/language_provider.dart';
import 'package:words625/application/theme_provider.dart';
import 'package:words625/core/enums.dart';
import 'package:words625/core/extensions.dart';
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
            const _SectionTitle(
                title: 'Appearance', icon: Icons.palette_rounded),
            const _ThemeSelector(),
            const SizedBox(height: 16),
            const _SectionTitle(
                title: 'Language', icon: Icons.language_rounded),
            const _LanguageSelector(),
            const SizedBox(height: 16),
            const _SectionTitle(title: 'About', icon: Icons.info_rounded),
            _AboutTile(),
          ],
        ),
      ),
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

class _ThemeSelector extends StatelessWidget {
  const _ThemeSelector();

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final current = themeProvider.themeMode;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: VarnamalaTheme.cardBg(context),
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusLarge),
        border: Border.all(color: VarnamalaTheme.statCardBorder(context)),
      ),
      child: Column(
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
            indent: 16,
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
            indent: 16,
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
      ),
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
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected
                  ? VarnamalaTheme.peacockTeal
                  : VarnamalaTheme.textHint,
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
    );
  }
}

class _LanguageSelector extends StatelessWidget {
  const _LanguageSelector();

  @override
  Widget build(BuildContext context) {
    final languageProvider = context.watch<LanguageProvider>();
    final current = languageProvider.selectedLanguage;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: VarnamalaTheme.cardBg(context),
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusLarge),
        border: Border.all(color: VarnamalaTheme.statCardBorder(context)),
      ),
      child: PopupMenuButton<TargetLanguage>(
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
                        fontWeight: lang == current
                            ? FontWeight.w700
                            : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
        child: ListTile(
          leading: const Icon(
            Icons.language_rounded,
            color: VarnamalaTheme.peacockTeal,
          ),
          title: Text(
            'Learning Language',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
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
      ),
    );
  }
}

class _AboutTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: VarnamalaTheme.cardBg(context),
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusLarge),
        border: Border.all(color: VarnamalaTheme.statCardBorder(context)),
      ),
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
            child: const Icon(
              Icons.school_rounded,
              color: VarnamalaTheme.peacockTeal,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Varnamala',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Learn languages, one step at a time.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: VarnamalaTheme.textHintColor(context),
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
