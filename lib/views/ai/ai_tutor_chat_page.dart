// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/ai/ai_error_mapper.dart';
import 'package:turna/application/ai/ai_explain_prefs.dart';
import 'package:turna/application/ai/ai_tutor_chat_provider.dart';
import 'package:turna/application/ai/chat_auto_scroll_coordinator.dart';
import 'package:turna/application/ai/engine/ai_engine_config_holder.dart';
import 'package:turna/application/language_provider.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/ai/chat_bubble.dart';
import 'package:turna/views/ai/components/ai_error_banner.dart';
import 'package:turna/views/ai/components/ai_not_configured_panel.dart';
import 'package:turna/views/ai/components/ai_sheet_widgets.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/views/widgets/turna_select.dart';

String _tutorModeLabel(String modeName) {
  return switch (modeName) {
    'sentenceCheck' => AppStrings.aiTutorChatModeSentence,
    'roleplay' => AppStrings.aiTutorChatModeRoleplay,
    _ => AppStrings.aiTutorChatModeQa,
  };
}

/// Free AI companion chat (Q&A / sentence-check / role-play).
///
/// Rebuild scoping (Plan 3 §21.2): only the streaming bubble listens to the
/// high-frequency [AiTutorChatProvider.streamingRevision]; the shell, mode
/// tabs, history bubbles, error banner, activity bar and composer each
/// select the small immutable slice they depend on. A token batch therefore
/// rebuilds one bubble, not the whole page.
///
/// [initialMode] is consumed on open so callers can land directly on a
/// specific mode (问一问/句子纠错/情景对话).
@RoutePage()
class AiTutorChatPage extends StatefulWidget {
  const AiTutorChatPage({super.key, this.initialMode});

  final AiTutorChatMode? initialMode;

  @override
  State<AiTutorChatPage> createState() => _AiTutorChatPageState();
}

class _AiTutorChatPageState extends State<AiTutorChatPage> {
  late final AiTutorChatProvider _provider;
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  late final ChatAutoScrollCoordinator _autoScroll;

  @override
  void initState() {
    super.initState();
    AiExplainPrefsStore? prefs;
    try {
      prefs = context.read<AiExplainPrefsStore>();
    } catch (_) {/* prefs provider optional — fall back to defaults */}
    _provider = AiTutorChatProvider(prefs: prefs);
    final restored = _provider.restorePersisted();
    if (!restored) {
      _provider.setLanguage(context.read<LanguageProvider>().displayName);
    }
    if (widget.initialMode != null) {
      _provider.setMode(widget.initialMode!);
    }
    _autoScroll = ChatAutoScrollCoordinator()..attach(_scrollCtrl);
    _provider.addListener(_onProviderChanged);
  }

  int _lastMessageCount = 0;
  int _lastRevision = 0;
  AiTutorChatState _lastState = AiTutorChatState.idle;

