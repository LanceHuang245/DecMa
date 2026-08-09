import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart';

import '../../models/trading_models.dart';
import '../../utils/display_formatters.dart';
import 'candle_chart_colors.dart';
import 'candle_chart_viewport.dart';

class CandlePainter extends CustomPainter {
  const CandlePainter({
    required this.candles,
    required this.plan,
    required this.zoom,
    required this.pan,
    required this.hoverPosition,
  });

  final List<Candle> candles;
  final TradePlan? plan;
  final double zoom;
  final double pan;
  final Offset? hoverPosition;
  static const _grid = Color(0xFFBBC3CC);

  @override
  void paint(Canvas canvas, Size size) {
    final view = CandleViewport.from(size, candles.length, zoom, pan);
    if (!view.canPaint) return;
    final visible = candles.sublist(view.start, view.start + view.visibleCount);
    final prices = <double>[
      ...visible.map((candle) => candle.low),
      ...visible.map((candle) => candle.high),
      if (plan?.entryLow != null) plan!.entryLow!,
      if (plan?.entryHigh != null) plan!.entryHigh!,
      if (plan?.isSetup == true && plan?.stopLoss != null) plan!.stopLoss!,
      if (plan?.isSetup == true) ...?plan?.takeProfits,
    ];
    var low = prices.reduce(math.min);
    var high = prices.reduce(math.max);
    final padding = (high - low) * 0.06;
    low -= padding == 0 ? high.abs() * 0.01 : padding;
    high += padding == 0 ? high.abs() * 0.01 : padding;
    final range = high - low;
    double yOf(double value) =>
        view.chart.bottom - (value - low) / range * view.chart.height;

    _drawGrid(canvas, view.chart, low, range, yOf);
    _drawPlan(canvas, view.chart, yOf);
    _drawCandles(canvas, view, yOf);
    _drawTimeAxis(canvas, view, visible);
    _drawCurrentPrice(
      canvas,
      view.chart,
      yOf(candles.last.close),
      candles.last,
    );
    _drawHover(canvas, view, low, range);
  }

