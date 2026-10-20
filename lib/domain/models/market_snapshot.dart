import 'candle.dart';

class InstrumentSnapshot {
  const InstrumentSnapshot({
    required this.symbol,
    required this.contractType,
    required this.status,
    required this.tickSize,
    required this.quantityStep,
    required this.minimumOrderQuantity,
    required this.maximumOrderQuantity,
    required this.minimumNotionalValue,
    required this.fundingIntervalMinutes,
    required this.observedAt,
  });

  final String symbol;
  final String contractType;
  final String status;
  final double tickSize;
  final double quantityStep;
  final double minimumOrderQuantity;
  final double maximumOrderQuantity;
  final double minimumNotionalValue;
  final int fundingIntervalMinutes;
  final DateTime observedAt;

  Map<String, Object> toJson() => {
    'symbol': symbol,
    'contract_type': contractType,
    'status': status,
    'tick_size': tickSize,
    'quantity_step': quantityStep,
    'min_order_qty': minimumOrderQuantity,
    'max_order_qty': maximumOrderQuantity,
    'min_notional_value': minimumNotionalValue,
    'funding_interval_minutes': fundingIntervalMinutes,
    'observed_at': observedAt.toUtc().toIso8601String(),
  };
}

class TickerSnapshot {
  const TickerSnapshot({
    required this.symbol,
    required this.lastPrice,
    required this.markPrice,
    required this.indexPrice,
    required this.bestBid,
    required this.bestAsk,
    required this.openInterest,
    required this.fundingRate,
    required this.observedAt,
    this.nextFundingAt,
  });

  final DateTime? nextFundingAt;
  final String symbol;
  final double lastPrice;
  final double markPrice;
  final double indexPrice;
  final double bestBid;
  final double bestAsk;
  final double? openInterest;
  final double? fundingRate;
  final DateTime observedAt;

  Map<String, Object?> toJson() => {
    'symbol': symbol,
    'last_price': lastPrice,
    'mark_price': markPrice,
    'index_price': indexPrice,
    'best_bid': bestBid,
    'best_ask': bestAsk,
    'open_interest': openInterest,
    'funding_rate': fundingRate,
    'next_funding_at': nextFundingAt?.toUtc().toIso8601String(),
    'observed_at': observedAt.toUtc().toIso8601String(),
  };
}

class MarketSnapshot {
  const MarketSnapshot({
    required this.snapshotId,
    required this.symbol,
    required this.buildStartedAt,
    required this.buildCompletedAt,
    required this.instrument,
    required this.ticker,
    required this.candlesByInterval,
    required this.maxSourceSkewMs,
    required this.warnings,
    this.openInterestHistory = const [],
  });

  final List<({DateTime at, double value})> openInterestHistory;
  final String snapshotId;
  final String symbol;
  final DateTime buildStartedAt;
  final DateTime buildCompletedAt;
  final InstrumentSnapshot instrument;
  final TickerSnapshot ticker;
  final Map<String, List<Candle>> candlesByInterval;
  final int maxSourceSkewMs;
  final List<String> warnings;

  // Compare exact five-minute samples; stale or missing intervals stay unavailable.
  double? _oiChange(Duration window) {
    if (openInterestHistory.isEmpty) return null;
    final last = openInterestHistory.last;
    if (buildCompletedAt.difference(last.at) > const Duration(minutes: 10) ||
        last.at.isAfter(buildCompletedAt)) {
      return null;
    }
    final first = openInterestHistory
        .where((p) => p.at == last.at.subtract(window))
        .firstOrNull;
    if (first == null || first.value <= 0) return null;
    final samples = openInterestHistory
        .where((p) => !p.at.isBefore(first.at) && !p.at.isAfter(last.at))
        .toList();
    if (samples.length != window.inMinutes ~/ 5 + 1) return null;
    for (var i = 0; i < samples.length; i++) {
      if (samples[i].at != first.at.add(Duration(minutes: i * 5)) ||
          !samples[i].value.isFinite ||
          samples[i].value < 0) {
        return null;
      }
    }
    return (last.value / first.value - 1) * 100;
  }

  Map<String, Object?> toJson() => {
    'snapshot_id': snapshotId,
    'symbol': symbol,
    'build_started_at': buildStartedAt.toUtc().toIso8601String(),
    'build_completed_at': buildCompletedAt.toUtc().toIso8601String(),
    'max_source_skew_ms': maxSourceSkewMs,
    'oi_history': [
      for (final point in openInterestHistory)
        {'at': point.at.toUtc().toIso8601String(), 'value': point.value},
    ],
    'oi_change_15m_percent': _oiChange(const Duration(minutes: 15)),
    'oi_change_1h_percent': _oiChange(const Duration(hours: 1)),
    'quality': warnings.isEmpty ? 'VALID' : 'DEGRADED',
    'warnings': warnings,
    'instrument': instrument.toJson(),
    'ticker': ticker.toJson(),
    'timeframes': {
      for (final entry in candlesByInterval.entries)
        entry.key: {
          'candle_count': entry.value.length,
          'first_open_at': entry.value.isEmpty
              ? null
              : entry.value.first.time.toUtc().toIso8601String(),
          'last_open_at': entry.value.isEmpty
              ? null
              : entry.value.last.time.toUtc().toIso8601String(),
        },
    },
  };
}
