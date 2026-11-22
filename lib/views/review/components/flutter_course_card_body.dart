import 'package:flutter/material.dart';
import 'package:turna/core/spacing.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/core/turna_icon_id.dart';
import 'package:turna/domain/review/review_item.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/lesson/components/anki_media_strip.dart';
import 'package:turna/views/widgets/turna_icon.dart';

/// Flutter-native card renderer for standard course cards and legacy flip cards.
class FlutterCourseCardBody extends StatelessWidget {
  final StandardCourseCardContent content;
  final bool isRevealed;
  final VoidCallback onReveal;
  final VoidCallback onSpeak;

  const FlutterCourseCardBody({
    super.key,
    required this.content,
    required this.isRevealed,
    required this.onReveal,
    required this.onSpeak,
  });

  /// The question face keeps its media visible; the answer face's media is
  /// built only after the reveal, so a back-face clip or image cannot be read
  /// by the screen reader or played early.
  Widget _frontMedia() {
    if (content.frontAudioAssets.isEmpty && content.frontImageAssets.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: AnkiMediaStrip(
        audioAssets: content.frontAudioAssets,
        imageAssets: content.frontImageAssets,
      ),
    );
  }

  Widget _backMedia() {
    if (content.backAudioAssets.isEmpty && content.backImageAssets.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: AnkiMediaStrip(
        audioAssets: content.backAudioAssets,
        imageAssets: content.backImageAssets,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isRevealed ? null : onReveal,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.xl + AppSpacing.xs),
        // ADR 0062：复习主卡是全页焦点 → teal L2 玻璃。
        // 翻面后用更高的淡彩浓度表示「已揭示」，不再另造一套底色 + 描边。
        decoration: TurnaTheme.glassDecoration(
          context,
          TurnaTheme.glassFocus,
          level: GlassLevel.l2,
          borderRadius: TurnaTheme.borderRadius,
          scale: isRevealed ? 1.25 : 1.0,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              content.frontText.isNotEmpty ? content.frontText : '—',
              style: AppTextStyles.termHero(context),
              textAlign: TextAlign.center,
            ),
            if (content.frontPronunciation != null &&
                content.frontPronunciation!.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                '/${content.frontPronunciation}/',
                style: AppTextStyles.bodyText(context).copyWith(
                  color: TurnaTheme.textSecondaryColor(context),
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            _frontMedia(),
            const SizedBox(height: AppSpacing.lg),
            IconButton(
              tooltip: AppStrings.reviewSrsPlayPronunciation,
              onPressed: onSpeak,
              icon: const TurnaIcon(
                TurnaIconId.speaker,
                size: 28,
                color: TurnaTheme.brandTeal,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            if (isRevealed) ...[
              Divider(height: 1, color: TurnaTheme.dividerBg(context)),
              const SizedBox(height: AppSpacing.xl - AppSpacing.xs),
              Text(
                content.backText,
                style: AppTextStyles.promptLg(context).copyWith(
                  fontWeight: FontWeight.w700,
                  color: TurnaTheme.brandTeal,
                ),
                textAlign: TextAlign.center,
              ),
              if (content.backNote != null && content.backNote!.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  content.backNote!,
                  style: AppTextStyles.captionSm(context),
                  textAlign: TextAlign.center,
                ),
              ],
              if (content.lessonName != null &&
                  content.lessonName!.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                Text(
                  AppStrings.reviewSrsLearnedIn(content.lessonName!),
                  style: AppTextStyles.captionSm(context)
                      .copyWith(color: TurnaTheme.textHintColor(context)),
                ),
              ],
              _backMedia(),
            ] else ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                AppStrings.reviewSrsTapToReveal,
                style: AppTextStyles.captionSm(context)
                    .copyWith(color: TurnaTheme.textHintColor(context)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
