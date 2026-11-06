// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/core/spacing.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/lesson/components/cached_asset_image.dart';
import 'package:turna/views/lesson/components/interactions/interaction_fields.dart';
import 'package:turna/views/lesson/components/interactions/interaction_renderer.dart';
import 'package:turna/views/widgets/session_shell.dart';

/// Pick one or more options out of N.
///
/// Used for listening exercises such as "select the 3 words you heard".
/// The learner can toggle options on/off; submit is enabled once the number
/// of selected options falls within [minSelections] and [maxSelections].
@injectable
class MultiSelectRenderer extends InteractionRenderer {
  @override
  Type get handlesType => MultiSelect;

  @override
  Widget build(
    Interaction interaction,
    InteractionState state,
    OnInteractionSubmit onSubmit,
  ) {
    final i = interaction as MultiSelect;
    return _MultiSelectBody(
      prompt: i.prompt,
      options: i.options,
      correctIndices: i.correctIndices,
      minSelections: i.minSelections,
      maxSelections: i.maxSelections,
      imageAsset: i.imageAsset,
      state: state,
      onSubmit: onSubmit,
    );
  }
}

class _MultiSelectBody extends StatefulWidget {
  final String prompt;
  final List<String> options;
  final List<int> correctIndices;
  final int minSelections;
  final int maxSelections;
  final String? imageAsset;
  final InteractionState state;
  final OnInteractionSubmit onSubmit;

  const _MultiSelectBody({
    required this.prompt,
    required this.options,
    required this.correctIndices,
    required this.minSelections,
    required this.maxSelections,
    required this.imageAsset,
    required this.state,
    required this.onSubmit,
  });

  @override
  State<_MultiSelectBody> createState() => _MultiSelectBodyState();
}

class _MultiSelectBodyState extends State<_MultiSelectBody> {
  final Set<int> _picked = {};

  @override
  void initState() {
    super.initState();
    if (widget.state.submitted) {
      _restorePicked();
    }
  }

  @override
  void didUpdateWidget(covariant _MultiSelectBody old) {
    super.didUpdateWidget(old);
    if (widget.state.submitted && !old.state.submitted) {
      _restorePicked();
    }
  }

  void _restorePicked() {
    final answer = widget.state.userAnswerText;
    if (answer != null && answer.isNotEmpty) {
      _picked.clear();
      for (final part in answer.split(',')) {
        final idx = int.tryParse(part.trim());
        if (idx != null && idx >= 0 && idx < widget.options.length) {
          _picked.add(idx);
        }
      }
    } else {
      _picked.clear();
      _picked.addAll(widget.correctIndices);
    }
  }

  bool get _canSubmit {
    if (widget.state.submitted) return false;
    return _picked.length >= widget.minSelections &&
        _picked.length <= widget.maxSelections;
  }

  bool _isCorrect() {
    final correct = widget.correctIndices.toSet();
    return _picked.length == correct.length && _picked.containsAll(correct);
  }

  void _toggle(int index) {
    if (widget.state.submitted) return;
    setState(() {
      if (_picked.contains(index)) {
        _picked.remove(index);
      } else {
        _picked.add(index);
      }
    });
  }

  String _selectionSummary() {
    final count = _picked.length;
    final min = widget.minSelections;
    final max = widget.maxSelections;
    if (max == 2147483647) {
      return AppStrings.lessonSelectAtLeast(min, count);
    }
    if (min == max) {
      return AppStrings.lessonSelectExact(min, count);
    }
    return AppStrings.lessonSelectRange(min, max, count);
  }

  @override
  Widget build(BuildContext context) {
    final submitted = widget.state.submitted;
    final correct = widget.state.correct;

    // 按钮由页面底栏统一画; 这里只报"能不能提交 / 提交做什么".
    LessonActionScope.maybeOf(context)?.report(
      canSubmit: _canSubmit,
      submit: _canSubmit
          ? () => widget.onSubmit(
                _isCorrect(),
                userAnswerText: (_picked.toList()..sort()).join(','),
              )
          : null,
    );

    return InteractionBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SessionRecallCanvas(
            minHeight: 120,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.checklist_rounded,
                      size: 18,
                      color: TurnaTheme.brandTeal,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        AppStrings.lessonSelectAllCaption,
                        style: AppTextStyles.caption(context),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  widget.prompt,
                  style: AppTextStyles.promptLg(context).copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (widget.imageAsset != null) ...[
                  const SizedBox(height: 16),
                  RoundedCachedAssetImage(asset: widget.imageAsset!),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          // 操作提示行（§7.1「多选显示操作提示」）: 紧贴选项区而不是挤在题面里。
          Text(
            _selectionSummary(),
            style: AppTextStyles.captionSm(context),
          ),
          const SizedBox(height: AppSpacing.sm),
          ..._buildOptions(submitted, correct),
          if (submitted) ...[
            const SizedBox(height: AppSpacing.lg),
            InteractionFeedbackPanel(
              correct: correct == true,
              userAnswer: (_picked.toList()..sort())
                  .map((i) => widget.options[i])
                  .join('、'),
              correctAnswer: (widget.correctIndices.toList()..sort())
                  .map((i) => widget.options[i])
                  .join('、'),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildOptions(bool submitted, bool? correct) {
    final correctSet = widget.correctIndices.toSet();
    final widgets = <Widget>[];
    for (var idx = 0; idx < widget.options.length; idx++) {
      final isSelected = _picked.contains(idx);
      widgets.add(InteractionOptionTile(
        label: widget.options[idx],
        index: idx + 1,
        isSelected: isSelected,
        isCorrect: submitted && correctSet.contains(idx),
        isWrong: submitted &&
            correct == false &&
            isSelected &&
            !correctSet.contains(idx),
        showDivider: idx < widget.options.length - 1,
        onTap: submitted ? null : () => _toggle(idx),
      ));
    }
    return widgets;
  }
}
