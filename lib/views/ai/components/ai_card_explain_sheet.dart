// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/ai/ai_card_context_resolver.dart';
import 'package:turna/application/ai/ai_card_explain_provider.dart';
import 'package:turna/application/ai/ai_explain_prefs.dart';
import 'package:turna/application/ai/ai_saved_explanations.dart';
import 'package:turna/application/ai/engine/ai_engine_config_holder.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/ai/components/ai_not_configured_panel.dart';
import 'package:turna/views/ai/components/ai_sheet_widgets.dart';
import 'package:turna/views/theme.dart';

/// Lightweight sheet: explain an SRS/Anki card without mutating scores/notes.
Future<void> showAiCardExplainSheet(
  BuildContext context, {
  required AiCardContext cardContext,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: TurnaTheme.cardBg(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(TurnaTheme.radiusXLarge),
      ),
    ),
    builder: (sheetCtx) {
      AiExplainPrefsStore? prefs;
      try {
        prefs = context.read<AiExplainPrefsStore>();
      } catch (_) {}
      return ChangeNotifierProvider(
        create: (_) => AiCardExplainProvider(prefs: prefs),
        child: _AiCardExplainBody(
          cardContext: cardContext,
        ),
      );
    },
  );
}

class _AiCardExplainBody extends StatefulWidget {
  const _AiCardExplainBody({
    required this.cardContext,
  });

  final AiCardContext cardContext;

  @override
  State<_AiCardExplainBody> createState() => _AiCardExplainBodyState();
}

class _AiCardExplainBodyState extends State<_AiCardExplainBody> {
  bool _seeded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeSeed());
  }

  void _maybeSeed() {
    if (_seeded || !mounted) return;
    _seeded = true;
    final config = context.read<AiEngineConfigHolder>().config;
    if (!config.isComplete) return;
    context.read<AiCardExplainProvider>().explain(
          config: config,
          context: widget.cardContext,
        );
  }

  @override
  Widget build(BuildContext context) {
    final config = context.watch<AiEngineConfigHolder>().config;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome_rounded,
                    color: TurnaTheme.brandTeal, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    AppStrings.aiExplainCardTitle,
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
            ),
            Text(
              AppStrings.aiExplainCardDisclaimer,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: TurnaTheme.textSecondaryColor(context),
                  ),
            ),
            const SizedBox(height: 12),
            if (!config.isComplete)
              const AiNotConfiguredPanel(compact: true)
            else
              Flexible(
                fit: FlexFit.loose,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 360),
                  child: Selector<
                      AiCardExplainProvider,
                      ({
                        AiCardExplainState state,
                        String? error,
                        bool hasText,
                      })>(
                    selector: (_, p) => (
                      state: p.state,
                      error: p.error,
                      hasText: p.explanation?.isNotEmpty ?? false,
                    ),
                    builder: (context, snap, _) {
                      final p = context.read<AiCardExplainProvider>();
                      if (snap.state == AiCardExplainState.loading &&
                          !snap.hasText) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: CircularProgressIndicator(
                              color: TurnaTheme.brandTeal,
                            ),
                          ),
                        );
                      }
                      if (snap.error != null && !snap.hasText) {
                        return Text(
                          snap.error!,
                          style: const TextStyle(color: TurnaTheme.error),
                        );
                      }
                      final text = p.explanation ?? '';
                      return AiSurfaceCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: SingleChildScrollView(
                                child: const _StreamingCardExplanation(),
                              ),
                            ),
                            if (snap.state == AiCardExplainState.ready &&
                                text.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  TextButton.icon(
                                    onPressed: () {
                                      Clipboard.setData(
                                          ClipboardData(text: text));
                                      ScaffoldMessenger.maybeOf(context)
                                          ?.showSnackBar(
                                        SnackBar(
                                            content:
                                                Text(AppStrings.aiDepthCopied)),
                                      );
                                    },
                                    icon: const Icon(Icons.copy_rounded,
                                        size: 18),
                                    label: Text(AppStrings.aiDepthCopy),
                                  ),
                                  TextButton.icon(
                                    onPressed: () async {
                                      final store = context
                                          .read<AiSavedExplanationsStore>();
                                      await store.save(SavedExplanation(
                                        id: AiSavedExplanationsStore.newId(),
                                        title: widget.cardContext
                                                    .questionPlainText.length >
                                                40
                                            ? '${widget.cardContext.questionPlainText.substring(0, 40)}…'
                                            : widget
                                                .cardContext.questionPlainText,
                                        body: text,
                                        source: 'review',
                                        language: widget.cardContext.language,
                                        createdAt: DateTime.now(),
                                      ));
                                      if (context.mounted) {
                                        ScaffoldMessenger.maybeOf(context)
                                            ?.showSnackBar(
                                          SnackBar(
                                              content: Text(AppStrings
                                                  .aiExplanationSaved)),
                                        );
                                      }
                                    },
                                    icon: const Icon(
                                        Icons.bookmark_add_outlined,
                                        size: 18),
                                    label: Text(AppStrings.aiSaveExplanation),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The only sheet subtree rebuilt for each coalesced streaming batch.
class _StreamingCardExplanation extends StatelessWidget {
  const _StreamingCardExplanation();

  @override
  Widget build(BuildContext context) {
    return Selector<AiCardExplainProvider, int>(
      selector: (_, p) => p.streamingRevision,
      builder: (context, _, __) => Text(
        context.read<AiCardExplainProvider>().explanation ?? '',
      ),
    );
  }
}
