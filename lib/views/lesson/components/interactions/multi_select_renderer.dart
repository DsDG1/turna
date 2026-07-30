// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:varnamala/core/spacing.dart';
import 'package:varnamala/core/text_styles.dart';
import 'package:varnamala/domain/course/interaction.dart';
import 'package:varnamala/l10n/app_strings.dart';
import 'package:varnamala/views/lesson/components/cached_asset_image.dart';
import 'package:varnamala/views/lesson/components/interactions/interaction_renderer.dart';
import 'package:varnamala/views/theme.dart';

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
    final l10n = AppStrings;
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

    return InteractionBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionCaption(AppStrings.lessonSelectAllCaption),
          Text(
            widget.prompt,
            style: AppTextStyles.promptLg(context).copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            _selectionSummary(),
            style: AppTextStyles.promptMd(context).copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: VarnamalaTheme.textSecondaryColor(context),
            ),
          ),
          if (widget.imageAsset != null) ...[
            const SizedBox(height: 16),
            RoundedCachedAssetImage(asset: widget.imageAsset!),
          ],
          const SizedBox(height: 24),
          ..._buildOptions(submitted, correct),
          const SizedBox(height: 20),
          LessonCheckButton(
            label: submitted ? AppStrings.lessonChecked : AppStrings.lessonCheck,
            enabled: _canSubmit,
            onPressed: _canSubmit
                ? () => widget.onSubmit(
                      _isCorrect(),
                      userAnswerText: (_picked.toList()..sort()).join(','),
                    )
                : null,
          ),
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
        isSelected: isSelected,
        isCorrect: submitted && correctSet.contains(idx),
        isWrong: submitted &&
            correct == false &&
            isSelected &&
            !correctSet.contains(idx),
        onTap: submitted ? null : () => _toggle(idx),
      ));
      if (idx < widget.options.length - 1) {
        widgets.add(const SizedBox(height: 10));
      }
    }
    return widgets;
  }
}
