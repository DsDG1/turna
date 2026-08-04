// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/application/audio_controller.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/lesson/components/interactions/interaction_renderer.dart';
import 'package:turna/views/theme.dart';

/// Listen-only summary (or similar) card: play audio / TTS, then continue.
///
/// Always reports correct — there is nothing to grade. The lesson screen
/// shows CONTINUE (autoAdvance is false) so the learner must acknowledge.
@injectable
class ListenOnlyRenderer extends InteractionRenderer {
  @override
  Type get handlesType => ListenOnly;

  @override
  bool get autoAdvance => false;

  @override
  Widget build(
    Interaction interaction,
    InteractionState state,
    OnInteractionSubmit onSubmit,
  ) {
    final i = interaction as ListenOnly;
    return _ListenOnlyBody(
      audioAsset: i.audioAsset,
      transcript: i.transcript,
      prompt: i.prompt,
      state: state,
      onSubmit: onSubmit,
    );
  }
}

class _ListenOnlyBody extends StatefulWidget {
  final String? audioAsset;
  final String transcript;
  final String prompt;
  final InteractionState state;
  final OnInteractionSubmit onSubmit;

  const _ListenOnlyBody({
    required this.audioAsset,
    required this.transcript,
    required this.prompt,
    required this.state,
    required this.onSubmit,
  });

  @override
  State<_ListenOnlyBody> createState() => _ListenOnlyBodyState();
}

class _ListenOnlyBodyState extends State<_ListenOnlyBody> {
  bool _hasPlayed = false;

  Future<void> _speak() async {
    // Path-vs-word-id routing and asset-prefix normalization live in
    // AudioController so renderers stay free of content/path heuristics.
    await getIt<AudioController>().speakListenContent(
      audioAsset: widget.audioAsset,
      transcript: widget.transcript,
    );

    if (mounted) setState(() => _hasPlayed = true);
  }

  @override
  Widget build(BuildContext context) {
    final submitted = widget.state.submitted;
    final showTranscript =
        widget.transcript.isNotEmpty && (_hasPlayed || submitted);

    return InteractionBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionCaption(AppStrings.lessonSummaryCaption),
          const SizedBox(height: 8),
          Text(
            widget.prompt.isEmpty
                ? AppStrings.lessonListenToSummary
                : widget.prompt,
            style: AppTextStyles.promptMd(context),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          Center(
            child: SpeakerButton(onPressed: _speak),
          ),
          const SizedBox(height: 12),
          Text(
            _hasPlayed
                ? AppStrings.lessonTapToReplay
                : AppStrings.lessonTapToListen,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TurnaTheme.textHintColor(context),
                ),
            textAlign: TextAlign.center,
          ),
          if (showTranscript) ...[
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: TurnaTheme.brandTeal.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
              ),
              child: Text(
                widget.transcript,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      height: 1.5,
                      fontWeight: FontWeight.w600,
                    ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
          const SizedBox(height: 28),
          LessonCheckButton(
            label: submitted
                ? AppStrings.commonDone
                : AppStrings.lessonContinueUpper,
            enabled: !submitted,
            onPressed: submitted
                ? null
                : () => widget.onSubmit(true, userAnswerText: 'listened'),
          ),
        ],
      ),
    );
  }
}
