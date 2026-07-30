// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:varnamala/core/text_styles.dart';
import 'package:varnamala/domain/audio/anki_audio_resolver.dart';
import 'package:varnamala/domain/course/interaction.dart';
import 'package:varnamala/l10n/app_strings.dart';
import 'package:varnamala/views/lesson/components/anki_media_strip.dart';
import 'package:varnamala/views/lesson/components/cached_asset_image.dart';
import 'package:varnamala/views/lesson/components/interactions/interaction_renderer.dart';

/// Pick one of N options. Submit locks the UI and colours correct/incorrect
/// choices using [InteractionState.correct].
@injectable
class MultipleChoiceRenderer extends InteractionRenderer {
  @override
  Type get handlesType => MultipleChoice;

  @override
  Widget build(
    Interaction interaction,
    InteractionState state,
    OnInteractionSubmit onSubmit,
  ) {
    final i = interaction as MultipleChoice;
    return _MultipleChoiceBody(
      prompt: i.prompt,
      options: i.options,
      correctIndex: i.correctIndex,
      imageAsset: i.imageAsset,
      audioAssets: i.audioAssets,
      state: state,
      onSubmit: onSubmit,
    );
  }
}

class _MultipleChoiceBody extends StatefulWidget {
  final String prompt;
  final List<String> options;
  final int correctIndex;
  final String? imageAsset;
  final List<String> audioAssets;
  final InteractionState state;
  final OnInteractionSubmit onSubmit;

  const _MultipleChoiceBody({
    required this.prompt,
    required this.options,
    required this.correctIndex,
    required this.imageAsset,
    required this.audioAssets,
    required this.state,
    required this.onSubmit,
  });

  @override
  State<_MultipleChoiceBody> createState() => _MultipleChoiceBodyState();
}

class _MultipleChoiceBodyState extends State<_MultipleChoiceBody> {
  int? _picked;

  @override
  void initState() {
    super.initState();
    if (widget.state.submitted) {
      _restorePicked();
    }
  }

  @override
  void didUpdateWidget(covariant _MultipleChoiceBody old) {
    super.didUpdateWidget(old);
    if (widget.state.submitted && !old.state.submitted) {
      _restorePicked();
    }
  }

  void _restorePicked() {
    final answer = widget.state.userAnswerText;
    if (answer != null) {
      final idx = widget.options.indexOf(answer);
      _picked = idx >= 0 ? idx : widget.correctIndex;
    } else {
      _picked = widget.correctIndex;
    }
  }

  @override
  Widget build(BuildContext context) {
    final submitted = widget.state.submitted;
    final correct = widget.state.correct;
    final canSubmit = !submitted && _picked != null;

    return InteractionBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionCaption(AppStrings.lessonMultipleChoiceCaption),
          Text(
            widget.prompt,
            style: AppTextStyles.promptLg(context).copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (widget.imageAsset != null &&
              !AnkiAudioResolver.isAnkiAsset(widget.imageAsset)) ...[
            const SizedBox(height: 16),
            RoundedCachedAssetImage(asset: widget.imageAsset!),
          ],
          if (widget.audioAssets.isNotEmpty ||
              AnkiAudioResolver.isAnkiAsset(widget.imageAsset)) ...[
            const SizedBox(height: 16),
            Center(
              child: AnkiMediaStrip(
                audioAssets: widget.audioAssets,
                imageAssets: [
                  if (AnkiAudioResolver.isAnkiAsset(widget.imageAsset))
                    widget.imageAsset!,
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          ..._buildOptions(submitted, correct),
          const SizedBox(height: 20),
          LessonCheckButton(
            label: submitted ? AppStrings.lessonChecked : AppStrings.lessonCheck,
            enabled: canSubmit,
            onPressed: canSubmit
                ? () => widget.onSubmit(_picked == widget.correctIndex,
                    userAnswerText: widget.options[_picked!])
                : null,
          ),
        ],
      ),
    );
  }

  List<Widget> _buildOptions(bool submitted, bool? correct) {
    final widgets = <Widget>[];
    for (var idx = 0; idx < widget.options.length; idx++) {
      widgets.add(InteractionOptionTile(
        label: widget.options[idx],
        isSelected: _picked == idx,
        isCorrect: submitted && idx == widget.correctIndex,
        isWrong:
            submitted && correct == false && _picked == idx,
        onTap: submitted
            ? null
            : () => setState(() => _picked = idx),
      ));
      if (idx < widget.options.length - 1) {
        widgets.add(const SizedBox(height: 10));
      }
    }
    return widgets;
  }
}
