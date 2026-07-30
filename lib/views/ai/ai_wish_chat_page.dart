// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:varnamala/application/ai/ai_course_provider.dart';
import 'package:varnamala/application/ai/ai_course_spec.dart';
import 'package:varnamala/application/ai/ai_genre.dart';
import 'package:varnamala/application/ai/ai_wish_provider.dart';
import 'package:varnamala/application/ai/engine/ai_engine_config.dart';
import 'package:varnamala/application/ai/engine/ai_engine_config_holder.dart';
import 'package:varnamala/application/course_provider.dart';
import 'package:varnamala/l10n/app_strings.dart';
import 'package:varnamala/views/ai/chat_bubble.dart';
import 'package:varnamala/views/theme.dart';

@RoutePage()
class AiWishChatPage extends StatefulWidget {
  const AiWishChatPage({Key? key}) : super(key: key);

  @override
  State<AiWishChatPage> createState() => _AiWishChatPageState();
}

class _AiWishChatPageState extends State<AiWishChatPage> {
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  // Local spec inputs (edited via the gear bottom sheet).
  late final TextEditingController _languageCtrl;
  late final TextEditingController _sourceLanguageCtrl;
  late final TextEditingController _topicCtrl;
  late final TextEditingController _extraCtrl;
  String _level = 'A1';
  int _unitCount = 1;
  int _lessonsPerUnit = 3;
  String _template = 'mixed';
  bool _useGenreBatch = false;
  bool _groundedMode = false;
  final List<String> _resourceScope = ['words', 'expressions', 'grammarPoints'];

  @override
  void initState() {
    super.initState();
    _languageCtrl = TextEditingController(text: 'Turkish');
    _sourceLanguageCtrl = TextEditingController(text: 'Chinese');
    _topicCtrl = TextEditingController();
    _extraCtrl = TextEditingController();
    context.read<AiWishProvider>().reset();
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _languageCtrl.dispose();
    _sourceLanguageCtrl.dispose();
    _topicCtrl.dispose();
    _extraCtrl.dispose();
    super.dispose();
  }

  AiEngineConfig _config() => context.read<AiEngineConfigHolder>().config;

  AiCourseSpec _buildSpec() => AiCourseSpec(
        language: _languageCtrl.text.trim().isEmpty
            ? 'Turkish'
            : _languageCtrl.text.trim(),
        sourceLanguage: _sourceLanguageCtrl.text.trim().isEmpty
            ? 'Chinese'
            : _sourceLanguageCtrl.text.trim(),
        topic: _topicCtrl.text.trim(),
        level: _level,
        unitCount: _unitCount,
        lessonsPerUnit: _lessonsPerUnit,
        template: _template,
        useGenreBatch: _useGenreBatch,
        extraInstructions: _extraCtrl.text.trim(),
        groundedMode: _groundedMode,
        resourceScope: _resourceScope,
      );

