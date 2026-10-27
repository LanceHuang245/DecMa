import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart';

import '../../domain/models/candle.dart';
import '../../domain/models/trade_plan.dart';
import '../../utils/display_formatters.dart';
import 'candle_chart_frame.dart';
import 'candle_chart_painter.dart';
import 'candle_chart_viewport.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../l10n/app_languages.dart';

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
  ChartFrame? _cachedFrame;
  bool _frameStale = true;

  TradePlan? get _paintPlan =>
      widget.plan?.isSetup == true || widget.showWaitZone ? widget.plan : null;

  // Build the frame once per data, layout or viewport change; all layers share it.
  ChartFrame? _frame() {
    if (_frameStale) {
      _cachedFrame = ChartFrame.build(
        source: widget.candles,
        viewport: _controller.viewport,
        plan: _paintPlan,
      );
      _frameStale = false;
    }
    return _cachedFrame;
  }

  void _invalidateFrame() => _frameStale = true;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_invalidateFrame);
  }

  @override
  void didUpdateWidget(covariant CandleChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    _invalidateFrame();
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
    _controller.removeListener(_invalidateFrame);
    _pointer.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final resources = FluentTheme.of(context).resources;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (widget.candles.isNotEmpty)
          LayoutBuilder(
            builder: (context, constraints) {
              _size = constraints.biggest;
              _controller.updateLayout(_size, widget.candles.length);
              _invalidateFrame();
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
                  // Separate layers so hovering repaints only the crosshair.
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      RepaintBoundary(
                        child: CustomPaint(
                          painter: MainCandlePainter(
                            frame: _frame,
                            grid: resources.textFillColorSecondary,
                            repaint: _controller,
                          ),
                        ),
                      ),
                      RepaintBoundary(
                        child: CustomPaint(
                          painter: PlanCandlePainter(
                            frame: _frame,
                            plan: () => _paintPlan,
                            repaint: _controller,
                          ),
                        ),
                      ),
                      RepaintBoundary(
                        child: CustomPaint(
                          painter: InteractionCandlePainter(
                            frame: _frame,
                            pointer: () => _pointer.value,
                            foreground: resources.textFillColorPrimary,
                            repaint: Listenable.merge([_controller, _pointer]),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        if (widget.plan case final plan?) _PlanCard(plan: plan, showWaitZone: widget.showWaitZone),
        if (widget.loading || (widget.candles.isEmpty && widget.error == null))
          ColoredBox(
            color: FluentTheme.of(context).scaffoldBackgroundColor.withAlpha(0xE6),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const ProgressRing(),
                  const SizedBox(height: 10),
                  Text(AppLocalizations.of(context).loadingKlines),
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
        FilledButton(onPressed: onRetry, child: Text(AppLocalizations.of(context).retry)),
        const SizedBox(height: 8),
        SizedBox(width: 320, child: Text(error, textAlign: TextAlign.center, style: const TextStyle(color: Colors.errorPrimaryColor))),
      ],
    ),
  );
}

class _HistoryLoading extends StatelessWidget {
  const _HistoryLoading();
  @override
  Widget build(BuildContext context) => Positioned(
    right: 80,
    bottom: 46,
    child: Card(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 12, height: 12, child: ProgressRing(strokeWidth: 2)),
          const SizedBox(width: 6),
          Text(AppLocalizations.of(context).loadingHistory, style: const TextStyle(fontSize: 11)),
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
    final loc = AppLocalizations.of(context);
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
                  Text(loc.planEntryZone(plan.isSetup || showWaitZone ? _entryRange(plan) : '-'), style: const TextStyle(fontSize: 12)),
                  Text(loc.planStopLoss(plan.isSetup ? _price(plan.stopLoss) : '-'), style: const TextStyle(fontSize: 12)),
                  Text(loc.planTakeProfit(plan.isSetup ? (plan.takeProfits.isEmpty ? loc.notProvided : plan.takeProfits.take(3).map(_price).join(' / ')) : '-'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 4),
                  Text(loc.viewFullJson, style: TextStyle(fontSize: 11, color: FluentTheme.of(context).resources.textFillColorSecondary)),
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
    builder: (context) {
      final loc = AppLocalizations.of(context);
      return ContentDialog(
        title: Text(loc.jsonResultTitle(_decisionLabel(plan.decision))),
        content: SizedBox(
          width: 680,
          height: 520,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (plan.summary.isNotEmpty) ...[Text(plan.summary), const SizedBox(height: 12)],
              Text(loc.fullJson, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Expanded(child: Card(padding: const EdgeInsets.all(10), child: SingleChildScrollView(child: SelectableText(plan.parsedJson, style: const TextStyle(fontFamily: 'monospace', fontSize: 12))))),
            ],
          ),
        ),
        actions: [Button(onPressed: () => Navigator.pop(context), child: Text(loc.close))],
      );
    },
  );
}

String _decisionLabel(String decision) => switch (decision) {
  'LONG_SETUP' => appL10n.decisionLongSetup, 'SHORT_SETUP' => appL10n.decisionShortSetup, 'WAIT' => appL10n.decisionWait,
  'NO_TRADE' => appL10n.decisionNoTrade, 'DATA_INSUFFICIENT' => appL10n.decisionDataInsufficient, _ => decision,
};

String _entryRange(TradePlan plan) {
  final low = plan.entryLow;
  final high = plan.entryHigh;
  if (low == null && high == null) return appL10n.notProvided;
  if (low == null || high == null || low == high) return _price(low ?? high);
  return '${_price(low)} — ${_price(high)}';
}

String _price(double? value) => value == null ? appL10n.notProvided : formatMarketPrice(value);
