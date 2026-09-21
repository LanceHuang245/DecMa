import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart';

/// Immutable geometry shared by every chart layer.
class CandleViewport {
  const CandleViewport({
    required this.chart,
    required this.candleSpacing,
    required this.firstPosition,
    required this.start,
    required this.end,
  });

  factory CandleViewport.from({
    required Size size,
    required int candleCount,
    required double candleSpacing,
    required double trailingOffset,
  }) {
    const left = 10.0;
    const right = 68.0;
    const top = 12.0;
    const bottom = 36.0;
    final chart = Rect.fromLTWH(
      left,
      top,
      math.max(0, size.width - left - right),
      math.max(0, size.height - top - bottom),
    );
    if (candleCount == 0 || chart.width <= 0 || chart.height <= 0) {
      return CandleViewport(
        chart: chart,
        candleSpacing: candleSpacing,
        firstPosition: 0,
        start: 0,
        end: 0,
      );
    }
    final visibleSlots = chart.width / candleSpacing;
    final maxOffset = math.max(0.0, candleCount - visibleSlots);
    final safeOffset = trailingOffset.clamp(0.0, maxOffset).toDouble();
    final firstPosition = candleCount - visibleSlots - safeOffset;
    final start = math.max(0, firstPosition.floor());
    final end = math.min(candleCount, (firstPosition + visibleSlots).ceil() + 1);
    return CandleViewport(
      chart: chart,
      candleSpacing: candleSpacing,
      firstPosition: firstPosition,
      start: start,
      end: end,
    );
  }

  final Rect chart;
  final double candleSpacing;
  final double firstPosition;
  final int start;
  final int end;

  bool get canPaint => chart.width > 0 && chart.height > 0 && end > start;
  int get visibleCount => end - start;

  double xForIndex(num index) =>
      chart.left + (index + 0.5 - firstPosition) * candleSpacing;

  double positionAtX(double x) =>
      firstPosition + (x - chart.left) / candleSpacing - 0.5;
}

/// Stores zoom and pan independently from the total history length.
class ChartController extends ChangeNotifier {
  ChartController({double initialSpacing = 8}) : _spacing = initialSpacing;

  static const minSpacing = 0.35;
  static const minVisibleCandles = 8.0;
  static const preloadThreshold = 12;

  double _spacing;
  double _trailingOffset = 0;
  Size _size = Size.zero;
  int _candleCount = 0;
  bool _disposed = false;

  double get candleSpacing => _spacing;
  double get trailingOffset => _trailingOffset;
  bool get followsLatest => _trailingOffset < 0.5;

  CandleViewport get viewport => CandleViewport.from(
    size: _size,
    candleCount: _candleCount,
    candleSpacing: _spacing,
    trailingOffset: _trailingOffset,
  );

  void updateLayout(Size size, int candleCount) {
    final oldView = viewport;
    final wasFollowing = followsLatest;
    _size = size;
    _candleCount = candleCount;
    _clampOffset();
    if (!wasFollowing && oldView.canPaint && viewport.canPaint) {
      // Keep the same left-edge data position across window resizing.
      final visibleSlots = viewport.chart.width / _spacing;
      _trailingOffset = candleCount - visibleSlots - oldView.firstPosition;
      _clampOffset();
    }
  }

  void zoomAt(double x, double scrollDelta) {
    final oldView = viewport;
    if (!oldView.canPaint) return;
    final anchorPosition = oldView.positionAtX(x);
    final factor = scrollDelta > 0 ? 1.18 : 1 / 1.18;
    final maxSpacing = math.max(
      minSpacing,
      oldView.chart.width / minVisibleCandles,
    );
    final nextSpacing = (_spacing * factor)
        .clamp(minSpacing, maxSpacing)
        .toDouble();
    if (nextSpacing == _spacing) return;
    _spacing = nextSpacing;
    final slotsLeftOfAnchor = (x - oldView.chart.left) / _spacing - 0.5;
    final desiredFirst = anchorPosition - slotsLeftOfAnchor;
    final visibleSlots = oldView.chart.width / _spacing;
    _trailingOffset = _candleCount - visibleSlots - desiredFirst;
    _clampOffset();
    _notify();
  }

  void dragBy(double pixels) {
    if (!viewport.canPaint || pixels == 0) return;
    _trailingOffset += pixels / _spacing;
    _clampOffset();
    _notify();
  }

  /// Prefix insertion shifts indices while the same candles retain their pixels.
  void historyPrepended(int count) {
    if (count <= 0) return;
    _candleCount += count;
    _clampOffset();
    _notify();
  }

  void updateCandleCount(int candleCount) {
    if (candleCount == _candleCount) return;
    final wasFollowing = followsLatest;
    _candleCount = candleCount;
    if (wasFollowing) _trailingOffset = 0;
    _clampOffset();
    _notify();
  }

  bool get shouldLoadMore {
    final view = viewport;
    return view.canPaint && view.start <= preloadThreshold;
  }

  void _clampOffset() {
    final width = viewport.chart.width;
    final visibleSlots = width <= 0 ? 0.0 : width / _spacing;
    final maximum = math.max(0.0, _candleCount - visibleSlots);
    _trailingOffset = _trailingOffset.clamp(0.0, maximum).toDouble();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Price mapping is computed once and then reused by all painters.
class ChartTransform {
  const ChartTransform({
    required this.viewport,
    required this.low,
    required this.high,
  });

  final CandleViewport viewport;
  final double low;
  final double high;

  double get range => high - low;
  double xForIndex(num index) => viewport.xForIndex(index);
  double yForPrice(double price) =>
      viewport.chart.bottom - (price - low) / range * viewport.chart.height;
  double priceForY(double y) =>
      low + (viewport.chart.bottom - y) / viewport.chart.height * range;
}
