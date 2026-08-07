import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart';

import '../models/trading_models.dart';

class CandleChart extends StatelessWidget {
  const CandleChart({super.key, required this.candles, this.plan});

  final List<Candle> candles;
  final TradePlan? plan;

  @override
  Widget build(BuildContext context) {
    if (candles.isEmpty) {
      return const Center(child: Text('点击刷新以加载 Bybit 永续合约 K 线'));
    }
    // Keep the drawing self-contained so price markers stay aligned to candles.
    return RepaintBoundary(
      child: CustomPaint(
        painter: _CandlePainter(candles, plan),
        size: Size.infinite,
      ),
    );
  }
}

class _CandlePainter extends CustomPainter {
  _CandlePainter(this.candles, this.plan);

  final List<Candle> candles;
  final TradePlan? plan;
  static const _up = Color(0xFF27A376);
  static const _down = Color(0xFFD94C5D);
  static const _grid = Color(0xFFBBC3CC);

  @override
  void paint(Canvas canvas, Size size) {
    const left = 10.0;
    const right = 68.0;
    const top = 12.0;
    const bottom = 22.0;
    final chart = Rect.fromLTWH(
      left,
      top,
      size.width - left - right,
      size.height - top - bottom,
    );
    if (chart.width <= 0 || chart.height <= 0) return;
    final prices = <double>[
      ...candles.map((candle) => candle.low),
      ...candles.map((candle) => candle.high),
      if (plan?.entryLow != null) plan!.entryLow!,
      if (plan?.entryHigh != null) plan!.entryHigh!,
      if (plan?.stopLoss != null) plan!.stopLoss!,
      ...?plan?.takeProfits,
    ];
    var low = prices.reduce(math.min);
    var high = prices.reduce(math.max);
    final padding = (high - low) * 0.06;
    low -= padding == 0 ? high.abs() * 0.01 : padding;
    high += padding == 0 ? high.abs() * 0.01 : padding;
    final range = high - low;
    double yOf(double value) =>
        chart.bottom - (value - low) / range * chart.height;

    // Faint grid lines provide the price reference for a compact desktop chart.
    final gridPaint = Paint()
      ..color = _grid.withAlpha(72)
      ..strokeWidth = 1;
    for (var index = 0; index <= 4; index++) {
      final value = low + range * index / 4;
      final y = yOf(value);
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), gridPaint);
      _label(canvas, _price(value), Offset(chart.right + 6, y - 7), _grid);
    }

    _drawPlan(canvas, chart, yOf);
    final step = chart.width / candles.length;
    final bodyWidth = math.max(2.0, step * 0.62);
    for (var index = 0; index < candles.length; index++) {
      final candle = candles[index];
      final x = chart.left + step * (index + 0.5);
      final color = candle.close >= candle.open ? _up : _down;
      final paint = Paint()..color = color;
      canvas.drawLine(
        Offset(x, yOf(candle.high)),
        Offset(x, yOf(candle.low)),
        paint,
      );
      final bodyTop = yOf(math.max(candle.open, candle.close));
      final bodyBottom = yOf(math.min(candle.open, candle.close));
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(x, (bodyTop + bodyBottom) / 2),
          width: bodyWidth,
          height: math.max(1, bodyBottom - bodyTop),
        ),
        paint,
      );
    }
  }

  void _drawPlan(Canvas canvas, Rect chart, double Function(double) yOf) {
    if (plan == null) return;
    final entryLow = plan!.entryLow;
    final entryHigh = plan!.entryHigh;
    if (entryLow != null && entryHigh != null) {
      final zone = Rect.fromLTRB(
        chart.left,
        yOf(entryHigh),
        chart.right,
        yOf(entryLow),
      );
      canvas.drawRect(zone, Paint()..color = Colors.blue.withAlpha(35));
      _level(
        canvas,
        chart,
        yOf(entryLow),
        Colors.blue,
        'Entry ${_price(entryLow)}',
      );
      _level(
        canvas,
        chart,
        yOf(entryHigh),
        Colors.blue,
        'Entry ${_price(entryHigh)}',
      );
    }
    if (plan!.stopLoss case final stop?) {
      _level(canvas, chart, yOf(stop), _down, 'SL ${_price(stop)}');
    }
    for (var index = 0; index < plan!.takeProfits.length; index++) {
      final price = plan!.takeProfits[index];
      _level(canvas, chart, yOf(price), _up, 'TP${index + 1} ${_price(price)}');
    }
  }

  void _level(Canvas canvas, Rect chart, double y, Color color, String label) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.4;
    for (var x = chart.left; x < chart.right; x += 8) {
      canvas.drawLine(
        Offset(x, y),
        Offset(math.min(x + 4, chart.right), y),
        paint,
      );
    }
    _label(canvas, label, Offset(chart.left + 5, y - 17), color);
  }

  void _label(Canvas canvas, String text, Offset offset, Color color) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 110);
    painter.paint(canvas, offset);
  }

  String _price(double value) {
    if (value >= 1000) return value.toStringAsFixed(1);
    if (value >= 1) return value.toStringAsFixed(3);
    return value.toStringAsFixed(5);
  }

  @override
  bool shouldRepaint(covariant _CandlePainter oldDelegate) =>
      oldDelegate.candles != candles || oldDelegate.plan != plan;
}