  /// Single scheduling point for scroll behavior (§21.3): jumps on new
  /// messages, throttled follows on content batches, one settle on finish.
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
    if (state != _lastState) {
      final wasLoading = _lastState == AiTutorChatState.loading;
      _lastState = state;
      if (wasLoading && state != AiTutorChatState.loading) {
        _autoScroll.onStreamFinished();
      }
    }
    _lastRevision = revision;
  }

  @override
  void dispose() {
    // Cancel the in-flight stream and timers before tearing down (§21.4).
    _provider.removeListener(_onProviderChanged);
    _provider.cancel();
    _autoScroll.dispose();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _provider.dispose();
    super.dispose();
  }

  Future<void> _openSessionList(BuildContext context) async {
    final sessions = _provider.savedSessions;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: TurnaTheme.cardBg(context),
      showDragHandle: true,
      builder: (sheetContext) {
        if (sessions.isEmpty) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
            child: Text(AppStrings.aiTutorSessionEmpty),
          );
        }
        return SafeArea(
          child: ListView.builder(
            itemCount: sessions.length,
            itemBuilder: (context, index) {
              final session = sessions[index];
              final title = session.title.isEmpty
                  ? AppStrings.aiTutorChatTitle
                  : session.title;
              return ListTile(
                title:
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(_tutorModeLabel(session.modeName)),
                onTap: () {
                  _provider.openSavedSession(session.id);
                  Navigator.of(sheetContext).pop();
                },
                trailing: IconButton(
                  tooltip: AppStrings.aiTutorDeleteSession,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    await _provider.deleteSavedSession(session.id);
                    if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                  },
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _onSend() async {
    if (_provider.state == AiTutorChatState.loading) return;
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    final config = context.read<AiEngineConfigHolder>().config;
    _inputCtrl.clear();
    await _provider.ask(config: config, text: text);
    final draft = _provider.consumeFailedInput();
    if (draft != null && mounted) {
      _inputCtrl.text = draft;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AiTutorChatProvider>.value(
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
              tooltip: AppStrings.aiTutorSessionList,
              icon: const Icon(Icons.history_rounded),
              onPressed: () => _openSessionList(context),
            ),
            IconButton(
              tooltip: AppStrings.aiTutorNewSession,
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _provider.startNewSession,
            ),
          ],
        ),
        body: SafeArea(
          // The shell only listens to "is the AI connection configured".
          child: Selector<AiEngineConfigHolder, bool>(
            selector: (_, holder) => holder.config.isComplete,
            builder: (context, configured, _) {
              if (!configured) {
                return const Center(child: AiNotConfiguredPanel());
              }
              return Column(
                children: [
                  const _ModeSection(),
                  Expanded(
                      child: _MessageList(
                          scrollCtrl: _scrollCtrl, autoScroll: _autoScroll)),
                  const _ErrorBanner(),
                  const _ActivityIndicator(),
                  _Composer(onSend: _onSend, inputCtrl: _inputCtrl),
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
}

// ─── Mode selection (rebuilds on mode change only) ────────────────────────

class _ModeSection extends StatelessWidget {
  const _ModeSection();

  @override
  Widget build(BuildContext context) {
    return Selector<AiTutorChatProvider, AiTutorChatMode>(
      selector: (_, p) => p.mode,
      builder: (context, mode, _) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: TurnaSegmented<AiTutorChatMode>(
                selected: mode,
                onChanged: context.read<AiTutorChatProvider>().setMode,
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
              ),
            ),
            if (mode == AiTutorChatMode.roleplay) const _RoleplayChips(),
          ],
        );
      },
    );
  }
}

class _RoleplayChips extends StatelessWidget {
  const _RoleplayChips();

  @override
  Widget build(BuildContext context) {
    final scenes = [
      AppStrings.aiRoleplayDining,
      AppStrings.aiRoleplayDirections,
      AppStrings.aiRoleplayIntro,
      AppStrings.aiRoleplayShopping,
    ];
    return Selector<AiTutorChatProvider, bool>(
      selector: (_, p) => p.state == AiTutorChatState.loading,
      builder: (context, busy, _) {
        final config = context.read<AiEngineConfigHolder>().config;
        final provider = context.read<AiTutorChatProvider>();
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
                    onPressed: busy
                        ? null
                        : () => provider.startRoleplayScene(
                              config: config,
                              sceneLabel: s,
                            ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Message list (rebuilds on count/state, NOT per token) ────────────────

class _MessageList extends StatelessWidget {
  const _MessageList({required this.scrollCtrl, required this.autoScroll});

  final ScrollController scrollCtrl;
  final ChatAutoScrollCoordinator autoScroll;

  @override
  Widget build(BuildContext context) {
    return Selector<AiTutorChatProvider, (int, AiTutorChatState)>(
      selector: (_, p) => (p.messages.length, p.state),
      builder: (context, snap, _) {
        final (count, state) = snap;
        final provider = context.read<AiTutorChatProvider>();
        if (count == 0) {
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
        return NotificationListener<UserScrollNotification>(
          onNotification: (n) {
            // User intent only (not our own animateTo): upward drag locks
            // following; returning to the bottom unlocks.
            if (n.direction == ScrollDirection.forward) {
              autoScroll.lockFollow();
            } else if (n.metrics.pixels >= n.metrics.maxScrollExtent - 120) {
              autoScroll.unlockFollow();
            }
            return false;
          },
          child: ListView.builder(
            controller: scrollCtrl,
            padding: const EdgeInsets.all(12),
            itemCount: count,
            itemBuilder: (context, i) {
              final m = provider.messages[i];
              final isStreamingTarget =
                  i == count - 1 && state == AiTutorChatState.loading;
              if (isStreamingTarget) {
                if (m.content.isEmpty) {
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(AppStrings.aiThinking),
                    ),
                  );
                }
                // The ONLY widget listening to the high-frequency revision.
                return Selector<AiTutorChatProvider, int>(
                  selector: (_, p) => p.streamingRevision,
                  builder: (context, _, __) {
                    final content =
                        context.read<AiTutorChatProvider>().messages[i].content;
                    return ChatBubble(role: 'assistant', content: content);
                  },
                );
              }
              // History bubbles are immutable — no token can rebuild them.
              return ChatBubble(role: m.role, content: m.content);
            },
          ),
        );
      },
    );
  }
}

// ─── Error / activity / composer (each selects its own slice) ─────────────

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner();

  @override
  Widget build(BuildContext context) {
    return Selector<AiTutorChatProvider, AiErrorMapping?>(
      selector: (_, p) => p.errorMapping,
      builder: (context, mapping, _) {
        if (mapping == null) return const SizedBox.shrink();
        return AiErrorBanner(mapping: mapping);
      },
    );
  }
}

class _ActivityIndicator extends StatelessWidget {
  const _ActivityIndicator();

  @override
  Widget build(BuildContext context) {
    return Selector<AiTutorChatProvider, bool>(
      selector: (_, p) => p.state == AiTutorChatState.loading,
      builder: (context, busy, _) {
        if (!busy) return const SizedBox.shrink();
        return const LinearProgressIndicator();
      },
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({required this.onSend, required this.inputCtrl});

  final Future<void> Function() onSend;
  final TextEditingController inputCtrl;

  @override
  Widget build(BuildContext context) {
    return Selector<AiTutorChatProvider, bool>(
      selector: (_, p) => p.state == AiTutorChatState.loading,
      builder: (context, busy, _) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: inputCtrl,
                  decoration: aiSheetInputDecoration(
                    context,
                    hint: AppStrings.aiTutorChatHint,
                  ),
                  onSubmitted: busy ? null : (_) => onSend(),
                ),
              ),
              const SizedBox(width: 8),
              if (busy)
                IconButton.filled(
                  onPressed: context.read<AiTutorChatProvider>().cancel,
                  icon: const Icon(Icons.stop_rounded),
                  tooltip: AppStrings.aiStopGenerating,
                )
              else
                IconButton.filled(
                  onPressed: onSend,
                  icon: const Icon(Icons.send_rounded),
                  tooltip: AppStrings.commonSend,
                ),
            ],
          ),
        );
      },
    );
  }
}
