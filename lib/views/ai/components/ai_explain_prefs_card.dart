// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/ai/ai_explain_prefs.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/ai/components/ai_sheet_widgets.dart';
import 'package:turna/views/widgets/turna_select.dart';

/// AI 助手偏好 (Plan 2 §6.2 / §19.1): reply language, explanation depth,
/// reveal-answer policy and learner-context injection. These are *assistant*
/// preferences, not connection settings — the card lives on the AI Hub, not
/// the AI connection page.
class AiExplainPrefsCard extends StatelessWidget {
  const AiExplainPrefsCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AiExplainPrefsStore>(
      builder: (context, prefs, _) {
        return AiGroupCard(
          icon: Icons.school_outlined,
          title: AppStrings.aiPrefsSectionTitle,
          children: [
            _label(context, AppStrings.aiPrefsReplyLanguage),
            const SizedBox(height: 8),
            TurnaSegmented<AiReplyLanguage>(
              selected: prefs.replyLanguage,
              onChanged: prefs.setReplyLanguage,
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
            const SizedBox(height: 12),
            _label(context, AppStrings.aiPrefsDepth),
            const SizedBox(height: 8),
            TurnaSegmented<AiExplainDepth>(
              selected: prefs.depth,
              onChanged: prefs.setDepth,
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
            _switchRow(
              context,
              label: AppStrings.aiPrefsAllowReveal,
              value: prefs.allowRevealAnswer,
              onChanged: prefs.setAllowRevealAnswer,
            ),
            _switchRow(
              context,
              label: AppStrings.aiPrefsInjectContext,
              value: prefs.injectLearnerContext,
              onChanged: prefs.setInjectLearnerContext,
            ),
          ],
        );
      },
    );
  }

  /// SwitchListTile asserts when nested inside a colored DecoratedBox
  /// (AiGroupCard), so compose the row manually.
  Widget _switchRow(
    BuildContext context, {
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _label(BuildContext context, String text) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
    );
  }
}
