// Dart imports:
import 'dart:async';
import 'dart:math' as math;

// Flutter imports:
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Project imports:
import 'package:turna/application/audio_controller.dart';
import 'package:turna/application/accessibility_capabilities.dart';
import 'package:turna/core/motion.dart';
import 'package:turna/core/spacing.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/domain/course/interaction_state.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/widgets/session_shell.dart';

// Re-exported for the ~22 files that historically imported the state types
// from this file; the definitions live in the domain layer now.
export 'package:turna/domain/course/interaction_state.dart'
    show InteractionState, interactionItemId, OnInteractionSubmit;

/// Plugin-style renderer. Each [Interaction] subclass maps to one renderer,
/// registered as `@injectable` and collected into a `Set<InteractionRenderer>`
/// at app start (see [lib/di/injection.dart]).
abstract class InteractionRenderer {
  /// The concrete Interaction type this renderer handles. Used by the
  /// dispatcher: `renderers.firstWhere((r) => r.handlesType == i.runtimeType)`.
  Type get handlesType;

  /// Whether this interaction auto-advances immediately on submit (no
  /// "Continue"/"Got It" button shown by the lesson screen). Types like
  /// [ShowWord] — which has no correctness check — override this to `true`.
  /// New auto-advancing types only override this getter; the screen never
  /// branches on a concrete interaction type.
  bool get autoAdvance => false;

  /// Build the widget for [interaction]. [state] drives feedback display;
  /// [onSubmit] is invoked once per submit with the correctness verdict.
  ///
  /// 核对型 renderer 在 build 里通过 [LessonActionScope] 报一次"能不能提交 /
  /// 提交做什么", 按钮本身由页面统一画在底栏. 揭示型 / 自评型 (Anki 翻面、
  /// 图像回忆、朗读) 不碰它, 自己保留按钮.
  Widget build(
    Interaction interaction,
    InteractionState state,
    OnInteractionSubmit onSubmit,
  );
}

/// 把 [LessonActionDraft] 下发给 renderer 子树.
///
/// 用 InheritedWidget 而不是逐层构造参数: 草稿状态在各 renderer 的私有
/// `State` 里, 走构造参数要给 11 个 body 组件各加一个字段; 走 scope 则只需要
/// 在 build 里查一次.
class LessonActionScope extends InheritedWidget {
  final LessonActionDraft? draft;

  const LessonActionScope({
    super.key,
    required this.draft,
    required super.child,
  });

  /// 用 `getInheritedWidgetOfExactType` 而不是 `dependOn...`: 这个方法也会在
  /// 输入监听器里被调用 (非 build 阶段), 注册依赖既没必要也会踩断言.
  static LessonActionDraft? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<LessonActionScope>()?.draft;

  @override
  bool updateShouldNotify(LessonActionScope oldWidget) =>
      oldWidget.draft != draft;
}

/// 页面底栏 CTA 的草稿契约.
///
/// 为什么需要它: 提交按钮必须**永远在同一个位置** —— 之前未提交时由各
/// renderer 画在滚动内容尾部, 提交后由页面画在固定底栏, 点一下"核对"按钮就
/// 会从内容中间跳到屏幕底部. 收归页面后, renderer 只报状态, 不画按钮.
///
/// 为什么只存不通知: [report] 在 renderer 的 `build` 期间被调用, 此刻
/// `notifyListeners` 会触发底栏 setState —— 那是"build 期间 setState"。
/// 因此通知一律推迟到帧后, 且只在**能否提交翻转**时才发 (提交动作每次都换
/// 闭包, 不能作为变化判据, 否则每帧都会排一次通知).
class LessonActionDraft {
  bool _canSubmit = false;
  bool _hasCta = false;
  String? _label;
  VoidCallback? _submit;
  VoidCallback? _onChanged;
  bool _notifyScheduled = false;

  /// 现在能不能提交.
  bool get canSubmit => _canSubmit;

  /// 这一题是否把 CTA 交给了页面. `false` 表示它自己画按钮 (或自动推进),
  /// 页面此时不显示底栏.
  bool get hasCta => _hasCta;

  /// 题型自定的底栏文案 (如"继续"); `null` 用页面默认「核对」.
  String? get label => _label;

  /// 底栏订阅变化.
  void attach(VoidCallback onChanged) => _onChanged = onChanged;

