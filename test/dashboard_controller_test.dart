import 'dart:async';

import 'package:decma/models/trading_models.dart';
import 'package:decma/services/bybit_service.dart';
import 'package:decma/ui/dashboard/dashboard_controller.dart';
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

    bybit.complete('ETHUSDT', 2000);
    await _flushAsync();
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
  }) {
    return (_requests[symbol] ??= Completer<List<Candle>>()).future;
  }

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
