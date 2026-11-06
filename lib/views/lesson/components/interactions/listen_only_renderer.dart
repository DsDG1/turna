// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/application/audio_controller.dart';
import 'package:turna/application/smart_speech.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/lesson/components/listening_audio_panel.dart';
import 'package:turna/views/lesson/components/interactions/interaction_renderer.dart';
import 'package:turna/views/widgets/tts_feedback.dart';

/// Listen-only summary (or similar) card: play audio / TTS, then continue.
///
/// Always reports correct — there is nothing to grade. The bottom action band
/// carries the CONTINUE CTA (autoAdvance is false) so the learner must
/// acknowledge.
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

  @override
  void initState() {
    super.initState();
    maybeAutoSpeak(_speak);
  }

  Future<void> _speak() async {
    // Path-vs-word-id routing and asset-prefix normalization live in
    // AudioController so renderers stay free of content/path heuristics.
    final result = await getIt<AudioController>().speakListenContentWithResult(
      audioAsset: widget.audioAsset,
      transcript: widget.transcript,
    );

    if (!mounted) return;
    setState(() => _hasPlayed = true);
    showTtsFailureFeedback(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final submitted = widget.state.submitted;
    final showTranscript =
        widget.transcript.isNotEmpty && (_hasPlayed || submitted);

    // 「继续」CTA 交给页面底栏（P1：主操作跨题型位置稳定），提交语义
    // 不变——点按即以 always-correct 记录 'listened'。
    LessonActionScope.maybeOf(context)?.report(
      canSubmit: !submitted,
      submit: () => widget.onSubmit(true, userAnswerText: 'listened'),
      label: AppStrings.lessonContinueUpper,
    );

    return InteractionBody(
      child: ListeningAudioPanel(
        title: AppStrings.lessonSummaryCaption,
        prompt: widget.prompt.isEmpty
            ? AppStrings.lessonListenToSummary
            : widget.prompt,
        hasPlayed: _hasPlayed,
        onPlay: _speak,
        transcript: widget.transcript,
        showTranscript: showTranscript,
      ),
    );
  }
}