  void detach(VoidCallback onChanged) {
    if (identical(_onChanged, onChanged)) _onChanged = null;
  }

  /// renderer 在 build 里调用一次.
  void report({
    required bool canSubmit,
    VoidCallback? submit,
    String? label,
  }) {
    _hasCta = true;
    _submit = submit;
    _label = label;
    if (_canSubmit == canSubmit) return;
    _canSubmit = canSubmit;
    _scheduleNotify();
  }

  /// 底栏按下时调用. 已经不可提交时直接吞掉.
  void submit() {
    if (!_canSubmit) return;
    _submit?.call();
  }

  void _scheduleNotify() {
    if (_notifyScheduled || _onChanged == null) return;
    _notifyScheduled = true;
    // 微任务而不是 addPostFrameCallback: 后者要等到**下一帧**才重建底栏,
    // 输入一个字后底栏的可用态就会慢一帧 (测试里表现为必须多 pump 一次).
    // 微任务在当前同步流程结束后立刻跑, build 阶段不可能被它打断.
    scheduleMicrotask(() {
      _notifyScheduled = false;
      _onChanged?.call();
    });
  }
}

/// Convenience: get the renderer for a specific interaction, or throw.
///
/// Matches on freezed **interface** types via `is` / sealed switch, not
/// `runtimeType` (which is the private `_$FooImpl` and never equals
/// `handlesType => Foo`).
InteractionRenderer lookupRenderer(
  Iterable<InteractionRenderer> renderers,
  Interaction interaction,
) {
  final target = _handlesTypeFor(interaction);
  return renderers.firstWhere(
    (r) => r.handlesType == target,
    orElse: () => throw StateError(
      'No InteractionRenderer registered for $target '
      '(${interaction.runtimeType}). Did you forget to @injectable it?',
    ),
  );
}

/// Public freezed interface type corresponding to [interaction].
Type _handlesTypeFor(Interaction interaction) {
  return switch (interaction) {
    ShowWord() => ShowWord,
    MultipleChoice() => MultipleChoice,
    MultiSelect() => MultiSelect,
    FillBlank() => FillBlank,
    TranslateSentence() => TranslateSentence,
    ListenAndPick() => ListenAndPick,
    TypeTheWord() => TypeTheWord,
    ListenOnly() => ListenOnly,
    ReorderSentence() => ReorderSentence,
    ReadingMcq() => ReadingMcq,
    ReadingTrueFalse() => ReadingTrueFalse,
    ReadingShortAnswer() => ReadingShortAnswer,
    AnkiCard() => AnkiCard,
    AnkiHtmlCard() => AnkiHtmlCard,
    ImageRecall() => ImageRecall,
    Dictation() => Dictation,
    ReadAloud() => ReadAloud,
  };
}

/// Binary recall grading row ("forgotten" / "remembered").
///
/// Shared by every self-graded presentation (flip card, image recall) so the
/// two do not drift into two different-looking verdict rows.
///
/// 「湿地雾光」R05：视觉语言收编进 [SessionRatingBand]——负档按评审稿走
/// 天光蓝描边而非错误红（评分不是错误），正档 teal 实底；API 与回调不变。
class BinaryGradeRow extends StatelessWidget {
  const BinaryGradeRow({
    super.key,
    required this.onForgotten,
    required this.onRemembered,
  });

  final VoidCallback onForgotten;
  final VoidCallback onRemembered;

  @override
  Widget build(BuildContext context) {
    return SessionRatingBand(
      actions: [
        SessionRatingAction(
          label: AppStrings.reviewBinaryForgotten,
          tone: SessionRatingTone.outline,
          onPressed: onForgotten,
        ),
        SessionRatingAction(
          label: AppStrings.reviewBinaryRemembered,
          tone: SessionRatingTone.primary,
          onPressed: onRemembered,
        ),
      ],
    );
  }
}

/// In-card reveal CTA ("显示答案"): 52 高 teal 主操作，与页面底栏的
/// [SessionPrimaryAction] 同一质感。
///
/// 「湿地雾光」R04/R05 之后，核对型 renderer 的提交键由页面底栏统一承担；
/// 本组件只服务**揭示型** renderer（Anki 翻面、图像回忆、旧版记忆卡占位）
/// 与复习域仍在用的手写按钮位——它们的按钮语义是"揭示"，不是"核对"。
class LessonCheckButton extends StatefulWidget {
  final String label;
  final bool enabled;
  final VoidCallback? onPressed;

