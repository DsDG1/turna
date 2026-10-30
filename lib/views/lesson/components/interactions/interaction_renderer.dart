// Dart imports:
import 'dart:async';
import 'dart:math' as math;

// Flutter imports:
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Project imports:
import 'package:turna/application/audio_controller.dart';
import 'package:turna/core/spacing.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/domain/course/interaction_state.dart';
import 'package:turna/l10n/app_strings.dart';

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
  VoidCallback? _submit;
  VoidCallback? _onChanged;
  bool _notifyScheduled = false;

  /// 现在能不能提交.
  bool get canSubmit => _canSubmit;

  /// 这一题是否把 CTA 交给了页面. `false` 表示它自己画按钮 (或自动推进),
  /// 页面此时不显示底栏.
  bool get hasCta => _hasCta;

  /// 底栏订阅变化.
  void attach(VoidCallback onChanged) => _onChanged = onChanged;

  void detach(VoidCallback onChanged) {
    if (identical(_onChanged, onChanged)) _onChanged = null;
  }

  /// renderer 在 build 里调用一次.
  void report({required bool canSubmit, VoidCallback? submit}) {
    _hasCta = true;
    _submit = submit;
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
    return Row(
      children: [
        Expanded(
          child: _BinaryGradeButton(
            label: AppStrings.reviewBinaryForgotten,
            color: TurnaTheme.error,
            onPressed: onForgotten,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _BinaryGradeButton(
            label: AppStrings.reviewBinaryRemembered,
            color: TurnaTheme.brandTeal,
            onPressed: onRemembered,
          ),
        ),
      ],
    );
  }
}

class _BinaryGradeButton extends StatelessWidget {
  const _BinaryGradeButton({
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      // styleFrom treats elevation as a base level (pressed: +6); pin all states flat.
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withValues(alpha: 0.12),
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        // Height floor instead of a fixed SizedBox height: labels wrap to two
        // lines under large text scaling and must grow the button instead of
        // overflowing it.
        minimumSize: const Size(0, 48),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: color.withValues(alpha: 0.4)),
        ),
      ).copyWith(elevation: const WidgetStatePropertyAll<double>(0)),
      child: Text(
        label,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    );
  }
}

/// Bottom action button shared by all graders (MCQ, FillBlank, Translate,
/// ListenAndPick, TypeTheWord, ReorderSentence). ShowWord has no button — it
/// auto-advances on card tap.
///
/// 质感要点: 竖向渐变 (亮在上) + 品牌阴影 + 同色外发光. 之前传
/// `elevated: false` 把阴影整个关掉了, 按钮在画布上是一片纯色块, 这也是
/// "点不动"的心理暗示来源之一.
///
/// 按下时缩放 0.985 且阴影收到零 —— 光靠水波纹不足以让拇指相信"按到了".
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
  /// 与 [TurnaTheme.buttonGradient] 同一对品牌色, 但改为竖向 ——
  /// 从上到下由亮到暗才读作"受光的实体键", 对角渐变在按钮高度上几乎看不出.
  static const LinearGradient _ctaGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [TurnaTheme.brandTealLight, TurnaTheme.brandTeal],
  );

  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(TurnaTheme.radiusOption);
    final enabled = widget.enabled;
    final lifted = enabled && !_pressed;

    return AnimatedScale(
      scale: _pressed ? 0.985 : 1.0,
      duration: const Duration(milliseconds: 110),
      curve: Curves.easeOutCubic,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        height: 52,
        width: double.infinity,
        decoration: enabled
            ? BoxDecoration(
                gradient: _ctaGradient,
                borderRadius: radius,
                boxShadow: lifted
                    ? [
                        ...TurnaTheme.buttonShadow,
                        ...TurnaTheme.stateGlow(TurnaTheme.brandTeal),
                      ]
                    : null,
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
                    unawaited(HapticFeedback.mediumImpact());
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

/// Selectable option tile for MCQ / pick-from-list interactions.
class InteractionOptionTile extends StatefulWidget {
  final String label;
  final bool isSelected;
  final bool isCorrect;
  final bool isWrong;
  final VoidCallback? onTap;

  const InteractionOptionTile({
    super.key,
    required this.label,
    required this.isSelected,
    required this.isCorrect,
    required this.isWrong,
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
      _verdict.forward(from: 0);
      unawaited(HapticFeedback.mediumImpact());
    }
  }

  @override
  void dispose() {
    _verdict.dispose();
    super.dispose();
  }

  /// 状态 → 强调色. `null` 表示未选中的常态 (走 L1 中性卡).
  Color? _accent() {
    if (widget.isCorrect) return TurnaTheme.leagueEmerald;
    if (widget.isWrong) return TurnaTheme.error;
    if (widget.isSelected) return TurnaTheme.brandTeal;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _verdict,
      child: _buildTile(context),
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

  Widget _buildTile(BuildContext context) {
    final stateAccent = _accent();
    // ADR 0062：未判定时走中性灰玻璃（表单级浓度），判定后按结果色相上彩。
    final accent = stateAccent ?? TurnaTheme.glassNeutral;
    final level = stateAccent == null ? GlassLevel.l1Subtle : GlassLevel.l1;

    final radius = BorderRadius.circular(TurnaTheme.radiusOption);
    final labelColor = TurnaTheme.textPrimaryColor(context);

    return Semantics(
      button: true,
      label: widget.label,
      selected: widget.isSelected,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          // 单层 gradient（白高光已预混进 stop）—— 所以 180ms 状态切换
          // 能平滑插值。拆成两层 fill 会让这里的过渡直接跳变。
          decoration: TurnaTheme.glassDecoration(
            context,
            accent,
            level: level,
            borderRadius: radius,
            // 按下时阴影收到零: 视觉上"被按进去", 而不是只有一个缩放.
            boxShadow: _pressed
                ? const <BoxShadow>[]
                : [
                    ...TurnaTheme.glassShadow(context, accent, level: level),
                    if (stateAccent != null)
                      ...TurnaTheme.stateGlow(stateAccent),
                  ],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: radius,
              onTap: widget.onTap == null
                  ? null
                  : () {
                      unawaited(HapticFeedback.selectionClick());
                      widget.onTap!();
                    },
              onHighlightChanged: (v) {
                if (widget.onTap == null) return;
                setState(() => _pressed = v);
              },
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: stateAccent ?? Colors.transparent,
                        border: Border.all(
                          color:
                              stateAccent ?? TurnaTheme.textHintColor(context),
                          width: 1.5,
                        ),
                      ),
                      child: stateAccent == null
                          ? null
                          : Icon(
                              widget.isWrong ? Icons.close : Icons.check,
                              size: 12,
                              color: Colors.white,
                            ),
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
                          color: labelColor,
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
        child: Material(
          color: speaking
              ? TurnaTheme.brandTeal.withValues(alpha: 0.72)
              : TurnaTheme.brandTeal,
          shape: const CircleBorder(),
          elevation: 4,
          shadowColor: TurnaTheme.brandTeal.withValues(alpha: 0.4),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: speaking ? null : onPressed,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Icon(
                speaking ? Icons.graphic_eq_rounded : Icons.volume_up_rounded,
                color: TurnaTheme.textOnPrimary,
                size: 36,
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
