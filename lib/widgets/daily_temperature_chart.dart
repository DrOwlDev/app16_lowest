import 'dart:math' as math;

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
    const lineColor = Color(0xFF111827);
    const minColor = Color(0xFF2563EB);
    const minStroke = Color(0xFF1D4ED8);
    const maxColor = Color(0xFFEA580C);
    const maxStroke = Color(0xFFC2410C);
    const nowColor = Color(0xFFDC2626);
    double? dailyMinTemp;
    double? dailyMaxTemp;
    for (final p in points) {
      if (p.isDailyMinimum) dailyMinTemp ??= p.temperature;
      if (p.isDailyMaximum) dailyMaxTemp ??= p.temperature;
    }

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
            // Avoid clipping the next-day 00:00 endpoint / extreme stars at the right edge.
            clipData: const FlClipData.none(),
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
              horizontalLines: [
                if (dailyMinTemp != null)
                  HorizontalLine(
                    y: dailyMinTemp,
                    color: minColor,
                    strokeWidth: 1.5,
                    dashArray: const [6, 4],
                    label: HorizontalLineLabel(
                      show: true,
                      alignment: Alignment.topLeft,
                      padding: const EdgeInsets.only(left: 4, bottom: 2),
                      style: const TextStyle(
                        fontSize: 10,
                        color: minStroke,
                        fontWeight: FontWeight.w600,
                      ),
                      labelResolver: (line) =>
                          'min ${line.y.toStringAsFixed(0)}$unitSuffix',
                    ),
                  ),
                if (dailyMaxTemp != null)
                  HorizontalLine(
                    y: dailyMaxTemp,
                    color: maxColor,
                    strokeWidth: 1.5,
                    dashArray: const [6, 4],
                    label: HorizontalLineLabel(
                      show: true,
                      alignment: Alignment.topLeft,
                      padding: const EdgeInsets.only(left: 4, bottom: 2),
                      style: const TextStyle(
                        fontSize: 10,
                        color: maxStroke,
                        fontWeight: FontWeight.w600,
                      ),
                      labelResolver: (line) =>
                          'max ${line.y.toStringAsFixed(0)}$unitSuffix',
                    ),
                  ),
              ],
              verticalLines: [
                if (nowMs > dayMs && nowMs < dayEndMs)
                  VerticalLine(
                    x: nowMs,
                    color: nowColor,
                    strokeWidth: 1.5,
                    dashArray: const [5, 4],
                    label: VerticalLineLabel(
                      show: true,
                      alignment: Alignment.topRight,
                      padding: const EdgeInsets.only(left: 4, top: 2),
                      style: const TextStyle(
                        fontSize: 10,
                        color: nowColor,
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
                    HourlyTempPoint? point;
                    for (final p in points) {
                      if (p.localHourStart.millisecondsSinceEpoch ==
                          spot.x.round()) {
                        point = p;
                        break;
                      }
                    }
                    final tags = <String>[
                      if (point?.isDailyMinimum == true) 'min',
                      if (point?.isDailyMaximum == true) 'max',
                    ];
                    final tagSuffix =
                        tags.isEmpty ? '' : ' · ${tags.join('/')}';
                    return LineTooltipItem(
                      '${hourFmt.format(local)}\n'
                      '${spot.y.toStringAsFixed(1)}$unitSuffix$tagSuffix',
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
                color: lineColor,
                barWidth: 2,
                isStrokeCapRound: true,
                dotData: FlDotData(
                  show: true,
                  getDotPainter: (spot, percent, bar, index) {
                    final point = points[index];
                    if (point.isDailyMaximum) {
                      return const _FlDotStarPainter(
                        color: maxColor,
                        strokeColor: maxStroke,
                        size: 12,
                      );
                    }
                    if (point.isDailyMinimum) {
                      return const _FlDotStarPainter(
                        color: minColor,
                        strokeColor: minStroke,
                        size: 12,
                      );
                    }
                    final filled = point.kind == TempPointKind.observed;
                    return FlDotCirclePainter(
                      radius: 2.5,
                      color: filled ? lineColor : Colors.white,
                      strokeWidth: 1.5,
                      strokeColor: lineColor,
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

/// Star marker for daily min/max temperature hours.
class _FlDotStarPainter extends FlDotPainter {
  const _FlDotStarPainter({
    required this.color,
    required this.strokeColor,
    required this.size,
  });

  final Color color;
  final Color strokeColor;
  final double size;

  @override
  void draw(Canvas canvas, FlSpot spot, Offset offsetInCanvas) {
    final path = _starPath(offsetInCanvas, size / 2);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = strokeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  static Path _starPath(Offset center, double radius) {
    const points = 5;
    final path = Path();
    final inner = radius * 0.45;
    for (var i = 0; i < points * 2; i++) {
      final r = i.isEven ? radius : inner;
      final angle = -math.pi / 2 + (i * math.pi / points);
      final x = center.dx + r * math.cos(angle);
      final y = center.dy + r * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    return path;
  }

  @override
  Size getSize(FlSpot spot) => Size(size, size);

  @override
  Color get mainColor => color;

  @override
  List<Object?> get props => [color, strokeColor, size];

  @override
  FlDotPainter lerp(FlDotPainter a, FlDotPainter b, double t) => this;
}
