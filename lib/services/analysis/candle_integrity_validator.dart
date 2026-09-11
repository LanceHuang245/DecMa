import '../../models/trading_models.dart';

class CandleIntegrityResult {
  const CandleIntegrityResult({required this.errors});

  final List<String> errors;

  bool get isValid => errors.isEmpty;
}

class CandleIntegrityValidator {
  const CandleIntegrityValidator();

  // Validate the fixed-interval OHLCV evidence used by deterministic approval.
  CandleIntegrityResult validate({
    required List<Candle> candles,
    required Duration interval,
    required DateTime snapshotCompletedAt,
  }) {
    final errors = <String>[];
    if (candles.isEmpty) {
      return const CandleIntegrityResult(errors: ['No candles available']);
    }

    final timestamps = <int>{};
    for (var index = 0; index < candles.length; index++) {
      final candle = candles[index];
      if (!timestamps.add(candle.time.microsecondsSinceEpoch)) {
        _addOnce(errors, 'Duplicate candle timestamp');
      }
      final values = [
        candle.open,
        candle.high,
        candle.low,
        candle.close,
        candle.volume,
      ];
      if (values.any((value) => !value.isFinite)) {
        _addOnce(errors, 'Candle contains a non-finite value');
      }
      if (candle.volume < 0) {
        _addOnce(errors, 'Candle volume is negative');
      }
      if (candle.open <= 0 ||
          candle.high <= 0 ||
          candle.low <= 0 ||
          candle.close <= 0 ||
          candle.high < candle.low ||
          candle.high < candle.open ||
          candle.high < candle.close ||
          candle.low > candle.open ||
          candle.low > candle.close) {
        _addOnce(errors, 'Candle OHLC relationship is invalid');
      }
      if (index == 0) continue;

      final previous = candles[index - 1];
      if (!candle.time.isAfter(previous.time)) {
        _addOnce(errors, 'Candle timestamps are not chronological');
      } else if (candle.time.difference(previous.time) != interval) {
        _addOnce(errors, 'Candle interval gap');
      }
    }

    Candle? latestClosed;
    for (final candle in candles.reversed) {
      if (!candle.time.add(interval).isAfter(snapshotCompletedAt)) {
        latestClosed = candle;
        break;
      }
    }
    if (latestClosed == null) {
      _addOnce(errors, 'No closed candles available');
    } else if (!latestClosed.time.isAfter(
      snapshotCompletedAt.subtract(interval * 2),
    )) {
      _addOnce(errors, 'Latest closed candle is stale');
    }
    return CandleIntegrityResult(errors: errors);
  }

  void _addOnce(List<String> errors, String error) {
    if (!errors.contains(error)) errors.add(error);
  }
}
