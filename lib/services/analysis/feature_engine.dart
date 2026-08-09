import 'dart:math' as math;

import '../../models/market_snapshot.dart';
import '../../models/trading_models.dart';

class TimeframeFeatures {
  const TimeframeFeatures({
    required this.closedCandleCount,
    required this.asOf,
    required this.ema20,
    required this.ema50,
    required this.macd,
    required this.macdSignal,
    required this.macdHistogram,
    required this.rsi14,
    required this.atr14,
    required this.vwap20,
    required this.realizedVolatilityPercent,
    required this.volumeZScore,
    required this.rangeExpansionRatio,
    required this.volumeExpansionRatio,
  });

  final int closedCandleCount;
  final DateTime? asOf;
  final double? ema20;
  final double? ema50;
  final double? macd;
  final double? macdSignal;
  final double? macdHistogram;
  final double? rsi14;
  final double? atr14;
  final double? vwap20;
  final double? realizedVolatilityPercent;
  final double? volumeZScore;
  final double? rangeExpansionRatio;
  final double? volumeExpansionRatio;

  Map<String, Object?> toJson() => {
    'closed_candle_count': closedCandleCount,
    'as_of': asOf?.toUtc().toIso8601String(),
    'ema20': ema20,
    'ema50': ema50,
    'macd': macd,
    'macd_signal': macdSignal,
    'macd_histogram': macdHistogram,
    'rsi14': rsi14,
    'atr14': atr14,
    'vwap20': vwap20,
    'realized_volatility_annualized_percent': realizedVolatilityPercent,
    'volume_zscore_20': volumeZScore,
    'range_expansion_ratio_20': rangeExpansionRatio,
    'volume_expansion_ratio_20': volumeExpansionRatio,
    'ema_alignment': _emaAlignment(),
  };

  String _emaAlignment() {
    if (ema20 == null || ema50 == null) return 'UNAVAILABLE';
    if (ema20! > ema50!) return 'BULLISH';
    if (ema20! < ema50!) return 'BEARISH';
    return 'FLAT';
  }
}

class MarketFeatures {
  const MarketFeatures({
    required this.snapshotId,
    required this.calculatedAt,
    required this.timeframes,
    required this.basisBps,
    required this.spreadBps,
    required this.fundingAnnualizedPercent,
    required this.unavailable,
  });

  final String snapshotId;
  final DateTime calculatedAt;
  final Map<String, TimeframeFeatures> timeframes;
  final double? basisBps;
  final double? spreadBps;
  final double? fundingAnnualizedPercent;
  final List<String> unavailable;

  bool get hasAbnormalShortTerm => ['5m', '15m'].any((interval) {
    final feature = timeframes[interval];
    return (feature?.rangeExpansionRatio ?? 0) >= 3 ||
        (feature?.volumeExpansionRatio ?? 0) >= 3;
  });

  Map<String, Object?> toJson() => {
    'snapshot_id': snapshotId,
    'calculated_at': calculatedAt.toUtc().toIso8601String(),
    'basis_bps': basisBps,
    'spread_bps': spreadBps,
    'funding_annualized_percent': fundingAnnualizedPercent,
    'short_term_anomaly': hasAbnormalShortTerm,
    'timeframes': {
      for (final entry in timeframes.entries) entry.key: entry.value.toJson(),
    },
    'unavailable': unavailable,
  };
}

class FeatureEngine {
  const FeatureEngine();

  static const _intervalMinutes = {'4h': 240, '1h': 60, '15m': 15, '5m': 5};
  static const _volatilityWindow = 20;
  static const _vwapWindow = 20;

  // Calculate all features from the same immutable market snapshot.
  MarketFeatures calculate(MarketSnapshot snapshot) {
    final calculatedAt = snapshot.buildCompletedAt.toUtc();
    final timeframes = <String, TimeframeFeatures>{};
    for (final entry in snapshot.candlesByInterval.entries) {
      final minutes = _intervalMinutes[entry.key];
      if (minutes == null) continue;
      final closed = entry.value
          .where(
            (candle) => !candle.time
                .toUtc()
                .add(Duration(minutes: minutes))
                .isAfter(calculatedAt),
          )
          .toList();
      timeframes[entry.key] = _timeframe(closed, minutes);
    }
    final ticker = snapshot.ticker;
    final midpoint = (ticker.bestBid + ticker.bestAsk) / 2;
    final funding = ticker.fundingRate;
    return MarketFeatures(
      snapshotId: snapshot.snapshotId,
      calculatedAt: calculatedAt,
      timeframes: timeframes,
      basisBps: ticker.indexPrice > 0
          ? (ticker.markPrice - ticker.indexPrice) / ticker.indexPrice * 10000
          : null,
      spreadBps: midpoint > 0
          ? (ticker.bestAsk - ticker.bestBid) / midpoint * 10000
          : null,
      fundingAnnualizedPercent:
          funding == null || snapshot.instrument.fundingIntervalMinutes <= 0
          ? null
          : funding *
                (525600 / snapshot.instrument.fundingIntervalMinutes) *
                100,
      unavailable: const [
        'oi_change',
        'order_book_imbalance',
        'trade_delta',
        'continuous_cvd',
        'slippage',
      ],
    );
  }

