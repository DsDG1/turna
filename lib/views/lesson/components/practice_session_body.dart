// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Project imports:
import 'package:turna/core/theme.dart';
import 'package:turna/core/motion.dart';
import 'package:turna/application/accessibility_capabilities.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/lesson/components/interactions/interaction_renderer.dart';
import 'package:turna/views/lesson/components/lesson_stage_widgets.dart';
import 'package:turna/views/widgets/session_shell.dart';
import 'package:turna/views/widgets/turna_page_content.dart';

/// Shared lesson-practice chrome: stage banner, optional header (reading
/// passage), scrollable renderer, bottom action bar.
///
/// 底栏是**唯一**的主操作位置: 核对型 renderer 不再自己画按钮, 只在 build 里
/// 通过 [LessonActionScope] 报"能不能提交 / 提交做什么". 这样同一个按钮在
/// 提交前后是同一个 widget、同一个位置, 不会从内容中间跳到屏幕底部.
///
/// 揭示型 / 自评型 (Anki 翻面、图像回忆、朗读) 不参与这套契约 —— 它们的按钮
/// 语义是"显示答案", 留在卡片内部; 它们提交后由底栏接管"继续".
///
/// [LessonActionDraft] 由本组件自己持有并按题轮换, 页面只需给 [submitted] /
/// [autoAdvance] / [continueLabel].
class PracticeSessionBody extends StatefulWidget {
  const PracticeSessionBody({
    super.key,
    required this.child,
    this.stageName,
    this.stageAccent,
    this.stageIcon,
    this.header,
    this.scrollController,
    this.interactionKey,
    this.submitted = false,
    this.autoAdvance = false,
    this.continueLabel,
    this.onAdvance,
    this.wrapRendererBoundary = false,
    this.maxWidth = 720,
  });

  final Widget child;
  final String? stageName;
  final Color? stageAccent;
  final IconData? stageIcon;
  final Widget? header;
  final ScrollController? scrollController;
  final double maxWidth;

  /// 当前题的稳定标识. 变了就意味着换题, 草稿随之重置.
  final Key? interactionKey;

  /// 当前题是否已提交. 决定底栏是"核对"还是"继续".
  final bool submitted;

  /// 自动推进的题型没有主按钮, 底栏整条不出现.
  final bool autoAdvance;

  /// 提交后的按钮文案 ("继续" / "知道了").
  final String? continueLabel;

  final VoidCallback? onAdvance;
  final bool wrapRendererBoundary;

  @override
  State<PracticeSessionBody> createState() => _PracticeSessionBodyState();
}

class _PracticeSessionBodyState extends State<PracticeSessionBody> {
  /// 当前题的 CTA 草稿. 换题时换实例, 上一题的"能否提交"不会渗到下一题.
  LessonActionDraft _draft = LessonActionDraft();
  late bool _wasSubmitted = widget.submitted;

  @override
  void didUpdateWidget(covariant PracticeSessionBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 换题信号: 题目标识变了, 或者刚提交完又被重置 (没有 interactionKey 的
    // 调用方靠这一步复位, 否则上一题的"可提交"会留在下一题).
    final newItem = oldWidget.interactionKey != widget.interactionKey ||
        (_wasSubmitted && !widget.submitted);
    if (newItem) _draft = LessonActionDraft();
    _wasSubmitted = widget.submitted;
  }

  @override
  Widget build(BuildContext context) {
    // 换题时新内容淡入 + 上移 8px. key 挂在 _EnterTransition 上, 每道题都会
    // 重建并重播动画. 只做"进入"不做"退出": 两份内容同时占位会让滚动位置跳.
    final Widget scrollChild = widget.interactionKey == null
        ? widget.child
        : _EnterTransition(key: widget.interactionKey, child: widget.child);
    Widget scrollerFor(double? minContentHeight) => SingleChildScrollView(
          controller: widget.scrollController,
          // 底部留白由 [InteractionBody] 的 24 承担, 这里只留 8 的呼吸位,
          // 两处都写 32 会让最后一行和操作栏之间凭空多出半屏空白.
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: minContentHeight == null
              ? scrollChild
              : ConstrainedBox(
                  constraints: BoxConstraints(minHeight: minContentHeight),
                  child: Center(child: scrollChild),
                ),
        );

    // 读卡类（无底栏）把内容在画布里垂直居中。
    //
    // 滚动的孩子拿到的最大高度是无穷大，所以 renderer 里自己写的 `Center`
    // 从来没有生效过 —— 读卡永远贴在阶段行下面，画布下半截空着（实拍约
    // 47% 屏高）。给滚动内容一个「至少一屏」的下限，居中才成立；内容超过
    // 一屏时下限不起作用，滚动行为与之前完全一致。
    //
    // 只对 autoAdvance 生效：作答卡提交后会在卡下长出解析，居中会让整张卡
    // 在每次提交时向上跳半个增量；读卡没有这种增长，位移风险为零。
    Widget scroller = widget.autoAdvance
        ? LayoutBuilder(
            builder: (context, constraints) => scrollerFor(
              (constraints.maxHeight - 16).clamp(0.0, double.infinity),
            ),
          )
        : scrollerFor(null);
    if (widget.wrapRendererBoundary) {
      scroller = RepaintBoundary(child: scroller);
    }

    final body = Column(
      children: [
        if (widget.stageName != null)
          LessonStageBanner(
            name: widget.stageName!,
            accent: widget.stageAccent ?? TurnaTheme.brandTeal,
            icon: widget.stageIcon,
          ),
        if (widget.header != null) widget.header!,
        // 草稿契约在 scroller 之上注入, renderer 子树里任何 State 都能查到.
        Expanded(child: LessonActionScope(draft: _draft, child: scroller)),
        if (!widget.autoAdvance)
          _ActionBar(
            draft: _draft,
            submitted: widget.submitted,
            continueLabel: widget.continueLabel,
            onAdvance: widget.onAdvance,
          ),
      ],
    );

    final content = TurnaPageContent(maxWidth: widget.maxWidth, child: body);
    // 安全区只收一次: 有底栏时由底栏自己吞底部 inset (它的底色要铺满),
    // 没有底栏时退回到整列. 两边都加就会在按钮上方凭空多出 34px 死区.
    if (!widget.autoAdvance) return content;
    return SafeArea(top: false, left: false, right: false, child: content);
  }
}

/// 单题入场: 220ms 淡入 + 从下方 8px 滑到位.
///
/// 只做进入. 退出交给内容直接替换 —— 换题时两层内容叠在一起会让
/// [SingleChildScrollView] 的滚动位置抖动, 而做题页每换一题都会跳回顶部.
class _EnterTransition extends StatelessWidget {
  final Widget child;

