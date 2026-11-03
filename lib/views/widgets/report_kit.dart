/// 报告构图套件 ——「湿地雾光」学习报告版式（P2 组件，P3 / P4 逐域接线）。
///
/// 洞察、复习进度、错题仪表盘与牌组统计共用同一套构图：一个核心指标开篇
/// （[ReportMetricHeader]）→ 主图独立段落（[ReportBarChart] /
/// [ReportLineChart] / [ReportHeatmap] / [ReportCompositionBar]）→ 辅助
/// 指标按解释顺序（[ReportDefinitionList]）。
///
/// 图表全部 CustomPaint 自绘（与 `retention_curve_chart` 同一做法），不引入
/// 图表依赖；每个图表把 [semanticsLabel] 作为必填语义名交给调用方组织——
/// 纯装饰像素图对屏幕阅读器是空的，朗读稿必须由数据侧生成。
library;

// Dart imports:
import 'dart:math' as math;

// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

// Project imports:
import 'package:turna/core/spacing.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/theme.dart';

/// 核心指标头：小标签 + 大数字（+ 单位）+ 副行说明。
///
/// 报告页的开篇件。数字走 [AppTextStyles.metricHero]，语义色由调用方给
/// （待复习 teal 深档、警示 warning）。
class ReportMetricHeader extends StatelessWidget {
  const ReportMetricHeader({
    required this.label,
    required this.value,
    this.unit,
    this.caption,
    this.accentColor,
    super.key,
  });

  final String label;
  final String value;
  final String? unit;
  final String? caption;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.caption(context),
        ),
        const SizedBox(height: AppSpacing.sm - 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: AppTextStyles.metricHero(
                context,
                color: accentColor ?? TurnaTheme.brandTealDark,
              ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
            ),
            if (unit != null && unit!.isNotEmpty) ...[
              const SizedBox(width: AppSpacing.xs + 2),
              Text(
                unit!,
                style: AppTextStyles.captionSm(context).copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ],
        ),
        if (caption != null && caption!.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs + 2),
          Text(caption!, style: AppTextStyles.captionSm(context)),
        ],
      ],
    );
  }
}

/// 报告区块标题：分组名 + 可选尾注（时间窗切换等）。
class ReportSectionHeading extends StatelessWidget {
  const ReportSectionHeading({required this.title, this.trailing, super.key});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        children: [
          Expanded(child: Text(title, style: AppTextStyles.sectionTitle(context))),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// 一段构成（构成条的一个色段）。
class ReportSegment {
  const ReportSegment({
    required this.label,
    required this.value,
    required this.color,
    this.valueLabel,
  });

  final String label;
  final double value;
  final Color color;

  /// 图例上显示的值文案（「12 张」「38%」）；缺省显示 [value] 取整。
  final String? valueLabel;
}

/// 构成条：横向分段比例条 + 图例行（点 + 名称 + 值）。
///
/// 用于「这批待复习都从哪来」「存储都被什么占了」一类构成解释。
class ReportCompositionBar extends StatelessWidget {
  const ReportCompositionBar({
    required this.segments,
    this.showLegend = true,
    super.key,
  });

  final List<ReportSegment> segments;
  final bool showLegend;

  @override
  Widget build(BuildContext context) {
    final visible =
        segments.where((s) => s.value > 0).toList(growable: false);
    final total = visible.fold<double>(0, (sum, s) => sum + s.value);

    if (visible.isEmpty || total <= 0) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: Row(
            children: [
              for (var i = 0; i < visible.length; i++) ...[
                if (i > 0) const SizedBox(width: 2),
                Expanded(
                  flex: math.max(1, (visible[i].value / total * 1000).round()),
                  child: Container(height: 10, color: visible[i].color),
                ),
              ],
            ],
          ),
        ),
        if (showLegend) ...[
          const SizedBox(height: AppSpacing.md),
          for (var i = 0; i < visible.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.sm - 2),
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: visible[i].color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm + 2),
                Expanded(child: Text(visible[i].label, style: AppTextStyles.captionSm(context))),
                Text(
                  visible[i].valueLabel ?? _defaultLabel(visible[i].value),
                  style: AppTextStyles.captionSm(context).copyWith(
                        color: TurnaTheme.textPrimaryColor(context),
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                ),
              ],
            ),
          ],
        ],
      ],
    );
  }

  static String _defaultLabel(double value) {
    final rounded = value.round();
    return value == rounded ? '$rounded' : value.toStringAsFixed(1);
  }
}

