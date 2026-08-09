import '../../models/market_snapshot.dart';
import '../../models/trading_models.dart';
import '../bybit_service.dart';

class MarketSnapshotService {
  const MarketSnapshotService(this._bybit);

  static const intervals = {'4h': '240', '1h': '60', '15m': '15', '5m': '5'};
  static const _candleLimit = 200;
  static const _maximumCoreSkew = Duration(seconds: 15);
  final BybitService _bybit;

  Future<MarketSnapshot> build(String symbol) async {
    final normalized = symbol.trim().toUpperCase();
    final startedAt = DateTime.now().toUtc();
    final results = await Future.wait<Object>([
      _bybit.fetchInstrument(normalized),
      _bybit.fetchTicker(normalized),
      for (final interval in intervals.values)
        _bybit.fetchKlines(
          symbol: normalized,
          interval: interval,
          limit: _candleLimit,
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
      if (candles.values.any((items) => items.length < 50))
        'One or more timeframes have fewer than 50 candles',
      if (maxSkew > _maximumCoreSkew) 'Core source timestamps are skewed',
    ];
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
    );
  }
}
