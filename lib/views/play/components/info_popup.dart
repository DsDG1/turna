// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/accessibility_provider.dart';
import 'package:turna/application/settings_provider.dart';
import 'package:turna/views/theme.dart';

/// 长按浮窗：锚定在源卡片旁的数据详情浮层（Play Hub 专用交互）。
///
/// 交互契约：
/// * 短按仍由卡片自身的 `onTap` 处理（进入页面），本组件只负责长按详情。
/// * 浮窗优先出现在锚点卡片下方；下方空间不足时翻转到上方。
/// * 打开 = 缩放 + 淡入（自锚点中心方向），内容行逐条 stagger 滑入；
///   关闭 = 反向收拢。`reducedMotion` / 系统禁用动画时退化为纯淡入淡出。
/// * 打开前触发一次 medium 触感（`sensoryReduce` 时跳过）。
/// * 点击遮罩关闭；面板内「进入」按钮先关闭浮窗再导航。
class PlayInfoPopup {
  PlayInfoPopup._(this._hostKey);

  final GlobalKey<_InfoPopupHostState> _hostKey;

  /// 在 [anchorContext]（长按的卡片）旁弹出数据浮窗。
  ///
  /// [builder] 的内容会被包进 [InfoPopupScope]，行级 stagger 用
  /// [InfoStaggeredRow] / [InfoPopupScope.of] 取进度动画。
  static PlayInfoPopup show({
    required BuildContext anchorContext,
    required String semanticsLabel,
    required WidgetBuilder builder,
  }) {
    final overlay = Overlay.of(anchorContext, rootOverlay: true);
    final hostKey = GlobalKey<_InfoPopupHostState>();

    _triggerHaptic(anchorContext);

    late final OverlayEntry entry;
    entry = OverlayEntry(
      opaque: false,
      builder: (_) => _InfoPopupHost(
        key: hostKey,
        anchorContext: anchorContext,
        semanticsLabel: semanticsLabel,
        onDismissed: () => entry.remove(),
        builder: builder,
      ),
    );
    overlay.insert(entry);
    return PlayInfoPopup._(hostKey);
  }

  /// 反向播放关闭动画后移除浮层。
  void close() => _hostKey.currentState?._dismiss();
}

void _triggerHaptic(BuildContext context) {
  final a11y = context.read<AccessibilityProvider>();
  if (a11y.quietFeedback) return;
  context.read<SettingsProvider>().triggerHaptic(HapticFeedbackType.medium);
}

/// 面板内容通过该 InheritedWidget 读取打开进度（0→1），
/// 行级 stagger 用 [InfoStaggeredRow] 封装。
class InfoPopupScope extends InheritedWidget {
  const InfoPopupScope({
    required this.progress,
    required super.child,
    super.key,
  });

  final Animation<double> progress;

  static Animation<double>? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<InfoPopupScope>()?.progress;

  @override
  bool updateShouldNotify(InfoPopupScope oldWidget) =>
      oldWidget.progress != progress;
}

/// stagger 淡入 + 上滑的行。`reducedMotion` 下直接显示。
class InfoStaggeredRow extends StatelessWidget {
  final int index;
  final Widget child;

  const InfoStaggeredRow({required this.index, required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    final progress = InfoPopupScope.maybeOf(context);
    if (progress == null) return child;

    final start = (0.08 + index * 0.07).clamp(0.0, 0.72);
    final curved = CurvedAnimation(
      parent: progress,
      curve: Interval(start, (start + 0.28).clamp(0.0, 1.0),
          curve: Curves.easeOutCubic),
    );

    return AnimatedBuilder(
      animation: curved,
      builder: (context, _) {
        final t = curved.value;
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 10),
            child: child,
          ),
        );
      },
    );
  }
}

class _InfoPopupHost extends StatefulWidget {
  const _InfoPopupHost({
    required this.anchorContext,
    required this.semanticsLabel,
    required this.onDismissed,
    required this.builder,
    super.key,
  });

  final BuildContext anchorContext;
  final String semanticsLabel;
  final VoidCallback onDismissed;
  final WidgetBuilder builder;

  @override
  State<_InfoPopupHost> createState() => _InfoPopupHostState();
}

