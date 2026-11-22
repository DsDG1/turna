import 'package:flutter/material.dart';
import 'package:turna/core/spacing.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/core/turna_icon_id.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/widgets/turna_icon.dart';

/// Global learning style preset modes for imported Anki decks.
enum StudyPresetMode {
  /// Interactive practice: transforms recognized cards into multiple choice,
  /// fill-in-the-blank, and listening questions, with flip as fallback.
  interactive,

  /// Classic flashcards: uses traditional active-recall front/back flips.
  classicFlip,

  /// Raw official fidelity: preserves original HTML/CSS styling via WebView.
  fidelity,
}

/// Selector widget for global study preset modes.
class StudyPresetSelector extends StatelessWidget {
  const StudyPresetSelector({
    super.key,
    required this.selectedMode,
    required this.onSelectMode,
  });

  final StudyPresetMode selectedMode;
  final ValueChanged<StudyPresetMode> onSelectMode;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const TurnaIcon(
              TurnaIconId.filter,
              size: 18,
              color: TurnaTheme.brandTeal,
            ),
            const SizedBox(width: 6),
            Text(
              AppStrings.studyPresetTitle,
              style: AppTextStyles.cardTitle(context),
            ),
            const Spacer(),
            Text(
              AppStrings.studyPresetChangeHint,
              style: AppTextStyles.caption(context).copyWith(letterSpacing: 0),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _buildModeCard(
          context,
          mode: StudyPresetMode.interactive,
          icon: TurnaIconId.brain,
          title: AppStrings.studyPresetInteractiveTitle,
          badgeText: AppStrings.studyPresetRecommended,
          description: AppStrings.studyPresetInteractiveDesc,
        ),
        const SizedBox(height: AppSpacing.sm),
        _buildModeCard(
          context,
          mode: StudyPresetMode.classicFlip,
          icon: TurnaIconId.cards,
          title: AppStrings.studyPresetClassicFlipTitle,
          description: AppStrings.studyPresetClassicFlipDesc,
        ),
        const SizedBox(height: AppSpacing.sm),
        _buildModeCard(
          context,
          mode: StudyPresetMode.fidelity,
          icon: TurnaIconId.code,
          title: AppStrings.studyPresetFidelityTitle,
          description: AppStrings.studyPresetFidelityDesc,
        ),
      ],
    );
  }

  Widget _buildModeCard(
    BuildContext context, {
    required StudyPresetMode mode,
    required TurnaIconId icon,
    required String title,
    required String description,
    String? badgeText,
  }) {
    final isSelected = selectedMode == mode;
    const activeColor = TurnaTheme.brandTeal;

    return Material(
      color: TurnaTheme.cardBg(context),
      borderRadius: TurnaTheme.borderRadius,
      child: InkWell(
        onTap: () => onSelectMode(mode),
        borderRadius: TurnaTheme.borderRadius,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: TurnaTheme.borderRadius,
            border: Border.all(
              color: isSelected
                  ? activeColor
                  : TurnaTheme.textHintColor(context).withValues(alpha: 0.18),
              width: isSelected ? 1.5 : 1.0,
            ),
            color: isSelected
                ? activeColor.withValues(alpha: 0.04)
                : Colors.transparent,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TurnaIcon(
                isSelected
                    ? TurnaIconId.radioChecked
                    : TurnaIconId.radioUnchecked,
                color: isSelected
                    ? activeColor
                    : TurnaTheme.textHintColor(context),
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        TurnaIcon(icon, size: 16, color: activeColor),
                        const SizedBox(width: 6),
                        Text(
                          title,
                          style: AppTextStyles.captionSm(context).copyWith(
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w600,
                            color: isSelected
                                ? activeColor
                                : TurnaTheme.textPrimaryColor(context),
                          ),
                        ),
                        if (badgeText != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1.5,
                            ),
                            decoration: const BoxDecoration(
                              color: TurnaTheme.anatolianClay,
                              borderRadius: TurnaTheme.borderRadius,
                            ),
                            child: Text(
                              badgeText,
                              style: AppTextStyles.caption(context).copyWith(
                                color: TurnaTheme.textOnPrimary,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      description,
                      style: AppTextStyles.captionSm(context)
                          .copyWith(height: 1.35),
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