  Future<void> _onSend() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    _inputCtrl.clear();
    await context.read<AiWishProvider>().sendAlignment(
          config: _config(),
          spec: _buildSpec(),
          userText: text,
        );
    _scrollToBottom();
  }

  Future<void> _onFinalize() async {
    await context.read<AiWishProvider>().finalizeGeneration(
          config: _config(),
          spec: _buildSpec(),
        );
    if (!mounted) return;
    final wish = context.read<AiWishProvider>();
    if (wish.generatedJson != null) {
      final courseProvider = context.read<AiCourseProvider>();
      courseProvider.updateGeneratedJson(wish.generatedJson!);
      courseProvider.setExplanation(wish.explanation);
    }
  }

  Future<void> _onSave() async {
    final courseProvider = context.read<AiCourseProvider>();
    try {
      await courseProvider.save();
      if (!mounted) return;
      await context.read<CourseProvider>().reloadCourse();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.aiCourseSaved)),
      );
      context.router.maybePop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.aiSaveFailed(e))),
      );
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

  Future<void> _openCourseParamsSheet() async {
    // The sheet keeps its own ephemeral StatefulBuilder state so toggles (e.g.
    // Genre batch) react instantly without depending on the parent rebuild,
    // and the last-edited values persist on the page fields for the spec.
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: VarnamalaTheme.cardBg(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (innerContext, setInnerState) {
          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 12,
              bottom: MediaQuery.of(innerContext).viewInsets.bottom + 16,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        AppStrings.aiCourseParametersTitle,
                        style: Theme.of(innerContext).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, size: 22),
                        tooltip: AppStrings.commonClose,
                        onPressed: () => Navigator.of(sheetContext).maybePop(),
                      ),
                    ],
                  ),
                  _courseParamsForm(setInnerState),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (mounted) setState(() {}); // refresh spec-derived UI after editing
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VarnamalaTheme.scaffoldBg(context),
      appBar: AppBar(
        title: Text(
          AppStrings.aiCourseDesignerTitle,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        backgroundColor: VarnamalaTheme.bottomNavBg(context),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, size: 22),
            tooltip: AppStrings.aiCourseParametersTooltip,
            onPressed: _openCourseParamsSheet,
          ),
        ],
      ),
      // Body is rebuilt only when the conversation length or the high-level
      // generation state changes — not on every notifyListeners() (e.g. while
      // the AI streams progress). Selectors + const leaf widgets keep the chat
      // list from being rebuilt during input edits and AI polling.
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Selector<AiWishProvider, ({bool empty, int count, bool hasError})>(
                selector: (_, w) => (
                  empty: w.messages.isEmpty,
                  count: w.messages.length,
                  hasError: w.error != null,
                ),
                builder: (context, v, _) {
                  final empty = v.empty && !_busyValue(context);
                  if (empty) return _emptyHint();
                  return ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.all(12),
                    // +1 row reserved for the trailing error bubble, if any.
                    itemCount: v.count + (v.hasError ? 1 : 0),
                    itemBuilder: (context, i) {
                      final w = context.read<AiWishProvider>();
                      if (i == v.count && v.hasError) {
                        return _errorBubble(w.error!);
                      }
                      final m = w.messages[i];
                      return ChatBubble(role: m.role, content: m.content);
                    },
                  );
                },
              ),
            ),
            Selector<AiWishProvider, AiWishState>(
              selector: (_, w) => w.state,
              builder: (context, state, _) {
                final busy = state == AiWishState.aligning ||
                    state == AiWishState.generating ||
                    state == AiWishState.explaining;
                final generated = state == AiWishState.generated;
                return Column(
                  children: [
                    if (generated)
              Selector<AiWishProvider, String?>(
                selector: (_, w) => w.explanation,
                builder: (context, explanation, _) => _generatedPanel(explanation),
              ),
                    if (busy) const LinearProgressIndicator(),
                    _chatInputBar(busy, generated),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  bool _busyValue(BuildContext context) {
    final s = context.read<AiWishProvider>().state;
    return s == AiWishState.aligning ||
        s == AiWishState.generating ||
        s == AiWishState.explaining;
  }

  Widget _courseParamsForm(void Function(void Function()) setInnerState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _languageCtrl,
                decoration: InputDecoration(
                  labelText: AppStrings.aiTargetLanguageLabel,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _sourceLanguageCtrl,
                decoration: InputDecoration(
                  labelText: AppStrings.aiSourceLanguageLabel,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _topicCtrl,
          decoration: InputDecoration(
            labelText: AppStrings.aiTopicLabel,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _level,
                decoration: InputDecoration(
                  labelText: AppStrings.aiLevelLabel,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
                items: ['A1', 'A2', 'B1', 'B2', 'C1']
                    .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                    .toList(),
                onChanged: (v) => setInnerState(() => _level = v ?? 'A1'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<int>(
                value: _unitCount,
                decoration: InputDecoration(
                  labelText: AppStrings.aiUnitsLabel,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
                items: [1, 2, 3, 4, 5]
                    .map((n) => DropdownMenuItem(value: n, child: Text('$n')))
                    .toList(),
                onChanged: (v) => setInnerState(() => _unitCount = v ?? 1),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<int>(
                value: _lessonsPerUnit,
                decoration: InputDecoration(
                  labelText: AppStrings.aiLessonsPerUnitLabel,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
                items: [1, 2, 3, 4, 5]
                    .map((n) => DropdownMenuItem(value: n, child: Text('$n')))
                    .toList(),
                onChanged: (v) =>
                    setInnerState(() => _lessonsPerUnit = v ?? 3),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Template dropdown is full-width: its labels ("listening (听力训练)")
        // are too long to share a row with the Genre batch toggle without
        // overflowing, so the toggle gets its own row below.
        DropdownButtonFormField<String>(
          value: _template,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: AppStrings.aiTemplateLabel,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
          items: ['intro', 'practice', 'review', 'listening', 'reading', 'mastery', 'mixed']
              .map((t) => DropdownMenuItem(
                    value: t,
                    child: Text(
                        '$t (${templateLabel(t, l10n: AppStrings.instance)})',
                        overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          onChanged: (v) => setInnerState(() => _template = v ?? 'mixed'),
        ),
        // Genre batch toggle on its own row — a custom Switch row avoids the
        // SwitchListTile intrinsic-width overflow and reacts via setInnerState.
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(AppStrings.aiGenreBatchTitle,
                        style: const TextStyle(fontWeight: FontWeight.w500)),
                    const SizedBox(height: 2),
                    Text(
                      AppStrings.aiGenreBatchSubtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Switch(
                value: _useGenreBatch,
                onChanged: (v) => setInnerState(() => _useGenreBatch = v),
              ),
            ],
          ),
        ),
        // Grounded generation toggle — reuse existing course resources.
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(AppStrings.aiGroundedGenerationTitle,
                        style: const TextStyle(fontWeight: FontWeight.w500)),
                    const SizedBox(height: 2),
                    Text(
                      AppStrings.aiGroundedGenerationSubtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Switch(
                value: _groundedMode,
                onChanged: (v) => setInnerState(() => _groundedMode = v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _extraCtrl,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: AppStrings.aiExtraInstructionsLabel,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  Widget _emptyHint() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          AppStrings.aiEmptyHintWish,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
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
          AppStrings.aiErrorBubble(error),
          style: const TextStyle(color: VarnamalaTheme.error),
        ),
      ),
    );
  }

  Widget _generatedPanel(String? explanation) {
    return Container(
      width: double.infinity,
      color: VarnamalaTheme.cardBg(context),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppStrings.aiCourseGenerated,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          if (explanation != null && explanation.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(AppStrings.aiAiExplanation(explanation)),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _onSave,
                  icon: const Icon(Icons.save),
                  label: Text(AppStrings.aiSaveToCourseTree),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chatInputBar(bool busy, bool generated) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _inputCtrl,
                  enabled: !busy && !generated,
                  decoration: InputDecoration(
                    hintText: AppStrings.aiTypeIdea,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _onSend(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: busy || generated ? null : _onSend,
                icon: const Icon(Icons.send),
                tooltip: AppStrings.commonSend,
              ),
            ],
          ),
          const SizedBox(height: 8),
          _SwipeConfirmBar(
            enabled: !busy && !generated,
            onConfirm: _onFinalize,
          ),
        ],
      ),
    );
  }
}

/// A horizontal swipe-to-confirm bar. Drag the handle from left to right; the
/// track fills gray → green as it nears completion, and a full swipe triggers
/// [onConfirm]. Releasing below the threshold springs back to the start.
class _SwipeConfirmBar extends StatefulWidget {
  final bool enabled;
  final Future<void> Function() onConfirm;

  const _SwipeConfirmBar({required this.enabled, required this.onConfirm});

  @override
  State<_SwipeConfirmBar> createState() => _SwipeConfirmBarState();
}

class _SwipeConfirmBarState extends State<_SwipeConfirmBar>
    with SingleTickerProviderStateMixin {
  static const _height = 48.0;
  // Confirm at ~80% — dragging the handle all the way to the far edge is
  // awkward on most phones, so we trigger before the physical end.
  static const _threshold = 0.8;

  double _fraction = 0;
  double _trackWidth = 0;
  bool _fired = false;

  late final AnimationController _spring = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );
  Animation<double>? _springAnim;

  @override
  void dispose() {
    _spring.dispose();
    super.dispose();
  }

  void _snapBack() {
    final start = _fraction;
    if (start <= 0) return;
    _springAnim = Tween<double>(begin: start, end: 0).animate(
      CurvedAnimation(parent: _spring, curve: Curves.easeOut),
    )..addListener(() {
        setState(() => _fraction = _springAnim!.value);
      });
    _spring.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final fillWidth = _trackWidth * _fraction;
    final fillColor = Color.lerp(
      Colors.grey.shade400,
      VarnamalaTheme.primary,
      _fraction,
    )!;
    final dim = widget.enabled ? 1.0 : 0.4;
    // Show the "release to confirm" cue once past the threshold.
    final atThreshold = _fraction >= _threshold;

    return Opacity(
      opacity: dim,
      child: LayoutBuilder(
        builder: (context, constraints) {
          _trackWidth = constraints.maxWidth;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: widget.enabled
                ? (d) {
                    if (_trackWidth <= 0) return;
                    _spring.stop();
                    final next =
                        (_fraction + d.delta.dx / _trackWidth).clamp(0.0, 1.0);
                    // Haptic bump exactly when crossing the threshold.
                    if (_fraction < _threshold && next >= _threshold) {
                      HapticFeedback.mediumImpact();
                    }
                    setState(() => _fraction = next);
                  }
                : null,
            onHorizontalDragEnd: widget.enabled
                ? (_) {
                    if (_fraction >= _threshold && !_fired) {
                      _fired = true;
                      setState(() => _fraction = 1.0);
                      HapticFeedback.heavyImpact();
                      widget.onConfirm().whenComplete(() {
                        if (mounted) {
                          setState(() {
                            _fraction = 0;
                            _fired = false;
                          });
                        }
                      });
                    } else {
                      _snapBack();
                    }
                  }
                : null,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(_height / 2),
              child: SizedBox(
                height: _height,
                child: Stack(
                  children: [
                    // Base track (gray).
                    Container(color: Colors.grey.shade300),
                    // Fill (gray → green).
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 80),
                      width: fillWidth + _height / 2,
                      color: fillColor,
                    ),
                    // Centered label.
                    Center(
                      child: Text(
                        atThreshold ? AppStrings.aiReleaseToFinalize : AppStrings.aiSwipeToFinalize,
                        style: TextStyle(
                          color: _fraction > 0.5
                              ? Colors.white
                              : Theme.of(context).textTheme.bodyMedium?.color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    // Handle on the leading edge.
                    Positioned(
                      left: _fraction * (_trackWidth - _height),
                      child: Container(
                        width: _height,
                        height: _height,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.chevron_right,
                          color: VarnamalaTheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}