/// 一根柱（柱状图的一个数据点）。
class ReportBar {
  const ReportBar({required this.label, required this.value, this.highlight = false});

  final String label;
  final double value;
  final bool highlight;
}

/// 柱状图：自绘纵向柱 + 底部标签。
///
/// 高对比与深色下靠 [TurnaTheme] 的主题感知色（轨道 / 文字）保持可读，
/// 柱体颜色默认 teal，[ReportBar.highlight] 的柱加深一档。
class ReportBarChart extends StatelessWidget {
  const ReportBarChart({
    required this.bars,
    required this.semanticsLabel,
    this.height = 180,
    this.maxValue,
    this.barColor,
    super.key,
  });

  final List<ReportBar> bars;
  final String semanticsLabel;
  final double height;

  /// 值轴上限；缺省取数据最大值（全零时为 1，避免除零）。
  final double? maxValue;
  final Color? barColor;

  @override
  Widget build(BuildContext context) {
    if (bars.isEmpty) return const SizedBox.shrink();

    final resolvedMax = maxValue ??
        bars.fold<double>(0, (m, b) => math.max(m, b.value)).clamp(1, double.infinity);
    final painter = _BarChartPainter(
      bars: bars,
      maxValue: resolvedMax,
      barColor: barColor ?? TurnaTheme.brandTeal,
      highlightColor: TurnaTheme.brandTealDark,
      trackColor: TurnaTheme.dividerBg(context),
      labelColor: TurnaTheme.textHintColor(context),
    );

    return Semantics(
      label: semanticsLabel,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(painter: painter),
      ),
    );
  }
}

class _BarChartPainter extends CustomPainter {
  _BarChartPainter({
    required this.bars,
    required this.maxValue,
    required this.barColor,
    required this.highlightColor,
    required this.trackColor,
    required this.labelColor,
  });

  final List<ReportBar> bars;
  final double maxValue;
  final Color barColor;
  final Color highlightColor;
  final Color trackColor;
  final Color labelColor;

  static const double _labelHeight = 18;
  static const double _labelFontSize = 11;
  static const double _barMaxWidth = 34;

  @override
  void paint(Canvas canvas, Size size) {
    final plotHeight = math.max(0.0, size.height - _labelHeight);
    final slot = size.width / bars.length;
    final barWidth = math.min(_barMaxWidth, slot * 0.55);

    for (var i = 0; i < bars.length; i++) {
      final bar = bars[i];
      final cx = slot * i + slot / 2;

      // 轨道：整列浅底，零值柱也有位置感。
      final trackRect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(cx, plotHeight / 2),
          width: barWidth,
          height: plotHeight,
        ),
        const Radius.circular(4),
      );
      canvas.drawRRect(trackRect, Paint()..color = trackColor);

      final h = (bar.value / maxValue).clamp(0.0, 1.0) * plotHeight;
      if (h > 0) {
        final rect = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(cx, plotHeight - h / 2),
            width: barWidth,
            height: h,
          ),
          const Radius.circular(4),
        );
        canvas.drawRRect(rect, Paint()..color = bar.highlight ? highlightColor : barColor);
      }

      _paintLabel(canvas, bar.label, Offset(cx, plotHeight + _labelHeight / 2));
    }
  }

  void _paintLabel(Canvas canvas, String text, Offset center) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: _labelFontSize, color: labelColor),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: 64);
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _BarChartPainter old) =>
      old.bars != bars ||
      old.maxValue != maxValue ||
      old.barColor != barColor;
}

/// 一个点（折线图）。
class ReportPoint {
  const ReportPoint({required this.label, required this.value});

  final String label;
  final double value;
}

/// 折线图：自绘折线 + 淡域填充 + 数据点。
///
/// 数据点超过 6 个时只在两端画标签，中间不挤字。
class ReportLineChart extends StatelessWidget {
  const ReportLineChart({
    required this.points,
    required this.semanticsLabel,
    this.height = 160,
    this.maxValue,
    this.lineColor,
    super.key,
  });

