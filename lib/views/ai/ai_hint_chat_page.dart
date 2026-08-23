// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/ai/ai_explain_prefs.dart';
import 'package:turna/application/ai/ai_hint_provider.dart';
import 'package:turna/application/ai/ai_saved_explanations.dart';
import 'package:turna/application/ai/chat_auto_scroll_coordinator.dart';
import 'package:turna/application/ai/engine/ai_engine_config.dart';
import 'package:turna/application/ai/engine/ai_engine_config_holder.dart';
import 'package:turna/application/ai/learner_ai_context_assembler.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/ai/chat_bubble.dart';
import 'package:turna/views/ai/components/ai_not_configured_panel.dart';
import 'package:turna/views/ai/components/ai_quick_chips.dart';
import 'package:turna/views/ai/components/ai_sheet_widgets.dart';
import 'package:turna/views/theme.dart';

@RoutePage()
class AiHintChatPage extends StatefulWidget {
  /// The question this chat is about. When non-null and the provider has no
  /// conversation yet, the page seeds an explanation request on entry.
  final AiQuestionContext? context;

  const AiHintChatPage({Key? key, this.context}) : super(key: key);

  @override
  State<AiHintChatPage> createState() => _AiHintChatPageState();
}

class _AiHintChatPageState extends State<AiHintChatPage> {
  late final AiHintProvider _provider;
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  late final ChatAutoScrollCoordinator _autoScroll;
  bool _seeded = false;
  int _lastMessageCount = 0;
  int _lastRevision = 0;
  AiHintState _lastState = AiHintState.idle;

  @override
  void initState() {
    super.initState();
    _provider = context.read<AiHintProvider>();
    _autoScroll = ChatAutoScrollCoordinator()..attach(_scrollCtrl);
    _provider.addListener(_onProviderChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeSeed());
  }

  void _onProviderChanged() {
    final count = _provider.messages.length;
    final revision = _provider.streamingRevision;
    final state = _provider.state;
    if (count != _lastMessageCount) {
      _lastMessageCount = count;
      _autoScroll.onMessagesAppended();
    } else if (revision != _lastRevision) {
      _autoScroll.onContentChanged();
    }
    if (_lastState == AiHintState.loading && state != AiHintState.loading) {
      _autoScroll.onStreamFinished();
    }
    _lastRevision = revision;
    _lastState = state;
  }

