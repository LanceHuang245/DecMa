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

  test('a fresh trigger can be assessed without account or risk setup', () {
    final candles = [bar(0, close: 100.5)];
    final result = const EntryEvaluator().evaluate(
      plan: setup(),
      createdAt: created,
      now: created.add(const Duration(minutes: 5)),
      path: [],
      triggerCandles: candles,
      price: 101,
      fresh: true,
    );
    expect(result.state, EntryState.ready);
  });
  for (final minutes in [5, 15, 60, 240]) {
    test('native $minutes-minute volume trigger uses 20 prior bars', () {
      final plan = TradePlan(
        decision: 'LONG_SETUP',
        summary: '',
        parsedJson: '{}',
        conditions: PlanConditions(
          triggerType: 'VOLUME_ABOVE_MULTIPLE',
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
  }

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
