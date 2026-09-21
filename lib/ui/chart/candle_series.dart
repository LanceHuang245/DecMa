import '../../models/trading_models.dart';

/// Owns a chronological, validated candle sequence and applies localized updates.
class CandleSeries {
  CandleSeries([Iterable<Candle> candles = const []]) {
    replaceAll(candles);
  }

  final List<Candle> _items = [];
  int _version = 0;
  int _totalPrepended = 0;

  List<Candle> get items => _items;
  int get version => _version;
  int get totalPrepended => _totalPrepended;
  bool get isEmpty => _items.isEmpty;
  bool get isNotEmpty => _items.isNotEmpty;
  int get length => _items.length;
  Candle get first => _items.first;
  Candle get last => _items.last;

  bool replaceAll(Iterable<Candle> candles) {
    final normalized = _normalize(candles);
    if (_sameSequence(_items, normalized)) return false;
    _items
      ..clear()
      ..addAll(normalized);
    _totalPrepended = 0;
    _version++;
    return true;
  }

  /// Optimizes the polling path: the common case touches only the final candle.
  bool applyLatest(Iterable<Candle> incoming) {
    final normalized = _normalize(incoming);
    if (normalized.isEmpty) return false;
    if (_items.isEmpty) return replaceAll(normalized);

    var changed = false;
    for (final candle in normalized) {
      final timestamp = candle.time.millisecondsSinceEpoch;
      final lastTimestamp = last.time.millisecondsSinceEpoch;
      if (timestamp > lastTimestamp) {
        _items.add(candle);
        changed = true;
      } else if (timestamp == lastTimestamp) {
        if (!_sameCandle(last, candle)) {
          _items[_items.length - 1] = candle;
          changed = true;
        }
      } else {
        final index = _lowerBound(timestamp);
        if (index < _items.length &&
            _items[index].time.millisecondsSinceEpoch == timestamp &&
            !_sameCandle(_items[index], candle)) {
          _items[index] = candle;
          changed = true;
        }
      }
    }
    if (changed) _version++;
    return changed;
  }

  /// Prepends a history page while preserving newer records on duplicate times.
  bool prepend(Iterable<Candle> older) {
    final normalized = _normalize(older);
    if (normalized.isEmpty) return false;
    if (_items.isEmpty) return replaceAll(normalized);

    final cutoff = first.time.millisecondsSinceEpoch;
    final prefix = normalized
        .where((candle) => candle.time.millisecondsSinceEpoch < cutoff)
        .toList(growable: false);
    var changed = prefix.isNotEmpty;

    // A history response may also revise records already present.
    for (final candle in normalized) {
      final timestamp = candle.time.millisecondsSinceEpoch;
      if (timestamp < cutoff) continue;
      final index = _lowerBound(timestamp);
      if (index < _items.length &&
          _items[index].time.millisecondsSinceEpoch == timestamp &&
          !_sameCandle(_items[index], candle)) {
        _items[index] = candle;
        changed = true;
      }
    }
    if (!changed) return false;
    if (prefix.isNotEmpty) {
      _items.insertAll(0, prefix);
      _totalPrepended += prefix.length;
    }
    _version++;
    return true;
  }

  void clear() {
    if (_items.isEmpty) return;
    _items.clear();
    _totalPrepended = 0;
    _version++;
  }

  int _lowerBound(int timestamp) {
    var low = 0;
    var high = _items.length;
    while (low < high) {
      final middle = low + ((high - low) >> 1);
      if (_items[middle].time.millisecondsSinceEpoch < timestamp) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  static List<Candle> _normalize(Iterable<Candle> source) {
    final byTime = <int, Candle>{};
    for (final candle in source) {
      if (!_isValid(candle)) continue;
      byTime[candle.time.millisecondsSinceEpoch] = candle;
    }
    return byTime.values.toList()
      ..sort((left, right) => left.time.compareTo(right.time));
  }

  static bool _isValid(Candle candle) {
    final values = [
      candle.open,
      candle.high,
      candle.low,
      candle.close,
      candle.volume,
    ];
    if (values.any((value) => !value.isFinite) || candle.volume < 0) {
      return false;
    }
    final bodyHigh = candle.open > candle.close ? candle.open : candle.close;
    final bodyLow = candle.open < candle.close ? candle.open : candle.close;
    return candle.high >= bodyHigh && candle.low <= bodyLow && candle.high >= candle.low;
  }

  static bool _sameSequence(List<Candle> left, List<Candle> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (!_sameCandle(left[index], right[index])) return false;
    }
    return true;
  }

  static bool _sameCandle(Candle left, Candle right) =>
      left.time == right.time &&
      left.open == right.open &&
      left.high == right.high &&
      left.low == right.low &&
      left.close == right.close &&
      left.volume == right.volume;
}
