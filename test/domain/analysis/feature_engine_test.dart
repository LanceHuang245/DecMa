import 'package:decma/domain/models/market_snapshot.dart';
import 'package:decma/domain/models/candle.dart';
import 'package:decma/domain/analysis/feature_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:decma/data/services/agent_context.dart';

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

  test('new indicators reach the actual model context as numeric features', () {
    final at = DateTime.utc(2026, 10, 20, 12);
    final bars = List.generate(
      160,
      (i) => Candle(
        time: at.subtract(Duration(minutes: (160 - i) * 15)),
        open: 100,
        high: 100,
        low: 100,
        close: 100,
        volume: 0,
      ),
    );
    final snapshot = _snapshot(at, {'15m': bars});
    final features = const FeatureEngine().calculate(snapshot);
    final details = features.timeframes['15m']!.details;
    expect(details['adx14'], 0);
    expect(details['kdj_k9'], closeTo(50, 1e-9));
    expect(details['kdj_d3'], closeTo(50, 1e-9));
    expect(details['kdj_j3'], closeTo(50, 1e-9));
    expect(details['bollinger_upper20'], 100);
    expect(details['bollinger_bandwidth_percentile120'], 100);
    expect(details['rsi14_change_3'], 0);
    final context = agentContext(
      prompt: '分析',
      symbol: 'BTCUSDT',
      candles: bars,
      warnings: [],
      sourceAvailability: {},
      marketSnapshot: snapshot,
      marketFeatures: features,
    );
    for (final key in [
      'kdj_k9',
      'kdj_d3',
      'kdj_j3',
      'adx14',
      'bollinger_bandwidth_percentile120',
      'rsi14_change_3',
      'prior_high20',
    ]) {
      expect(context, contains('"$key":${details[key]}'));
    }
  });
  test(
    'rising-market KDJ and ADX follow their fixed smoothing definitions',
    () {
      final at = DateTime.utc(2026, 10, 20, 12);
      final bars = List.generate(
        60,
        (i) => Candle(
          time: at.subtract(Duration(minutes: (60 - i) * 15)),
          open: 100 + i.toDouble(),
          high: 101 + i.toDouble(),
          low: 99 + i.toDouble(),
          close: 100 + i.toDouble(),
          volume: 10,
        ),
      );
      final details = const FeatureEngine()
          .calculate(_snapshot(at, {'15m': bars}))
          .timeframes['15m']!
          .details;
      expect(details['adx14'], closeTo(100, 1e-9));
      expect(details['minus_di14'], 0);
      final expectedK =
          90 - 40 * (List.filled(52, 2 / 3).fold<double>(1, (a, b) => a * b));
      expect(details['kdj_k9'], closeTo(expectedK, 1e-9));
      expect(details['prior_high20'], 159); // Excludes the newest high of 160.
    },
  );
  test('gapped history produces unavailable indicators', () {
    final at = DateTime.utc(2026, 10, 20, 12);
    final bars = List.generate(
      60,
      (i) => Candle(
        time: at.subtract(Duration(minutes: (60 - i) * 15)),
        open: 100,
        high: 101,
        low: 99,
        close: 100,
        volume: 10,
      ),
    )..removeAt(20);
    final tf = const FeatureEngine()
        .calculate(_snapshot(at, {'15m': bars}))
        .timeframes['15m']!;
    expect(tf.rsi14, isNull);
    expect(tf.details['kdj_k9'], isNull);
    expect(tf.details['adx14'], isNull);
  });

  test(
    'model-facing OI changes require complete fresh observation windows',
    () {
      final at = DateTime.utc(2026, 10, 20, 12);
      final base = _snapshot(at, {});
      MarketSnapshot withHistory(List<({DateTime at, double value})> history) =>
          MarketSnapshot(
            snapshotId: base.snapshotId,
            symbol: base.symbol,
            buildStartedAt: base.buildStartedAt,
            buildCompletedAt: at,
            instrument: base.instrument,
            ticker: base.ticker,
            candlesByInterval: {},
            maxSourceSkewMs: 0,
            warnings: [],
            openInterestHistory: history,
          );
      final history = List.generate(
        13,
        (i) => (
          at: at.subtract(Duration(minutes: (12 - i) * 5)),
          value: 100 + i.toDouble(),
        ),
      );
      final json = withHistory(history).toJson();
      expect(json['oi_change_1h_percent'], closeTo(12, 1e-9));
      expect(
        json['oi_change_15m_percent'],
        closeTo((112 / 109 - 1) * 100, 1e-9),
      );
      final gap = [...history]..removeAt(10);
      expect(withHistory(gap).toJson()['oi_change_15m_percent'], isNull);
      expect(
        withHistory(
          history
              .map(
                (p) => (
                  at: p.at.subtract(const Duration(minutes: 15)),
                  value: p.value,
                ),
              )
              .toList(),
        ).toJson()['oi_change_1h_percent'],
        isNull,
      );
    },
  );
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
    minimumOrderQuantity: 0.001,
    maximumOrderQuantity: 100,
    minimumNotionalValue: 5,
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
