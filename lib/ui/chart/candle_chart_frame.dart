import 'dart:math' as math;

import '../../domain/models/candle.dart';
import '../../domain/models/trade_plan.dart';
import 'candle_chart_viewport.dart';

class ChartFrame {
  const ChartFrame({required this.transform, required this.candles});

  final ChartTransform transform;
  // The full series; painters draw only the viewport's index range.
  final List<Candle> candles;

  Candle get latest => candles.last;

  static ChartFrame? build({
    required List<Candle> source,
    required CandleViewport viewport,
    TradePlan? plan,
  }) {
    if (source.isEmpty || !viewport.canPaint) return null;
    var low = double.infinity;
    var high = double.negativeInfinity;
    for (var index = viewport.start; index < viewport.end; index++) {
      low = math.min(low, source[index].low);
      high = math.max(high, source[index].high);
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
      for (final target in plan!.takeProfits.take(3)) {
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
      candles: source,
    );
  }
}