  void _drawGrid(
    Canvas canvas,
    Rect chart,
    double low,
    double range,
    double Function(double) yOf,
  ) {
    final paint = Paint()
      ..color = _grid.withAlpha(72)
      ..strokeWidth = 1;
    for (var index = 0; index <= 4; index++) {
      final value = low + range * index / 4;
      final y = yOf(value);
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), paint);
      _label(canvas, _price(value), Offset(chart.right + 6, y - 7), _grid);
    }
  }

  void _drawCandles(
    Canvas canvas,
    CandleViewport view,
    double Function(double) yOf,
  ) {
    final bodyWidth = math.max(2.0, view.step * 0.62);
    for (
      var visibleIndex = 0;
      visibleIndex < view.visibleCount;
      visibleIndex++
    ) {
      final candle = candles[view.start + visibleIndex];
      final x = view.chart.left + view.step * (visibleIndex + 0.5);
      final color = candleColor(candle);
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

  // Show evenly spaced time labels for the current pan and zoom window.
  void _drawTimeAxis(Canvas canvas, CandleViewport view, List<Candle> visible) {
    final daily =
        visible.length > 1 &&
        visible[1].time.difference(visible.first.time).inHours >= 23;
    final tickPaint = Paint()
      ..color = _grid.withAlpha(110)
      ..strokeWidth = 1;
    for (var tick = 0; tick <= 4; tick++) {
      final index = (tick * (visible.length - 1) / 4).round();
      final x = view.chart.left + view.step * (index + 0.5);
      canvas.drawLine(
        Offset(x, view.chart.bottom),
        Offset(x, view.chart.bottom + 4),
        tickPaint,
      );
      final painter = TextPainter(
        text: TextSpan(
          text: _axisTime(visible[index].time, daily),
          style: const TextStyle(
            color: _grid,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final left = (x - painter.width / 2)
          .clamp(
            view.chart.left,
            math.max(view.chart.left, view.chart.right - painter.width),
          )
          .toDouble();
      painter.paint(canvas, Offset(left, view.chart.bottom + 6));
    }
  }

  void _drawCurrentPrice(Canvas canvas, Rect chart, double y, Candle latest) {
    if (y < chart.top || y > chart.bottom) return;
    final color = candleColor(latest);
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var x = chart.left; x < chart.right; x += 7) {
      canvas.drawLine(
        Offset(x, y),
        Offset(math.min(x + 3, chart.right), y),
        paint,
      );
    }
    _label(canvas, _price(latest.close), Offset(chart.right + 6, y - 7), color);
  }

  // Draw crosshairs and the hovered candle's OHLC values for desktop inspection.
  void _drawHover(
    Canvas canvas,
    CandleViewport view,
    double low,
    double range,
  ) {
    final pointer = hoverPosition;
    if (pointer == null || !view.chart.contains(pointer)) return;
    final visibleIndex = ((pointer.dx - view.chart.left) / view.step)
        .floor()
        .clamp(0, view.visibleCount - 1);
    final candle = candles[view.start + visibleIndex];
    final x = view.chart.left + view.step * (visibleIndex + 0.5);
    final y = pointer.dy.clamp(view.chart.top, view.chart.bottom).toDouble();
    final cursorPrice =
        low + (view.chart.bottom - y) / view.chart.height * range;
    final paint = Paint()
      ..color = Colors.white.withAlpha(145)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(x, view.chart.top),
      Offset(x, view.chart.bottom),
      paint,
    );
    canvas.drawLine(
      Offset(view.chart.left, y),
      Offset(view.chart.right, y),
      paint,
    );

    final candlePriceColor = candleColor(candle);
    final latest = candles.last;
    final latestColor = candleColor(latest);
    _tooltip(
      canvas,
      TextSpan(
        style: const TextStyle(color: Colors.white, fontSize: 11),
        children: [
          TextSpan(
            text: '${_fullTime(candle.time)}\n',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          _valueSpan('开', candle.open, Colors.white),
          _valueSpan('高', candle.high, candleUpColor),
          const TextSpan(text: '\n'),
          _valueSpan('低', candle.low, candleDownColor),
          _valueSpan('收', candle.close, candlePriceColor),
          const TextSpan(text: '\n'),
          _valueSpan('鼠标', cursorPrice, Colors.white),
          _valueSpan('最新', latest.close, latestColor),
        ],
      ),
      view.chart,
    );
    _label(
      canvas,
      _price(cursorPrice),
      Offset(view.chart.right + 6, y - 7),
      Colors.white,
    );
  }

  void _drawPlan(Canvas canvas, Rect chart, double Function(double) yOf) {
    if (plan == null) return;
    final entryLow = plan!.entryLow;
    final entryHigh = plan!.entryHigh;
    final entryColor = plan!.decision == 'LONG_SETUP'
        ? candleUpColor
        : plan!.decision == 'SHORT_SETUP'
        ? candleDownColor
        : Colors.blue;
    final entryLabel = plan!.decision == 'LONG_SETUP'
        ? '做多'
        : plan!.decision == 'SHORT_SETUP'
        ? '做空'
        : '等待区';
    if (entryLow != null || entryHigh != null) {
      final lower = math.min(entryLow ?? entryHigh!, entryHigh ?? entryLow!);
      final upper = math.max(entryLow ?? entryHigh!, entryHigh ?? entryLow!);
      final zone = Rect.fromLTRB(
        chart.left,
        yOf(upper),
        chart.right,
        yOf(lower),
      );
      canvas.drawRect(zone, Paint()..color = entryColor.withAlpha(35));
      _level(
        canvas,
        chart,
        yOf(lower),
        entryColor,
        '${plan!.isSetup ? '$entryLabel 开仓' : entryLabel} ${_price(lower)}',
      );
      if (upper != lower) {
        _level(
          canvas,
          chart,
          yOf(upper),
          entryColor,
          '${plan!.isSetup ? '$entryLabel 开仓' : entryLabel} ${_price(upper)}',
        );
      }
    }
    if (!plan!.isSetup) return;
    if (plan!.stopLoss case final stop?) {
      _level(canvas, chart, yOf(stop), candleDownColor, 'SL ${_price(stop)}');
    }
    for (var index = 0; index < plan!.takeProfits.length; index++) {
      final price = plan!.takeProfits[index];
      _level(
        canvas,
        chart,
        yOf(price),
        candleUpColor,
        'TP${index + 1} ${_price(price)}',
      );
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

  TextSpan _valueSpan(String label, double value, Color color) => TextSpan(
    text: '$label ${_price(value)}  ',
    style: TextStyle(color: color, fontWeight: FontWeight.w600),
  );

  void _tooltip(Canvas canvas, InlineSpan text, Rect chart) {
    const padding = 7.0;
    final textPainter = TextPainter(
      text: text,
      textDirection: TextDirection.ltr,
    )..layout();
    final rect = Rect.fromLTWH(
      chart.left + 6,
      chart.top + 6,
      textPainter.width + padding * 2,
      textPainter.height + padding * 2,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      Paint()..color = const Color(0xE614171B),
    );
    textPainter.paint(canvas, Offset(rect.left + padding, rect.top + padding));
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

  String _axisTime(DateTime time, bool daily) {
    return daily
        ? formatLocalDate(time)
        : '${formatLocalDate(time)} ${formatLocalTime(time)}';
  }

  String _fullTime(DateTime time) => formatLocalDateTime(time);

  @override
  bool shouldRepaint(covariant CandlePainter oldDelegate) =>
      oldDelegate.candles != candles ||
      oldDelegate.plan != plan ||
      oldDelegate.zoom != zoom ||
      oldDelegate.pan != pan ||
      oldDelegate.hoverPosition != hoverPosition;
}
