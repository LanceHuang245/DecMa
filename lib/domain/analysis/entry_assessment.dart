import '../models/candle.dart';
import '../models/trade_plan.dart';
import 'candle_integrity_validator.dart';
import '../../l10n/app_languages.dart';

enum EntryState { waiting, ready, paused, realized, invalid, unverified }

class EntryAssessment {
  const EntryAssessment(this.state, this.reason, this.at);
  final EntryState state;
  final String reason;
  final DateTime at;
  bool get terminal =>
      state == EntryState.realized || state == EntryState.invalid;
  String get label => switch (state) {
    EntryState.waiting => appL10n.entryWaiting,
    EntryState.ready => appL10n.entryReady,
    EntryState.paused => appL10n.entryPaused,
    EntryState.realized => appL10n.entryRealized,
    EntryState.invalid => appL10n.entryInvalid,
    EntryState.unverified => appL10n.entryUnverified,
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
    EntryAssessment? previous,
    DateTime? pathStart,
    DateTime? triggerAfter,
    double? entryPrice,
    List<Candle> triggerCandles = const [],
  }) {
    EntryAssessment result(EntryState state, String reason) =>
        EntryAssessment(state, reason, now);
    if (previous?.terminal == true) return previous!;
    if (!plan.isSetup) {
      return result(EntryState.unverified, appL10n.entryNoPlan);
    }
    final low = plan.entryLow, high = plan.entryHigh, stop = plan.stopLoss;
    if (low == null ||
        high == null ||
        stop == null ||
        plan.targets.isEmpty ||
        !price.isFinite ||
        price <= 0) {
      return result(EntryState.unverified, appL10n.entryIncomplete);
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
        return result(EntryState.unverified, appL10n.entryAmbiguousStart);
      }
      if (stopHit && targetHit) {
        return result(EntryState.invalid, appL10n.entryAmbiguousPath);
      }
      if (stopHit) {
        return result(EntryState.invalid, appL10n.entryInvalidBeforeEntry);
      }
      if (targetHit) {
        return result(EntryState.realized, appL10n.entryTargetReached);
      }
    }
    if (invalid(price)) {
      return result(EntryState.invalid, appL10n.entryStructureInvalid);
    }
    if (reached(price)) {
      return result(EntryState.realized, appL10n.entryTargetReached);
    }
    final rule = plan.conditions;
    final ttlMinutes = rule.timeframeMinutes * 3;
    final defaultExpiry = createdAt.add(Duration(minutes: ttlMinutes));
    final expiry =
        rule.expiresAt != null && rule.expiresAt!.isBefore(defaultExpiry)
        ? rule.expiresAt!
        : defaultExpiry;
    if (!now.isBefore(expiry)) {
      return result(EntryState.invalid, appL10n.entryExpired);
    }
    if (!fresh) return result(EntryState.unverified, appL10n.entryStale);
    if (!rule.supported || rule.stopReference != 'LastPrice') {
      return result(EntryState.unverified, appL10n.entryNeedsConfirmation);
    }
    final executable = entryPrice ?? price;
    final chase = plan.maximumChasePrice;
    if (chase == null) {
      return result(EntryState.unverified, appL10n.entryChaseUndefined);
    }
    if (long ? executable > chase : executable < chase) {
      return result(EntryState.paused, appL10n.entryAboveChase);
    }
    if (long ? executable < low : executable > high) {
      return result(EntryState.waiting, appL10n.entryOutsideZone);
    }
    // Reuse a fresh closed signal initially; a risk pause requires a new full bar.
    var triggerStart = triggerAfter;
    if (previous?.state == EntryState.paused &&
        (triggerStart == null || previous!.at.isAfter(triggerStart))) {
      triggerStart = previous!.at;
    }
    for (final candle in relevant) {
      if (long ? candle.high > chase : candle.low < chase) {
        final end = candle.time.add(const Duration(minutes: 1));
        if (triggerStart == null || end.isAfter(triggerStart)) {
          triggerStart = end;
        }
      }
    }
    if (!triggered(plan, triggerCandles, triggerStart, now)) {
      return result(EntryState.waiting, appL10n.entryAwaitTriggerCandle);
    }
    return result(EntryState.ready, appL10n.entryTriggerConfirmed);
  }

  // Exchange-native bars avoid reconstructing long timeframes from minute history.
  bool triggered(
    TradePlan plan,
    List<Candle> candles,
    DateTime? triggerAfter,
    DateTime now,
  ) {
    final rule = plan.conditions;
    if (!rule.supported) return false;
    final width = Duration(minutes: rule.timeframeMinutes);
    final closed =
        candles.where((c) => !c.time.add(width).isAfter(now)).toList()
          ..sort((a, b) => a.time.compareTo(b.time));
    if (closed.isEmpty ||
        !const CandleIntegrityValidator()
            .validate(
              candles: closed,
              interval: width,
              snapshotCompletedAt: now,
            )
            .isValid) {
      return false;
    }
    if (rule.strategy == 'BREAKOUT' &&
        (rule.version < 2 ||
            rule.triggerType !=
                (plan.decision == 'LONG_SETUP'
                    ? 'CLOSE_ABOVE'
                    : 'CLOSE_BELOW'))) {
      return false;
    }
    if (rule.version >= 2 &&
        (rule.strategy == 'BREAKOUT_RETEST' &&
                rule.triggerType != 'BREAKOUT_RETEST' ||
            rule.strategy == 'MEAN_REVERSION' &&
                rule.triggerType != 'TOUCH_ZONE_AND_CLOSE_INSIDE')) {
      return false;
    }
    final bar = closed.last;
    // Initial signals may predate analysis, but signals after a pause must not.
    if (triggerAfter != null && bar.time.isBefore(triggerAfter) ||
        now.difference(bar.time.add(width)) >= width) {
      return false;
    }
    // A direct breakout needs a crossing, not a close already beyond the level.
    if (rule.strategy == 'BREAKOUT') {
      if (closed.length < 2) return false;
      final previousClose = closed[closed.length - 2].close;
      if (plan.decision == 'LONG_SETUP'
          ? previousClose > rule.triggerPrice!
          : previousClose < rule.triggerPrice!) {
        return false;
      }
    }
    switch (rule.triggerType) {
      case 'CLOSE_ABOVE':
        return bar.close > rule.triggerPrice! &&
            _volumeConfirmed(rule.volumeMultiple, closed);
      case 'CLOSE_BELOW':
        return bar.close < rule.triggerPrice! &&
            _volumeConfirmed(rule.volumeMultiple, closed);
      case 'BREAKOUT_RETEST':
        if (rule.version < 2 || rule.triggerPrice == null) return false;
        final level = rule.triggerPrice!;
        final long = plan.decision == 'LONG_SETUP';
        var broke = false;
        for (final c in closed.where(
          (c) => triggerAfter == null || !c.time.isBefore(triggerAfter),
        )) {
          final holds = long ? c.close > level : c.close < level;
          final touches = long ? c.low <= level : c.high >= level;
          if (identical(c, bar) && broke && holds && touches) return true;
          if (!holds) {
            broke = false;
            continue;
          }
          if (long ? c.open <= level : c.open >= level) broke = true;
        }
        return false;
      case 'TOUCH_ZONE_AND_CLOSE_INSIDE':
        if (rule.version < 2 ||
            plan.entryLow == null ||
            plan.entryHigh == null) {
          return false;
        }
        final touch = plan.decision == 'LONG_SETUP'
            ? bar.low <= plan.entryLow!
            : bar.high >= plan.entryHigh!;
        return touch &&
            bar.close >= plan.entryLow! &&
            bar.close <= plan.entryHigh!;
      case 'VOLUME_ABOVE_MULTIPLE':
        // Legacy volume-only plans need a directional price condition before approval.
        if (rule.triggerPrice == null) return false;
        final direction = plan.decision == 'LONG_SETUP'
            ? bar.close > rule.triggerPrice!
            : bar.close < rule.triggerPrice!;
        return direction && _volumeConfirmed(rule.volumeMultiple, closed);
      default:
        return false;
    }
  }

  // Volume supplements a directional trigger and requires a contiguous baseline.
  bool _volumeConfirmed(double? multiple, List<Candle> closed) {
    if (multiple == null) return true;
    if (closed.length < 21) return false;
    final bar = closed.last;
    final history = closed.sublist(closed.length - 21, closed.length - 1);
    final mean = history.fold<double>(0, (sum, c) => sum + c.volume) / 20;
    return mean > 0 && bar.volume >= mean * multiple;
  }
}
