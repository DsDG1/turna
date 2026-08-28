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

/// Slider tile (100%–200%, 10 steps) controlling
/// [AccessibilityProvider.textScale] (global UI text).
class SettingsTextScaleTile extends StatelessWidget {
  const SettingsTextScaleTile({super.key});

  @override
  Widget build(BuildContext context) => _AccessibilityScaleTile(
        icon: Icons.format_size_rounded,
        title: AppStrings.settingsTextSizeTitle,
        subtitle: AppStrings.settingsTextSizeSubtitle,
        valueSelector: (p) => p.textScale,
        onPreview: (p, v) => p.previewTextScale(v),
        onCommit: (p, v) => p.setTextScale(v),
      );
}

/// Slider tile (100%–200%, 10 steps) controlling
/// [AccessibilityProvider.cardTextScale] (card content only; 100% leaves
/// card rendering untouched).
class SettingsCardTextScaleTile extends StatelessWidget {
  const SettingsCardTextScaleTile({super.key});

  @override
  Widget build(BuildContext context) => _AccessibilityScaleTile(
        icon: Icons.aspect_ratio_rounded,
        title: AppStrings.settingsCardTextSizeTitle,
        subtitle: AppStrings.settingsCardTextSizeSubtitle,
        valueSelector: (p) => p.cardTextScale,
        onPreview: (p, v) => p.previewCardTextScale(v),
        onCommit: (p, v) => p.setCardTextScale(v),
      );
}

/// Shared slider implementation for percentage-based text-scale settings.
///
/// During a drag, [onPreview] mirrors each snapped step into the provider's
/// in-memory value so the whole app reacts live (the provider notifies
/// without touching prefs); [onCommit] persists once the drag ends. Local
/// drag state keeps the knob and label tracking the gesture between snaps.
class _AccessibilityScaleTile extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final int Function(AccessibilityProvider) valueSelector;
  final void Function(AccessibilityProvider, int) onPreview;
  final Future<void> Function(AccessibilityProvider, int) onCommit;

  const _AccessibilityScaleTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.valueSelector,
    required this.onPreview,
    required this.onCommit,
  });

  @override
  State<_AccessibilityScaleTile> createState() => _AccessibilityScaleTileState();
}

class _AccessibilityScaleTileState extends State<_AccessibilityScaleTile> {
  int? _dragValue;

  @override
  Widget build(BuildContext context) {
    final persisted = context
        .select<AccessibilityProvider, int>(widget.valueSelector);
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
                child: Icon(
                  widget.icon,
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
                      widget.title,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    Text(
                      widget.subtitle,
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
              divisions: 10,
              activeColor: TurnaTheme.brandTeal,
              inactiveColor: TurnaTheme.dividerBg(context),
              onChanged: (v) {
                setState(() => _dragValue = v.round());
                widget.onPreview(context.read<AccessibilityProvider>(), v.round());
              },
              onChangeEnd: (v) async {
                await widget.onCommit(
                    context.read<AccessibilityProvider>(), v.round());
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