class _InfoPopupHostState extends State<_InfoPopupHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _panelCurve;
  late final CurvedAnimation _scrimCurve;
  bool _closing = false;

  static const _panelMargin = 12.0;
  static const _anchorGap = 10.0;
  static const _maxPanelWidth = 360.0;
  static const _maxPanelHeight = 420.0;
  /// 下方至少留出这么高才把浮窗放在锚点下方，否则翻转到上方。
  static const _preferBelowMinSpace = 200.0;

  @override
  void initState() {
    super.initState();
    final a11y = widget.anchorContext.read<AccessibilityProvider>();
    final reduceMotion =
        MediaQuery.disableAnimationsOf(widget.anchorContext) ||
            a11y.reducedMotion;
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 300);

    _controller = AnimationController(vsync: this, duration: duration)
      ..forward();
    _panelCurve = CurvedAnimation(
      parent: _controller,
      curve: reduceMotion ? Curves.linear : Curves.easeOutBack,
      reverseCurve: Curves.easeInCubic,
    );
    _scrimCurve = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      reverseCurve: const Interval(0.0, 0.6, curve: Curves.easeIn),
    );
  }

  @override
  void dispose() {
    _panelCurve.dispose();
    _scrimCurve.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _dismiss() {
    if (_closing) return;
    _closing = true;
    _controller.reverse().whenComplete(widget.onDismissed);
  }

  @override
  Widget build(BuildContext context) {
    final anchorBox =
        widget.anchorContext.findRenderObject() as RenderBox?;
    if (anchorBox == null || !anchorBox.attached) return const SizedBox.shrink();

    final overlay = Overlay.of(context);
    final overlayBox = overlay.context.findRenderObject() as RenderBox;
    final anchorRect = Rect.fromPoints(
      anchorBox.localToGlobal(Offset.zero, ancestor: overlayBox),
      anchorBox.localToGlobal(
        anchorBox.size.bottomRight(Offset.zero),
        ancestor: overlayBox,
      ),
    );
    final overlaySize = overlayBox.size;
    final belowSpace = overlaySize.height - anchorRect.bottom - _anchorGap;
    final aboveSpace = anchorRect.top - _anchorGap;
    final placeBelow = belowSpace >= _preferBelowMinSpace || belowSpace >= aboveSpace;

    final panelWidth =
        _maxPanelWidth.clamp(0.0, overlaySize.width - _panelMargin * 2);
    final left = (anchorRect.center.dx - panelWidth / 2)
        .clamp(_panelMargin, overlaySize.width - panelWidth - _panelMargin);

    final maxPanelHeight = (placeBelow ? belowSpace : aboveSpace)
        .clamp(0.0, _maxPanelHeight) - _panelMargin;

    final panel = _AnimatedPanel(
      controller: _controller,
      curve: _panelCurve,
      semanticsLabel: widget.semanticsLabel,
      anchorCenterX: anchorRect.center.dx,
      top: placeBelow ? anchorRect.bottom + _anchorGap : null,
      bottom: placeBelow
          ? null
          : overlaySize.height - anchorRect.top + _anchorGap,
      left: left,
      width: panelWidth,
      maxHeight: maxPanelHeight < 120 ? 120 : maxPanelHeight,
      child: InfoPopupScope(
        progress: _controller,
        child: widget.builder(context),
      ),
    );

    return Stack(
      children: [
        // 遮罩：淡入，点击关闭。
        Positioned.fill(
          child: GestureDetector(
            onTap: _dismiss,
            behavior: HitTestBehavior.opaque,
            child: FadeTransition(
              opacity: _scrimCurve,
              child: const ColoredBox(
                color: Color(0x46000000),
              ),
            ),
          ),
        ),
        panel,
      ],
    );
  }
}

/// 缩放 + 淡入浮窗本体：scale 原点对齐锚点中心方向，模拟「从卡片里弹出」。
class _AnimatedPanel extends StatelessWidget {
  const _AnimatedPanel({
    required this.controller,
    required this.curve,
    required this.semanticsLabel,
    required this.anchorCenterX,
    required this.top,
    required this.bottom,
    required this.left,
    required this.width,
    required this.maxHeight,
    required this.child,
  });

  final AnimationController controller;
  final CurvedAnimation curve;
  final String semanticsLabel;
  final double anchorCenterX;
  final double? top;
  final double? bottom;
  final double left;
  final double width;
  final double maxHeight;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: curve,
      builder: (context, child) {
        final t = curve.value;
        final alignment = Alignment(
          ((anchorCenterX - left) / width - 0.5).clamp(-1.0, 1.0) * 2,
          bottom != null ? 1.0 : -1.0,
        );
        return Positioned(
          top: top,
          bottom: bottom,
          left: left,
          width: width,
          child: Opacity(
            opacity: Curves.easeOut.transform(t.clamp(0.0, 1.0)),
            child: Transform.scale(
              scale: 0.88 + 0.12 * t,
              alignment: alignment,
              child: child,
            ),
          ),
        );
      },
      child: Material(
        elevation: 0,
        color: Colors.transparent,
        child: Semantics(
          container: true,
          label: semanticsLabel,
          explicitChildNodes: true,
          child: Container(
            constraints: BoxConstraints(maxHeight: maxHeight),
            decoration: BoxDecoration(
              color: TurnaTheme.surfaceColor(context),
              borderRadius: const BorderRadius.all(
                Radius.circular(TurnaTheme.radiusXLarge),
              ),
              border: Border.all(color: TurnaTheme.glassBorder(context)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: Theme.of(context).brightness == Brightness.dark
                        ? 0.5
                        : 0.16,
                  ),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.all(
                Radius.circular(TurnaTheme.radiusXLarge),
              ),
              child: SingleChildScrollView(
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
