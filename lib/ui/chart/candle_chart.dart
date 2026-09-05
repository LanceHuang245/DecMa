import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart';

import '../../models/trading_models.dart';
import '../../utils/display_formatters.dart';
import 'candle_chart_painter.dart';
import 'candle_chart_viewport.dart';

class CandleChart extends StatefulWidget {
  const CandleChart({
    super.key,
    required this.candles,
    this.plan,
    this.showWaitZone = false,
    this.error,
    this.loading = false,
    this.onRetry,
    this.onLoadMore,
    this.loadingMore = false,
  });

  final List<Candle> candles;
  final TradePlan? plan;
  final bool showWaitZone;
  final String? error;
  final bool loading;
  final VoidCallback? onRetry;
  final Future<void> Function()? onLoadMore;
  final bool loadingMore;

  @override
  State<CandleChart> createState() => _CandleChartState();
}

class _CandleChartState extends State<CandleChart> {
  var _zoom = 3.0;
  var _pan = 0.0;
  Offset? _hoverPosition;
  Offset? _dragPosition;
  bool _isDragging = false;
  bool _wasAtLeftEdge = false;

  @override
  void didUpdateWidget(covariant CandleChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Do not forcibly adjust focus while the user is dragging;
    // new history will appear on the next left-drag after load completes.
    // This avoids the viewport being pulled away during an active drag.
    if (oldWidget.candles.length != widget.candles.length &&
        widget.candles.length > oldWidget.candles.length &&
        _wasAtLeftEdge &&
        !_isDragging) {
      // Keep the view near the left edge after load, but without forcing
      // during an active drag. Use a post-frame clamp to avoid jump.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _pan = 1e9;
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final chart = widget.candles.isEmpty
        ? const SizedBox.expand()
        : LayoutBuilder(
            builder: (context, constraints) {
              final size = constraints.biggest;
              // Track whether the current viewport is at the left edge for the next didUpdateWidget.
              final viewForFlag = _viewFor(size);
              _wasAtLeftEdge = viewForFlag.start == 0 && viewForFlag.maxPan > 0;
              // Also consider fully zoomed-out state as at edge.
              if (widget.candles.length <= viewForFlag.visibleCount) {
                _wasAtLeftEdge = true;
              }
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
                        // WAIT may draw only a validated candidate zone.
                        plan:
                            widget.plan?.isSetup == true || widget.showWaitZone
                            ? widget.plan
                            : null,
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
        if (widget.plan case final plan?) _buildPlanOverlay(plan),
        if (widget.loading || (widget.candles.isEmpty && widget.error == null))
          const ColoredBox(
            color: Color(0xE6171A1F),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ProgressRing(),
                  SizedBox(height: 10),
                  Text('正在加载 Bybit 永续合约 K 线…'),
                ],
              ),
            ),
          ),
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
        if (widget.loadingMore)
          const Positioned(
            right: 80,
            bottom: 46,
            child: Card(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: ProgressRing(strokeWidth: 2),
                  ),
                  SizedBox(width: 6),
                  Text('加载更早历史…', style: TextStyle(fontSize: 11)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPlanOverlay(TradePlan plan) {
    final color = plan.decision == 'LONG_SETUP'
        ? Colors.green
        : plan.decision == 'SHORT_SETUP'
        ? Colors.red
        : Colors.warningPrimaryColor;
    return Positioned(
      right: 76,
      top: 18,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        // The overlay only consumes pointer events inside its own small card.
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _showPlanDetails(plan),
          child: Card(
            padding: const EdgeInsets.all(8),
            backgroundColor: FluentTheme.of(
              context,
            ).resources.layerFillColorDefault,
            child: SizedBox(
              width: 210,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _decisionLabel(plan.decision),
                    style: TextStyle(color: color, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '开仓区：${plan.isSetup || widget.showWaitZone ? _entryRange(plan) : '-'}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  Text(
                    '止损：${plan.isSetup ? _price(plan.stopLoss) : '-'}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  Text(
                    '止盈：${plan.isSetup ? (plan.takeProfits.isEmpty ? '未提供' : plan.takeProfits.map(_price).join(' / ')) : '-'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '点击查看完整 JSON 解析',
                    style: TextStyle(
                      fontSize: 11,
                      color: FluentTheme.of(
                        context,
                      ).resources.textFillColorSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showPlanDetails(TradePlan plan) {
    showDialog<void>(
      context: context,
      builder: (context) => ContentDialog(
        title: Text('${_decisionLabel(plan.decision)}：JSON 解析结果'),
        content: SizedBox(
          width: 680,
          height: 520,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (plan.summary.isNotEmpty) ...[
                Text(plan.summary),
                const SizedBox(height: 12),
              ],
              const Text(
                '完整 JSON',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: Card(
                  padding: const EdgeInsets.all(10),
                  backgroundColor: FluentTheme.of(
                    context,
                  ).resources.layerFillColorDefault,
                  child: SingleChildScrollView(
                    child: SelectableText(
                      plan.parsedJson,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          Button(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  void _zoomAt(PointerScrollEvent event, Size size) {
    final oldView = _viewFor(size);
    if (!oldView.canPaint) return;
    // Hyperliquid-like: if already fully zoomed out and user keeps zooming out, load older history.
    final isZoomingOut = event.scrollDelta.dy < 0;
    if (isZoomingOut &&
        _zoom <= 1.05 &&
        widget.onLoadMore != null &&
        !widget.loadingMore &&
        widget.candles.isNotEmpty) {
      widget.onLoadMore!.call();
      return;
    }
    final horizontal =
        ((event.localPosition.dx - oldView.chart.left) / oldView.chart.width)
            .clamp(0.0, 1.0)
            .toDouble();
    final focusedIndex = oldView.start + horizontal * oldView.visibleCount;
    final zoom = (_zoom * (isZoomingOut ? 1.2 : 1 / 1.2))
        .clamp(1.0, 16.0)
        .toDouble();
    final newView = CandleViewport.from(size, widget.candles.length, zoom, 0);
    final desiredStart = focusedIndex - horizontal * newView.visibleCount;
    final pan = widget.candles.length - newView.visibleCount - desiredStart;
    setState(() {
      _zoom = zoom;
      _pan = pan.clamp(0.0, newView.maxPan).toDouble();
    });
    // After zooming out near the left edge, proactively load more.
    if (isZoomingOut &&
        widget.onLoadMore != null &&
        !widget.loadingMore) {
      final updatedView = CandleViewport.from(size, widget.candles.length, _zoom, _pan);
      if (updatedView.start < 5) {
        widget.onLoadMore!.call();
      }
    }
  }

  void _drag(PointerMoveEvent event, Size size) {
    final previous = _dragPosition;
    if (!_isDragging || previous == null) return;
    final view = _viewFor(size);
    if (!view.canPaint) return;
    final movedCandles = (event.localPosition.dx - previous.dx) / view.step;
    final oldPan = _pan;
    setState(() {
      _pan = (_pan + movedCandles).clamp(0.0, view.maxPan).toDouble();
      _dragPosition = event.localPosition;
      _hoverPosition = event.localPosition;
    });
    // Hyperliquid-like: when dragging to the left edge (showing oldest), load older history.
    final atLeftEdge = view.start == 0 && movedCandles > 0;
    final nearLeftEdge = view.start < 8 && movedCandles > 0;
    // Also trigger if pan is already at max and user keeps dragging left.
    final panAtMax = oldPan >= view.maxPan - 0.5 && movedCandles > 0;
    if ((atLeftEdge || nearLeftEdge || panAtMax) &&
        widget.onLoadMore != null &&
        !widget.loadingMore) {
      widget.onLoadMore!.call();
    }
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

  String _decisionLabel(String decision) => switch (decision) {
    'LONG_SETUP' => '做多方案',
    'SHORT_SETUP' => '做空方案',
    'WAIT' => '等待',
    'NO_TRADE' => '不交易',
    'DATA_INSUFFICIENT' => '数据不足',
    _ => decision,
  };

  String _entryRange(TradePlan plan) {
    final low = plan.entryLow;
    final high = plan.entryHigh;
    if (low == null && high == null) return '未提供';
    if (low == null || high == null || low == high) return _price(low ?? high);
    return '${_price(low)} — ${_price(high)}';
  }

  String _price(double? value) {
    if (value == null) return '未提供';
    return formatMarketPrice(value);
  }
}
