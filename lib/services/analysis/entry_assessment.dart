import '../../models/trading_models.dart';

enum EntryState { waiting, ready, paused, realized, invalid, unverified }

class EntryAssessment {
  const EntryAssessment(this.state, this.reason, this.at);
  final EntryState state;
  final String reason;
  final DateTime at;
  bool get terminal =>
      state == EntryState.realized || state == EntryState.invalid;
  String get label => switch (state) {
    EntryState.waiting => '等待触发',
    EntryState.ready => '触发已确认',
    EntryState.paused => '等待回踩',
    EntryState.realized => '机会已兑现',
    EntryState.invalid => '已失效',
    EntryState.unverified => '等待确认',
  };
}

// A direction is immutable; its current entry eligibility is checked separately.
class EntryEvaluator {
  const EntryEvaluator();

  EntryAssessment evaluate({
    required TradePlan plan,
    required DateTime createdAt,
    required DateTime now,
    required List<Candle> path,
    required double price,
    required bool fresh,
    required Duration holding,
    EntryAssessment? previous,
    DateTime? pathStart,
  }) {
    EntryAssessment result(EntryState state, String reason) =>
        EntryAssessment(state, reason, now);
    if (previous?.terminal == true) return previous!;
    if (!plan.isSetup) return result(EntryState.unverified, '没有可核验的开仓计划');
    final low = plan.entryLow, high = plan.entryHigh, stop = plan.stopLoss;
    if (low == null ||
        high == null ||
        stop == null ||
        plan.targets.isEmpty ||
        !price.isFinite ||
        price <= 0) {
      return result(EntryState.unverified, '价格或目标不完整');
    }
    final long = plan.decision == 'LONG_SETUP';
    final firstTarget = plan.targets.first.price;
    final cancellation = plan.conditions.cancellationPrice;
    bool reached(double value) =>
        long ? value >= firstTarget : value <= firstTarget;
    bool invalid(double value) =>
        (plan.conditions.stopReference == 'LastPrice' &&
            (long ? value <= stop : value >= stop)) ||
        (cancellation != null &&
            (long ? value <= cancellation : value >= cancellation));
    // Inspect the analysis-time path, not only the quote visible at completion.
    final start = pathStart ?? createdAt;
    final relevant = path
        .where(
          (c) =>
              c.time.add(const Duration(minutes: 1)).isAfter(start) &&
              !c.time.isAfter(now),
        )
        .toList();
    for (final candle in relevant) {
      final targetHit = reached(long ? candle.high : candle.low);
      final stopHit = invalid(long ? candle.low : candle.high);
      if (candle.time.isBefore(start) && (targetHit || stopHit)) {
        return result(EntryState.unverified, '起始分钟内事件时间不明确，请重新分析');
      }
      if (stopHit && targetHit) {
        return result(EntryState.invalid, '同分钟触及失效与目标，路径不确定');
      }
      if (stopHit) return result(EntryState.invalid, '入场前结构已失效');
      if (targetHit) return result(EntryState.realized, '未入场已到 TP1，需要新计划');
    }
    if (invalid(price)) return result(EntryState.invalid, '结构已失效');
    if (reached(price)) return result(EntryState.realized, '未入场已到 TP1，需要新计划');
    final rule = plan.conditions;
    final ttlMinutes = (rule.timeframeMinutes * 3).clamp(1, holding.inMinutes);
    final defaultExpiry = createdAt.add(Duration(minutes: ttlMinutes));
    final expiry =
        rule.expiresAt != null && rule.expiresAt!.isBefore(defaultExpiry)
        ? rule.expiresAt!
        : defaultExpiry;
    if (!now.isBefore(expiry)) return result(EntryState.invalid, '候选计划已过期');
    if (!fresh) return result(EntryState.unverified, '行情已过期或价格路径不完整');
    if (!rule.supported || rule.stopReference != 'LastPrice') {
      return result(EntryState.unverified, '仍需确认入场条件，以最新行情为准');
    }
    final chase = plan.maximumChasePrice;
    if (chase == null) return result(EntryState.unverified, '最大追价未定义');
    if (long ? price > chase : price < chase) {
      return result(EntryState.paused, '超过最大追价，等待回踩并重新核验');
    }
    if (long ? price < low : price > high) {
      return result(EntryState.waiting, '尚未进入允许开仓区域');
    }
    var triggerStart = createdAt;
    for (final candle in relevant) {
      if (long ? candle.high > chase : candle.low < chase) {
        final end = candle.time.add(const Duration(minutes: 1));
        if (end.isAfter(triggerStart)) triggerStart = end;
      }
    }
    if (!triggered(plan, path, triggerStart, now)) {
      return result(EntryState.waiting, '等待新的完整触发 K 线');
    }
    return result(EntryState.ready, '当前参考行情的入场触发已确认；价格变化后需要重新检查');
  }

  // Aggregate only complete minutes; partial candles cannot prove a close trigger.
  bool triggered(
    TradePlan plan,
    List<Candle> minutes,
    DateTime created,
    DateTime now,
  ) {
    final rule = plan.conditions;
    if (!rule.supported) return false;
    final groups = <int, List<Candle>>{};
    final width = rule.timeframeMinutes * 60000;
    for (final c in minutes) {
      final key = c.time.millisecondsSinceEpoch ~/ width * width;
      (groups[key] ??= []).add(c);
    }
    final keys = groups.keys.toList()..sort();
    for (final key in keys.reversed) {
      final open = DateTime.fromMillisecondsSinceEpoch(key, isUtc: true);
      final end = open.add(Duration(minutes: rule.timeframeMinutes));
      if (open.isBefore(created) || end.isAfter(now)) continue;
      final bars = groups[key]!..sort((a, b) => a.time.compareTo(b.time));
      if (bars.length != rule.timeframeMinutes ||
          bars.asMap().entries.any(
            (e) => e.value.time != open.add(Duration(minutes: e.key)),
          )) {
        continue;
      }
      final close = bars.last.close;
      if (rule.triggerType == 'CLOSE_ABOVE') return close > rule.triggerPrice!;
      if (rule.triggerType == 'CLOSE_BELOW') return close < rule.triggerPrice!;
      if (rule.triggerType == 'TOUCH_ZONE_AND_CLOSE_INSIDE') {
        return bars.any(
              (c) => c.low <= plan.entryHigh! && c.high >= plan.entryLow!,
            ) &&
            close >= plan.entryLow! &&
            close <= plan.entryHigh!;
      }
      final history = keys.where((k) => k < key).toList();
      if (history.length < 20) return false;
      final previous = history.sublist(history.length - 20);
      if (previous.first != key - 20 * width ||
          previous.asMap().entries.any(
            (e) => e.value != key - (20 - e.key) * width,
          ) ||
          previous.any(
            (k) =>
                groups[k]!.length != rule.timeframeMinutes ||
                groups[k]!.asMap().entries.any(
                  (e) =>
                      e.value.time.millisecondsSinceEpoch !=
                          k + e.key * 60000 ||
                      !e.value.volume.isFinite ||
                      e.value.volume < 0,
                ),
          )) {
        return false;
      }
      final mean =
          previous
              .map((k) => groups[k]!.fold<double>(0, (s, c) => s + c.volume))
              .reduce((a, b) => a + b) /
          20;
      return mean > 0 &&
          bars.fold<double>(0, (s, c) => s + c.volume) >=
              mean * rule.volumeMultiple!;
    }
    return false;
  }
}
