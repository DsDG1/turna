// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/core/theme.dart';

/// L0 环境层：画布底色 + 三片极淡天光（ADR 0068）。
///
/// 上一代这里是「湿地晨光」——湿地渐变 + 两团晨雾 + 滚动视差。那套氛围
/// 是「彩色背景 + 磨砂白卡」物理模型的配套：白卡之所以能读作玻璃，全靠
/// 背后那层有色渐变透上来。ADR 0062 换模型时把它整个撤掉，画布退成纯白。
///
/// 纯白解决了「卡面淡彩失去参照」，却也带走了空间：一屏白纸叠几张淡彩卡，
/// 读不出光源方位。ADR 0068 补回来的**不是背景色，是光**——
///
/// * 光斑只落在页面边缘（左上 / 右上 / 底缘），中部保持净白；
/// * 峰值 alpha ≤ 5%，低到不足以改变卡面淡彩的参照；
/// * 高对比 / [GlassMode.off] 时整层退化为纯色，不参与对比度。
///
/// 静态绘制，无动画：光不呼吸，页面也就不需要为了环境层每帧重绘。
/// [reduceMotion] 为兼容既有调用点保留，当前 L0 层没有任何动画，取值不影响
/// 渲染。
class AmbientBackdrop extends StatelessWidget {
  const AmbientBackdrop({
    required this.child,
    this.reduceMotion = false,
    this.baseColor,
    super.key,
  });

  final Widget child;

  /// 兼容参数，L0 层已无动画。
  final bool reduceMotion;

  /// 画布底色。缺省按主题取（浅色白 / 深色近黑）；外壳按 Tab 切换底色时
  /// 传具体色，避免光斑层把外壳的过渡色盖掉。
  final Color? baseColor;

  @override
  Widget build(BuildContext context) {
    final lights = TurnaTheme.ambientLights(context);
    final base = baseColor ??
        (Theme.of(context).brightness == Brightness.dark
            ? TurnaTheme.darkScaffold
            : TurnaTheme.scaffoldBackground);

    return Stack(
      fit: StackFit.expand,
      children: [
        // 整层独立成一层绘制：光斑是静态的，不该跟着内容滚动重绘。
        RepaintBoundary(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(color: base),
              child: lights.isEmpty
                  ? null
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        for (final light in lights) _AmbientLightLayer(light),
                      ],
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

/// 单片光晕：径向渐变 + 纵向拉伸。
class _AmbientLightLayer extends StatelessWidget {
  const _AmbientLightLayer(this.light);

  final AmbientLight light;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Transform.scale(
        scaleY: light.scale,
        // 以顶边为锚点拉伸：光心在上方时不会因为缩放跑到画布外。
        alignment: Alignment.topCenter,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: light.center,
              radius: light.radius,
              colors: <Color>[
                light.color,
                light.color.withValues(alpha: 0),
              ],
              stops: const <double>[0.0, 1.0],
            ),
          ),
        ),
      ),
    );
  }
}
