// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:varnamala/application/ai/ai_hint_provider.dart';
import 'package:varnamala/views/theme.dart';

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
            color: VarnamalaTheme.peacockTeal, size: 22),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            ctx == null ? 'AI hint' : 'AI hint · ${ctx.typeLabel}',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        IconButton(
          tooltip: 'Close',
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
              child: SelectableText(
                reply,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            );
        }
      },
    );
  }

  Widget _loading(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: CircularProgressIndicator(
          color: VarnamalaTheme.peacockTeal,
          strokeWidth: 3,
        ),
      ),
    );
  }

  Widget _error(BuildContext context) {
    final error = context.read<AiHintProvider>().error;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: VarnamalaTheme.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusMedium),
      ),
      child: Text(
        'Something went wrong: ${error ?? 'Unknown error'}',
        style: const TextStyle(color: VarnamalaTheme.error),
      ),
    );
  }

  Widget _actions(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: () {
              Navigator.of(context).maybePop();
              onEnterChat();
            },
            icon: const Icon(Icons.chat_outlined),
            label: const Text('Open chat'),
          ),
        ),
      ],
    );
  }
}