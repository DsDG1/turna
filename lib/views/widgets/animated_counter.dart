// Flutter imports:
import 'package:flutter/material.dart';

/// 数字滚动动画：从上一个显示值补间到新目标，而不是每次归零再数。
///
/// 原住在 home 的 `stat_app_bar.dart`（积分 / 连胜胶囊退役后唯一的存活
/// 依赖是课时完成结算的奖励计数）。
class AnimatedCounter extends StatefulWidget {
  final int target;
  final TextStyle style;

  const AnimatedCounter({
    super.key,
    required this.target,
    required this.style,
  });

  @override
  State<AnimatedCounter> createState() => _AnimatedCounterState();
}

class _AnimatedCounterState extends State<AnimatedCounter> {
  /// The value the counter was last displaying. The next tween animates from
  /// this value to the new target, so score/streak updates count up from the
  /// previous number instead of resetting to zero on every stream emit.
  late int _from = widget.target;

  @override
  void didUpdateWidget(covariant AnimatedCounter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.target != widget.target) {
      _from = oldWidget.target;
    }
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: TweenAnimationBuilder<int>(
        tween: IntTween(begin: _from, end: widget.target),
        duration: const Duration(milliseconds: 1000),
        builder: (context, value, child) {
          return Text(
            value.toString(),
            style: widget.style,
          );
        },
      ),
    );
  }
}
