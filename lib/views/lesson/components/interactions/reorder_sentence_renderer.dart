// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:injectable/injectable.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/accessibility_provider.dart';
import 'package:turna/application/smart_speech.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/lesson/components/interactions/interaction_fields.dart';
import 'package:turna/views/lesson/components/interactions/interaction_renderer.dart';
import 'package:turna/views/widgets/session_shell.dart';
import 'package:turna/views/widgets/tts_feedback.dart';

/// 词库拼句：把打乱的词块点进答案行，组成目标句子。
///
/// 交互形态（三个 affordance，缺一不可）：
/// * **词库芯片原位变暗锁定**——放进句子的词不消失，只变暗、不可再点；
///   结构上杜绝「同一个词重复放入」，词库布局也永不重排。重复文本的词
///   （"the the"）各自身份独立（见 [_Token]）。
/// * **句中可编辑**——点句中词块退回词库（词库芯片亮起）；长按拖动调整
///   词在句中的位置。拖拽用水平 [Wrap] + [LongPressDraggable]/[DragTarget]
///   逐槽实现，不用 [ReorderableListView]——那是纵向列表，会把句子竖着排。
/// * **飞行动画**——放入/退回时一个幽灵芯片从源位置飞到目标槽位
///   （根 [Overlay]，测量方式与 `PlayInfoPopup` 同款）。减少动效
///   （系统禁用动画或 a11y reducedMotion）时整条链路退化为瞬时换位。
///
/// 每次点击芯片都用目标语语音读一遍（见 [speakTargetChip]）。
@injectable
class ReorderSentenceRenderer extends InteractionRenderer {
  @override
  Type get handlesType => ReorderSentence;

  @override
  Widget build(
    Interaction interaction,
    InteractionState state,
    OnInteractionSubmit onSubmit,
  ) {
    final i = interaction as ReorderSentence;
    return _ReorderBody(
      prompt: i.prompt,
      scrambled: i.scrambled,
      correct: i.correct,
      state: state,
      onSubmit: onSubmit,
    );
  }
}

/// A word-bank token with a stable identity. [id] is the original pool index
/// (the pool never reorders), so two identical strings stay distinguishable —
/// by-value matching was the old bug class ("the the" collapsed into one).
class _Token {
  const _Token(this.id, this.text);

  final int id;
  final String text;
}

/// One active ghost flight: its controller plus the overlay entry riding on
/// the root overlay. Both are torn down in [State.dispose] so a question
/// change mid-flight cannot leak an entry.
class _GhostFlight {
  const _GhostFlight(this.controller, this.entry);

  final AnimationController controller;
  final OverlayEntry entry;
}

class _ReorderBody extends StatefulWidget {
  final String? prompt;
  final List<String> scrambled;
  final List<String> correct;
  final InteractionState state;
  final OnInteractionSubmit onSubmit;

  const _ReorderBody({
    required this.prompt,
    required this.scrambled,
    required this.correct,
    required this.state,
    required this.onSubmit,
  });

  @override
  State<_ReorderBody> createState() => _ReorderBodyState();
}