  @override
  void dispose() {
    _provider.removeListener(_onProviderChanged);
    _autoScroll.dispose();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  AiEngineConfig _config() => context.read<AiEngineConfigHolder>().config;

  /// If opened without a prior explanation (e.g. routed directly), seed the
  /// first explanation turn. When opened from the hint sheet the provider
  /// already holds the conversation, so we leave it as-is.
  Future<void> _maybeSeed() async {
    if (_seeded) return;
    _seeded = true;
    final provider = context.read<AiHintProvider>();
    final cfg = _config();
    if (!cfg.isComplete) return;
    try {
      final inject = context.read<AiExplainPrefsStore>().injectLearnerContext;
      if (inject) {
        final lang = widget.context?.language ?? 'Turkish';
        provider.setLearnerContext(
          await LearnerAiContextAssembler.assemble(languageName: lang),
        );
      } else {
        provider.setLearnerContext(null);
      }
    } catch (_) {}
    if (!mounted) return;
    final ctx = widget.context;
    if (provider.messages.isEmpty && ctx != null) {
      provider.explainQuestion(config: cfg, ctx: ctx);
    }
  }

  Future<void> _onSend([String? chipText]) async {
    final text = (chipText ?? _inputCtrl.text).trim();
    if (text.isEmpty) return;
    final started =
        await context.read<AiHintProvider>().ask(config: _config(), text: text);
    if (started && chipText == null) {
      _inputCtrl.clear();
    }
  }

  Future<void> _saveLatest() async {
    final provider = context.read<AiHintProvider>();
    final reply = provider.latestReply;
    if (reply == null || reply.isEmpty) return;
    final store = context.read<AiSavedExplanationsStore>();
    final ctx = provider.context;
    await store.save(SavedExplanation(
      id: AiSavedExplanationsStore.newId(),
      title: ctx?.promptLabel ?? AppStrings.aiTutorTitle,
      body: reply,
      source: 'hint',
      language: ctx?.language,
      createdAt: DateTime.now(),
    ));
    if (mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(AppStrings.aiExplanationSaved)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctx = widget.context;
    final configured = context.watch<AiEngineConfigHolder>().config.isComplete;
    return Scaffold(
      backgroundColor: TurnaTheme.scaffoldBg(context),
      appBar: AppBar(
        title: Text(
          ctx == null
              ? AppStrings.aiTutorTitle
              : AppStrings.aiTutorTitleWithType(ctx.typeLabel),
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        backgroundColor: TurnaTheme.bottomNavBg(context),
        actions: [
          IconButton(
            tooltip: AppStrings.aiSaveExplanation,
            icon: const Icon(Icons.bookmark_add_outlined),
            onPressed: _saveLatest,
          ),
        ],
      ),
      body: SafeArea(
        child: !configured
            ? const Center(child: AiNotConfiguredPanel())
            : Column(
                children: [
                  Expanded(
                    child: Selector<
                        AiHintProvider,
                        ({
                          bool empty,
                          int count,
                          bool hasError,
                          AiHintState state,
                        })>(
                      selector: (_, w) => (
                        empty: w.messages.isEmpty,
                        count: w.messages.length,
                        hasError: w.error != null,
                        state: w.state,
                      ),
                      builder: (context, v, _) {
                        if (v.empty && v.state != AiHintState.loading) {
                          return _emptyHint();
                        }
                        final showThinking = v.state == AiHintState.loading &&
                            _lastIsUserOrEmptyAssistant(v.count);
                        final itemCount = v.count +
                            (v.hasError ? 1 : 0) +
                            (showThinking && !_hasStreamingAssistant(v.count)
                                ? 1
                                : 0);
                        return NotificationListener<UserScrollNotification>(
                          onNotification: (n) {
                            if (n.direction == ScrollDirection.forward) {
                              _autoScroll.lockFollow();
                            } else if (n.metrics.pixels >=
                                n.metrics.maxScrollExtent - 120) {
                              _autoScroll.unlockFollow();
                            }
                            return false;
                          },
                          child: ListView.builder(
                            controller: _scrollCtrl,
                            padding: const EdgeInsets.all(12),
                            itemCount: itemCount,
                            itemBuilder: (context, i) {
                              final w = context.read<AiHintProvider>();
                              if (i < w.messages.length) {
                                final m = w.messages[i];
                                final streamingTarget = i == v.count - 1 &&
                                    m.role == 'assistant' &&
                                    v.state == AiHintState.loading;
                                if (streamingTarget && m.content.isEmpty) {
                                  return _thinkingBubble();
                                }
                                if (streamingTarget) {
                                  return Selector<AiHintProvider, int>(
                                    selector: (_, p) => p.streamingRevision,
                                    builder: (context, _, __) {
                                      final latest = context
                                          .read<AiHintProvider>()
                                          .messages[i];
                                      return ChatBubble(
                                        role: latest.role,
                                        content: latest.content,
                                      );
                                    },
                                  );
                                }
                                return ChatBubble(
                                    role: m.role, content: m.content);
                              }
                              if (v.hasError && i == v.count) {
                                return _errorBubble(
                                    w.error ?? AppStrings.aiErrorUnknown);
                              }
                              return _thinkingBubble();
                            },
                          ),
                        );
                      },
                    ),
                  ),
                  Selector<AiHintProvider,
                      ({AiHintState state, bool hasAnswer})>(
                    selector: (_, w) => (
                      state: w.state,
                      hasAnswer: w.context?.hasSubmittedAnswer ?? false,
                    ),
                    builder: (context, snap, _) {
                      final busy = snap.state == AiHintState.loading;
                      return Column(
                        children: [
                          AiQuickChipsBar(
                            enabled: !busy,
                            hasUserAnswer: snap.hasAnswer,
                            onChip: (label) => _onSend(label),
                          ),
                          if (busy) const LinearProgressIndicator(),
                          _chatInputBar(busy),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              AppStrings.aiDisclaimer,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: TurnaTheme.textHintColor(context),
                                  ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
      ),
    );
  }

  bool _lastIsUserOrEmptyAssistant(int count) {
    final messages = context.read<AiHintProvider>().messages;
    if (count <= 0 || messages.isEmpty) return false;
    final last = messages[messages.length - 1];
    return last.role == 'user' ||
        (last.role == 'assistant' && last.content.isEmpty);
  }

  bool _hasStreamingAssistant(int count) {
    final messages = context.read<AiHintProvider>().messages;
    if (count <= 0 || messages.isEmpty) return false;
    final last = messages[messages.length - 1];
    return last.role == 'assistant' && last.content.isNotEmpty;
  }

  Widget _emptyHint() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          AppStrings.aiEmptyHintTutor,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }

  Widget _thinkingBubble() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: TurnaTheme.cardBg(context),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: TurnaTheme.brandTeal,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              AppStrings.aiThinking,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorBubble(String error) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: TurnaTheme.error.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
        ),
        child: Text(
          error,
          style: const TextStyle(color: TurnaTheme.error),
        ),
      ),
    );
  }

  Widget _chatInputBar(bool busy) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _inputCtrl,
              enabled: !busy,
              decoration: aiSheetInputDecoration(
                context,
                hint: AppStrings.aiAskMore,
              ),
              onSubmitted: (_) => _onSend(),
            ),
          ),
          const SizedBox(width: 8),
          if (busy)
            IconButton.filled(
              onPressed: () => context.read<AiHintProvider>().cancel(),
              icon: const Icon(Icons.stop_rounded),
              tooltip: AppStrings.aiStopGenerating,
            )
          else
            IconButton.filled(
              onPressed: () => _onSend(),
              icon: const Icon(Icons.send_rounded),
              tooltip: AppStrings.commonSend,
            ),
        ],
      ),
    );
  }
}
