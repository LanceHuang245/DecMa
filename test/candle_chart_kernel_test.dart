import 'package:decma/models/trading_models.dart';
import 'package:decma/ui/chart/candle_chart.dart';
import 'package:decma/ui/chart/candle_chart_frame.dart';
import 'package:decma/ui/chart/candle_chart_viewport.dart';
import 'package:decma/ui/chart/candle_series.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CandleSeries', () {
    test('latest updates replace or append without rebuilding history', () {
      final series = CandleSeries(List.generate(100000, _candle));
      final listIdentity = series.items;
      final version = series.version;

      expect(series.applyLatest([_candle(99999, close: 100001)]), isTrue);
      expect(identical(series.items, listIdentity), isTrue);
      expect(series.length, 100000);
      expect(series.last.close, 100001);
      expect(series.version, version + 1);
      expect(series.applyLatest([_candle(99999, close: 100001)]), isFalse);
      expect(series.applyLatest([_candle(100000)]), isTrue);
      expect(series.length, 100001);
    });

    test('history prepend deduplicates, validates, and keeps newer records', () {
      final series = CandleSeries([_candle(2), _candle(3)]);
      final invalid = Candle(
        time: DateTime.utc(2026),
        open: double.nan,
        high: 1,
        low: 1,
        close: 1,
        volume: 1,
      );

      expect(series.prepend([_candle(0), _candle(1), _candle(2), invalid]), isTrue);
      expect(series.items.map((item) => item.close), [0, 1, 2, 3]);
    });
  });

  group('ChartController', () {
    test('zoom keeps the candle under the pointer anchored', () {
      final controller = ChartController();
      controller.updateLayout(const Size(1000, 500), 100000);
      final before = controller.viewport.positionAtX(400);

      controller.zoomAt(400, 1);

      expect(controller.viewport.positionAtX(400), closeTo(before, 1e-9));
      expect(controller.viewport.visibleCount, lessThan(150));
      controller.dispose();
    });

    test('history prepend and live updates preserve viewport rules', () {
      final controller = ChartController();
      controller.updateLayout(const Size(1000, 500), 1000);
      controller.dragBy(240);
      final before = controller.viewport.firstPosition;

      controller.historyPrepended(1000);
      expect(controller.viewport.firstPosition, closeTo(before + 1000, 1e-9));
      final historical = controller.viewport.firstPosition;
      controller.updateCandleCount(2001);
      expect(controller.viewport.firstPosition, closeTo(historical + 1, 1e-9));

      final following = ChartController();
      following.updateLayout(const Size(1000, 500), 1000);
      following.updateCandleCount(1001);
      expect(following.trailingOffset, 0);
      controller.dispose();
      following.dispose();
    });
  });

  test('sub-pixel candles aggregate with OHLC semantics', () {
    final candles = List.generate(10000, _candle);
    final viewport = CandleViewport.from(
      size: const Size(1000, 500),
      candleCount: candles.length,
      candleSpacing: 0.35,
      trailingOffset: 0,
    );
    final frame = ChartFrame.build(source: candles, viewport: viewport)!;

    expect(frame.candles.length, lessThanOrEqualTo(viewport.chart.width.ceil() + 1));
    final aggregate = frame.candles.firstWhere((item) => item.aggregated);
    expect(aggregate.open, candles[aggregate.firstIndex].open);
    expect(aggregate.close, candles[aggregate.lastIndex].close);
    expect(
      aggregate.high,
      candles
          .sublist(aggregate.firstIndex, aggregate.lastIndex + 1)
          .map((item) => item.high)
          .reduce((left, right) => left > right ? left : right),
    );
  });
  testWidgets('100k chart paints, zooms, drags, and resizes without errors', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 700);
    addTearDown(() => tester.view.resetPhysicalSize());
    final candles = List.generate(100000, _candle);
    await tester.pumpWidget(
      FluentApp(home: CandleChart(candles: candles)),
    );

    await tester.sendEventToBinding(
      const PointerScrollEvent(
        position: Offset(500, 300),
        scrollDelta: Offset(0, -120),
      ),
    );
    final gesture = await tester.startGesture(const Offset(500, 300));
    await gesture.moveBy(const Offset(180, 0));
    await gesture.up();
    tester.view.physicalSize = const Size(900, 500);
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(CandleChart), findsOneWidget);
  });

}

Candle _candle(int index, {double? close}) {
  final value = index.toDouble();
  final actualClose = close ?? value;
  return Candle(
    time: DateTime.utc(2026).add(Duration(minutes: index)),
    open: value,
    high: actualClose > value ? actualClose : value,
    low: actualClose < value ? actualClose : value,
    close: actualClose,
    volume: 1,
  );
}
