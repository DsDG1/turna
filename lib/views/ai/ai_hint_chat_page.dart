// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:varnamala/application/ai/ai_api_config.dart';
import 'package:varnamala/application/ai/ai_course_provider.dart';
import 'package:varnamala/application/ai/ai_hint_provider.dart';
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
    _inputCtrl.clear();
    await context.read<AiHintProvider>().ask(config: _config(), text: text);
    _scrollToBottom();
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ctx = widget.context;
    return Scaffold(
      backgroundColor: VarnamalaTheme.scaffoldBg(context),
      appBar: AppBar(
        title: Text(
          ctx == null ? 'AI 答疑' : 'AI 答疑 · ${ctx.typeLabel}',
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
                  ({bool empty, int count, bool hasError})>(
                selector: (_, w) => (
                  empty: w.messages.isEmpty,
                  count: w.messages.length,
                  hasError: w.error != null,
                ),
                builder: (context, v, _) {
                  if (v.empty && !_busy(context)) return _emptyHint();
                  return ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.all(12),
                    itemCount: v.count + (v.hasError ? 1 : 0),
                    itemBuilder: (context, i) {
                      final w = context.read<AiHintProvider>();
                      if (i == v.count && v.hasError) {
                        return _errorBubble(w.error!);
                      }
                      final m = w.messages[i];
                      return _bubble(m.role, m.content, isDark);
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

  bool _busy(BuildContext context) =>
      context.read<AiHintProvider>().state == AiHintState.loading;

  Widget _emptyHint() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'AI 正在准备这道题的讲解…',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }

  Widget _bubble(String role, String content, bool isDark) {
    final isUser = role == 'user';
    final bg = isUser
        ? VarnamalaTheme.primaryLight
        : (isDark ? const Color(0xFF2A2A2A) : Colors.white);
    final textColor =
        isUser ? Colors.white : (isDark ? Colors.white : Colors.black87);
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(content, style: TextStyle(color: textColor)),
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
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          'Error: $error',
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
              decoration: const InputDecoration(
                hintText: '继续提问…',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (_) => _onSend(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: busy ? null : _onSend,
            icon: const Icon(Icons.send),
            tooltip: '发送',
          ),
        ],
      ),
    );
  }
}