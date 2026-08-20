import 'package:flutter/material.dart';
import 'package:turna/domain/review/review_item.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/theme.dart';

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

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isRevealed ? null : onReveal,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: TurnaTheme.cardBg(context),
          borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
          border: Border.all(
            color: TurnaTheme.brandTeal.withValues(alpha: 0.12),
          ),
          boxShadow: [
            BoxShadow(
              color: TurnaTheme.brandTeal.withValues(alpha: 0.08),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              content.frontText.isNotEmpty ? content.frontText : '—',
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: TurnaTheme.textPrimaryColor(context),
                  ),
              textAlign: TextAlign.center,
            ),
            if (content.frontPronunciation != null &&
                content.frontPronunciation!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '/${content.frontPronunciation}/',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: TurnaTheme.textSecondaryColor(context),
                      fontStyle: FontStyle.italic,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 16),
            IconButton(
              tooltip: AppStrings.reviewSrsPlayPronunciation,
              onPressed: onSpeak,
              icon: const Icon(Icons.volume_up_rounded),
              iconSize: 32,
              color: TurnaTheme.brandTeal,
            ),
            const SizedBox(height: 24),
            if (isRevealed) ...[
              const Divider(),
              const SizedBox(height: 20),
              Text(
                content.backText,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: TurnaTheme.brandTeal,
                    ),
                textAlign: TextAlign.center,
              ),
              if (content.backNote != null && content.backNote!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  content.backNote!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: TurnaTheme.textSecondaryColor(context),
                      ),
                  textAlign: TextAlign.center,
                ),
              ],
              if (content.lessonName != null &&
                  content.lessonName!.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  AppStrings.reviewSrsLearnedIn(content.lessonName!),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: TurnaTheme.textHintColor(context),
                      ),
                ),
              ],
            ] else ...[
              const SizedBox(height: 12),
              Text(
                AppStrings.reviewSrsTapToReveal,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: TurnaTheme.textHintColor(context),
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
