import 'dart:math' as math;

import '../models/market_snapshot.dart';
import '../models/trade_plan.dart';

// Public cost scenarios describe market entry quality without account or size inputs.
class ReferenceEntry {
  const ReferenceEntry(this.price, this.netRewardRisk, this.maximumPrice);
  final double price, netRewardRisk, maximumPrice;
  static const feeRate = 0.00055;
  static const policyVersion = 1;

  static ReferenceEntry? calculate(
    TradePlan plan,
    TickerSnapshot quote,
    InstrumentSnapshot instrument,
    DateTime now,
  ) {
    final stop = plan.stopLoss;
    final chase = plan.maximumChasePrice;
    final rate = quote.fundingRate;
    final next = quote.nextFundingAt;
    if (stop == null ||
        chase == null ||
        plan.targets.isEmpty ||
        rate == null ||
        !rate.isFinite ||
        next == null ||
        next.isBefore(now) ||
        instrument.fundingIntervalMinutes <= 0 ||
        instrument.tickSize <= 0 ||
        !instrument.tickSize.isFinite ||
        ![quote.bestBid, quote.bestAsk].every((p) => p.isFinite && p > 0) ||
        quote.bestAsk < quote.bestBid) {
      return null;
    }
    final long = plan.decision == 'LONG_SETUP';
    final sign = long ? 1.0 : -1.0;
    final price = long ? quote.bestAsk : quote.bestBid;
    final halfSpread = (quote.bestAsk - quote.bestBid) / 2;
    final targetExit = plan.targets.first.price - sign * halfSpread;
    final stopExit = stop - sign * halfSpread;
    final end = now.add(const Duration(hours: 3));
    final count = next.isAfter(end)
        ? 0
        : 1 +
              end.difference(next).inMinutes ~/
                  instrument.fundingIntervalMinutes;
    final funding = math.max(0.0, rate * sign) * count;
    double rr(double entry) {
      final gain =
          sign * (targetExit - entry) -
          entry * (feeRate + funding) -
          targetExit * feeRate;
      final loss =
          sign * (entry - stopExit) +
          entry * (feeRate + funding) +
          stopExit * feeRate;
      return loss > 0 ? gain / loss : double.negativeInfinity;
    }

    final netRewardRisk = rr(price);
    if (!netRewardRisk.isFinite || targetExit <= 0 || stopExit <= 0) {
      return null;
    }
    // Solve gain >= loss analytically, then round toward the safer entry price.
    final boundary =
        (sign * (targetExit + stopExit) - feeRate * (targetExit + stopExit)) /
        (2 * (sign + feeRate + funding));
    if (!boundary.isFinite || boundary <= 0) return null;
    final tick = instrument.tickSize;
    final rounded = long
        ? (boundary / tick).floor() * tick
        : (boundary / tick).ceil() * tick;
    final maximum = long ? math.min(chase, rounded) : math.max(chase, rounded);
    return ReferenceEntry(price, netRewardRisk, maximum);
  }
}
