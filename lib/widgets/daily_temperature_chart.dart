import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

import '../services/station_temperature_api.dart';

/// Daily hourly temperature chart (observed + forecast) with a "now" line.
class DailyTemperatureChart extends StatelessWidget {
  const DailyTemperatureChart({
    super.key,
    required this.series,
    this.height = 180,
  });

  final DailyTemperatureSeries series;
  final double height;

  @override
  Widget build(BuildContext context) {
    final points = series.points;
    if (points.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: Text(
          'No hourly temperature data',
          style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
        ),
      );
    }

    final unitSuffix = series.unit == 'F' ? '°F' : '°C';
    final dayMs = series.dayStart.millisecondsSinceEpoch.toDouble();
    final dayEndMs = series.dayEnd.millisecondsSinceEpoch.toDouble();
    final nowMs = series.nowLocal.millisecondsSinceEpoch.toDouble().clamp(
          dayMs,
          dayEndMs,
        );

    final spots = <FlSpot>[
      for (final p in points)
        FlSpot(
          p.localHourStart.millisecondsSinceEpoch.toDouble(),
          p.temperature,
        ),
    ];

    var minY = points.first.temperature;
    var maxY = points.first.temperature;
    for (final p in points) {
      if (p.temperature < minY) minY = p.temperature;
      if (p.temperature > maxY) maxY = p.temperature;
    }
    final pad = ((maxY - minY).abs() * 0.15).clamp(1.0, 8.0);
    minY = (minY - pad).floorToDouble();
    maxY = (maxY + pad).ceilToDouble();
    if (maxY <= minY) maxY = minY + 2;

    final hourFmt = DateFormat('HH:mm');
    final dayFmt = DateFormat('MMM d');

    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 12, 4),
        child: LineChart(
          LineChartData(
            minX: dayMs,
            maxX: dayEndMs,
            minY: minY,
            maxY: maxY,
            clipData: const FlClipData.all(),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: true,
              horizontalInterval: _niceInterval(maxY - minY),
              getDrawingHorizontalLine: (v) => FlLine(
                color: Colors.grey.shade300,
                strokeWidth: 1,
              ),
              getDrawingVerticalLine: (v) => FlLine(
                color: Colors.grey.shade200,
                strokeWidth: 1,
              ),
            ),
            borderData: FlBorderData(
              show: true,
              border: Border.all(color: Colors.grey.shade400, width: 1),
            ),
            extraLinesData: ExtraLinesData(
              verticalLines: [
                if (nowMs > dayMs && nowMs < dayEndMs)
                  VerticalLine(
                    x: nowMs,
                    color: Colors.grey.shade600,
                    strokeWidth: 1.5,
                    dashArray: const [5, 4],
                    label: VerticalLineLabel(
                      show: true,
                      alignment: Alignment.topRight,
                      padding: const EdgeInsets.only(left: 4, top: 2),
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                      labelResolver: (_) => 'now',
                    ),
                  ),
              ],
            ),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 36,
                  interval: _niceInterval(maxY - minY),
                  getTitlesWidget: (value, meta) {
                    if (value == meta.min || value == meta.max) {
                      return const SizedBox.shrink();
                    }
                    return Text(
                      '${value.toStringAsFixed(0)}$unitSuffix',
                      style: TextStyle(
                        fontSize: 9,
                        color: Colors.grey.shade700,
                      ),
                    );
                  },
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 22,
                  interval: const Duration(hours: 3).inMilliseconds.toDouble(),
                  getTitlesWidget: (value, meta) {
                    final local = tz.TZDateTime.fromMillisecondsSinceEpoch(
                      series.dayStart.location,
                      value.round(),
                    );
                    final label = local.hour == 0 &&
                            local.millisecondsSinceEpoch !=
                                series.dayStart.millisecondsSinceEpoch
                        ? dayFmt.format(local)
                        : hourFmt.format(local);
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 9,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            lineTouchData: LineTouchData(
              enabled: true,
              touchTooltipData: LineTouchTooltipData(
                getTooltipItems: (touched) {
                  return touched.map((spot) {
                    final local = tz.TZDateTime.fromMillisecondsSinceEpoch(
                      series.dayStart.location,
                      spot.x.round(),
                    );
                    return LineTooltipItem(
                      '${hourFmt.format(local)}\n'
                      '${spot.y.toStringAsFixed(1)}$unitSuffix',
                      const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  }).toList();
                },
              ),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: false,
                color: const Color(0xFFDC2626),
                barWidth: 2,
                isStrokeCapRound: true,
                dotData: FlDotData(
                  show: true,
                  getDotPainter: (spot, percent, bar, index) {
                    final kind = points[index].kind;
                    final filled = kind == TempPointKind.observed;
                    return FlDotCirclePainter(
                      radius: 2.5,
                      color: filled
                          ? const Color(0xFFDC2626)
                          : Colors.white,
                      strokeWidth: 1.5,
                      strokeColor: const Color(0xFFDC2626),
                    );
                  },
                ),
                belowBarData: BarAreaData(show: false),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static double _niceInterval(double range) {
    if (range <= 4) return 1;
    if (range <= 10) return 2;
    if (range <= 20) return 5;
    return 10;
  }
}
