// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/ai/ai_hint_provider.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/ai/components/ai_sheet_widgets.dart';
import 'package:turna/views/lesson/components/ai_depth_tutor_sheet.dart';
import 'package:turna/views/theme.dart';

/// Bottom sheet that pops up when the learner taps the AI button on a
/// lesson question. Shows the AI's explanation of the current question and
/// offers an entry point into a follow-up chat page.
///
/// The caller is expected to have already triggered
/// `AiHintProvider.explainQuestion` (so the sheet can render the loading
/// state immediately), and passes [onEnterChat] which pushes the chat route.
class AiHintSheet extends StatelessWidget {
  final VoidCallback onEnterChat;

  const AiHintSheet({Key? key, required this.onEnterChat}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final ctx = context.read<AiHintProvider>().context;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(context, ctx),
            const SizedBox(height: 12),
            Flexible(
              fit: FlexFit.loose,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: _body(context),
              ),
            ),
            const SizedBox(height: 12),
            _actions(context),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, AiQuestionContext? ctx) {
    return Row(
      children: [
        const Icon(Icons.auto_awesome_rounded,
            color: TurnaTheme.peacockTeal, size: 22),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            ctx == null
                ? AppStrings.aiHintTitle
                : AppStrings.aiHintTitleWithType(ctx.typeLabel),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        IconButton(
          tooltip: AppStrings.commonClose,
          icon: const Icon(Icons.close, size: 22),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ],
    );
  }

  Widget _body(BuildContext context) {
    return Selector<AiHintProvider, AiHintState>(
      selector: (_, w) => w.state,
      builder: (context, state, _) {
        switch (state) {
          case AiHintState.loading:
            return _loading(context);
          case AiHintState.error:
            return _error(context);
          case AiHintState.ready:
          case AiHintState.idle:
            final reply = context.read<AiHintProvider>().latestReply;
            if (reply == null || reply.isEmpty) return _loading(context);
            return SingleChildScrollView(
              child: AiSurfaceCard(
                child: SelectableText(
                  reply,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            );
        }
      },
    );
  }

  Widget _loading(BuildContext context) {
    return AiSurfaceCard(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: CircularProgressIndicator(
          color: TurnaTheme.peacockTeal,
          strokeWidth: 3,
        ),
      ),
    );
  }

  Widget _error(BuildContext context) {
    final error = context.read<AiHintProvider>().error;
    return AiSurfaceCard(
      accent: TurnaTheme.error,
      child: Text(
        error != null
            ? AppStrings.aiHintError(error)
            : AppStrings.aiHintErrorUnknown,
        style: const TextStyle(color: TurnaTheme.error),
      ),
    );
  }

  Widget _actions(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            style: aiSheetSecondaryButtonStyle(),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              backgroundColor: TurnaTheme.cardBg(context),
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(TurnaTheme.radiusXLarge),
                ),
              ),
              builder: (_) => const AiDepthTutorSheet(),
            ),
            icon: const Icon(Icons.auto_awesome_outlined),
            label: Text(AppStrings.aiDepthTutorTitle),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton.icon(
            style: aiSheetPrimaryButtonStyle(),
            onPressed: () {
              Navigator.of(context).maybePop();
              onEnterChat();
            },
            icon: const Icon(Icons.chat_outlined),
            label: Text(AppStrings.aiHintOpenChat),
          ),
        ),
      ],
    );
  }
}
