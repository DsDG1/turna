// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:varnamala/application/ai/ai_api_config.dart';
import 'package:varnamala/application/ai/ai_course_provider.dart';
import 'package:varnamala/application/ai/ai_hint_provider.dart';
import 'package:varnamala/l10n/app_localizations.dart';
import 'package:varnamala/views/ai/chat_bubble.dart';
import 'package:varnamala/views/theme.dart';

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
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  bool _seeded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeSeed());
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  AiApiConfig _config() => context.read<AiCourseProvider>().config;

  /// If opened without a prior explanation (e.g. routed directly), seed the
  /// first explanation turn. When opened from the hint sheet the provider
  /// already holds the conversation, so we leave it as-is.
  void _maybeSeed() {
    if (_seeded) return;
    _seeded = true;
    final provider = context.read<AiHintProvider>();
    final ctx = widget.context;
    if (provider.messages.isEmpty && ctx != null) {
      provider.explainQuestion(config: _config(), ctx: ctx);
    }
  }

  Future<void> _onSend() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    // Ask first; only clear the field once the turn is actually accepted,
    // so a no-op (e.g. context cleared by a concurrent reset) doesn't
    // silently swallow the user's text.
    final started = await context
        .read<AiHintProvider>()
        .ask(config: _config(), text: text);
    if (started) {
      _inputCtrl.clear();
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ctx = widget.context;
    return Scaffold(
      backgroundColor: VarnamalaTheme.scaffoldBg(context),
      appBar: AppBar(
        title: Text(
          ctx == null ? AppLocalizations.of(context)!.aiTutorTitle : AppLocalizations.of(context)!.aiTutorTitleWithType(ctx.typeLabel),
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        backgroundColor: VarnamalaTheme.bottomNavBg(context),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Selector<
                  AiHintProvider,
                  ({bool empty, int count, bool hasError, AiHintState state})>(
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
                  // Loading + no assistant reply yet → show an in-list
                  // "thinking" bubble so the message area doesn't look
                  // answered-but-unanswered.
                  final showThinking = v.state == AiHintState.loading &&
                      _lastIsUser(v.count);
                  final itemCount =
                      v.count + (v.hasError ? 1 : 0) + (showThinking ? 1 : 0);
                  return ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.all(12),
                    itemCount: itemCount,
                    itemBuilder: (context, i) {
                      final w = context.read<AiHintProvider>();
                      // Guard against a concurrent reset()/new question
                      // shrinking _messages between the Selector snapshot
                      // and this item build.
                      if (i < w.messages.length) {
                        final m = w.messages[i];
                        return ChatBubble(role: m.role, content: m.content);
                      }
                      if (v.hasError && i == v.count) {
                        return _errorBubble(w.error ?? 'Unknown error');
                      }
                      return _thinkingBubble();
                    },
                  );
                },
              ),
            ),
            Selector<AiHintProvider, AiHintState>(
              selector: (_, w) => w.state,
              builder: (context, state, _) {
                final busy = state == AiHintState.loading;
                return Column(
                  children: [
                    if (busy) const LinearProgressIndicator(),
                    _chatInputBar(busy),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  bool _lastIsUser(int count) {
    // `count` is the Selector snapshot; the live list may have shrunk via a
    // concurrent reset()/new question, so bound the index before reading.
    final messages = context.read<AiHintProvider>().messages;
    return count > 0 &&
        messages.isNotEmpty &&
        messages[messages.length - 1].role == 'user';
  }

  Widget _emptyHint() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          AppLocalizations.of(context)!.aiEmptyHintTutor,
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
          color: VarnamalaTheme.cardBg(context),
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
                color: VarnamalaTheme.peacockTeal,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              AppLocalizations.of(context)!.aiThinking,
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
          color: VarnamalaTheme.error.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(VarnamalaTheme.radiusMedium),
        ),
        child: Text(
          AppLocalizations.of(context)!.aiErrorBubble(error),
          style: const TextStyle(color: VarnamalaTheme.error),
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
              decoration: InputDecoration(
                hintText: AppLocalizations.of(context)!.aiAskMore,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (_) => _onSend(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: busy ? null : _onSend,
            icon: const Icon(Icons.send),
            tooltip: AppLocalizations.of(context)!.commonSend,
          ),
        ],
      ),
    );
  }
}