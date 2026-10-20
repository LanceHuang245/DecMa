import 'package:decma/domain/analysis/reference_entry.dart';
import 'package:decma/domain/models/market_snapshot.dart';
import 'package:decma/domain/models/trade_plan.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime.utc(2026, 10, 20, 12);
InstrumentSnapshot instrument({int interval = 480}) => InstrumentSnapshot(
  symbol: 'BTCUSDT',
  contractType: 'LinearPerpetual',
  status: 'Trading',
  tickSize: 0.1,
  quantityStep: 0.001,
  minimumOrderQuantity: 0.001,
  maximumOrderQuantity: 100,
  minimumNotionalValue: 5,
  fundingIntervalMinutes: interval,
  observedAt: now,
);
TradePlan plan(bool long) => TradePlan(
  decision: long ? 'LONG_SETUP' : 'SHORT_SETUP',
  summary: '',
  parsedJson: '{}',
  entryLow: 99,
  entryHigh: 101,
  stopLoss: long ? 95 : 105,
  maximumChasePrice: long ? 109 : 91,
  targets: [TradeTarget(price: long ? 110 : 90)],
);
TickerSnapshot quote({double price = 100, double rate = 0, DateTime? next}) =>
    TickerSnapshot(
      symbol: 'BTCUSDT',
      lastPrice: price,
      markPrice: price,
      indexPrice: price,
      bestBid: price - 0.1,
      bestAsk: price + 0.1,
      openInterest: 1,
      fundingRate: rate,
      nextFundingAt: next ?? now.add(const Duration(hours: 4)),
      observedAt: now,
    );

void main() {
  for (final long in [true, false]) {
    test('executable quote, fees and tick boundary, long=$long', () {
      final result = ReferenceEntry.calculate(
        plan(long),
        quote(),
        instrument(),
        now,
      )!;
      expect(result.price, long ? 100.1 : 99.9);
      final target = long ? 109.9 : 90.1;
      final stop = long ? 94.9 : 105.1;
      final sign = long ? 1 : -1;
      final gain =
          sign * (target - result.price) - (target + result.price) * 0.00055;
      final loss =
          sign * (result.price - stop) + (stop + result.price) * 0.00055;
      expect(result.netRewardRisk, closeTo(gain / loss, 1e-10));
      // The selected tick qualifies, while the next adverse tick fails the 1:1 test.
      double rr(double p) =>
          (sign * (target - p) - (target + p) * 0.00055) /
          (sign * (p - stop) + (stop + p) * 0.00055);
      expect(rr(result.maximumPrice), greaterThanOrEqualTo(1));
      expect(rr(result.maximumPrice + sign * 0.1), lessThan(1));
    });
    test('funding receipts do not loosen eligibility, long=$long', () {
      final base = ReferenceEntry.calculate(
        plan(long),
        quote(),
        instrument(interval: 60),
        now,
      )!;
      final receipt = ReferenceEntry.calculate(
        plan(long),
        quote(
          rate: long ? -0.01 : 0.01,
          next: now.add(const Duration(minutes: 30)),
        ),
        instrument(interval: 60),
        now,
      )!;
      final payment = ReferenceEntry.calculate(
        plan(long),
        quote(
          rate: long ? 0.01 : -0.01,
          next: now.add(const Duration(minutes: 30)),
        ),
        instrument(interval: 60),
        now,
      )!;
      expect(receipt.netRewardRisk, base.netRewardRisk);
      expect(payment.netRewardRisk, lessThan(base.netRewardRisk));
      final target = long ? 109.9 : 90.1, stop = long ? 94.9 : 105.1;
      final sign = long ? 1 : -1;
      final gain =
          sign * (target - base.price) -
          (target + base.price) * 0.00055 -
          base.price * 0.03;
      final loss =
          sign * (base.price - stop) +
          (stop + base.price) * 0.00055 +
          base.price * 0.03;
      expect(payment.netRewardRisk, closeTo(gain / loss, 1e-10));
    });
  }
  test('a quote beyond the stop cannot produce non-finite stored metrics', () {
    expect(
      ReferenceEntry.calculate(plan(true), quote(price: 90), instrument(), now),
      isNull,
    );
  });
}