  const LessonCheckButton({
    super.key,
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  @override
  State<LessonCheckButton> createState() => _LessonCheckButtonState();
}

class _LessonCheckButtonState extends State<LessonCheckButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(TurnaTheme.radiusOption);
    final enabled = widget.enabled;
    final lifted = enabled && !_pressed;
    final a11y = accessibilityOf(context);
    final reduceMotion =
        MediaQuery.disableAnimationsOf(context) || a11y.reduceMotion;

    return AnimatedScale(
      scale: _pressed && !reduceMotion ? 0.985 : 1.0,
      duration: TurnaMotion.scaled(TurnaMotion.fast, reduceMotion),
      curve: Curves.easeOutCubic,
      child: AnimatedContainer(
        duration: TurnaMotion.scaled(TurnaMotion.base, reduceMotion),
        curve: Curves.easeOutCubic,
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        width: double.infinity,
        decoration: enabled
            // 竖向渐变 + 品牌光晕由 theme 统一持有（ADR 0033 的主 CTA 色对，
            // 绝不混入 clay）—— 页面不再自己写渐变字面量。
            ? TurnaTheme.primaryCtaDecoration(
                borderRadius: radius,
                elevated: lifted,
                vertical: true,
              )
            : BoxDecoration(
                color: TurnaTheme.dividerBg(context),
                borderRadius: radius,
                border: Border.all(color: TurnaTheme.statCardBorder(context)),
              ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: enabled
                ? () {
                    if (!a11y.quietFeedback) {
                      unawaited(HapticFeedback.mediumImpact());
                    }
                    widget.onPressed?.call();
                  }
                : null,
            onHighlightChanged: (v) {
              if (!enabled) return;
              setState(() => _pressed = v);
            },
            borderRadius: radius,
            child: Center(
              child: Text(
                widget.label,
                style: AppTextStyles.buttonLabel.copyWith(
                  color:
                      enabled ? TurnaTheme.textOnPrimary : TurnaTheme.textHint,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Default body chrome every renderer sits inside. Provides the standard
/// side padding. Scrolling is owned by the lesson page's outer
/// [SingleChildScrollView] — this used to nest its own scroll view,
/// which double-wrapped FillBlank / Translate / TypeTheWord / Reading* and
/// caused nested-scroll jank. Centering padding only; no [LayoutBuilder]
/// (its `minHeight: maxHeight - 120` math broke under the outer scroll's
/// unbounded height constraint).
///
/// 这里**不再带 [SafeArea]**: 它的底部内边距会和固定操作栏的 inset 叠加,
/// 造成按钮上方凭空多出一条 34px 死区. 安全区改由 [PracticeSessionBody]
/// 在整列底部统一收一次.
class InteractionBody extends StatelessWidget {
  final Widget child;

  const InteractionBody({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: child,
    );
  }
}

// ──────────────────────────────────────────────────────────────
// Shared widgets used by interaction renderers
// ──────────────────────────────────────────────────────────────

/// 编号行选项（「湿地雾光」R05）：单选 / 多选 / 听选 / 阅读选择共用。
///
/// 行式语言（P1「选项为编号行」）：26px 圆形编号圈（1.5 发丝边，未选 hint
/// 色、选中 teal 实底白字）+ 16/500 选项文本；行间由 [showDivider] 画
/// `TurnaTheme.dividerBg` 发丝线（最后一行传 `false`）。选中态整行 teal 6%
/// 底（radius 12、左右外扩 8）。判分后按语义色收敛——正确 success 实圈 +
/// 对钩、错误 error 实圈 + 叉，形状与图标保证不是纯颜色信号（高对比可辨）。
class InteractionOptionTile extends StatefulWidget {
  final String label;

  /// 1 起的显示编号（圈里的数字）。
  final int index;
  final bool isSelected;
  final bool isCorrect;
  final bool isWrong;

  /// 是否在行尾画发丝分隔线；列表里除最后一行外都传 `true`。
  final bool showDivider;
  final VoidCallback? onTap;

  const InteractionOptionTile({
    super.key,
    required this.label,
    required this.index,
    required this.isSelected,
    required this.isCorrect,
    required this.isWrong,
    this.showDivider = false,
    required this.onTap,
  });

  @override
  State<InteractionOptionTile> createState() => _InteractionOptionTileState();
}

class _InteractionOptionTileState extends State<InteractionOptionTile>
    with SingleTickerProviderStateMixin {
  /// 判定落地的冲击: 正确轻弹一下, 错误横向抖两下再收住.
  ///
  /// 只做 340ms —— 再长就开始妨碍"下一题"的节奏.
  late final AnimationController _verdict = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 340),
  );
  bool _pressed = false;

  @override
  void didUpdateWidget(covariant InteractionOptionTile old) {
    super.didUpdateWidget(old);
    final wasJudged = old.isCorrect || old.isWrong;
    if ((widget.isCorrect || widget.isWrong) && !wasJudged) {
      final a11y = accessibilityOf(context);
      final reduceMotion =
          MediaQuery.disableAnimationsOf(context) || a11y.reduceMotion;
      if (!reduceMotion) _verdict.forward(from: 0);
      if (!a11y.quietFeedback) unawaited(HapticFeedback.mediumImpact());
    }
  }

  @override
  void dispose() {
    _verdict.dispose();
    super.dispose();
  }

  /// 状态 → 强调色. `null` 表示未选中的常态（无底色行）.
  Color? _accent() {
    if (widget.isCorrect) return TurnaTheme.success;
    if (widget.isWrong) return TurnaTheme.error;
    if (widget.isSelected) return TurnaTheme.brandTeal;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _verdict,
      child: _buildRow(context),
      builder: (context, child) {
        final t = _verdict.value;
        if (t == 0.0) return child!;
        // 错误: 频率 2 个周期, 振幅随时间衰减. 正确: 单峰轻弹.
        final dx =
            widget.isWrong ? math.sin(t * math.pi * 4) * 6 * (1 - t) : 0.0;
        final scale = widget.isCorrect ? 1 + 0.03 * math.sin(t * math.pi) : 1.0;
        return Transform.translate(
          offset: Offset(dx, 0),
          child: Transform.scale(scale: scale, child: child),
        );
      },
    );
  }

  Widget _buildRow(BuildContext context) {
    final stateAccent = _accent();
    final a11y = accessibilityOf(context);
    final reduceMotion =
        MediaQuery.disableAnimationsOf(context) || a11y.reduceMotion;
    // 选中 teal 6%；判分用语义色淡底（与圈、图标同一色相）。
    final rowColor = switch (stateAccent) {
      null => Colors.transparent,
      final accent => accent.withValues(alpha: accent == TurnaTheme.brandTeal ? 0.06 : 0.10),
    };
    final radius = BorderRadius.circular(TurnaTheme.radiusMedium);

    return Padding(
      // 高亮底左右外扩 8：比题干/文本列宽出一圈，选中行一眼成块。
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            button: true,
            label: widget.label,
            selected: widget.isSelected,
            child: AnimatedScale(
              scale: _pressed && !reduceMotion ? 0.98 : 1.0,
              duration: TurnaMotion.scaled(TurnaMotion.fast, reduceMotion),
              curve: Curves.easeOutCubic,
              child: AnimatedContainer(
                duration: TurnaMotion.scaled(TurnaMotion.base, reduceMotion),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(color: rowColor, borderRadius: radius),
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    borderRadius: radius,
                    onTap: widget.onTap == null
                        ? null
                        : () {
                            if (!a11y.quietFeedback) {
                              unawaited(HapticFeedback.selectionClick());
                            }
                            widget.onTap!();
                          },
                    onHighlightChanged: (v) {
                      if (widget.onTap == null) return;
                      setState(() => _pressed = v);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 14,
                      ),
                      child: Row(
                        children: [
                          _NumberRing(
                            index: widget.index,
                            accent: stateAccent,
                            isWrong: widget.isWrong,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              widget.label,
                              style: TextStyle(
                                fontSize: 16,
                                height: 1.4,
                                fontWeight: stateAccent == null
                                    ? FontWeight.w500
                                    : FontWeight.w600,
                                color: TurnaTheme.textPrimaryColor(context),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (widget.showDivider)
            Container(
              height: 1,
              color: TurnaTheme.dividerBg(context),
            ),
        ],
      ),
    );
  }
}

/// 26px 圆形编号圈：常态 hint 发丝边 + hint 数字；选中 teal 实底白字；
/// 判分后语义色实底 + 对钩 / 叉（形状信号，不依赖颜色）。
class _NumberRing extends StatelessWidget {
  const _NumberRing({
    required this.index,
    required this.accent,
    required this.isWrong,
  });

  final int index;
  final Color? accent;
  final bool isWrong;

  @override
  Widget build(BuildContext context) {
    final hint = TurnaTheme.textHintColor(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: accent ?? Colors.transparent,
        border: accent == null ? Border.all(color: hint, width: 1.5) : null,
      ),
      child: accent == null
          ? Text(
              '$index',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: hint,
                height: 1,
              ),
            )
          : Icon(
              isWrong ? Icons.close : Icons.check,
              size: 15,
              color: TurnaTheme.textOnPrimary,
            ),
    );
  }
}

/// Word chip for word-bank style interactions — 拼句题的词库/句中芯片、
/// 选择填空的候选词块共用这一视觉语汇。Neutral card look by default;
/// [selected] fills with the brand teal (placed-in-sentence state).
/// `onTap == null` renders an inert chip (no ripple, semantics disabled) —
/// used for already-placed pool chips and post-submit locks.
class WordChip extends StatelessWidget {
  const WordChip({
    super.key,
    required this.label,
    this.onTap,
    this.selected = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? TurnaTheme.brandTeal : TurnaTheme.cardBg(context);
    final fg = selected
        ? TurnaTheme.textOnPrimary
        : TurnaTheme.textPrimaryColor(context);
    final border = selected
        ? TurnaTheme.brandTeal
        : TurnaTheme.textHint.withValues(alpha: 0.3);

    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      selected: selected,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: border, width: 1.5),
          borderRadius: BorderRadius.circular(TurnaTheme.radiusRound),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(TurnaTheme.radiusRound),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Correct-answer feedback banner shown after a wrong submission.
class LessonCorrectAnswerBanner extends StatelessWidget {
  final String label;
  final String answer;
  final bool showBorder;

  const LessonCorrectAnswerBanner({
    super.key,
    required this.label,
    required this.answer,
    this.showBorder = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: TurnaTheme.success.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
        border: showBorder
            ? Border.all(color: TurnaTheme.success.withValues(alpha: 0.4))
            : null,
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: TurnaTheme.successDark),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  fontSize: 14,
                  color: TurnaTheme.textPrimaryColor(context),
                ),
                children: [
                  TextSpan(text: '$label: '),
                  TextSpan(
                    text: answer,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Circular speaker button that plays audio via TTS.
///
/// 「湿地雾光」R05：44px 圆形 teal 描边键（transparent 底 + 1.5 teal 边 +
/// teal 图标）——题面去装饰后音频键是唯一的圆形控件，描边档让它不再从
/// 纸面题干里"浮"出来。朗读中图标切换为声纹并禁点。
class SpeakerButton extends StatelessWidget {
  final VoidCallback onPressed;

  const SpeakerButton({super.key, required this.onPressed});

  ValueListenable<bool>? _speakingListenable() {
    try {
      return getIt<AudioController>().speakingListenable;
    } catch (_) {
      // Tests and early frames may not have AudioController registered.
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final listenable = _speakingListenable();
    if (listenable == null) {
      return _buildButton(context, speaking: false);
    }
    return ValueListenableBuilder<bool>(
      valueListenable: listenable,
      builder: (context, speaking, _) =>
          _buildButton(context, speaking: speaking),
    );
  }

  Widget _buildButton(BuildContext context, {required bool speaking}) {
    return Semantics(
      button: true,
      label: AppStrings.lessonPlayAudioLabel,
      child: Tooltip(
        message: AppStrings.lessonPlayAudioLabel,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Material(
            color: speaking
                ? TurnaTheme.brandTeal.withValues(alpha: 0.12)
                : Colors.transparent,
            shape: const CircleBorder(
              side: BorderSide(color: TurnaTheme.brandTeal, width: 1.5),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: speaking ? null : onPressed,
              child: Icon(
                speaking ? Icons.graphic_eq_rounded : Icons.volume_up_rounded,
                color: TurnaTheme.brandTeal,
                size: 22,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small uppercase caption rendered above the prompt in each interaction
/// body ("Fill in the blank", "Listen and pick", etc.). Centralises the
/// caption style + the bottom padding so renderers stay visually aligned.
class SectionCaption extends StatelessWidget {
  final String text;

  const SectionCaption(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Text(
        text.toUpperCase(),
        style: AppTextStyles.caption(context),
      ),
    );
  }
}
