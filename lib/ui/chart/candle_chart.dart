import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart';

import '../../models/trading_models.dart';
import '../../utils/display_formatters.dart';
import 'candle_chart_frame.dart';
import 'candle_chart_painter.dart';
import 'candle_chart_viewport.dart';

class CandleChart extends StatefulWidget {
  const CandleChart({
    super.key,
    required this.candles,
    this.totalPrepended = 0,
    this.plan,
    this.showWaitZone = false,
    this.error,
    this.historyError,
    this.loading = false,
    this.onRetry,
    this.onLoadMore,
    this.loadingMore = false,
  });

  final List<Candle> candles;
  final int totalPrepended;
  final TradePlan? plan;
  final bool showWaitZone;
  final String? error;
  final String? historyError;
  final bool loading;
  final VoidCallback? onRetry;
  final Future<void> Function()? onLoadMore;
  final bool loadingMore;

  @override
  State<CandleChart> createState() => _CandleChartState();
}

class _CandleChartState extends State<CandleChart> {
  final _controller = ChartController();
  final _pointer = ValueNotifier<Offset?>(null);
  Offset? _dragPosition;
  bool _isDragging = false;
  bool _loadRequested = false;
  Size _size = Size.zero;

  TradePlan? get _paintPlan =>
      widget.plan?.isSetup == true || widget.showWaitZone ? widget.plan : null;

  ChartFrame? _frame() => ChartFrame.build(
    source: widget.candles,
    viewport: _controller.viewport,
    plan: _paintPlan,
  );

  @override
  void didUpdateWidget(covariant CandleChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    final prepended = widget.totalPrepended - oldWidget.totalPrepended;
    if (prepended > 0) {
      _controller.historyPrepended(prepended);
    } else {
      _controller.updateCandleCount(widget.candles.length);
    }
    if (!widget.loadingMore) _loadRequested = false;
  }

  @override
  void dispose() {
    _pointer.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (widget.candles.isNotEmpty)
          LayoutBuilder(
            builder: (context, constraints) {
              _size = constraints.biggest;
              _controller.updateLayout(_size, widget.candles.length);
              return MouseRegion(
                cursor: _isDragging
                    ? SystemMouseCursors.grabbing
                    : SystemMouseCursors.grab,
                onExit: (_) => _pointer.value = null,
                onHover: (event) => _pointer.value = event.localPosition,
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerSignal: (event) {
                    if (event is PointerScrollEvent) _zoom(event);
                  },
                  onPointerDown: (event) {
                    if ((event.buttons & kPrimaryMouseButton) == 0) return;
                    setState(() {
                      _isDragging = true;
                      _dragPosition = event.localPosition;
                    });
                  },
                  onPointerMove: _drag,
                  onPointerUp: (_) => _stopDragging(),
                  onPointerCancel: (_) => _stopDragging(),
                  child: RepaintBoundary(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CustomPaint(
                          painter: MainCandlePainter(
                            frame: _frame,
                            repaint: _controller,
                          ),
                        ),
                        CustomPaint(
                          painter: PlanCandlePainter(
                            frame: _frame,
                            plan: () => _paintPlan,
                            repaint: _controller,
                          ),
                        ),
                        CustomPaint(
                          painter: InteractionCandlePainter(
                            frame: _frame,
                            pointer: () => _pointer.value,
                            repaint: Listenable.merge([_controller, _pointer]),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        if (widget.plan case final plan?) _PlanCard(plan: plan, showWaitZone: widget.showWaitZone),
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
        if (widget.error case final error?) _LoadError(error: error, onRetry: widget.onRetry),
        if (widget.loadingMore) const _HistoryLoading(),
        if (!widget.loadingMore && widget.historyError != null)
          Positioned(
            left: 12,
            bottom: 42,
            child: Card(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(widget.historyError!, style: const TextStyle(fontSize: 11, color: Colors.errorPrimaryColor)),
            ),
          ),
      ],
    );
  }

  void _zoom(PointerScrollEvent event) {
    final before = _controller.candleSpacing;
    _controller.zoomAt(event.localPosition.dx, -event.scrollDelta.dy);
    final zoomingOut = _controller.candleSpacing < before;
    if (zoomingOut && _controller.shouldLoadMore) _requestMore();
  }

  void _drag(PointerMoveEvent event) {
    final previous = _dragPosition;
    if (!_isDragging || previous == null) return;
    final movement = event.localPosition.dx - previous.dx;
    _dragPosition = event.localPosition;
    _pointer.value = event.localPosition;
    _controller.dragBy(movement);
    if (movement > 0 && _controller.shouldLoadMore) _requestMore();
  }

  void _requestMore() {
    if (_loadRequested || widget.loadingMore || widget.onLoadMore == null) return;
    _loadRequested = true;
    widget.onLoadMore!.call().whenComplete(() {
      if (mounted) _loadRequested = false;
    });
  }

  void _stopDragging() {
    if (!_isDragging) return;
    setState(() {
      _isDragging = false;
      _dragPosition = null;
    });
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.error, required this.onRetry});
  final String error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FilledButton(onPressed: onRetry, child: const Text('重试')),
        const SizedBox(height: 8),
        SizedBox(width: 320, child: Text(error, textAlign: TextAlign.center, style: const TextStyle(color: Colors.errorPrimaryColor))),
      ],
    ),
  );
}

