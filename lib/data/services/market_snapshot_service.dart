import 'package:dio/dio.dart';

import '../../domain/models/market_snapshot.dart';
import '../../domain/models/candle.dart';
import 'bybit_service.dart';
import '../../domain/analysis/candle_integrity_validator.dart';

class MarketSnapshotService {
  const MarketSnapshotService(this._bybit);

  static const intervals = {
    '1d': 'D',
    '4h': '240',
    '1h': '60',
    '15m': '15',
    '5m': '5',
  };
  static const _intervalDurations = {
    '1d': Duration(days: 1),
    '4h': Duration(hours: 4),
    '1h': Duration(hours: 1),
    '15m': Duration(minutes: 15),
    '5m': Duration(minutes: 5),
  };
  // Per-interval limits for balanced coverage: 1d 200d, 4h 50d, 1h 20d, 15m 4d, 5m 1.3d.
  static const _candleLimits = {
    '1d': 200,
    '4h': 300,
    '1h': 500,
    '15m': 400,
    '5m': 400,
  };
  static const _maximumCoreSkew = Duration(seconds: 15);
  final BybitService _bybit;

  // Share the Agent's data token across the fixed multi-timeframe snapshot.
  Future<MarketSnapshot> build(
    String symbol, {
    CancelToken? cancelToken,
  }) async {
    final normalized = symbol.trim().toUpperCase();
    final startedAt = DateTime.now().toUtc();
    // Start optional history alongside core requests; failures do not reject price analysis.
    final oi = _bybit
        .fetchOpenInterestHistory(normalized, cancelToken: cancelToken)
        .timeout(const Duration(seconds: 3))
        .catchError((Object _) => <({DateTime at, double value})>[]);
    final results = await Future.wait<Object>([
      _bybit.fetchInstrument(normalized, cancelToken: cancelToken),
      _bybit.fetchTicker(normalized, cancelToken: cancelToken),
      for (final entry in intervals.entries)
        _bybit.fetchKlines(
          symbol: normalized,
          interval: entry.value,
          limit: _candleLimits[entry.key]!,
          cancelToken: cancelToken,
        ),
    ]);
    final completedAt = DateTime.now().toUtc();
    final instrument = results[0] as InstrumentSnapshot;
    final ticker = results[1] as TickerSnapshot;
    final candles = <String, List<Candle>>{};
    for (var index = 0; index < intervals.length; index++) {
      candles[intervals.keys.elementAt(index)] =
          results[index + 2] as List<Candle>;
    }
    final timestamps = [instrument.observedAt, ticker.observedAt, completedAt]
      ..sort();
    final maxSkew = timestamps.last.difference(timestamps.first);
    final warnings = <String>[
      if (instrument.symbol != normalized || ticker.symbol != normalized)
        'Bybit returned a different symbol',
      if (instrument.status != 'Trading') 'Instrument is not trading',
      if (instrument.contractType != 'LinearPerpetual')
        'Instrument is not a linear perpetual',
      // Recent listings lack 50 daily candles; that must not degrade intraday analysis.
      if (candles.entries.any((e) => e.key != '1d' && e.value.length < 50))
        'One or more timeframes have fewer than 50 candles',
      if (maxSkew > _maximumCoreSkew) 'Core source timestamps are skewed',
    ];
    // Preserve per-timeframe data defects for the later approval decision.
    for (final entry in candles.entries) {
      final integrity = const CandleIntegrityValidator().validate(
        candles: entry.value,
        interval: _intervalDurations[entry.key]!,
        snapshotCompletedAt: completedAt,
      );
      warnings.addAll(integrity.errors.map((error) => '${entry.key}: $error'));
    }
    return MarketSnapshot(
      snapshotId: '${normalized}_${startedAt.microsecondsSinceEpoch}',
      symbol: normalized,
      buildStartedAt: startedAt,
      buildCompletedAt: completedAt,
      instrument: instrument,
      ticker: ticker,
      candlesByInterval: candles,
      maxSourceSkewMs: maxSkew.inMilliseconds,
      warnings: warnings,
      openInterestHistory: await oi,
    );
  }
}