  final List<ReportPoint> points;
  final String semanticsLabel;
  final double height;
  final double? maxValue;
  final Color? lineColor;

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) return const SizedBox.shrink();

    final resolvedMax = maxValue ??
        points.fold<double>(0, (m, p) => math.max(m, p.value)).clamp(1, double.infinity);
    final painter = _LineChartPainter(
      points: points,
      maxValue: resolvedMax,
      lineColor: lineColor ?? TurnaTheme.brandTeal,
      fillColor: TurnaTheme.brandTeal.withValues(alpha: 0.08),
      labelColor: TurnaTheme.textHintColor(context),
    );

    return Semantics(
      label: semanticsLabel,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(painter: painter),
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  _LineChartPainter({
    required this.points,
    required this.maxValue,
    required this.lineColor,
    required this.fillColor,
    required this.labelColor,
  });

  final List<ReportPoint> points;
  final double maxValue;
  final Color lineColor;
  final Color fillColor;
  final Color labelColor;

  static const double _labelHeight = 18;

  @override
  void paint(Canvas canvas, Size size) {
    final plotHeight = math.max(0.0, size.height - _labelHeight);
    final dx = points.length <= 1 ? 0.0 : size.width / (points.length - 1);

    Offset at(int i) => Offset(
          dx * i,
          plotHeight - (points[i].value / maxValue).clamp(0.0, 1.0) * plotHeight,
        );

    final line = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < points.length; i++) {
      line.lineTo(at(i).dx, at(i).dy);
    }

    final area = Path.from(line)..relativeLineTo(0, plotHeight)..lineTo(0, plotHeight)..close();
    canvas.drawPath(area, Paint()..color = fillColor);
    canvas.drawPath(
      line,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );

    for (var i = 0; i < points.length; i++) {
      canvas.drawCircle(at(i), 3, Paint()..color = lineColor);
    }

    // 标签：≤6 个全画，多了只画两端。
    final showAll = points.length <= 6;
    for (var i = 0; i < points.length; i++) {
      if (!showAll && i != 0 && i != points.length - 1) continue;
      final tp = TextPainter(
        text: TextSpan(
          text: points[i].label,
          style: TextStyle(fontSize: 11, color: labelColor),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: 56);
      final x = at(i).dx.clamp(tp.width / 2, size.width - tp.width / 2);
      tp.paint(
        canvas,
        Offset(x - tp.width / 2, plotHeight + _labelHeight / 2 - tp.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter old) =>
      old.points != points || old.maxValue != maxValue || old.lineColor != lineColor;
}

/// 热图：学习记录日历（周列 × 日行由调用方决定方向，这里按行渲染）。
///
/// [levels] 每项 0–4：0 是轨道色，1–4 向 [accent] 逐步加深。数据侧负责
/// 分箱，本组件只负责把档位画成稳定的色阶。
class ReportHeatmap extends StatelessWidget {
  const ReportHeatmap({
    required this.levels,
    required this.columns,
    required this.semanticsLabel,
    this.cellLabel,
    this.accent,
    this.cellSize = 12,
    this.gap = 3,
    super.key,
  });

  final List<int> levels;
  final int columns;
  final String semanticsLabel;

  /// 逐格语义（`day-N：k 次复习`）——纯像素热图对屏幕阅读器是空的，
  /// 整图摘要之外必须给到逐日粒度。
  final String Function(int index, int level)? cellLabel;
  final Color? accent;
  final double cellSize;
  final double gap;

  @override
  Widget build(BuildContext context) {
    if (levels.isEmpty || columns <= 0) return const SizedBox.shrink();

    final accentColor = accent ?? TurnaTheme.brandTeal;
    final track = TurnaTheme.dividerBg(context);
    final rows = (levels.length / columns).ceil();

    return Semantics(
      label: semanticsLabel,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var r = 0; r < rows; r++)
            Padding(
              padding: EdgeInsets.only(bottom: r == rows - 1 ? 0 : gap),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var c = 0; c < columns; c++) ...[
                    if (c > 0) SizedBox(width: gap),
                    Builder(builder: (context) {
                      final index = r * columns + c;
                      final level =
                          index < levels.length ? levels[index] : 0;
                      final cell = Container(
                        width: cellSize,
                        height: cellSize,
                        decoration: BoxDecoration(
                          color: _cellColor(context, track, accentColor, level),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      );
                      final raw = cellLabel?.call(index, level);
                      final label =
                          raw == null || raw.isEmpty ? null : raw;
                      return label == null
                          ? cell
                          : Semantics(
                              // container：逐格成为独立语义节点，否则会被
                              // 合并进父级、逐日粒度丢失。
                              container: true,
                              label: label,
                              excludeSemantics: true,
                              child: cell,
                            );
                    }),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 档位 → 色值。0 = 轨道；1–4 走 [TurnaTheme.softTint] 阶梯（浅色罩白、
  /// 深色罩暗面，同一条主题感知混色）。
  Color _cellColor(
    BuildContext context,
    Color track,
    Color accent,
    int level,
  ) {
    if (level <= 0) return track;
    const alphas = [0.0, 0.18, 0.38, 0.62, 0.88];
    // 数据侧不保证截断，这里防御 0–4 之外的档位。
    final clamped = level.clamp(0, 4);
    return TurnaTheme.softTint(context, accent, alpha: alphas[clamped]);
  }
}

/// 一行定义（定义列表）。
class ReportDefinitionRow {
  const ReportDefinitionRow({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;
}

/// 定义列表：左标签右值的发丝线行组。
///
/// 报告尾部的「名词 → 数字」段（间隔均值、来源数、写入数……）。
class ReportDefinitionList extends StatelessWidget {
  const ReportDefinitionList({required this.rows, super.key});

  final List<ReportDefinitionRow> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0)
            Divider(height: 1, color: TurnaTheme.dividerBg(context)),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(child: Text(rows[i].label, style: AppTextStyles.captionSm(context))),
                Text(
                  rows[i].value,
                  style: AppTextStyles.cardTitle(context).copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: rows[i].valueColor,
                      ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

@Preview(name: 'Report kit · light', group: 'Wetland mist')
@Preview(
    name: 'Report kit · dark', group: 'Wetland mist', brightness: Brightness.dark)
Widget reportKitPreview() {
  return _ReportKitPreview();
}

class _ReportKitPreview extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.pageMargin),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ReportMetricHeader(
              label: '近 30 天复习',
              value: '412',
              unit: '张',
              caption: '比上一段多 18%',
            ),
            const SizedBox(height: AppSpacing.xl),
            const ReportBarChart(
              semanticsLabel: '每周复习量柱状图（示例）',
              bars: [
                ReportBar(label: '一', value: 40),
                ReportBar(label: '二', value: 68),
                ReportBar(label: '三', value: 52, highlight: true),
                ReportBar(label: '四', value: 90),
                ReportBar(label: '五', value: 34),
                ReportBar(label: '六', value: 12),
                ReportBar(label: '日', value: 26),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            const ReportLineChart(
              semanticsLabel: '记忆保持率折线（示例）',
              points: [
                ReportPoint(label: '10-28', value: 0.72),
                ReportPoint(label: '10-29', value: 0.81),
                ReportPoint(label: '10-30', value: 0.76),
                ReportPoint(label: '10-31', value: 0.88),
                ReportPoint(label: '11-01', value: 0.84),
                ReportPoint(label: '11-02', value: 0.93),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            const ReportCompositionBar(
              segments: [
                ReportSegment(label: '单词 · SRS', value: 12, color: TurnaTheme.brandTeal),
                ReportSegment(label: '语法', value: 5, color: TurnaTheme.brandSky),
                ReportSegment(label: '错题重练', value: 6, color: TurnaTheme.anatolianClay),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            const ReportHeatmap(
              semanticsLabel: '每日学习热图（示例）',
              columns: 10,
              levels: [
                0, 1, 2, 1, 0, 3, 2, 1, 0, 2,
                1, 3, 4, 2, 1, 0, 2, 3, 1, 4,
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            const ReportDefinitionList(
              rows: [
                ReportDefinitionRow(label: '平均间隔', value: '9.4 天'),
                ReportDefinitionRow(label: '主动来源', value: '3 个'),
                ReportDefinitionRow(label: '今日已写入', value: '21 条'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
