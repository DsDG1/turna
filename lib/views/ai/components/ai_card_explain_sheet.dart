// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/ai/ai_card_context_resolver.dart';
import 'package:turna/application/ai/ai_card_explain_provider.dart';
import 'package:turna/application/ai/ai_error_mapper.dart';
import 'package:turna/application/ai/ai_explain_prefs.dart';
import 'package:turna/application/ai/ai_saved_explanations.dart';
import 'package:turna/application/ai/engine/ai_engine_config_holder.dart';
import 'package:turna/core/spacing.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/ai/components/ai_error_banner.dart';
import 'package:turna/views/ai/components/ai_generated_notice.dart';
import 'package:turna/views/ai/components/ai_not_configured_panel.dart';
import 'package:turna/views/ai/components/ai_sheet_widgets.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/views/widgets/turna_sheet.dart';
import 'package:turna/views/widgets/turna_snack_bar.dart';

/// Lightweight sheet: explain an SRS/Anki card without mutating scores/notes.
///
/// R14：容器走全局弹层（拖手 / 标题 / 一句说明 / 关闭由 [showTurnaSheet] 给，
/// 键盘让位同理），正文只保留讲解内容与就地动作。
Future<void> showAiCardExplainSheet(
  BuildContext context, {
  required AiCardContext cardContext,
}) {
  return showTurnaSheet<void>(
    context: context,
    title: AppStrings.aiExplainCardTitle,
    subtitle: AppStrings.aiExplainCardDisclaimer,
    isScrollControlled: true,
    body: Builder(
      builder: (sheetCtx) {
        AiExplainPrefsStore? prefs;
        try {
          prefs = context.read<AiExplainPrefsStore>();
        } catch (_) {/* prefs provider optional — fall back to defaults */}
        return ChangeNotifierProvider(
          create: (_) => AiCardExplainProvider(prefs: prefs),
          child: _AiCardExplainBody(
            cardContext: cardContext,
          ),
        );
      },
    ),
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
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.pageMargin,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: AppSpacing.sm),
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
                        AiErrorMapping? errorMapping,
                        bool hasText,
                      })>(
                    selector: (_, p) => (
                      state: p.state,
                      errorMapping: p.errorMapping,
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
                      if (snap.errorMapping != null && !snap.hasText) {
                        return AiErrorBanner(
                          mapping: snap.errorMapping!,
                          onRetry: () => p.explain(
                            config: config,
                            context: widget.cardContext,
                          ),
                        );
                      }
                      final text = p.explanation ?? '';
                      return AiSurfaceCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: const [
                                    _StreamingCardExplanation(),
                                    // 显式标识：解释内容是模型输出，标识必须
                                    // 与内容同屏（《标识办法》）。
                                    AiGeneratedNotice(),
                                  ],
                                ),
                              ),
                            ),
                            if (snap.state == AiCardExplainState.ready &&
                                text.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  TextButton.icon(
                                    onPressed: () {
                                      Clipboard.setData(ClipboardData(
                                          text: labelAiGenerated(text)));
                                      TurnaSnackBar.maybeShow(
                                          context, AppStrings.aiDepthCopied);
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
                                        TurnaSnackBar.maybeShow(context,
                                            AppStrings.aiExplanationSaved);
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