  const _EnterTransition({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context) ||
        accessibilityOf(context).reduceMotion;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: TurnaMotion.scaled(TurnaMotion.base, reduceMotion),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 8 * (1 - t)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// 固定操作栏: 底色铺满底部安全区, 顶部一条 hairline 把它和滚动内容分开.
///
/// 它**常驻**在 Column 里 (提交前就在), 只是没有 CTA 时收成零高度. 位置恒定
/// 是这一层的全部意义 —— 任何"提交后才插进来"的写法都会把按钮顶走.
class _ActionBar extends StatefulWidget {
  final LessonActionDraft draft;
  final bool submitted;
  final String? continueLabel;
  final VoidCallback? onAdvance;

  const _ActionBar({
    required this.draft,
    required this.submitted,
    required this.continueLabel,
    required this.onAdvance,
  });

  @override
  State<_ActionBar> createState() => _ActionBarState();
}

class _ActionBarState extends State<_ActionBar> {
  @override
  void initState() {
    super.initState();
    widget.draft.attach(_onDraftChanged);
  }

  @override
  void didUpdateWidget(covariant _ActionBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.draft, widget.draft)) {
      oldWidget.draft.detach(_onDraftChanged);
      widget.draft.attach(_onDraftChanged);
    }
  }

  @override
  void dispose() {
    widget.draft.detach(_onDraftChanged);
    super.dispose();
  }

  /// 草稿的通知一律在帧后发出, 所以这里直接 setState 是安全的.
  void _onDraftChanged() {
    if (mounted) setState(() {});
  }

  /// 主操作：触感沿旧 [LessonCheckButton] 的约定（非静音反馈时中击），
  /// 提交前走草稿、提交后推进。
  void _handlePrimary() {
    final a11y = accessibilityOf(context);
    if (!a11y.quietFeedback) unawaited(HapticFeedback.mediumImpact());
    if (widget.submitted) {
      widget.onAdvance?.call();
    } else {
      widget.draft.submit();
    }
  }

  @override
  Widget build(BuildContext context) {
    // 提交后永远有底栏 (继续/知道了); 提交前只有托管了 CTA 的题型才有.
    final hasBar = widget.submitted || widget.draft.hasCta;
    if (!hasBar) return const SizedBox.shrink();

    final submitted = widget.submitted;

    // 「湿地雾光」R04：纸面动作带（顶部发丝线 + 底部安全区）+ 52 高 teal
    // 主键。位置跨题型恒定（P1），文案随作答阶段换（核对/题型自定 → 继续）。
    return SessionActionBand(
      child: SessionPrimaryAction(
        label: submitted
            ? (widget.continueLabel ?? AppStrings.lessonContinueUpper)
            : (widget.draft.label ?? AppStrings.lessonCheck),
        onPressed:
            (submitted || widget.draft.canSubmit) ? _handlePrimary : null,
      ),
    );
  }
}
