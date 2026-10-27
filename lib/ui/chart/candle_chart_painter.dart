import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart';

import '../../domain/models/candle.dart';
import '../../domain/models/trade_plan.dart';
import '../../utils/display_formatters.dart';
import 'candle_chart_colors.dart';
import 'candle_chart_frame.dart';
import 'candle_chart_viewport.dart';
import '../../l10n/app_languages.dart';

class MainCandlePainter extends CustomPainter {
  MainCandlePainter({required this.frame, required this.grid, super.repaint});

  final ChartFrame? Function() frame;
  final Color grid;
  final Paint _paint = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    final current = frame();
    if (current == null) return;
    final transform = current.transform;
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));
    _drawGrid(canvas, transform);
    _drawCandles(canvas, current);
    _drawTimeAxis(canvas, current);
    canvas.restore();
  }

  void _drawGrid(Canvas canvas, ChartTransform transform) {
    final chart = transform.viewport.chart;
    _paint
      ..color = grid.withAlpha(72)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    for (var index = 0; index <= 4; index++) {
      final value = transform.low + transform.range * index / 4;
      final y = transform.yForPrice(value);
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), _paint);
      _label(canvas, _price(value), Offset(chart.right + 6, y - 7), grid);
    }
  }

  void _drawCandles(Canvas canvas, ChartFrame frame) {
    final transform = frame.transform;
    final chart = transform.viewport.chart;
    canvas.save();
    canvas.clipRect(chart);
    final view = transform.viewport;
    // Bodies fill 80% of the slot like TradingView, so zooming in never opens wide gaps.
    final bodyWidth = math.max(1.0, view.candleSpacing * 0.8);
    for (var index = view.start; index < view.end; index++) {
      final candle = frame.candles[index];
      final x = transform.xForIndex(index);
      _paint
        ..color = candleColor(candle)
        ..strokeWidth = 1
        ..style = PaintingStyle.fill;
      canvas.drawLine(
        Offset(x, transform.yForPrice(candle.high)),
        Offset(x, transform.yForPrice(candle.low)),
        _paint,
      );
      final top = transform.yForPrice(math.max(candle.open, candle.close));
      final bottom = transform.yForPrice(math.min(candle.open, candle.close));
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(x, (top + bottom) / 2),
          width: bodyWidth,
          height: math.max(1, bottom - top),
        ),
        _paint,
      );
    }
    canvas.restore();
  }

  void _drawTimeAxis(Canvas canvas, ChartFrame frame) {
    final candles = frame.candles;
    final transform = frame.transform;
    final view = transform.viewport;
    final chart = view.chart;
    final daily = candles.length > 1 &&
        candles[1].time.difference(candles.first.time).inHours >= 23;
    _paint
      ..color = grid.withAlpha(110)
      ..strokeWidth = 1;
    for (var tick = 0; tick <= 4; tick++) {
      final index = view.start + (tick * (view.visibleCount - 1) / 4).round();
      final candle = candles[index];
      final x = transform.xForIndex(index);
      canvas.drawLine(
        Offset(x, chart.bottom),
        Offset(x, chart.bottom + 4),
        _paint,
      );
      final text = daily
          ? formatLocalDate(candle.time)
          : '${formatLocalDate(candle.time)} ${formatLocalTime(candle.time)}';
      final painter = _text(text, grid);
      final left = (x - painter.width / 2)
          .clamp(chart.left, math.max(chart.left, chart.right - painter.width))
          .toDouble();
      painter.paint(canvas, Offset(left, chart.bottom + 6));
    }
  }

  @override
  bool shouldRepaint(covariant MainCandlePainter oldDelegate) => true;
}

class PlanCandlePainter extends CustomPainter {
  PlanCandlePainter({
    required this.frame,
    required this.plan,
    super.repaint,
  });

