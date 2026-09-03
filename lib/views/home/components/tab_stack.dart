// Flutter imports:
import 'package:flutter/material.dart';

/// 主页底部 Tab 承载层：原生默认的瞬时切换（无过渡动画），与
/// IndexedStack 的经典行为一致——点击 Tab 内容立即整体替换。
///
/// 与懒挂载配合的硬约束：
/// - 子树永久挂载：滚动位置、手风琴状态跨 Tab 存活；
/// - 非激活子树 [Offstage] 隐藏 + [TickerMode] 关闭，闲置零帧成本；
/// - 未访问的 Tab 由调用方继续传 [SizedBox.shrink] 实现懒挂载；
/// - 语义树仅暴露激活页（[ExcludeSemantics]）。
class TabStack extends StatelessWidget {
  const TabStack({required this.index, required this.children, super.key});

  final int index;

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < children.length; i++)
          ExcludeSemantics(
            excluding: i != index,
            child: IgnorePointer(
              ignoring: i != index,
              child: TickerMode(
                enabled: i == index,
                child: Offstage(
                  offstage: i != index,
                  child: children[i],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