  TimeframeFeatures _timeframe(List<Candle> candles, int intervalMinutes) {
    final closes = candles.map((candle) => candle.close).toList();
    final macd = _macd(closes);
    return TimeframeFeatures(
      closedCandleCount: candles.length,
      asOf: candles.isEmpty ? null : candles.last.time,
      ema20: _ema(closes, 20),
      ema50: _ema(closes, 50),
      macd: macd?.$1,
      macdSignal: macd?.$2,
      macdHistogram: macd?.$3,
      rsi14: _rsi(closes, 14),
      atr14: _atr(candles, 14),
      vwap20: _vwap(candles, _vwapWindow),
      realizedVolatilityPercent: _realizedVolatility(
        closes,
        _volatilityWindow,
        intervalMinutes,
      ),
      volumeZScore: _volumeZScore(candles, _volatilityWindow),
      rangeExpansionRatio: _expansionRatio(
        candles.map((candle) => candle.high - candle.low).toList(),
        _volatilityWindow,
      ),
      volumeExpansionRatio: _expansionRatio(
        candles.map((candle) => candle.volume).toList(),
        _volatilityWindow,
      ),
    );
  }

  double? _ema(List<double> values, int period) {
    final series = _emaSeries(values, period);
    return series.isEmpty ? null : series.last;
  }

  List<double> _emaSeries(List<double> values, int period) {
    if (values.length < period) return const [];
    final seed = values.take(period).reduce((a, b) => a + b) / period;
    final multiplier = 2 / (period + 1);
    final result = <double>[seed];
    for (final value in values.skip(period)) {
      result.add((value - result.last) * multiplier + result.last);
    }
    return result;
  }

  (double, double, double)? _macd(List<double> closes) {
    final fast = _emaSeries(closes, 12);
    final slow = _emaSeries(closes, 26);
    if (slow.isEmpty) return null;
    final offset = 26 - 12;
    final line = <double>[];
    for (var index = 0; index < slow.length; index++) {
      line.add(fast[index + offset] - slow[index]);
    }
    final signal = _emaSeries(line, 9);
    if (signal.isEmpty) return null;
    return (line.last, signal.last, line.last - signal.last);
  }

  double? _rsi(List<double> closes, int period) {
    if (closes.length <= period) return null;
    var gains = 0.0;
    var losses = 0.0;
    for (var index = 1; index <= period; index++) {
      final change = closes[index] - closes[index - 1];
      if (change >= 0) {
        gains += change;
      } else {
        losses -= change;
      }
    }
    var averageGain = gains / period;
    var averageLoss = losses / period;
    for (var index = period + 1; index < closes.length; index++) {
      final change = closes[index] - closes[index - 1];
      averageGain = (averageGain * (period - 1) + math.max(change, 0)) / period;
      averageLoss =
          (averageLoss * (period - 1) + math.max(-change, 0)) / period;
    }
    if (averageLoss == 0) return averageGain == 0 ? 50 : 100;
    return 100 - 100 / (1 + averageGain / averageLoss);
  }

  double? _atr(List<Candle> candles, int period) {
    if (candles.length <= period) return null;
    final ranges = <double>[];
    for (var index = 1; index < candles.length; index++) {
      final candle = candles[index];
      final previousClose = candles[index - 1].close;
      ranges.add(
        math.max(
          candle.high - candle.low,
          math.max(
            (candle.high - previousClose).abs(),
            (candle.low - previousClose).abs(),
          ),
        ),
      );
    }
    var value = ranges.take(period).reduce((a, b) => a + b) / period;
    for (final range in ranges.skip(period)) {
      value = (value * (period - 1) + range) / period;
    }
    return value;
  }

  double? _vwap(List<Candle> candles, int window) {
    if (candles.isEmpty) return null;
    final values = candles.skip(math.max(0, candles.length - window));
    var weighted = 0.0;
    var volume = 0.0;
    for (final candle in values) {
      weighted += (candle.high + candle.low + candle.close) / 3 * candle.volume;
      volume += candle.volume;
    }
    return volume > 0 ? weighted / volume : null;
  }

  double? _realizedVolatility(
    List<double> closes,
    int window,
    int intervalMinutes,
  ) {
    if (closes.length <= window) return null;
    final values = closes.skip(closes.length - window - 1).toList();
    final returns = <double>[];
    for (var index = 1; index < values.length; index++) {
      if (values[index] <= 0 || values[index - 1] <= 0) return null;
      returns.add(math.log(values[index] / values[index - 1]));
    }
    final mean = returns.reduce((a, b) => a + b) / returns.length;
    final variance =
        returns
            .map((value) => math.pow(value - mean, 2).toDouble())
            .reduce((a, b) => a + b) /
        (returns.length - 1);
    final periodsPerYear = 525600 / intervalMinutes;
    return math.sqrt(variance * periodsPerYear) * 100;
  }

  double? _volumeZScore(List<Candle> candles, int window) {
    if (candles.length <= window) return null;
    final history = candles
        .skip(candles.length - window - 1)
        .take(window)
        .map((candle) => candle.volume)
        .toList();
    final mean = history.reduce((a, b) => a + b) / history.length;
    final variance =
        history
            .map((value) => math.pow(value - mean, 2).toDouble())
            .reduce((a, b) => a + b) /
        history.length;
    final deviation = math.sqrt(variance);
    if (deviation == 0) return candles.last.volume == mean ? 0 : null;
    return (candles.last.volume - mean) / deviation;
  }

  double? _expansionRatio(List<double> values, int window) {
    if (values.length <= window) return null;
    final history = values
        .skip(values.length - window - 1)
        .take(window)
        .toList();
    final average = history.reduce((a, b) => a + b) / history.length;
    return average > 0 ? values.last / average : null;
  }
}
