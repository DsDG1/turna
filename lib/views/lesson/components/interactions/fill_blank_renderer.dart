// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/application/smart_speech.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/turkish_text.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/lesson/components/anki_media_strip.dart';
import 'package:turna/views/lesson/components/interactions/interaction_fields.dart';
import 'package:turna/views/lesson/components/interactions/interaction_renderer.dart';
import 'package:turna/views/widgets/session_shell.dart';
import 'package:turna/views/widgets/tts_feedback.dart';
import 'package:turna/core/theme.dart';

/// Fill in a blanked word in a sentence. The data uses `_____` to mark the
/// gap; we replace the first occurrence with a tappable [TextField].
/// Matching is case-insensitive and whitespace-trimmed.
///
/// With non-empty `choices` the exercise becomes 选择填空: the gap is filled
/// by tapping a word chip (which reads the word aloud) instead of typing.
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
      choices: i.choices,
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
  final List<String> choices;
  final List<String> audioAssets;
  final List<String> imageAssets;
  final InteractionState state;
  final OnInteractionSubmit onSubmit;

  const _FillBlankBody({
    required this.sentence,
    required this.answer,
    required this.hint,
    required this.choices,
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

  /// 选择填空模式当前选中的词块; `null` 表示还没选. 打字模式不使用.
  String? _selectedChoice;

  /// 选择填空模式: 词块点选代替键盘输入.
  bool get _useChoices => widget.choices.isNotEmpty;

  /// 文本类题型的"能否提交"来自 controller, 输入变化不会重建父 widget ——
  /// 所以既要 build 时同步一次首帧, 也要监听输入变化.
  void _syncDraft(BuildContext context) {
    final canSubmit = !widget.state.submitted &&
        (_useChoices
            ? _selectedChoice != null
            : _controller.text.trim().isNotEmpty);
    LessonActionScope.maybeOf(context)?.report(
      canSubmit: canSubmit,
      submit: canSubmit ? _trySubmit : null,
    );
  }

  void _onTextChanged() {
    if (!mounted) return;
    _syncDraft(context);
  }

  late (String, String) _split;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
    _split = _splitOnBlank(widget.sentence);
    if (widget.state.submitted && widget.state.userAnswerText != null) {
      _controller.text = widget.state.userAnswerText!;
      if (_useChoices && widget.choices.contains(widget.state.userAnswerText)) {
        _selectedChoice = widget.state.userAnswerText;
      }
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
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  bool _matches(String input) =>
      foldTurkish(input.trim()) == foldTurkish(widget.answer.trim());

  void _trySubmit() {
    if (widget.state.submitted) return;
    final text = _useChoices ? _selectedChoice : _controller.text;
    if (text == null || text.trim().isEmpty) return;
    widget.onSubmit(_matches(text), userAnswerText: text);
    if (!_useChoices) {
      // Drop the soft keyboard once the answer is locked in — the field is
      // disabled on submit and the CONTINUE/GOT IT button takes over, so the
      // keyboard would otherwise sit over it until the user dismisses it.
      FocusScope.of(context).unfocus();
    }
  }

  Future<void> _pickChoice(String choice) async {
    if (widget.state.submitted) return;
    setState(() => _selectedChoice = choice);
    // 点词读音: 词块是题目本身的语言材料, 点一下就念一遍 (目标语语音).
    final result = await speakTargetChip(choice);
    if (result != null && mounted) {
      showTtsFailureFeedback(context, result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final submitted = widget.state.submitted;
    final correct = widget.state.correct;

    final (before, after) = _split;
    // 句中内联空与独立书写区共用同一判分配色（interaction_fields 收口处）。
    final verdict =
        interactionVerdictOf(submitted: submitted, correct: correct);

    _syncDraft(context);

    return InteractionBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.audioAssets.isNotEmpty ||
              widget.imageAssets.isNotEmpty) ...[
            Center(
              child: AnkiMediaStrip(
                audioAssets: widget.audioAssets,
                imageAssets: widget.imageAssets,
              ),
            ),
            const SizedBox(height: 12),
          ],
          // 完整上下文在纸面画布上（§7.1 输入族「上方保留完整上下文」）。
          SessionRecallCanvas(
            minHeight: 130,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.edit_note_rounded,
                      size: 18,
                      color: TurnaTheme.brandTeal,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      AppStrings.lessonFillBlankCaption,
                      style: AppTextStyles.caption(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                RichText(
                  textAlign: TextAlign.start,
                  text: TextSpan(
                    style:
                        AppTextStyles.promptLg(context).copyWith(height: 1.4),
                    children: [
                      TextSpan(text: before),
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: _buildBlank(context, verdict),
                      ),
                      TextSpan(text: after),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_useChoices) ...[
            const SizedBox(height: 20),
            SectionCaption(AppStrings.lessonWordBank),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                // Key by position: choices may repeat a word, and ValueKey
                // (token) would collide across siblings (same lesson as the
                // reorder word bank).
                for (var i = 0; i < widget.choices.length; i++)
                  WordChip(
                    key: ValueKey(i),
                    label: widget.choices[i],
                    selected: _selectedChoice == widget.choices[i],
                    onTap: submitted
                        ? null
                        : () => unawaited(_pickChoice(widget.choices[i])),
                  ),
              ],
            ),
          ],
          if (widget.hint != null && widget.hint!.isNotEmpty) ...[
            const SizedBox(height: 20),
            Center(child: InteractionHintChip(label: widget.hint!)),
          ],
          if (submitted) ...[
            const SizedBox(height: 16),
            InteractionFeedbackPanel(
              correct: correct == true,
              userAnswer: widget.state.userAnswerText,
              correctAnswer: widget.answer,
            ),
          ],
        ],
      ),
    );
  }

  /// The inline gap. 选择填空 shows the picked word (or a placeholder);
  /// 打字模式 keeps the tappable [TextField].
  Widget _buildBlank(BuildContext context, InteractionVerdict verdict) {
    final outline = verdict.outlineColor() ?? TurnaTheme.brandTeal;
    final border = Border.all(color: outline, width: 2);

    if (!_useChoices) {
      return ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 100),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: verdict.fillColor(context),
            border: border,
            borderRadius: BorderRadius.circular(TurnaTheme.radiusSmall),
          ),
          child: TextField(
            controller: _controller,
            enabled: !widget.state.submitted,
            autofocus: !widget.state.submitted,
            textAlign: TextAlign.center,
            style: AppTextStyles.promptMd(context).copyWith(fontSize: 18),
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
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 96),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: verdict.fillColor(context),
          border: border,
          borderRadius: BorderRadius.circular(TurnaTheme.radiusSmall),
        ),
        child: Text(
          _selectedChoice ?? AppStrings.lessonFillBlankHint,
          textAlign: TextAlign.center,
          style: _selectedChoice == null
              ? TextStyle(
                  fontSize: 14,
                  color: TurnaTheme.textHintColor(context),
                )
              : AppTextStyles.promptMd(context)
                  .copyWith(fontSize: 18, fontWeight: FontWeight.w600),
        ),
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
