// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:fl_chart/fl_chart.dart';

// Project imports:
import 'package:turna/application/memory_curve_provider.dart';
import 'package:turna/views/theme.dart';

/// Shared retention-vs-interval line chart (Profile + Review Progress).
class RetentionCurveChart extends StatelessWidget {
  final List<RetentionPoint> curve;
  final double height;

  const RetentionCurveChart({
    super.key,
    required this.curve,
    this.height = 140,
  });

  @override
  Widget build(BuildContext context) {
    if (curve.isEmpty) {
      return SizedBox(height: height);
    }
    final spots = [
      for (var i = 0; i < curve.length; i++)
        FlSpot(i.toDouble(), curve[i].retention),
    ];
    final lineColor = TurnaTheme.peacockTeal;
    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: 1,
          minX: 0,
          maxX: (curve.length - 1).toDouble(),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 0.25,
            getDrawingHorizontalLine: (v) => FlLine(
              color: TurnaTheme.dividerBg(context),
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 0.25,
                reservedSize: 30,
                getTitlesWidget: (v, _) => Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(
                    '${(v * 100).round()}%',
                    style: TextStyle(
                      fontSize: 10,
                      color: TurnaTheme.textHintColor(context),
                    ),
                  ),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                interval: 1,
                getTitlesWidget: (i, _) {
                  final idx = i.toInt();
                  if (idx < 0 || idx >= curve.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${curve[idx].intervalBucketDays}d',
                      style: TextStyle(
                        fontSize: 10,
                        color: TurnaTheme.textHintColor(context),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: lineColor,
              barWidth: 3,
              dotData: FlDotData(show: curve.length <= 6),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  colors: [
                    lineColor.withValues(alpha: 0.12),
                    lineColor.withValues(alpha: 0.02),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ],
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (touchedSpots) {
                return [
                  for (final s in touchedSpots)
                    if (s.spotIndex >= 0 && s.spotIndex < curve.length)
                      LineTooltipItem(
                        '${curve[s.spotIndex].intervalBucketDays}d · '
                        '${(curve[s.spotIndex].retention * 100).round()}%\n'
                        'n=${curve[s.spotIndex].sampleSize}',
                        TextStyle(
                          color: TurnaTheme.textOnPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                ];
              },
            ),
          ),
        ),
      ),
    );
  }
}
