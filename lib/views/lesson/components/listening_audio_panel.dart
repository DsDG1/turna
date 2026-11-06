import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:turna/application/accessibility_capabilities.dart';
import 'package:turna/core/motion.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/lesson/components/interactions/interaction_renderer.dart';
import 'package:turna/views/widgets/session_shell.dart';

class ListeningAudioPanel extends StatelessWidget {
  const ListeningAudioPanel({
    super.key,
    required this.title,
    required this.prompt,
    required this.hasPlayed,
    required this.onPlay,
    this.transcript = '',
    this.showTranscript = false,
    this.onToggleTranscript,
    this.compact = false,
  });

  final String title;
  final String prompt;
  final bool hasPlayed;
  final VoidCallback onPlay;
  final String transcript;
  final bool showTranscript;
  final VoidCallback? onToggleTranscript;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context) ||
        accessibilityOf(context).reduceMotion;
    final hasTranscript = transcript.trim().isNotEmpty;
    return SessionRecallCanvas(
      minHeight: compact ? null : 220,
      alignment: Alignment.centerLeft,
      padding: EdgeInsets.all(compact ? 16 : 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.headphones_rounded,
                size: 18,
                color: TurnaTheme.brandTeal,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: AppTextStyles.caption(context).copyWith(
                    color: TurnaTheme.brandTeal,
                  ),
                ),
              ),
              if (hasTranscript) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    hasPlayed
                        ? AppStrings.lessonTranscriptAvailable
                        : AppStrings.lessonTranscriptAfterListening,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style:
                        AppTextStyles.captionSm(context).copyWith(fontSize: 11),
                  ),
                ),
              ],
            ],
          ),
          if (prompt.isNotEmpty) ...[
            SizedBox(height: compact ? 12 : 18),
            Text(
              prompt,
              textAlign: TextAlign.center,
              style: compact
                  ? AppTextStyles.bodyText(context).copyWith(
                      fontWeight: FontWeight.w600,
                    )
                  : AppTextStyles.promptMd(context),
            ),
          ],
          SizedBox(height: compact ? 14 : 22),
          Center(child: SpeakerHero(onPressed: onPlay)),
          const SizedBox(height: 10),
          Text(
            hasPlayed
                ? AppStrings.lessonTapToReplay
                : AppStrings.lessonTapToListen,
            textAlign: TextAlign.center,
            style: AppTextStyles.captionSm(context).copyWith(
              color: TurnaTheme.textHintColor(context),
            ),
          ),
          if (hasTranscript && hasPlayed && onToggleTranscript != null) ...[
            const SizedBox(height: 6),
            Center(
              child: TextButton.icon(
                onPressed: onToggleTranscript,
                icon: Icon(
                  showTranscript
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 18,
                ),
                label: Text(
                  showTranscript
                      ? AppStrings.lessonHideTranscript
                      : AppStrings.lessonShowTranscript,
                ),
              ),
            ),
          ],
          AnimatedSwitcher(
            duration: TurnaMotion.scaled(TurnaMotion.base, reduceMotion),
            child: showTranscript && hasTranscript
                ? Container(
                    key: const ValueKey('listening-transcript'),
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: TurnaTheme.brandTeal.withValues(alpha: 0.06),
                      borderRadius:
                          BorderRadius.circular(TurnaTheme.radiusMedium),
                    ),
                    child: Text(
                      transcript,
                      maxLines: compact ? 4 : null,
                      overflow: compact ? TextOverflow.ellipsis : null,
                      style: AppTextStyles.bodyText(context).copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  )
                : const SizedBox.shrink(
                    key: ValueKey('listening-transcript-hidden'),
                  ),
          ),
        ],
      ),
    );
  }
}

@Preview(name: 'Listening · dialogue', group: 'Lesson templates')
@Preview(
  name: 'Listening · dialogue dark',
  group: 'Lesson templates',
  brightness: Brightness.dark,
)
Widget listeningDialoguePreview() => const _ListeningPanelPreview(
      title: '对话理解',
      prompt: '听对话，再回答问题',
      transcript: 'A: Merhaba!\nB: Merhaba, nasılsın?',
      showTranscript: true,
    );

@Preview(name: 'Listening · summary', group: 'Lesson templates')
Widget listeningSummaryPreview() => const _ListeningPanelPreview(
      title: '收听概要',
      prompt: '听一段总结，回顾刚才学到的表达',
      transcript: 'Bugün temel selamlaşma ifadelerini öğrendik.',
      showTranscript: true,
    );

class _ListeningPanelPreview extends StatelessWidget {
  const _ListeningPanelPreview({
    required this.title,
    required this.prompt,
    required this.transcript,
    required this.showTranscript,
  });

  final String title;
  final String prompt;
  final String transcript;
  final bool showTranscript;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TurnaTheme.lessonCanvasBg(context),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ListeningAudioPanel(
            title: title,
            prompt: prompt,
            transcript: transcript,
            hasPlayed: true,
            showTranscript: showTranscript,
            onPlay: () {},
            onToggleTranscript: () {},
          ),
        ),
      ),
    );
  }
}