class _HistoryLoading extends StatelessWidget {
  const _HistoryLoading();
  @override
  Widget build(BuildContext context) => const Positioned(
    right: 80,
    bottom: 46,
    child: Card(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 12, height: 12, child: ProgressRing(strokeWidth: 2)),
          SizedBox(width: 6),
          Text('加载更早历史…', style: TextStyle(fontSize: 11)),
        ],
      ),
    ),
  );
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.showWaitZone});
  final TradePlan plan;
  final bool showWaitZone;

  @override
  Widget build(BuildContext context) {
    final color = plan.decision == 'LONG_SETUP' ? Colors.green : plan.decision == 'SHORT_SETUP' ? Colors.red : Colors.warningPrimaryColor;
    return Positioned(
      right: 76,
      top: 18,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _showDetails(context),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Card(
            padding: const EdgeInsets.all(8),
            backgroundColor: FluentTheme.of(context).resources.layerFillColorDefault,
            child: SizedBox(
              width: 210,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_decisionLabel(plan.decision), style: TextStyle(color: color, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text('开仓区：${plan.isSetup || showWaitZone ? _entryRange(plan) : '-'}', style: const TextStyle(fontSize: 12)),
                  Text('止损：${plan.isSetup ? _price(plan.stopLoss) : '-'}', style: const TextStyle(fontSize: 12)),
                  Text('止盈：${plan.isSetup ? (plan.takeProfits.isEmpty ? '未提供' : plan.takeProfits.map(_price).join(' / ')) : '-'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 4),
                  Text('点击查看完整 JSON 解析', style: TextStyle(fontSize: 11, color: FluentTheme.of(context).resources.textFillColorSecondary)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showDetails(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) => ContentDialog(
      title: Text('${_decisionLabel(plan.decision)}：JSON 解析结果'),
      content: SizedBox(
        width: 680,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (plan.summary.isNotEmpty) ...[Text(plan.summary), const SizedBox(height: 12)],
            const Text('完整 JSON', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Expanded(child: Card(padding: const EdgeInsets.all(10), child: SingleChildScrollView(child: SelectableText(plan.parsedJson, style: const TextStyle(fontFamily: 'monospace', fontSize: 12))))),
          ],
        ),
      ),
      actions: [Button(onPressed: () => Navigator.pop(context), child: const Text('关闭'))],
    ),
  );
}

String _decisionLabel(String decision) => switch (decision) {
  'LONG_SETUP' => '做多方案', 'SHORT_SETUP' => '做空方案', 'WAIT' => '等待',
  'NO_TRADE' => '不交易', 'DATA_INSUFFICIENT' => '数据不足', _ => decision,
};

String _entryRange(TradePlan plan) {
  final low = plan.entryLow;
  final high = plan.entryHigh;
  if (low == null && high == null) return '未提供';
  if (low == null || high == null || low == high) return _price(low ?? high);
  return '${_price(low)} — ${_price(high)}';
}

String _price(double? value) => value == null ? '未提供' : formatMarketPrice(value);
