import 'package:decma/models/market_snapshot.dart';
import 'package:decma/models/trading_models.dart';
import 'package:decma/services/analysis/feature_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('FeatureEngine calculates stable flat-market features', () {
    final completedAt = DateTime.utc(2026, 8, 10, 12);
    final candles = List.generate(80, (index) {
      return Candle(
        time: completedAt.subtract(Duration(minutes: (80 - index) * 15)),
        open: 100,
        high: 101,
        low: 99,
        close: 100,
        volume: 10,
      );
    });
    final features = const FeatureEngine().calculate(
      _snapshot(completedAt, {'15m': candles}),
    );
    final timeframe = features.timeframes['15m']!;

    expect(timeframe.closedCandleCount, 80);
    expect(timeframe.ema20, 100);
    expect(timeframe.ema50, 100);
    expect(timeframe.rsi14, 50);
    expect(timeframe.atr14, 2);
    expect(timeframe.vwap20, 100);
    expect(timeframe.realizedVolatilityPercent, 0);
    expect(timeframe.volumeZScore, 0);
    expect(features.basisBps, closeTo(5, 1e-9));
    expect(features.spreadBps, closeTo(20, 1e-9));
    expect(features.fundingAnnualizedPercent, closeTo(10.95, 1e-9));
  });

  test('FeatureEngine excludes a still-forming candle', () {
    final completedAt = DateTime.utc(2026, 8, 10, 12, 7);
    final candles = [
      for (var index = 0; index < 60; index++)
        Candle(
          time: DateTime.utc(2026, 8, 9, 21).add(Duration(minutes: index * 15)),
          open: 100 + index.toDouble(),
          high: 101 + index.toDouble(),
          low: 99 + index.toDouble(),
          close: 100 + index.toDouble(),
          volume: 10,
        ),
      Candle(
        time: DateTime.utc(2026, 8, 10, 12),
        open: 500,
        high: 600,
        low: 400,
        close: 550,
        volume: 10000,
      ),
    ];
    final features = const FeatureEngine().calculate(
      _snapshot(completedAt, {'15m': candles}),
    );

    expect(features.timeframes['15m']!.closedCandleCount, 60);
    expect(features.timeframes['15m']!.ema20, lessThan(200));
  });

  test('short-term anomaly only uses fixed 5m and 15m features', () {
    final completedAt = DateTime.utc(2026, 8, 10, 12);
    List<Candle> candles(double latestVolume) => List.generate(
      40,
      (index) => Candle(
        time: completedAt.subtract(Duration(minutes: (40 - index) * 5)),
        open: 100,
        high: 101,
        low: 99,
        close: 100,
        volume: index == 39 ? latestVolume : 10,
      ),
    );

    final fourHourOnly = const FeatureEngine().calculate(
      _snapshot(completedAt, {'4h': candles(100)}),
    );
    final fiveMinute = const FeatureEngine().calculate(
      _snapshot(completedAt, {'5m': candles(100)}),
    );

    expect(fourHourOnly.hasAbnormalShortTerm, isFalse);
    expect(fiveMinute.hasAbnormalShortTerm, isTrue);
  });
}

MarketSnapshot _snapshot(
  DateTime completedAt,
  Map<String, List<Candle>> candles,
) => MarketSnapshot(
  snapshotId: 'BTCUSDT_test',
  symbol: 'BTCUSDT',
  buildStartedAt: completedAt.subtract(const Duration(seconds: 1)),
  buildCompletedAt: completedAt,
  instrument: InstrumentSnapshot(
    symbol: 'BTCUSDT',
    contractType: 'LinearPerpetual',
    status: 'Trading',
    tickSize: 0.1,
    quantityStep: 0.001,
    fundingIntervalMinutes: 480,
    observedAt: completedAt,
  ),
  ticker: TickerSnapshot(
    symbol: 'BTCUSDT',
    lastPrice: 100,
    markPrice: 100.05,
    indexPrice: 100,
    bestBid: 99.9,
    bestAsk: 100.1,
    openInterest: 1000,
    fundingRate: 0.0001,
    observedAt: completedAt,
  ),
  candlesByInterval: candles,
  maxSourceSkewMs: 1000,
  warnings: const [],
);
