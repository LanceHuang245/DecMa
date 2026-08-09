import 'trading_models.dart';

class InstrumentSnapshot {
  const InstrumentSnapshot({
    required this.symbol,
    required this.contractType,
    required this.status,
    required this.tickSize,
    required this.quantityStep,
    required this.fundingIntervalMinutes,
    required this.observedAt,
  });

  final String symbol;
  final String contractType;
  final String status;
  final double tickSize;
  final double quantityStep;
  final int fundingIntervalMinutes;
  final DateTime observedAt;

  Map<String, Object> toJson() => {
    'symbol': symbol,
    'contract_type': contractType,
    'status': status,
    'tick_size': tickSize,
    'quantity_step': quantityStep,
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
  });

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
  });

  final String snapshotId;
  final String symbol;
  final DateTime buildStartedAt;
  final DateTime buildCompletedAt;
  final InstrumentSnapshot instrument;
  final TickerSnapshot ticker;
  final Map<String, List<Candle>> candlesByInterval;
  final int maxSourceSkewMs;
  final List<String> warnings;

  Map<String, Object?> toJson() => {
    'snapshot_id': snapshotId,
    'symbol': symbol,
    'build_started_at': buildStartedAt.toUtc().toIso8601String(),
    'build_completed_at': buildCompletedAt.toUtc().toIso8601String(),
    'max_source_skew_ms': maxSourceSkewMs,
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
