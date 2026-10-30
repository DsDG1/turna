// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/core/theme.dart';

/// L0 环境层：纯白画布（ADR 0062）。
///
/// 上一代这里是「湿地晨光」——湿地渐变 + 两团晨雾 + 滚动视差。那套氛围
/// 是「彩色背景 + 磨砂白卡」物理模型的配套：白卡之所以能读作玻璃，全靠
/// 背后那层有色渐变透上来。
///
/// 本代玻璃是「白纸上的彩色玻璃片」：淡彩由玻璃自己发，影子也取同色相
/// 投在白纸上。背景一旦带色，卡面那点 9~19% 的淡彩就失去参照 —— 整页会
/// 读成「一层被染过的底 + 灰白卡片」，玻璃感反而消失。
///
/// 所以氛围层退场，只留画布底色。**保留这个组件而不是让调用方直接用
/// `ColoredBox`**：它是 L0 的语义锚点，以后若要加回极淡的层次，改这一处。
///
/// [reduceMotion] 仅为兼容既有调用点保留：当前 L0 层没有任何动画，
/// 取值不影响渲染。
class AmbientBackdrop extends StatelessWidget {
  const AmbientBackdrop({
    required this.child,
    this.reduceMotion = false,
    super.key,
  });

  final Widget child;

  /// 兼容参数，L0 层已无动画。
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: TurnaTheme.courseTreeGradientFor(context),
              ),
            ),
          ),
        ),
        // 内容层在背景之上，独立接收命中测试。
        Positioned.fill(child: child),
      ],
    );
  }
}
