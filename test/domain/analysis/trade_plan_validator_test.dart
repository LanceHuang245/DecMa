import 'package:decma/domain/models/trade_plan.dart';
import 'package:decma/domain/analysis/trade_plan_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const validator = TradePlanValidator();

  test('accepts a structurally valid long setup', () {
    final result = validator.validate(
      _plan(
        decision: 'LONG_SETUP',
        low: 100,
        high: 101,
        stop: 98,
        targets: const [105, 108],
      ),
      tickSize: 0.1,
    );

    expect(result.errors, isEmpty);
  });

  test('rejects a long stop inside the entry zone', () {
    final result = validator.validate(
      _plan(
        decision: 'LONG_SETUP',
        low: 100,
        high: 101,
        stop: 100.5,
        targets: const [105],
      ),
    );

    expect(result.errors, contains('多头止损必须低于开仓区'));
  });

  test('rejects reversed short targets and invalid tick size', () {
    final result = validator.validate(
      _plan(
        decision: 'SHORT_SETUP',
        low: 100,
        high: 101,
        stop: 103,
        targets: const [95.03, 97],
      ),
      tickSize: 0.1,
    );

    expect(result.errors, contains('空头止盈必须按价格降序排列'));
    expect(result.warnings, contains(contains('Tick Size')));
  });

  test('extra targets and precision issues only warn', () {
    final result = validator.validate(
      _plan(
        decision: 'LONG_SETUP',
        low: 100.03,
        high: 101,
        stop: 98,
        targets: const [105, 106, 107, 108],
      ),
      tickSize: 0.1,
    );
    expect(result.isValid, true);
    expect(result.warnings, contains(contains('前三档')));
    expect(result.warnings, contains(contains('Tick Size')));
  });

  test('invalid price remains fatal even with auxiliary warnings', () {
    final result = validator.validate(
      _plan(
        decision: 'LONG_SETUP',
        low: 100,
        high: 101,
        stop: double.nan,
        targets: const [105],
      ),
    );
    expect(result.isValid, false);
  });

  test('non-setup decisions never become chart setups', () {
    final plan = _plan(
      decision: 'WAIT',
      low: 100,
      high: 101,
      stop: 98,
      targets: const [105],
    );
    final result = validator.validate(plan);

    expect(result.isValid, isTrue);
    expect(plan.isSetup, isFalse);
    expect(result.warnings, isNotEmpty);
  });

  test('WAIT exposes only a valid tick-aligned candidate zone', () {
    final valid = validator.validate(
      _plan(
        decision: 'WAIT',
        low: 100,
        high: 101,
        stop: 98,
        targets: const [105],
      ),
      tickSize: 0.1,
    );
    final invalid = validator.validate(
      _plan(decision: 'WAIT', low: 101, high: 100, stop: 98, targets: const []),
      tickSize: 0.1,
    );

    expect(valid.canDrawWaitZone, isTrue);
    expect(valid.warnings, contains('WAIT 仅保留候选等待区，其他价格标记已忽略'));
    expect(invalid.canDrawWaitZone, isFalse);
    expect(invalid.warnings, contains('候选等待区无效，价格标记已忽略'));
  });

  test('parses take-profit prices from the simplified JSON', () {
    final plan = TradePlan.fromResponse('''
{"request":{"symbol":"BTCUSDT"},"decision":{"type":"LONG_SETUP","summary":"test"},"entry_plan":{"entry_zone_low":100,"entry_zone_high":101},"risk_plan":{"stop_loss":98},"take_profits":[105,108]}
''')!;

    expect(plan.takeProfits, [105, 108]);
    expect(validator.validate(plan).isValid, isTrue);
  });
}

TradePlan _plan({
  required String decision,
  required double low,
  required double high,
  required double stop,
  required List<double> targets,
}) => TradePlan(
  decision: decision,
  summary: '',
  parsedJson: '{}',
  entryLow: low,
  entryHigh: high,
  stopLoss: stop,
  takeProfits: targets,
);