  final ChartFrame? Function() frame;
  final TradePlan? Function() plan;
  final Paint _paint = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    final current = frame();
    if (current == null) return;
    final transform = current.transform;
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));
    _drawPlan(canvas, transform, plan());
    _drawCurrentPrice(canvas, transform, current.latest);
    canvas.restore();
  }

  void _drawCurrentPrice(Canvas canvas, ChartTransform transform, Candle latest) {
    final chart = transform.viewport.chart;
    final y = transform.yForPrice(latest.close);
    if (y < chart.top || y > chart.bottom) return;
    final color = candleColor(latest);
    _dashedLine(canvas, chart, y, color, 1);
    _label(canvas, _price(latest.close), Offset(chart.right + 6, y - 7), color);
  }

  void _drawPlan(Canvas canvas, ChartTransform transform, TradePlan? plan) {
    if (plan == null) return;
    final chart = transform.viewport.chart;
    final entryLow = plan.entryLow;
    final entryHigh = plan.entryHigh;
    final entryColor = chartEntryColor;
    final entryLabel = plan.decision == 'LONG_SETUP'
        ? appL10n.chartLong
        : plan.decision == 'SHORT_SETUP'
        ? appL10n.chartShort
        : appL10n.chartWaitZone;
    if (entryLow != null || entryHigh != null) {
      final lower = math.min(entryLow ?? entryHigh!, entryHigh ?? entryLow!);
      final upper = math.max(entryLow ?? entryHigh!, entryHigh ?? entryLow!);
      final zone = Rect.fromLTRB(
        chart.left,
        transform.yForPrice(upper),
        chart.right,
        transform.yForPrice(lower),
      );
      canvas.drawRect(
        zone,
        _paint
          ..color = entryColor.withAlpha(35)
          ..style = PaintingStyle.fill,
      );
      _level(canvas, transform, lower, entryColor, '${plan.isSetup ? appL10n.chartEntryLevel(entryLabel) : entryLabel} ${_price(lower)}');
      if (upper != lower) {
        _level(canvas, transform, upper, entryColor, '${plan.isSetup ? appL10n.chartEntryLevel(entryLabel) : entryLabel} ${_price(upper)}');
      }
    }
    if (!plan.isSetup) return;
    if (plan.stopLoss case final stop?) {
      _level(canvas, transform, stop, candleDownColor, 'SL ${_price(stop)}');
    }
    for (var index = 0; index < math.min(3, plan.takeProfits.length); index++) {
      final value = plan.takeProfits[index];
      _level(canvas, transform, value, candleUpColor, 'TP${index + 1} ${_price(value)}');
    }
  }

  void _level(Canvas canvas, ChartTransform transform, double value, Color color, String text) {
    final y = transform.yForPrice(value);
    _dashedLine(canvas, transform.viewport.chart, y, color, 1.4);
    _label(canvas, text, Offset(transform.viewport.chart.left + 5, y - 17), color);
  }

  // One path per line instead of one draw call per dash.
  void _dashedLine(Canvas canvas, Rect chart, double y, Color color, double width) {
    final path = Path();
    for (var x = chart.left; x < chart.right; x += 8) {
      path
        ..moveTo(x, y)
        ..lineTo(math.min(x + 4, chart.right), y);
    }
    canvas.drawPath(
      path,
      _paint
        ..color = color
        ..strokeWidth = width
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant PlanCandlePainter oldDelegate) => true;
}

class InteractionCandlePainter extends CustomPainter {
  InteractionCandlePainter({
    required this.frame,
    required this.pointer,
    required this.foreground,
    super.repaint,
  });

  final ChartFrame? Function() frame;
  final Offset? Function() pointer;
  final Color foreground;
  final Paint _paint = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    final current = frame();
    final position = pointer();
    if (current == null || position == null) return;
    final transform = current.transform;
    final chart = transform.viewport.chart;
    if (!chart.contains(position)) return;
    final index = transform.viewport.positionAtX(position.dx).round();
    if (index < transform.viewport.start || index >= transform.viewport.end) return;
    final hovered = current.candles[index];
    final x = transform.xForIndex(index);
    final y = position.dy.clamp(chart.top, chart.bottom).toDouble();
    final cursorPrice = transform.priceForY(y);
    _paint
      ..color = foreground.withAlpha(145)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(x, chart.top), Offset(x, chart.bottom), _paint);
    canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), _paint);
    final time = formatLocalDateTime(hovered.time);
    _tooltip(canvas, chart, TextSpan(
      style: const TextStyle(color: Colors.white, fontSize: 11),
      children: [
        TextSpan(text: '$time\n', style: const TextStyle(fontWeight: FontWeight.w700)),
        _valueSpan(appL10n.ohlcOpen, hovered.open, Colors.white),
        _valueSpan(appL10n.ohlcHigh, hovered.high, candleUpColor),
        const TextSpan(text: '\n'),
        _valueSpan(appL10n.ohlcLow, hovered.low, candleDownColor),
        _valueSpan(appL10n.ohlcClose, hovered.close, candleColor(hovered)),
        const TextSpan(text: '\n'),
        _valueSpan(appL10n.chartCursor, cursorPrice, Colors.white),
        _valueSpan(appL10n.chartLatest, current.latest.close, candleColor(current.latest)),
      ],
    ));
    _label(canvas, _price(cursorPrice), Offset(chart.right + 6, y - 7), foreground);
  }

  TextSpan _valueSpan(String label, double value, Color color) => TextSpan(
    text: '$label ${_price(value)}  ',
    style: TextStyle(color: color, fontWeight: FontWeight.w600),
  );

  void _tooltip(Canvas canvas, Rect chart, InlineSpan span) {
    const padding = 7.0;
    final painter = TextPainter(text: span, textDirection: TextDirection.ltr)..layout();
    final rect = Rect.fromLTWH(chart.left + 6, chart.top + 6, painter.width + padding * 2, painter.height + padding * 2);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4)), Paint()..color = const Color(0xE614171B));
    painter.paint(canvas, Offset(rect.left + padding, rect.top + padding));
  }

  @override
  bool shouldRepaint(covariant InteractionCandlePainter oldDelegate) => true;
}

TextPainter _text(String text, Color color) => TextPainter(
  text: TextSpan(text: text, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
  textDirection: TextDirection.ltr,
)..layout(maxWidth: 220);

void _label(Canvas canvas, String text, Offset offset, Color color) =>
    _text(text, color).paint(canvas, offset);

String _price(double value) {
  if (value >= 1000) return value.toStringAsFixed(1);
  if (value >= 1) return value.toStringAsFixed(3);
  return value.toStringAsFixed(5);
}
