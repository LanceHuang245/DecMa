import 'package:decma/models/trading_models.dart';
import 'package:decma/services/analysis/risk_engine.dart';
import 'package:decma/services/analysis/trade_plan_validator.dart';
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
        chase: 102,
        targets: const [
          TradeTarget(price: 105, closePercentage: 50),
          TradeTarget(price: 108, closePercentage: 50),
        ],
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
        targets: const [TradeTarget(price: 105)],
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
        targets: const [TradeTarget(price: 95.03), TradeTarget(price: 97)],
      ),
      tickSize: 0.1,
    );

    expect(result.errors, contains('空头止盈必须按价格降序排列'));
    expect(result.errors, contains('价格不符合合约 Tick Size'));
  });

  test('non-setup decisions never become chart setups', () {
    final plan = _plan(
      decision: 'WAIT',
      low: 100,
      high: 101,
      stop: 98,
      targets: const [TradeTarget(price: 105)],
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
        targets: const [TradeTarget(price: 105)],
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

  test(
    'RiskEngine calculates size and effective leverage deterministically',
    () {
      const engine = RiskEngine();
      final metrics = engine.calculate(
        direction: TradeDirection.long,
        entry: 100,
        stop: 98,
        target: 106,
        openFeeRate: 0.001,
        closeFeeRate: 0.001,
      )!;
      final size = engine.positionSize(
        riskCash: 100,
        riskPerUnit: metrics.riskPerUnit,
        estimatedCostPerUnit: metrics.estimatedCostPerUnit,
      )!;

      expect(metrics.grossRewardRisk, 3);
      expect(metrics.netRewardRisk, closeTo(5.8 / 2.2, 1e-9));
      expect(size, closeTo(100 / 2.2, 1e-9));
      expect(
        engine.effectiveLeverage(
          positionSize: size,
          entry: 100,
          accountEquity: 1000,
        ),
        closeTo(size / 10, 1e-9),
      );
    },
  );

  test('TradePlan parser keeps fields required by the validator', () {
    final plan = TradePlan.fromResponse('''
Result
{"request":{"symbol":"BTCUSDT"},"decision":{"type":"LONG_SETUP","summary":"test"},"entry_plan":{"entry_zone_low":100,"entry_zone_high":101,"maximum_chase_price":102},"risk_plan":{"stop_loss":98},"take_profit_plan":[{"price":105,"close_percentage":100,"gross_reward_risk":1.8,"estimated_net_reward_risk":1.7}]}
''')!;

    expect(plan.symbol, 'BTCUSDT');
    expect(plan.maximumChasePrice, 102);
    expect(plan.targets.single.closePercentage, 100);
    expect(validator.validate(plan).isValid, isTrue);
  });
}

TradePlan _plan({
  required String decision,
  required double low,
  required double high,
  required double stop,
  double? chase,
  required List<TradeTarget> targets,
}) => TradePlan(
  decision: decision,
  summary: '',
  parsedJson: '{}',
  entryLow: low,
  entryHigh: high,
  stopLoss: stop,
  maximumChasePrice: chase,
  targets: targets,
);
