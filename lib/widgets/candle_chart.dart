import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart';

import '../models/trading_models.dart';
import 'candle_chart_painter.dart';
import 'candle_chart_viewport.dart';

class CandleChart extends StatefulWidget {
  const CandleChart({
    super.key,
    required this.candles,
    this.plan,
    this.error,
    this.onRetry,
  });

  final List<Candle> candles;
  final TradePlan? plan;
  final String? error;
  final VoidCallback? onRetry;

  @override
  State<CandleChart> createState() => _CandleChartState();
}

class _CandleChartState extends State<CandleChart> {
  var _zoom = 3.0;
  var _pan = 0.0;
  Offset? _hoverPosition;
  Offset? _dragPosition;
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    final chart = widget.candles.isEmpty
        ? widget.error == null
              ? const Center(child: Text('正在加载 Bybit 永续合约 K 线…'))
              : const SizedBox.expand()
        : LayoutBuilder(
            builder: (context, constraints) {
              final size = constraints.biggest;
              return MouseRegion(
                cursor: _isDragging
                    ? SystemMouseCursors.grabbing
                    : SystemMouseCursors.grab,
                onExit: (_) => setState(() => _hoverPosition = null),
                onHover: (event) =>
                    setState(() => _hoverPosition = event.localPosition),
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerSignal: (event) {
                    if (event is PointerScrollEvent) _zoomAt(event, size);
                  },
                  onPointerDown: (event) {
                    if ((event.buttons & kPrimaryMouseButton) == 0) return;
                    setState(() {
                      _isDragging = true;
                      _dragPosition = event.localPosition;
                    });
                  },
                  onPointerMove: (event) => _drag(event, size),
                  onPointerUp: (_) => _stopDragging(),
                  onPointerCancel: (_) => _stopDragging(),
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: CandlePainter(
                        candles: widget.candles,
                        plan: widget.plan,
                        zoom: _zoom,
                        pan: _pan,
                        hoverPosition: _hoverPosition,
                      ),
                      size: Size.infinite,
                    ),
                  ),
                ),
              );
            },
          );
    return Stack(
      fit: StackFit.expand,
      children: [
        chart,
        if (widget.error case final error?)
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton(
                  onPressed: widget.onRetry,
                  child: const Text('重试'),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: 320,
                  child: Text(
                    error,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.errorPrimaryColor),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  void _zoomAt(PointerScrollEvent event, Size size) {
    final oldView = _viewFor(size);
    if (!oldView.canPaint) return;
    final horizontal =
        ((event.localPosition.dx - oldView.chart.left) / oldView.chart.width)
            .clamp(0.0, 1.0)
            .toDouble();
    final focusedIndex = oldView.start + horizontal * oldView.visibleCount;
    final zoom = (_zoom * (event.scrollDelta.dy < 0 ? 1.2 : 1 / 1.2))
        .clamp(1.0, 16.0)
        .toDouble();
    final newView = CandleViewport.from(size, widget.candles.length, zoom, 0);
    final desiredStart = focusedIndex - horizontal * newView.visibleCount;
    final pan = widget.candles.length - newView.visibleCount - desiredStart;
    setState(() {
      _zoom = zoom;
      _pan = pan.clamp(0.0, newView.maxPan).toDouble();
    });
  }

  void _drag(PointerMoveEvent event, Size size) {
    final previous = _dragPosition;
    if (!_isDragging || previous == null) return;
    final view = _viewFor(size);
    if (!view.canPaint) return;
    final movedCandles = (event.localPosition.dx - previous.dx) / view.step;
    setState(() {
      _pan = (_pan + movedCandles).clamp(0.0, view.maxPan).toDouble();
      _dragPosition = event.localPosition;
      _hoverPosition = event.localPosition;
    });
  }

  void _stopDragging() {
    if (!_isDragging) return;
    setState(() {
      _isDragging = false;
      _dragPosition = null;
    });
  }

  CandleViewport _viewFor(Size size) =>
      CandleViewport.from(size, widget.candles.length, _zoom, _pan);
}
