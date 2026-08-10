import 'dart:async';

import 'package:decma/models/trading_models.dart';
import 'package:decma/services/bybit_service.dart';
import 'package:decma/utils/network.dart';
import 'package:dio/dio.dart';
import 'package:decma/ui/chart/candle_chart.dart';
import 'package:decma/ui/chart/candle_chart_painter.dart';
import 'package:decma/ui/dashboard/dashboard_controller.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a stale symbol response cannot replace the current chart', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final bybit = _DelayedBybit();
    final controller = DashboardController(nodeAvailable: true, bybit: bybit);

    controller.selectSymbol('ETHUSDT');
    expect(controller.showChartLoading, isTrue);
    expect(controller.candles, isEmpty);

    controller.selectSymbol('XRPUSDT');
    expect(controller.activeSymbol, 'XRPUSDT');
    expect(controller.showChartLoading, isTrue);

    await _flushAsync();
    expect(bybit.wasCancelled('ETHUSDT'), isTrue);
    expect(controller.activeSymbol, 'XRPUSDT');
    expect(controller.candles, isEmpty);
    expect(controller.showChartLoading, isTrue);

    bybit.complete('XRPUSDT', 1);
    await _flushAsync();
    expect(controller.candles.single.close, 1);
    expect(controller.showChartLoading, isFalse);
    expect(controller.loadingChart, isFalse);

    controller.dispose();
  });

  testWidgets('WAIT renders its candidate zone but hides stop and targets', (
    tester,
  ) async {
    const plan = TradePlan(
      decision: 'WAIT',
      summary: 'Wait for a retest',
      parsedJson: '{}',
      entryLow: 100,
      entryHigh: 101,
      stopLoss: 98,
      targets: [TradeTarget(price: 105)],
    );
    await tester.pumpWidget(
      FluentApp(
        home: SizedBox(
          width: 800,
          height: 500,
          child: CandleChart(
            candles: [
              Candle(
                time: DateTime.utc(2026, 8, 10),
                open: 100,
                high: 101,
                low: 99,
                close: 100,
                volume: 1,
              ),
            ],
            plan: plan,
            showWaitZone: true,
          ),
        ),
      ),
    );

    final painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<CandlePainter>()
        .single;
    expect(painter.plan, same(plan));
    expect(find.text('开仓区：-'), findsNothing);
    expect(find.text('止损：-'), findsOneWidget);
    expect(find.text('止盈：-'), findsOneWidget);
  });
}

Future<void> _flushAsync() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class _DelayedBybit extends BybitService {
  final _requests = <String, Completer<List<Candle>>>{};

  @override
  Future<List<Candle>> fetchKlines({
    required String symbol,
    required String interval,
    int limit = 160,
    CancelToken? cancelToken,
  }) {
    final request = _requests[symbol] ??= Completer<List<Candle>>();
    cancelToken?.whenCancel.then((_) {
      _cancelled.add(symbol);
      if (!request.isCompleted) {
        request.completeError(
          const AppFailure(kind: AppFailureKind.cancelled, provider: 'Bybit'),
        );
      }
    });
    return request.future;
  }

  final _cancelled = <String>{};

  bool wasCancelled(String symbol) => _cancelled.contains(symbol);

  void complete(String symbol, double close) {
    _requests[symbol]!.complete([
      Candle(
        time: DateTime.utc(2026, 8, 10),
        open: close,
        high: close,
        low: close,
        close: close,
        volume: 1,
      ),
    ]);
  }
}
