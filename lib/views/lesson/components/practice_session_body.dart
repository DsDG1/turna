// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/core/theme.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/lesson/components/interactions/interaction_renderer.dart';
import 'package:turna/views/lesson/components/lesson_stage_widgets.dart';

/// Shared lesson-practice chrome: stage banner, optional header (reading
/// passage), scrollable renderer, continue button.
class PracticeSessionBody extends StatelessWidget {
  const PracticeSessionBody({
    super.key,
    required this.child,
    this.stageName,
    this.stageAccent,
    this.header,
    this.scrollController,
    this.interactionKey,
    this.showCheck = false,
    this.checkLabel,
    this.onAdvance,
    this.wrapRendererBoundary = false,
  });

  final Widget child;
  final String? stageName;
  final Color? stageAccent;
  final Widget? header;
  final ScrollController? scrollController;
  final Key? interactionKey;
  final bool showCheck;
  final String? checkLabel;
  final VoidCallback? onAdvance;
  final bool wrapRendererBoundary;

  @override
  Widget build(BuildContext context) {
    Widget scrollChild = interactionKey == null
        ? child
        : KeyedSubtree(key: interactionKey, child: child);
    Widget scroller = SingleChildScrollView(
      controller: scrollController,
      padding: const EdgeInsets.only(top: 8, bottom: 16),
      child: scrollChild,
    );
    if (wrapRendererBoundary) {
      scroller = RepaintBoundary(child: scroller);
    }
    return Column(
      children: [
        if (stageName != null)
          LessonStageBanner(
            name: stageName!,
            accent: stageAccent ?? TurnaTheme.brandTeal,
          ),
        if (header != null) header!,
        Expanded(child: scroller),
        if (showCheck)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: LessonCheckButton(
                label: checkLabel ?? AppStrings.lessonContinueUpper,
                enabled: true,
                onPressed: onAdvance,
              ),
            ),
          ),
      ],
    );
  }
}
