// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/ai/ai_explain_prefs.dart';
import 'package:turna/application/ai/ai_tutor_chat_provider.dart';
import 'package:turna/application/ai/engine/ai_engine_config_holder.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/ai/chat_bubble.dart';
import 'package:turna/views/ai/components/ai_not_configured_panel.dart';
import 'package:turna/views/ai/components/ai_sheet_widgets.dart';
import 'package:turna/views/theme.dart';

@RoutePage()
class AiTutorChatPage extends StatefulWidget {
  const AiTutorChatPage({Key? key}) : super(key: key);

  @override
  State<AiTutorChatPage> createState() => _AiTutorChatPageState();
}

class _AiTutorChatPageState extends State<AiTutorChatPage> {
  late final AiTutorChatProvider _provider;
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    AiExplainPrefsStore? prefs;
    try {
      prefs = context.read<AiExplainPrefsStore>();
    } catch (_) {}
    _provider = AiTutorChatProvider(prefs: prefs);
    _provider.setLanguage('Turkish');
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _provider.dispose();
    super.dispose();
  }

  Future<void> _onSend() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    final config = context.read<AiEngineConfigHolder>().config;
    final started = await _provider.ask(config: config, text: text);
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
    return ChangeNotifierProvider.value(
      value: _provider,
      child: Scaffold(
        backgroundColor: TurnaTheme.scaffoldBg(context),
        appBar: AppBar(
          title: Text(
            AppStrings.aiTutorChatTitle,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          backgroundColor: TurnaTheme.bottomNavBg(context),
          actions: [
            IconButton(
              tooltip: AppStrings.aiTutorNewSession,
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () => _provider.reset(),
            ),
          ],
        ),
        body: SafeArea(
          child: Consumer2<AiTutorChatProvider, AiEngineConfigHolder>(
            builder: (context, p, holder, _) {
              if (!holder.config.isComplete) {
                return const Center(child: AiNotConfiguredPanel());
              }
              final busy = p.state == AiTutorChatState.loading;
              return Column(
                children: [
                  _modeTabs(p),
                  if (p.mode == AiTutorChatMode.roleplay) _roleplayChips(p),
                  Expanded(child: _messageList(p)),
                  if (p.error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        p.error!,
                        style: const TextStyle(color: TurnaTheme.error),
                      ),
                    ),
                  if (busy) const LinearProgressIndicator(),
                  _inputBar(busy, p),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      AppStrings.aiDisclaimer,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: TurnaTheme.textHintColor(context),
                          ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _modeTabs(AiTutorChatProvider p) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: SegmentedButton<AiTutorChatMode>(
        segments: [
          ButtonSegment(
            value: AiTutorChatMode.qa,
            label: Text(AppStrings.aiTutorChatModeQa),
            icon: const Icon(Icons.help_outline, size: 16),
          ),
          ButtonSegment(
            value: AiTutorChatMode.sentenceCheck,
            label: Text(AppStrings.aiTutorChatModeSentence),
            icon: const Icon(Icons.spellcheck, size: 16),
          ),
          ButtonSegment(
            value: AiTutorChatMode.roleplay,
            label: Text(AppStrings.aiTutorChatModeRoleplay),
            icon: const Icon(Icons.theater_comedy_outlined, size: 16),
          ),
        ],
        selected: {p.mode},
        onSelectionChanged: (s) => p.setMode(s.first),
      ),
    );
  }

  Widget _roleplayChips(AiTutorChatProvider p) {
    final scenes = [
      AppStrings.aiRoleplayDining,
      AppStrings.aiRoleplayDirections,
      AppStrings.aiRoleplayIntro,
      AppStrings.aiRoleplayShopping,
    ];
    final config = context.read<AiEngineConfigHolder>().config;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          for (final s in scenes)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                label: Text(s),
                onPressed: p.state == AiTutorChatState.loading
                    ? null
                    : () => p.startRoleplayScene(config: config, sceneLabel: s),
              ),
            ),
        ],
      ),
    );
  }

  Widget _messageList(AiTutorChatProvider p) {
    if (p.messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            AppStrings.aiTutorChatEmpty,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.all(12),
      itemCount: p.messages.length,
      itemBuilder: (context, i) {
        final m = p.messages[i];
        if (m.role == 'assistant' &&
            m.content.isEmpty &&
            p.state == AiTutorChatState.loading) {
          return Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(AppStrings.aiThinking),
            ),
          );
        }
        return ChatBubble(role: m.role, content: m.content);
      },
    );
  }

  Widget _inputBar(bool busy, AiTutorChatProvider p) {
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
                hint: AppStrings.aiTutorChatHint,
              ),
              onSubmitted: (_) => _onSend(),
            ),
          ),
          const SizedBox(width: 8),
          if (busy)
            IconButton.filled(
              onPressed: p.cancel,
              icon: const Icon(Icons.stop_rounded),
              tooltip: AppStrings.aiStopGenerating,
            )
          else
            IconButton.filled(
              onPressed: _onSend,
              icon: const Icon(Icons.send_rounded),
              tooltip: AppStrings.commonSend,
            ),
        ],
      ),
    );
  }
}
