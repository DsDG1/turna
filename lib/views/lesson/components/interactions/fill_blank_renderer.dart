// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/core/text_styles.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/lesson/components/anki_media_strip.dart';
import 'package:turna/views/lesson/components/interactions/interaction_renderer.dart';
import 'package:turna/views/theme.dart';

/// Fill in a blanked word in a sentence. The data uses `_____` to mark the
/// gap; we replace the first occurrence with a tappable [TextField]. Matching
/// is case-insensitive and whitespace-trimmed.
@injectable
class FillBlankRenderer extends InteractionRenderer {
  @override
  Type get handlesType => FillBlank;

  @override
  Widget build(
    Interaction interaction,
    InteractionState state,
    OnInteractionSubmit onSubmit,
  ) {
    final i = interaction as FillBlank;
    return _FillBlankBody(
      sentence: i.sentence,
      answer: i.answer,
      hint: i.hint,
      audioAssets: i.audioAssets,
      imageAssets: i.imageAssets,
      state: state,
      onSubmit: onSubmit,
    );
  }
}

class _FillBlankBody extends StatefulWidget {
  final String sentence;
  final String answer;
  final String? hint;
  final List<String> audioAssets;
  final List<String> imageAssets;
  final InteractionState state;
  final OnInteractionSubmit onSubmit;

  const _FillBlankBody({
    required this.sentence,
    required this.answer,
    required this.hint,
    required this.audioAssets,
    required this.imageAssets,
    required this.state,
    required this.onSubmit,
  });

  @override
  State<_FillBlankBody> createState() => _FillBlankBodyState();
}

class _FillBlankBodyState extends State<_FillBlankBody> {
  final TextEditingController _controller = TextEditingController();
  late (String, String) _split;

  @override
  void initState() {
    super.initState();
    _split = _splitOnBlank(widget.sentence);
    if (widget.state.submitted && widget.state.userAnswerText != null) {
      _controller.text = widget.state.userAnswerText!;
    }
  }

  @override
  void didUpdateWidget(_FillBlankBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sentence != widget.sentence) {
      _split = _splitOnBlank(widget.sentence);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _matches(String input) =>
      input.trim().toLowerCase() == widget.answer.trim().toLowerCase();

  void _trySubmit() {
    final text = _controller.text;
    if (widget.state.submitted || text.trim().isEmpty) return;
    widget.onSubmit(_matches(text), userAnswerText: text);
    // Drop the soft keyboard once the answer is locked in — the field is
    // disabled on submit and the CONTINUE/GOT IT button takes over, so the
    // keyboard would otherwise sit over it until the user dismisses it.
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final submitted = widget.state.submitted;
    final correct = widget.state.correct;

    final (before, after) = _split;
    final inputBoxColor = submitted
        ? (correct == true
            ? TurnaTheme.success.withValues(alpha: 0.10)
            : TurnaTheme.error.withValues(alpha: 0.08))
        : TurnaTheme.inputFillColor(context);

    return InteractionBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          SectionCaption(AppStrings.lessonFillBlankCaption),
          if (widget.audioAssets.isNotEmpty ||
              widget.imageAssets.isNotEmpty) ...[
            Center(
              child: AnkiMediaStrip(
                audioAssets: widget.audioAssets,
                imageAssets: widget.imageAssets,
              ),
            ),
            const SizedBox(height: 8),
          ],
          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: AppTextStyles.promptLg(context).copyWith(height: 1.4),
              children: [
                TextSpan(text: before),
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 100),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: inputBoxColor,
                        border: Border.all(
                          color: submitted
                              ? (correct == true
                                  ? TurnaTheme.success
                                  : TurnaTheme.error)
                              : TurnaTheme.peacockTeal,
                          width: 2,
                        ),
                        borderRadius:
                            BorderRadius.circular(TurnaTheme.radiusSmall),
                      ),
                      child: TextField(
                        controller: _controller,
                        enabled: !submitted,
                        autofocus: !submitted,
                        textAlign: TextAlign.center,
                        style: AppTextStyles.promptMd(context)
                            .copyWith(fontSize: 18),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                          filled: false,
                          hintText: AppStrings.lessonFillBlankHint,
                        ),
                        // No setState on keystroke — CHECK enabled-state is
                        // driven by ValueListenableBuilder below.
                        onSubmitted: (_) => _trySubmit(),
                      ),
                    ),
                  ),
                ),
                TextSpan(text: after),
              ],
            ),
          ),
          if (widget.hint != null && widget.hint!.isNotEmpty) ...[
            const SizedBox(height: 20),
            _HintChip(hint: widget.hint!),
          ],
          if (submitted && correct == false) ...[
            const SizedBox(height: 16),
            LessonCorrectAnswerBanner(
                label: AppStrings.lessonCorrectAnswer,
                answer: widget.answer,
                showBorder: true),
          ],
          const SizedBox(height: 24),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (context, value, _) {
              final canSubmit = !submitted && value.text.trim().isNotEmpty;
              return LessonCheckButton(
                label: submitted
                    ? AppStrings.lessonChecked
                    : AppStrings.lessonCheck,
                enabled: canSubmit,
                onPressed: canSubmit ? _trySubmit : null,
              );
            },
          ),
        ],
      ),
    );
  }

  (String, String) _splitOnBlank(String s) {
    const marker = '_____';
    final idx = s.indexOf(marker);
    if (idx < 0) return (s, '');
    return (s.substring(0, idx), s.substring(idx + marker.length));
  }
}

class _HintChip extends StatelessWidget {
  final String hint;
  const _HintChip({required this.hint});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: TurnaTheme.warning.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(TurnaTheme.radiusRound),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lightbulb_outline,
                size: 16, color: TurnaTheme.warning),
            const SizedBox(width: 6),
            Text(
              hint,
              style: TextStyle(
                fontSize: 13,
                color: TurnaTheme.textSecondaryColor(context),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
