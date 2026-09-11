import 'package:decma/models/trading_models.dart';
import 'package:decma/services/analysis/candle_integrity_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const interval = Duration(minutes: 15);
  final completedAt = DateTime.utc(2026, 9, 12, 12);

  test('accepts chronological continuous fresh candles with valid OHLCV', () {
    final result = const CandleIntegrityValidator().validate(
      candles: _candles(completedAt),
      interval: interval,
      snapshotCompletedAt: completedAt,
    );

    expect(result.isValid, isTrue);
    expect(result.errors, isEmpty);
  });

  test('rejects duplicate candle timestamps', () {
    final candles = _candles(completedAt);
    final result = const CandleIntegrityValidator().validate(
      candles: [...candles, candles.last],
      interval: interval,
      snapshotCompletedAt: completedAt,
    );

    expect(result.isValid, isFalse);
    expect(result.errors, contains('Duplicate candle timestamp'));
  });

  test('rejects a repeated timestamp later in the candle series', () {
    final candles = _candles(completedAt);
    final result = const CandleIntegrityValidator().validate(
      candles: [candles.first, candles[1], candles.first],
      interval: interval,
      snapshotCompletedAt: completedAt,
    );

    expect(result.errors, contains('Duplicate candle timestamp'));
  });

  test('rejects candles that are not in chronological order', () {
    final candles = _candles(completedAt);
    final result = const CandleIntegrityValidator().validate(
      candles: [candles[1], candles.first, candles.last],
      interval: interval,
      snapshotCompletedAt: completedAt,
    );

    expect(result.errors, contains('Candle timestamps are not chronological'));
  });

  test('rejects a gap between candle opens', () {
    final candles = _candles(completedAt);
    final result = const CandleIntegrityValidator().validate(
      candles: [candles.first, candles.last],
      interval: interval,
      snapshotCompletedAt: completedAt,
    );

    expect(result.errors, contains('Candle interval gap'));
  });

  test('rejects a stale latest closed candle', () {
    final result = const CandleIntegrityValidator().validate(
      candles: _candles(completedAt.subtract(const Duration(minutes: 45))),
      interval: interval,
      snapshotCompletedAt: completedAt,
    );

    expect(result.errors, contains('Latest closed candle is stale'));
  });

  test('rejects non-finite OHLCV values', () {
    final candles = _candles(completedAt);
    final result = const CandleIntegrityValidator().validate(
      candles: [
        Candle(
          time: candles.first.time,
          open: double.nan,
          high: 101,
          low: 99,
          close: 100,
          volume: 10,
        ),
        ...candles.skip(1),
      ],
      interval: interval,
      snapshotCompletedAt: completedAt,
    );

    expect(result.errors, contains('Candle contains a non-finite value'));
  });

  test('rejects a negative candle volume', () {
    final candles = _candles(completedAt);
    final result = const CandleIntegrityValidator().validate(
      candles: [
        Candle(
          time: candles.first.time,
          open: 100,
          high: 101,
          low: 99,
          close: 100,
          volume: -1,
        ),
        ...candles.skip(1),
      ],
      interval: interval,
      snapshotCompletedAt: completedAt,
    );

    expect(result.errors, contains('Candle volume is negative'));
  });

  test('rejects an invalid OHLC relationship', () {
    final candles = _candles(completedAt);
    final result = const CandleIntegrityValidator().validate(
      candles: [
        Candle(
          time: candles.first.time,
          open: 100,
          high: 99,
          low: 98,
          close: 100,
          volume: 10,
        ),
        ...candles.skip(1),
      ],
      interval: interval,
      snapshotCompletedAt: completedAt,
    );

    expect(result.errors, contains('Candle OHLC relationship is invalid'));
  });
}

List<Candle> _candles(DateTime latestOpenAt) => [
  for (var index = 2; index >= 0; index--)
    Candle(
      time: latestOpenAt.subtract(Duration(minutes: index * 15)),
      open: 100,
      high: 101,
      low: 99,
      close: 100,
      volume: 10,
    ),
];
