import 'package:decma/domain/models/plan_conditions.dart';
import 'package:decma/domain/models/candle.dart';
import 'package:decma/domain/models/trade_plan.dart';
import 'package:decma/domain/analysis/entry_assessment.dart';
import 'package:flutter_test/flutter_test.dart';

final created = DateTime.utc(2026, 10, 1, 10);

TradePlan setup({bool long = true}) => TradePlan(
  decision: long ? 'LONG_SETUP' : 'SHORT_SETUP',
  summary: 'test',
  parsedJson: '{}',
  symbol: 'BTCUSDT',
  entryLow: 99,
  entryHigh: 101,
  maximumChasePrice: long ? 102 : 98,
  stopLoss: long ? 95 : 105,
  targets: [TradeTarget(price: long ? 110 : 90)],
  conditions: PlanConditions(
    triggerType: long ? 'CLOSE_ABOVE' : 'CLOSE_BELOW',
    triggerPrice: 100,
    timeframeMinutes: 5,
  ),
);

Candle bar(
  int minute, {
  double open = 100,
  double high = 101,
  double low = 99,
  double close = 100,
}) => Candle(
  time: created.add(Duration(minutes: minute)),
  open: open,
  high: high,
  low: low,
  close: close,
  volume: 10,
);

void main() {
  for (final long in [true, false]) {
    test('TP1 before entry stays realized after pullback, long=$long', () {
      final evaluator = const EntryEvaluator();
      final plan = setup(long: long);
      final result = evaluator.evaluate(
        plan: plan,
        createdAt: created,
        now: created.add(const Duration(minutes: 1)),
        path: [],
        price: long ? 110 : 90,
        fresh: true,
      );
      expect(result.state, EntryState.realized);
      final later = evaluator.evaluate(
        plan: plan,
        createdAt: created,
        now: created.add(const Duration(minutes: 2)),
        path: [],
        price: 100,
        fresh: true,

        previous: result,
      );
      expect(later.state, EntryState.realized);
    });

    test('chase suspends and does not cancel, long=$long', () {
      final evaluator = const EntryEvaluator();
      final result = evaluator.evaluate(
        plan: setup(long: long),
        createdAt: created,
        now: created.add(const Duration(minutes: 1)),
        path: [],
        price: long ? 103 : 97,
        fresh: true,
      );
      expect(result.state, EntryState.paused);
      final later = evaluator.evaluate(
        plan: setup(long: long),
        createdAt: created,
        now: created.add(const Duration(minutes: 2)),
        path: [],
        price: 100,
        fresh: true,

        previous: result,
      );
      expect(later.state, EntryState.waiting);
    });
  }

  test('same minute invalidation and target never implies profitable fill', () {
    final result = const EntryEvaluator().evaluate(
      plan: setup(),
      createdAt: created,
      now: created.add(const Duration(minutes: 2)),
      path: [bar(1, high: 112, low: 94)],
      price: 100,
      fresh: true,
    );
    expect(result.state, EntryState.invalid);
    expect(result.reason, contains('不确定'));
  });

  test('native trigger bars must be closed and start after creation', () {
    final candles = [bar(0, close: 100.5)];
    const e = EntryEvaluator();
    final now = created.add(const Duration(minutes: 5));
    expect(e.triggered(setup(), candles, created, now), true);
    expect(e.triggered(setup(), candles.sublist(1), created, now), false);
    expect(
      e.triggered(
        setup(),
        candles,
        created.add(const Duration(seconds: 1)),
        now,
      ),
      false,
    );
  });

  test('volume confirmation requires 20 contiguous closed baseline bars', () {
    const minutes = 15;
    final plan = TradePlan(
      decision: 'LONG_SETUP',
      summary: '',
      parsedJson: '{}',
      conditions: PlanConditions(
        triggerType: 'VOLUME_ABOVE_MULTIPLE',
        triggerPrice: 99,
        volumeMultiple: 2,
        timeframeMinutes: minutes,
      ),
    );
    final bars = List.generate(
      21,
      (i) => Candle(
        time: created.add(Duration(minutes: (i - 20) * minutes)),
        open: 100,
        high: 101,
        low: 99,
        close: 100,
        volume: i == 20 ? 25 : 10,
      ),
    );
    final now = created.add(Duration(minutes: minutes));
    const evaluator = EntryEvaluator();
    expect(evaluator.triggered(plan, bars, created, now), true);
    expect(evaluator.triggered(plan, bars.sublist(1), created, now), false);
    expect(
      evaluator.triggered(
        plan,
        bars,
        created,
        now.subtract(const Duration(seconds: 1)),
      ),
      false,
    );
    final missing = [...bars]..removeAt(10);
    expect(evaluator.triggered(plan, missing, created, now), false);
  });

  TradePlan conditional(String trigger, {bool long = true, int version = 2}) =>
      TradePlan(
        decision: long ? 'LONG_SETUP' : 'SHORT_SETUP',
        summary: '',
        parsedJson: '{}',
        entryLow: 99,
        entryHigh: 101,
        stopLoss: long ? 95 : 105,
        maximumChasePrice: long ? 103 : 97,
        targets: [TradeTarget(price: long ? 110 : 90)],
        conditions: PlanConditions(
          version: version,
          strategy: trigger == 'BREAKOUT_RETEST'
              ? 'BREAKOUT_RETEST'
              : 'MEAN_REVERSION',
          triggerType: trigger,
          triggerPrice: trigger == 'VOLUME_ABOVE_MULTIPLE' ? null : 100,
          volumeMultiple: trigger == 'VOLUME_ABOVE_MULTIPLE' ? 2 : null,
          timeframeMinutes: 5,
        ),
      );
  for (final long in [true, false]) {
    test('breakout retest requires distinct ordered bars, long=$long', () {
      final p = conditional('BREAKOUT_RETEST', long: long);
      final breakout = bar(0, close: long ? 100.5 : 99.5);
      final retest = bar(
        5,
        open: long ? 100.5 : 99.5,
        close: long ? 100.5 : 99.5,
      );
      const evaluator = EntryEvaluator();
      expect(
        evaluator.triggered(
          p,
          [breakout],
          created,
          created.add(const Duration(minutes: 5)),
        ),
        false,
      );
      expect(
        evaluator.triggered(
          p,
          [breakout, retest],
          created,
          created.add(const Duration(minutes: 10)),
        ),
        true,
      );
      expect(
        evaluator.triggered(
          p,
          [
            breakout,
            bar(5, close: long ? 99.5 : 100.5),
            bar(10, open: long ? 100.5 : 99.5, close: long ? 100.5 : 99.5),
          ],
          created,
          created.add(const Duration(minutes: 15)),
        ),
        false,
      );
      expect(
        evaluator.triggered(
          p,
          [
            breakout,
            bar(10, open: long ? 100.5 : 99.5, close: long ? 100.5 : 99.5),
          ],
          created,
          created.add(const Duration(minutes: 15)),
        ),
        false,
      );
    });
    test('range reentry must touch its directional boundary, long=$long', () {
      final p = conditional('TOUCH_ZONE_AND_CLOSE_INSIDE', long: long);
      const evaluator = EntryEvaluator();
      final now = created.add(const Duration(minutes: 5));
      expect(
        evaluator.triggered(p, [bar(0, high: 100.5, low: 99.5)], created, now),
        false,
      );
      expect(evaluator.triggered(p, [bar(0)], created, now), true);
      expect(
        evaluator.triggered(
          conditional('TOUCH_ZONE_AND_CLOSE_INSIDE', long: long, version: 1),
          [bar(0)],
          created,
          now,
        ),
        false,
      );
    });
  }
  test('volume without directional price confirmation never triggers', () {
    expect(
      const EntryEvaluator().triggered(
        conditional('VOLUME_ABOVE_MULTIPLE'),
        [bar(0)],
        created,
        created.add(const Duration(minutes: 5)),
      ),
      false,
    );
  });
  test('a four-hour trigger is not expired by an unrelated three-hour cap', () {
    final plan = TradePlan(
      decision: 'LONG_SETUP',
      summary: '',
      parsedJson: '{}',
      symbol: 'BTCUSDT',
      entryLow: 99,
      entryHigh: 101,
      stopLoss: 95,
      maximumChasePrice: 102,
      targets: const [TradeTarget(price: 110)],
      conditions: const PlanConditions(
        triggerType: 'CLOSE_ABOVE',
        triggerPrice: 100,
        timeframeMinutes: 240,
      ),
    );
    final result = const EntryEvaluator().evaluate(
      plan: plan,
      createdAt: created,
      now: created.add(const Duration(hours: 6)),
      path: [],
      triggerCandles: [bar(120, close: 100.5)],
      price: 101,
      fresh: true,
    );
    expect(result.state, EntryState.ready);
  });
}
