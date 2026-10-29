import 'package:flutter/material.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/domain/review/review_item.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/lesson/components/anki_media_strip.dart';

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
      padding: const EdgeInsets.only(top: 12),
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
      padding: const EdgeInsets.only(top: 16),
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
            _frontMedia(),
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
              _backMedia(),
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
