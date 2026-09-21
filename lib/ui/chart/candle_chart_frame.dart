import 'dart:math' as math;

import '../../models/trading_models.dart';
import 'candle_chart_viewport.dart';

class DisplayCandle {
  const DisplayCandle({
    required this.firstIndex,
    required this.lastIndex,
    required this.startTime,
    required this.endTime,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
  });

  final int firstIndex;
  final int lastIndex;
  final DateTime startTime;
  final DateTime endTime;
  final double open;
  final double high;
  final double low;
  final double close;

  bool get aggregated => firstIndex != lastIndex;
}

class ChartFrame {
  const ChartFrame({
    required this.transform,
    required this.candles,
    required this.latest,
  });

  final ChartTransform transform;
  final List<DisplayCandle> candles;
  final Candle latest;

  static ChartFrame? build({
    required List<Candle> source,
    required CandleViewport viewport,
    TradePlan? plan,
  }) {
    if (source.isEmpty || !viewport.canPaint) return null;
    final display = _aggregate(source, viewport);
    if (display.isEmpty) return null;

    var low = double.infinity;
    var high = double.negativeInfinity;
    for (final candle in display) {
      low = math.min(low, candle.low);
      high = math.max(high, candle.high);
    }
    void include(double? value) {
      if (value == null || !value.isFinite) return;
      low = math.min(low, value);
      high = math.max(high, value);
    }

    include(plan?.entryLow);
    include(plan?.entryHigh);
    if (plan?.isSetup == true) {
      include(plan?.stopLoss);
      for (final target in plan!.takeProfits) {
        include(target);
      }
    }
    final center = (high + low) / 2;
    final rawSpan = high - low;
    final minimumSpan = math.max(center.abs() * 0.0001, 1e-9);
    final span = math.max(rawSpan, minimumSpan);
    final padding = span * 0.06;
    low = center - span / 2 - padding;
    high = center + span / 2 + padding;
    if (!low.isFinite || !high.isFinite || high <= low) return null;

    return ChartFrame(
      transform: ChartTransform(viewport: viewport, low: low, high: high),
      candles: display,
      latest: source.last,
    );
  }

  /// Combines only candles sharing a horizontal pixel bucket, retaining OHLC.
  static List<DisplayCandle> _aggregate(
    List<Candle> source,
    CandleViewport viewport,
  ) {
    final result = <DisplayCandle>[];
    var index = viewport.start;
    while (index < viewport.end) {
      final first = source[index];
      final bucket = viewport.xForIndex(index).floor();
      var lastIndex = index;
      var high = first.high;
      var low = first.low;
      var close = first.close;
      while (lastIndex + 1 < viewport.end &&
          viewport.xForIndex(lastIndex + 1).floor() == bucket) {
        lastIndex++;
        final candle = source[lastIndex];
        high = math.max(high, candle.high);
        low = math.min(low, candle.low);
        close = candle.close;
      }
      result.add(
        DisplayCandle(
          firstIndex: index,
          lastIndex: lastIndex,
          startTime: first.time,
          endTime: source[lastIndex].time,
          open: first.open,
          high: high,
          low: low,
          close: close,
        ),
      );
      index = lastIndex + 1;
    }
    return result;
  }
}
