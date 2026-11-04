// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/core/text_styles.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/lesson/components/interactions/interaction_renderer.dart';
import 'package:turna/views/widgets/session_shell.dart';
import 'package:turna/core/theme.dart';

/// Placeholder for [AnkiHtmlCard] items persisted by retired Legacy imports
/// (doc 35 L2 deleted the NoteStore fidelity renderer). Official review
/// still renders fidelity HTML through its own surface — this renderer only
/// covers lesson bodies and mistake-log replays that still carry the type,
/// so they degrade to an acknowledge-and-continue card instead of throwing
/// in [lookupRenderer].
@injectable
class AnkiHtmlCardRetiredRenderer extends InteractionRenderer {
  @override
  Type get handlesType => AnkiHtmlCard;

  @override
  Widget build(
    Interaction interaction,
    InteractionState state,
    OnInteractionSubmit onSubmit,
  ) {
    return _RetiredAnkiHtmlCardBody(onSubmit: onSubmit);
  }
}

class _RetiredAnkiHtmlCardBody extends StatelessWidget {
  const _RetiredAnkiHtmlCardBody({required this.onSubmit});

  final OnInteractionSubmit onSubmit;

  @override
  Widget build(BuildContext context) {
    // 主操作交给页面底栏（LessonActionScope 契约）——这是最后一个在滚动
    // 内容里自画按钮的题型（P0 清点「主 CTA 位置三套并存」的残留）。
    // 没有底栏的消费面（错题练习等无 Scope 页）回退为卡内按钮, 行为不丢。
    final scope = LessonActionScope.maybeOf(context);
    scope?.report(
      canSubmit: true,
      submit: () => onSubmit(true),
      label: AppStrings.ankiRetiredCardContinue,
    );

    return InteractionBody(
      child: SessionRecallCanvas(
        minHeight: 260,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.style_outlined,
              size: 40,
              color: TurnaTheme.brandTeal.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 20),
            Text(
              AppStrings.ankiRetiredCardTitle,
              textAlign: TextAlign.center,
              style: AppTextStyles.cardTitle(context),
            ),
            const SizedBox(height: 8),
            Text(
              AppStrings.ankiRetiredCardBody,
              textAlign: TextAlign.center,
              style: AppTextStyles.captionSm(context).copyWith(height: 1.5),
            ),
            if (scope == null) ...[
              const SizedBox(height: 24),
              LessonCheckButton(
                label: AppStrings.ankiRetiredCardContinue,
                enabled: true,
                onPressed: () => onSubmit(true),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
