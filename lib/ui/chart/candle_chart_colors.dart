import 'package:fluent_ui/fluent_ui.dart';

import '../../models/trading_models.dart';

/// Shared colors for the price direction shown by the chart and dashboard.
const candleUpColor = Color(0xFF27A376);
const candleDownColor = Color(0xFFD94C5D);

// Keep entry zones and their legend on the same directional-neutral color.
final chartEntryColor = Colors.blue;

// Match the latest dashboard price to the candle direction shown on the chart.
Color candleColor(Candle candle) {
  if (candle.close >= candle.open) return candleUpColor;
  return candleDownColor;
}
