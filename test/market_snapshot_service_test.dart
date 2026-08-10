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

  test(
    'MarketSnapshotService always requests fixed analysis timeframes',
    () async {
      final bybit = _FakeBybit();
      final snapshot = await MarketSnapshotService(bybit).build('btcusdt');

      expect(bybit.intervals, ['240', '60', '15', '5']);
      expect(snapshot.symbol, 'BTCUSDT');
      expect(snapshot.candlesByInterval.keys, ['4h', '1h', '15m', '5m']);
      expect(snapshot.instrument.tickSize, 0.1);
      expect(snapshot.warnings, isEmpty);
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
    CancelToken? cancelToken,
  }) async {
    intervals.add(interval);
    return List.generate(
      60,
      (index) => Candle(
        time: DateTime.now().toUtc().subtract(Duration(minutes: 61 - index)),
        open: 100,
        high: 101,
        low: 99,
        close: 100,
        volume: 10,
      ),
    );
  }
}
