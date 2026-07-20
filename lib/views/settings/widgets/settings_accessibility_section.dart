// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:varnamala/application/accessibility_provider.dart';
import 'package:varnamala/views/settings/widgets/settings_common.dart';
import 'package:varnamala/views/theme.dart';

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
    final value = context.select<AccessibilityProvider, bool>(
      (acc) => valueSelector(acc),
    );

    return SettingsTile(
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
        onChanged: (newValue) =>
            onChanged(context.read<AccessibilityProvider>(), newValue),
      ),
    );
  }
}

/// Slider tile (100%–200%, 5 steps) controlling [AccessibilityProvider.textScale].
/// Mirrors [SettingsTtsSpeedTile]'s layout.
class SettingsTextScaleTile extends StatelessWidget {
  const SettingsTextScaleTile({super.key});

  @override
  Widget build(BuildContext context) {
    final acc = context.watch<AccessibilityProvider>();

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
                  Icons.format_size_rounded,
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
                      'Text size',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    Text(
                      'Magnify text app-wide',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: VarnamalaTheme.textHintColor(context),
                          ),
                    ),
                  ],
                ),
              ),
              Text(
                '${acc.textScale}%',
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
              value: acc.textScale.toDouble(),
              min: 100,
              max: 200,
              divisions: 5,
              activeColor: VarnamalaTheme.peacockTeal,
              inactiveColor: VarnamalaTheme.dividerBg(context),
              onChanged: (value) => acc.setTextScale(value.round()),
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
        title: 'Reduce motion',
        subtitle: 'Shorten or disable animations and transitions',
        valueSelector: (p) => p.reducedMotion,
        onChanged: (p, v) => p.setReducedMotion(v),
      );
}

class SettingsHighContrastTile extends StatelessWidget {
  const SettingsHighContrastTile({super.key});

  @override
  Widget build(BuildContext context) => AccessibilityToggleTile(
        icon: Icons.contrast_rounded,
        title: 'High contrast',
        subtitle: 'Use a high-contrast color theme',
        valueSelector: (p) => p.highContrast,
        onChanged: (p, v) => p.setHighContrast(v),
      );
}

class SettingsDyslexiaFontTile extends StatelessWidget {
  const SettingsDyslexiaFontTile({super.key});

  @override
  Widget build(BuildContext context) => AccessibilityToggleTile(
        icon: Icons.text_fields_rounded,
        title: 'Dyslexia-friendly font',
        subtitle: 'Switch to the Lexend typeface for easier reading',
        valueSelector: (p) => p.dyslexiaFont,
        onChanged: (p, v) => p.setDyslexiaFont(v),
      );
}

class SettingsSensoryReduceTile extends StatelessWidget {
  const SettingsSensoryReduceTile({super.key});

  @override
  Widget build(BuildContext context) => AccessibilityToggleTile(
        icon: Icons.graphic_eq_rounded,
        title: 'Reduce sensory input',
        subtitle: 'Mute non-essential sounds and haptics',
        valueSelector: (p) => p.sensoryReduce,
        onChanged: (p, v) => p.setSensoryReduce(v),
      );
}

class SettingsFocusModeTile extends StatelessWidget {
  const SettingsFocusModeTile({super.key});

  @override
  Widget build(BuildContext context) => AccessibilityToggleTile(
        icon: Icons.center_focus_strong_rounded,
        title: 'Focus mode',
        subtitle: 'Hide the rotating welcome animation on the home screen',
        valueSelector: (p) => p.focusMode,
        onChanged: (p, v) => p.setFocusMode(v),
      );
}