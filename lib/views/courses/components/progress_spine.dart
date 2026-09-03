// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/views/theme.dart';

/// 展开单元内的「学习旅程线」（Plan「湿地晨光」§3.3）。
///
/// 每行课程瓦片左侧一格：竖线贯穿上下行，行与行的线在视觉上连成一条
/// 从单元头部延伸到最后一课的路径。已走过的段落以品牌青绿着色——完成
/// 度不再只靠数字，而是「能看见自己走了多远」。
class ProgressSpine extends StatelessWidget {
  /// 是否为旅程第一行（不画上方线段）。
  final bool isFirst;

  /// 是否为旅程最后一行（不画下方线段）。
  final bool isLast;

  /// 本行节点状态。
  final SpineStatus status;

  /// 上方线段是否已完成（= 上一行的完成态）。
  final bool previousCompleted;

  const ProgressSpine({
    required this.isFirst,
    required this.isLast,
    required this.status,
    this.previousCompleted = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final done = status == SpineStatus.completed;
    final lineColor = done || previousCompleted
        ? TurnaTheme.brandTeal.withValues(alpha: 0.5)
        : TurnaTheme.dividerBg(context);

    return SizedBox(
      width: 24,
      child: Column(
        children: [
          // 与课程瓦片内容行对齐的锚点：图标中心距行顶 ~20px。
          SizedBox(
            height: 22,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: isFirst ? Colors.transparent : lineColor, width: 2.5),
                ),
              ),
            ),
          ),
          _SpineNode(status: status),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: isLast ? Colors.transparent : lineColor, width: 2.5),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum SpineStatus { upcoming, nextUp, completed }

class _SpineNode extends StatelessWidget {
  final SpineStatus status;

  const _SpineNode({required this.status});

  @override
  Widget build(BuildContext context) {
    final (fill, border, glow) = switch (status) {
      SpineStatus.completed => (
          TurnaTheme.brandTeal,
          TurnaTheme.brandTeal,
          false,
        ),
      SpineStatus.nextUp => (
          TurnaTheme.cardBg(context),
          TurnaTheme.brandTeal,
          true,
        ),
      SpineStatus.upcoming => (
          Colors.transparent,
          TurnaTheme.dividerBg(context),
          false,
        ),
    };

    return Container(
      width: 13,
      height: 13,
      margin: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: Border.all(color: border, width: status == SpineStatus.nextUp ? 2.5 : 2),
        boxShadow: glow
            ? [
                BoxShadow(
                  color: TurnaTheme.brandTeal.withValues(alpha: 0.30),
                  blurRadius: 7,
                ),
              ]
            : null,
      ),
    );
  }
}
