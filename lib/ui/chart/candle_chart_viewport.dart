import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart';

class CandleViewport {
  const CandleViewport({
    required this.chart,
    required this.start,
    required this.visibleCount,
    required this.maxPan,
  });

  factory CandleViewport.from(
    Size size,
    int candleCount,
    double zoom,
    double pan,
  ) {
    const left = 10.0;
    const right = 68.0;
    const top = 12.0;
    const bottom = 36.0;
    final chart = Rect.fromLTWH(
      left,
      top,
      math.max(0, size.width - left - right),
      math.max(0, size.height - top - bottom),
    );
    final countAtZoom = (candleCount / zoom).round();
    final minimumCount = countAtZoom < 8 ? 8 : countAtZoom;
    var visibleCount = minimumCount > candleCount ? candleCount : minimumCount;
    // Performance guard for unlimited history: cap visible to screen width.
    if (chart.width > 0 && visibleCount > chart.width) {
      final maxForWidth = (chart.width / 1.2).ceil().clamp(200, 5000);
      if (visibleCount > maxForWidth) visibleCount = maxForWidth;
    }
    final maxPan = (candleCount - visibleCount).toDouble();
    final safePan = pan.clamp(0.0, maxPan).toDouble();
    final start = (candleCount - visibleCount - safePan.round())
        .clamp(0, candleCount - visibleCount)
        .toInt();
    return CandleViewport(
      chart: chart,
      start: start,
      visibleCount: visibleCount,
      maxPan: maxPan,
    );
  }

  final Rect chart;
  final int start;
  final int visibleCount;
  final double maxPan;

  bool get canPaint => chart.width > 0 && chart.height > 0;
  double get step => chart.width / visibleCount;
}