class _ReorderBodyState extends State<_ReorderBody>
    with TickerProviderStateMixin {
  /// Full word bank in authored order — never reordered, ids stay stable.
  late List<_Token> _pool;

  /// Tokens placed in the sentence, in sentence order.
  List<_Token> _picked = <_Token>[];

  /// Pick 飞行中: 句中芯片先占位不绘制, 幽灵落地后显现.
  final Set<int> _inFlight = <int>{};

  /// 退回飞行中: 词库芯片保持暗态, 幽灵落到词库位后再亮起.
  final Set<int> _landing = <int>{};

  final List<_GhostFlight> _flights = <_GhostFlight>[];

  /// Rect 测量锚点. 词库锚在 AnimatedOpacity 上, 句中锚在 DragTarget 上 —
  /// 都是随 token 移动的稳定子树.
  final Map<int, GlobalKey> _poolKeys = <int, GlobalKey>{};
  final Map<int, GlobalKey> _answerKeys = <int, GlobalKey>{};

  /// 正被长按拖拽的 token id; null = 没有拖拽.
  int? _draggingId;

  /// 变暗过渡时长 — 减少动效时为 0.
  late Duration _dimDuration;

  static const _flightDuration = Duration(milliseconds: 260);

  @override
  void initState() {
    super.initState();
    _initTokens();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dimDuration =
        _reduceMotion() ? Duration.zero : const Duration(milliseconds: 180);
  }

  @override
  void didUpdateWidget(covariant _ReorderBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrambled != widget.scrambled) {
      _cancelFlights();
      _initTokens();
    }
  }

  void _initTokens() {
    _poolKeys.clear();
    _answerKeys.clear();
    _pool = [
      for (var i = 0; i < widget.scrambled.length; i++) _Token(i, widget.scrambled[i]),
    ];
    _picked = <_Token>[];
    _inFlight.clear();
    _landing.clear();
  }

  @override
  void dispose() {
    final flights = List<_GhostFlight>.of(_flights);
    for (final f in flights) {
      f.controller.stop();
    }
    // Remove entries outside build/dispose-safe order: stop() first so no
    // callback can resurrect one mid-teardown.
    for (final f in flights) {
      f.entry.remove();
      f.controller.dispose();
    }
    _flights.clear();
    super.dispose();
  }

  bool _isPlaced(int id) => _picked.any((t) => t.id == id);

  /// 减少动效守卫（全库约定，同 `PlayInfoPopup`）：系统禁用动画或
  /// a11y reducedMotion 任一为真即跳过飞行与变暗过渡。
  /// Provider 缺失（无 Provider 图的 widget 测试 harness）按「未开启」处理。
  bool _reduceMotion() {
    if (!mounted) return true;
    if (MediaQuery.disableAnimationsOf(context)) return true;
    try {
      return context.read<AccessibilityProvider>().reducedMotion;
    } on ProviderNotFoundException {
      return false;
    }
  }

  /// Chip rect in root-overlay coordinates (测量方式同 `PlayInfoPopup`).
  Rect? _rectOf(GlobalKey? key) {
    final ctx = key?.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return null;
    final overlay = Overlay.of(context, rootOverlay: true);
    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    if (overlayBox == null) return null;
    return box.localToGlobal(Offset.zero, ancestor: overlayBox) & box.size;
  }

  void _pick(_Token token) {
    if (widget.state.submitted || _isPlaced(token.id)) return;
    setState(() {
      _picked.add(token);
      _inFlight.add(token.id);
    });
    unawaited(_speakToken(token.text));
    if (_reduceMotion()) {
      setState(() => _inFlight.remove(token.id));
      return;
    }
    // 下一帧再测目标槽位: 隐藏芯片必须先完成布局才有 rect 可读.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final from = _rectOf(_poolKeys[token.id]);
      final to = _rectOf(_answerKeys[token.id]);
      if (from == null || to == null) {
        setState(() => _inFlight.remove(token.id));
        return;
      }
      _flyGhost(
        text: token.text,
        from: from,
        to: to,
        onLanded: () {
          if (mounted) setState(() => _inFlight.remove(token.id));
        },
      );
    });
  }

  void _unpick(_Token token, {bool byDrag = false}) {
    if (widget.state.submitted) return;
    final answerRect = byDrag ? null : _rectOf(_answerKeys[token.id]);
    setState(() => _picked.remove(token));
    if (!byDrag) unawaited(_speakToken(token.text));
    // 拖拽退回: 手指已经把芯片带到词库上, 不再补一段飞行.
    if (byDrag || answerRect == null || _reduceMotion()) return;
    setState(() => _landing.add(token.id));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final to = _rectOf(_poolKeys[token.id]);
      if (to == null) {
        setState(() => _landing.remove(token.id));
        return;
      }
      _flyGhost(
        text: token.text,
        from: answerRect,
        to: to,
        onLanded: () {
          if (mounted) setState(() => _landing.remove(token.id));
        },
      );
    });
  }

  /// 拖拽调序: 把 [dragged] 放到「第 [targetIndex] 个槽位」—— 拖到哪个芯片
  /// 上, 就落在那个芯片的位置, 原芯片向右让位. (insert-at, 不是 insert-before:
  /// 从左邻拖到相邻芯片也必须是有效的换位.)
  void _moveTo(_Token dragged, int targetIndex) {
    final oldIndex = _picked.indexOf(dragged);
    if (oldIndex < 0 || oldIndex == targetIndex) return;
    setState(() {
      _picked.removeAt(oldIndex);
      _picked.insert(targetIndex.clamp(0, _picked.length), dragged);
    });
  }

  void _flyGhost({
    required String text,
    required Rect from,
    required Rect to,
    required VoidCallback onLanded,
  }) {
    final controller = AnimationController(vsync: this, duration: _flightDuration);
    late final _GhostFlight flight;
    final entry = OverlayEntry(
      opaque: false,
      builder: (_) => _GhostChip(
        controller: controller,
        text: text,
        from: from,
        to: to,
      ),
    );
    flight = _GhostFlight(controller, entry);
    _flights.add(flight);
    Overlay.of(context, rootOverlay: true).insert(entry);
    // dispose() 里 stop() 后该 future 不再完成 — entry 已在 dispose 移除.
    controller.forward().whenComplete(() {
      _flights.remove(flight);
      entry.remove();
      onLanded();
    });
  }

  void _cancelFlights() {
    for (final f in List<_GhostFlight>.of(_flights)) {
      f.controller.stop();
      f.entry.remove();
      _flights.remove(f);
    }
  }

  Future<void> _speakToken(String token) async {
    final result = await speakTargetChip(token);
    if (result != null && mounted) {
      showTtsFailureFeedback(context, result);
    }
  }

  bool _matches() {
    if (_picked.length != widget.correct.length) return false;
    for (var i = 0; i < widget.correct.length; i++) {
      if (_picked[i].text != widget.correct[i]) return false;
    }
    return true;
  }

  String _formatAnswer() => [for (final t in _picked) t.text].join(' ');

  @override
  Widget build(BuildContext context) {
    final submitted = widget.state.submitted;
    final correct = widget.state.correct;
    final canSubmit = !submitted && _picked.length == widget.correct.length;

    // 按钮由页面底栏统一画; 这里只报"能不能提交 / 提交做什么".
    LessonActionScope.maybeOf(context)?.report(
      canSubmit: canSubmit,
      submit: canSubmit
          ? () => widget.onSubmit(_matches(), userAnswerText: _formatAnswer())
          : null,
    );

    final hasPrompt = widget.prompt != null && widget.prompt!.isNotEmpty;

    return InteractionBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionCaption(AppStrings.lessonArrangeWordsCaption),
          // 三段构图（§7.1 排序拼句）: 题面画布 → 可换行答案槽 → 词库。
          if (hasPrompt) ...[
            // 翻译拼句: 中文题面在词库上方, 与翻译题的源句画布同一形态。
            SessionRecallCanvas(
              minHeight: 120,
              padding: const EdgeInsets.all(20),
              child: Text(
                widget.prompt!,
                style: AppTextStyles.promptLg(context).copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
          Text(
            AppStrings.lessonTapRightOrder,
            style: AppTextStyles.captionSm(context).copyWith(
              color: TurnaTheme.textHintColor(context),
            ),
          ),
          const SizedBox(height: 12),
          _buildAnswerRow(submitted, correct),
          const SizedBox(height: 24),
          // 发丝线与选项行同语言（不用裸 Divider——它是全宽 16dp 间接缝）。
          Container(height: 1, color: TurnaTheme.dividerBg(context)),
          const SizedBox(height: 12),
          SectionCaption(AppStrings.lessonWordBank),
          _buildPool(),
          if (submitted) ...[
            const SizedBox(height: 16),
            InteractionFeedbackPanel(
              correct: correct == true,
              userAnswer: _formatAnswer(),
              correctAnswer: widget.correct.join(' '),
              correctAnswerLabel: AppStrings.lessonCorrectOrder,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAnswerRow(bool submitted, bool? correct) {
    Color border = TurnaTheme.textHintColor(context).withValues(alpha: 0.30);
    Color background = TurnaTheme.cardBg(context);
    if (submitted) {
      border = correct == true ? TurnaTheme.success : TurnaTheme.error;
      background = (correct == true ? TurnaTheme.success : TurnaTheme.error)
          .withValues(alpha: 0.06);
    } else if (_picked.isNotEmpty) {
      border = TurnaTheme.brandTeal;
      background = TurnaTheme.brandTeal.withValues(alpha: 0.04);
    }

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: border, width: 2),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
      ),
      child: _picked.isEmpty
          ? Center(
              child: Text(
                AppStrings.lessonTapWordToStart,
                style: TextStyle(
                  color: TurnaTheme.textHintColor(context).withValues(alpha: 0.7),
                  fontSize: 14,
                ),
              ),
            )
          : Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < _picked.length; i++) _answerSlot(i),
                _trailingDropSlot(),
              ],
            ),
    );
  }

  /// 句中一个槽位: 拖到它上面 = 插到它前面; 快速点它 = 退回词库;
  /// 长按它 = 拖动调序.
  Widget _answerSlot(int index) {
    final token = _picked[index];
    final hidden = _inFlight.contains(token.id);
    return DragTarget<_Token>(
      key: _answerKeys.putIfAbsent(token.id, () => GlobalKey()),
      onWillAcceptWithDetails: (details) =>
          !widget.state.submitted && details.data.id != token.id,
      onAcceptWithDetails: (details) => _moveTo(details.data, index),
      builder: (context, candidate, _) {
        final hovering = candidate.isNotEmpty && _draggingId != null;
        return LongPressDraggable<_Token>(
          data: token,
          maxSimultaneousDrags: widget.state.submitted ? 0 : 1,
          feedback: _DragFeedback(label: token.text),
          childWhenDragging: Opacity(
            opacity: 0.3,
            child: WordChip(label: token.text, selected: true),
          ),
          onDragStarted: () => setState(() => _draggingId = token.id),
          onDragEnd: (_) {
            if (_draggingId == token.id) setState(() => _draggingId = null);
          },
          child: hidden
              // 飞行中: 占住槽位尺寸但不绘制, 幽灵落地后换真身.
              ? ExcludeSemantics(
                  child: Opacity(
                    opacity: 0,
                    child: WordChip(label: token.text, selected: true),
                  ),
                )
              : AnimatedPadding(
                  duration: _dimDuration,
                  padding: EdgeInsets.only(left: hovering ? 10 : 0),
                  child: WordChip(
                    key: ValueKey('picked-${token.id}'),
                    label: token.text,
                    selected: true,
                    onTap: widget.state.submitted
                        ? null
                        : () => _unpick(token),
                  ),
                ),
        );
      },
    );
  }

  /// 句尾追加槽: 拖到最后 = 移到句末. 空态时不渲染.
  Widget _trailingDropSlot() {
    return DragTarget<_Token>(
      onWillAcceptWithDetails: (details) =>
          !widget.state.submitted &&
          _picked.isNotEmpty &&
          _picked.last.id != details.data.id,
      onAcceptWithDetails: (details) => _moveTo(details.data, _picked.length),
      builder: (context, candidate, _) {
        final hovering = candidate.isNotEmpty && _draggingId != null;
        return AnimatedContainer(
          duration: _dimDuration,
          width: hovering ? 36 : 0,
          height: 34,
        );
      },
    );
  }

  Widget _buildPool() {
    return DragTarget<_Token>(
      // 拖句中词到词库上 = 退回词库 (拖拽本身已把芯片带到, 不再飞).
      onWillAcceptWithDetails: (details) =>
          !widget.state.submitted && _isPlaced(details.data.id),
      onAcceptWithDetails: (details) => _unpick(details.data, byDrag: true),
      builder: (context, candidate, _) {
        final hovering = candidate.isNotEmpty;
        return Container(
          padding: const EdgeInsets.all(6),
          decoration: hovering
              ? BoxDecoration(
                  color: TurnaTheme.brandTeal.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
                )
              : null,
          child: Listener(
            // opaque: 拖拽期间整片词库区域都可命中 DragTarget —
            // 否则指针落在已放置(变暗)芯片的空隙上会 miss.
            behavior: HitTestBehavior.opaque,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final token in _pool) _poolChip(token),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _poolChip(_Token token) {
    final placed = _isPlaced(token.id);
    final dim = placed || _landing.contains(token.id);
    return AnimatedOpacity(
      key: _poolKeys.putIfAbsent(token.id, () => GlobalKey()),
      duration: _dimDuration,
      opacity: dim ? 0.35 : 1.0,
      child: WordChip(
        key: ValueKey('pool-${token.id}'),
        label: token.text,
        onTap: (widget.state.submitted || placed)
            ? null
            : () => _pick(token),
      ),
    );
  }
}

/// 幽灵芯片: 从 [from] 飞到 [to], 选中态外观 + 抬升阴影, 不进语义树.
class _GhostChip extends StatelessWidget {
  const _GhostChip({
    required this.controller,
    required this.text,
    required this.from,
    required this.to,
  });

  final AnimationController controller;
  final String text;
  final Rect from;
  final Rect to;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final t = Curves.easeOutCubic.transform(controller.value);
        return Positioned.fromRect(
          rect: Rect.lerp(from, to, t)!,
          child: child!,
        );
      },
      child: ExcludeSemantics(
        child: Material(
          color: TurnaTheme.brandTeal,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(TurnaTheme.radiusRound),
          ),
          elevation: 6,
          shadowColor: TurnaTheme.brandTeal.withValues(alpha: 0.4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: TurnaTheme.textOnPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 拖拽时跟手的悬浮芯片.
class _DragFeedback extends StatelessWidget {
  const _DragFeedback({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(TurnaTheme.radiusRound),
        boxShadow: TurnaTheme.buttonShadow,
      ),
      child: WordChip(label: label, selected: true),
    );
  }
}
