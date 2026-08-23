// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/accessibility_provider.dart';
import 'package:turna/views/settings/widgets/controls/settings_controls.dart';
import 'package:turna/views/settings/widgets/settings_common.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/theme.dart';

/// A switch tile bound to [AccessibilityProvider], mirroring
/// [SettingsToggleTile] (which is bound to [SettingsProvider]).
class AccessibilityToggleTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool Function(AccessibilityProvider) valueSelector;
  final void Function(AccessibilityProvider, bool) onChanged;

  const AccessibilityToggleTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.valueSelector,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ProviderBoundToggleTile<AccessibilityProvider>(
      icon: icon,
      title: title,
      subtitle: subtitle,
      valueSelector: valueSelector,
      onChanged: onChanged,
    );
  }
}

/// Slider tile (100%–200%, 5 steps) controlling [AccessibilityProvider.textScale].
///
/// Local drag state avoids writing prefs and rebuilding [MaterialApp] on every
/// frame (root shell watches [AccessibilityProvider.textScaler]).
class SettingsTextScaleTile extends StatefulWidget {
  const SettingsTextScaleTile({super.key});

  @override
  State<SettingsTextScaleTile> createState() => _SettingsTextScaleTileState();
}

class _SettingsTextScaleTileState extends State<SettingsTextScaleTile> {
  int? _dragValue;

  @override
  Widget build(BuildContext context) {
    final persisted =
        context.select<AccessibilityProvider, int>((p) => p.textScale);
    final value = _dragValue ?? persisted;

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
                  color: TurnaTheme.brandTeal.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
                ),
                child: const Icon(
                  Icons.format_size_rounded,
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
                      AppStrings.settingsTextSizeTitle,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    Text(
                      AppStrings.settingsTextSizeSubtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: TurnaTheme.textHintColor(context),
                          ),
                    ),
                  ],
                ),
              ),
              Text(
                '$value%',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: TurnaTheme.brandTeal,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 52),
            child: Slider.adaptive(
              value: value.toDouble(),
              min: 100,
              max: 200,
              divisions: 5,
              activeColor: TurnaTheme.brandTeal,
              inactiveColor: TurnaTheme.dividerBg(context),
              onChanged: (v) => setState(() => _dragValue = v.round()),
              onChangeEnd: (v) async {
                await context
                    .read<AccessibilityProvider>()
                    .setTextScale(v.round());
                if (mounted) setState(() => _dragValue = null);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsReducedMotionTile extends StatelessWidget {
  const SettingsReducedMotionTile({super.key});

  @override
  Widget build(BuildContext context) => AccessibilityToggleTile(
        icon: Icons.animation_rounded,
        title: AppStrings.settingsReduceMotionTitle,
        subtitle: AppStrings.settingsReduceMotionSubtitle,
        valueSelector: (p) => p.reducedMotion,
        onChanged: (p, v) => p.setReducedMotion(v),
      );
}

class SettingsHighContrastTile extends StatelessWidget {
  const SettingsHighContrastTile({super.key});

  @override
  Widget build(BuildContext context) => AccessibilityToggleTile(
        icon: Icons.contrast_rounded,
        title: AppStrings.settingsHighContrastTitle,
        subtitle: AppStrings.settingsHighContrastSubtitle,
        valueSelector: (p) => p.highContrast,
        onChanged: (p, v) => p.setHighContrast(v),
      );
}

class SettingsDyslexiaFontTile extends StatelessWidget {
  const SettingsDyslexiaFontTile({super.key});

  @override
  Widget build(BuildContext context) => AccessibilityToggleTile(
        icon: Icons.text_fields_rounded,
        title: AppStrings.settingsDyslexiaFontTitle,
        subtitle: AppStrings.settingsDyslexiaFontSubtitle,
        valueSelector: (p) => p.dyslexiaFont,
        onChanged: (p, v) => p.setDyslexiaFont(v),
      );
}

class SettingsSensoryReduceTile extends StatelessWidget {
  const SettingsSensoryReduceTile({super.key});

  @override
  Widget build(BuildContext context) => AccessibilityToggleTile(
        icon: Icons.graphic_eq_rounded,
        title: AppStrings.settingsSensoryReduceTitle,
        subtitle: AppStrings.settingsSensoryReduceSubtitle,
        valueSelector: (p) => p.sensoryReduce,
        onChanged: (p, v) => p.setSensoryReduce(v),
      );
}

class SettingsFocusModeTile extends StatelessWidget {
  const SettingsFocusModeTile({super.key});

  @override
  Widget build(BuildContext context) => AccessibilityToggleTile(
        icon: Icons.center_focus_strong_rounded,
        title: AppStrings.settingsFocusModeTitle,
        subtitle: AppStrings.settingsFocusModeSubtitle,
        valueSelector: (p) => p.focusMode,
        onChanged: (p, v) => p.setFocusMode(v),
      );
}
