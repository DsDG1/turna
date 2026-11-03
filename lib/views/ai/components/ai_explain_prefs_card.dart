// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/ai/ai_explain_prefs.dart';
import 'package:turna/core/spacing.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/widgets/directory_rows.dart';
import 'package:turna/views/widgets/turna_select.dart';

/// AI 助手偏好 (Plan 2 §6.2 / §19.1): reply language, explanation depth,
/// reveal-answer policy and learner-context injection. These are *assistant*
/// preferences, not connection settings — the block lives on the AI Hub, not
/// the AI connection page.
///
/// R14 口径：偏好目录表单模式 —— 分区标题 + 连续表单行（label 左、值/控件
/// 右，[DirectoryValueRow]），发丝线分隔，不再包卡。
class AiExplainPrefsCard extends StatelessWidget {
  const AiExplainPrefsCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AiExplainPrefsStore>(
      builder: (context, prefs, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.pageMargin,
              ),
              child: Text(
                AppStrings.aiPrefsSectionTitle,
                style: AppTextStyles.sectionTitle(context),
              ),
            ),
            const SizedBox(height: AppSpacing.xs + 2),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.pageMargin,
              ),
              child: DirectoryValueRow(
                label: AppStrings.aiPrefsReplyLanguage,
                control: TurnaSegmented<AiReplyLanguage>(
                  selected: prefs.replyLanguage,
                  onChanged: prefs.setReplyLanguage,
                  expanded: false,
                  segments: [
                    ButtonSegment(
                      value: AiReplyLanguage.zh,
                      label: Text(AppStrings.aiPrefsReplyZh),
                    ),
                    ButtonSegment(
                      value: AiReplyLanguage.en,
                      label: Text(AppStrings.aiPrefsReplyEn),
                    ),
                    ButtonSegment(
                      value: AiReplyLanguage.target,
                      label: Text(AppStrings.aiPrefsReplyTarget),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.pageMargin,
              ),
              child: DirectoryValueRow(
                label: AppStrings.aiPrefsDepth,
                control: TurnaSegmented<AiExplainDepth>(
                  selected: prefs.depth,
                  onChanged: prefs.setDepth,
                  expanded: false,
                  segments: [
                    ButtonSegment(
                      value: AiExplainDepth.brief,
                      label: Text(AppStrings.aiPrefsDepthBrief),
                    ),
                    ButtonSegment(
                      value: AiExplainDepth.standard,
                      label: Text(AppStrings.aiPrefsDepthStandard),
                    ),
                    ButtonSegment(
                      value: AiExplainDepth.detailed,
                      label: Text(AppStrings.aiPrefsDepthDetailed),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.pageMargin,
              ),
              child: DirectoryValueRow(
                label: AppStrings.aiPrefsAllowReveal,
                control: Switch(
                  value: prefs.allowRevealAnswer,
                  onChanged: prefs.setAllowRevealAnswer,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.pageMargin,
              ),
              child: DirectoryValueRow(
                label: AppStrings.aiPrefsInjectContext,
                control: Switch(
                  value: prefs.injectLearnerContext,
                  onChanged: prefs.setInjectLearnerContext,
                ),
                showDivider: false,
              ),
            ),
          ],
        );
      },
    );
  }
}
