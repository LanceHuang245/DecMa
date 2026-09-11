import 'package:decma/models/market_snapshot.dart';
import 'package:decma/models/trading_models.dart';
import 'package:decma/services/analysis/market_snapshot_service.dart';
import 'package:decma/services/bybit_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Bybit account fee signatures use the V5 authenticated GET payload', () {
    expect(
      BybitService.accountSignature(
        timestamp: 1670000000000,
        apiKey: 'test-key',
        recvWindow: '5000',
        query: 'category=linear&symbol=BTCUSDT',
        apiSecret: 'test-secret',
      ),
      'c7a1d6479554a14d1aff5e3cea0c0643ffba6af633008f2768ff888e867729c0',
    );
  });

  test('Bybit converts the 720-minute interval to milliseconds', () {
    expect(BybitService.intervalMs('720'), 43200000);
  });

  test(
    'MarketSnapshotService always requests fixed analysis timeframes',
    () async {
      final bybit = _FakeBybit();
      final snapshot = await MarketSnapshotService(bybit).build('btcusdt');

      expect(bybit.intervals, ['240', '60', '15', '5']);
      expect(snapshot.symbol, 'BTCUSDT');
      expect(snapshot.candlesByInterval.keys, ['4h', '1h', '15m', '5m']);
      expect(snapshot.instrument.tickSize, 0.1);
      expect(snapshot.instrument.minimumOrderQuantity, 0.001);
      expect(snapshot.instrument.maximumOrderQuantity, 100);
      expect(snapshot.instrument.minimumNotionalValue, 5);
      expect(
        snapshot.instrument.toJson(),
        containsPair('min_order_qty', 0.001),
      );
      expect(snapshot.instrument.toJson(), containsPair('max_order_qty', 100));
      expect(
        snapshot.instrument.toJson(),
        containsPair('min_notional_value', 5),
      );
      expect(snapshot.warnings, isEmpty);
    },
  );

  test(
    'MarketSnapshotService scopes candle integrity warnings by timeframe',
    () async {
      final snapshot = await MarketSnapshotService(
        _InvalidCandleBybit(),
      ).build('btcusdt');

      expect(snapshot.warnings, contains('15m: Duplicate candle timestamp'));
    },
  );
}

class _FakeBybit extends BybitService {
  final intervals = <String>[];

  @override
  Future<InstrumentSnapshot> fetchInstrument(
    String symbol, {
    CancelToken? cancelToken,
  }) async => InstrumentSnapshot(
    symbol: symbol,
    contractType: 'LinearPerpetual',
    status: 'Trading',
    tickSize: 0.1,
    quantityStep: 0.001,
    minimumOrderQuantity: 0.001,
    maximumOrderQuantity: 100,
    minimumNotionalValue: 5,
    fundingIntervalMinutes: 480,
    observedAt: DateTime.now().toUtc(),
  );

  @override
  Future<TickerSnapshot> fetchTicker(
    String symbol, {
    CancelToken? cancelToken,
  }) async => TickerSnapshot(
    symbol: symbol,
    lastPrice: 100,
    markPrice: 100,
    indexPrice: 100,
    bestBid: 99.9,
    bestAsk: 100.1,
    openInterest: 1000,
    fundingRate: 0.0001,
    observedAt: DateTime.now().toUtc(),
  );

  @override
  Future<List<Candle>> fetchKlines({
    required String symbol,
    required String interval,
    int limit = 160,
    int? start,
    int? end,
    CancelToken? cancelToken,
  }) async {
    intervals.add(interval);
    final intervalMinutes = int.parse(interval);
    final now = DateTime.now().toUtc();
    return List.generate(
      60,
      (index) => Candle(
        time: now.subtract(Duration(minutes: intervalMinutes * (60 - index))),
        open: 100,
        high: 101,
        low: 99,
        close: 100,
        volume: 10,
      ),
    );
  }
}

class _InvalidCandleBybit extends _FakeBybit {
  @override
  Future<List<Candle>> fetchKlines({
    required String symbol,
    required String interval,
    int limit = 160,
    int? start,
    int? end,
    CancelToken? cancelToken,
  }) async {
    final candles = await super.fetchKlines(
      symbol: symbol,
      interval: interval,
      limit: limit,
      start: start,
      end: end,
      cancelToken: cancelToken,
    );
    if (interval == '15') return [...candles, candles.last];
    return candles;
  }
}
