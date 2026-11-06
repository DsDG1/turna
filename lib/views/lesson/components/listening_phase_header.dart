import 'package:flutter/material.dart';
import 'package:turna/application/audio_controller.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/course/listening_phase.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/lesson/components/listening_audio_panel.dart';
import 'package:turna/views/widgets/tts_feedback.dart';

class ListeningPhaseHeader extends StatefulWidget {
  const ListeningPhaseHeader({super.key, required this.phase});

  final ListeningPhase phase;

  @override
  State<ListeningPhaseHeader> createState() => _ListeningPhaseHeaderState();
}

class _ListeningPhaseHeaderState extends State<ListeningPhaseHeader> {
  bool _hasPlayed = false;
  bool _showTranscript = false;

  @override
  void didUpdateWidget(covariant ListeningPhaseHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.phase.id != widget.phase.id) {
      _hasPlayed = false;
      _showTranscript = false;
    }
  }

  Future<void> _play() async {
    final result = await getIt<AudioController>().speakListenContentWithResult(
      audioAsset: widget.phase.audioAsset,
      transcript: widget.phase.transcript,
    );
    if (!mounted) return;
    setState(() => _hasPlayed = true);
    showTtsFailureFeedback(context, result);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: ListeningAudioPanel(
        title: AppStrings.lessonListeningDialogue,
        prompt: widget.phase.name,
        hasPlayed: _hasPlayed,
        onPlay: _play,
        transcript: widget.phase.transcript,
        showTranscript: _showTranscript,
        onToggleTranscript: () =>
            setState(() => _showTranscript = !_showTranscript),
        compact: true,
      ),
    );
  }
}
