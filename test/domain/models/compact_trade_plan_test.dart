import 'dart:convert';

import 'package:decma/domain/models/trade_plan.dart';
import 'package:decma/domain/analysis/trade_plan_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('machine plan is hidden while the readable conclusion stays intact', () {
    const raw = '{"decision":{"type":"WAIT","summary":"等待"}}';
    expect(
      TradePlan.displayText('偏多，但现在等待回踩。\n```json\n$raw\n```'),
      '偏多，但现在等待回踩。',
    );
    expect(TradePlan.displayText(raw), '等待');
    expect(
      TradePlan.displayText('```python\nprint(1)\n```\n$raw'),
      '```python\nprint(1)\n```',
    );
  });
  // The compact output must retain every field used by chart/risk validation.
  for (final direction in ['LONG_SETUP', 'SHORT_SETUP']) {
    test('$direction compact plan preserves chart levels and RR checks', () {
      final long = direction == 'LONG_SETUP';
      final json = {
        'request': {'symbol': 'BTCUSDT'},
        'decision': {'type': direction, 'summary': 'Conditional setup'},
        'entry_plan': {
          'entry_zone_low': 100,
          'entry_zone_high': 102,
          'maximum_chase_price': long ? 103 : 99,
        },
        'risk_plan': {'stop_loss': long ? 95 : 107},
        'take_profit_plan': [
          {
            'price': long ? 113 : 89,
            'close_percentage': 100,
            'gross_reward_risk': 2,
            'estimated_net_reward_risk': null,
          },
        ],
      };
      final plan = TradePlan.fromResponse(
        '结论与触发条件。\n```json\n${jsonEncode(json)}\n```',
      )!;
      expect(plan.symbol, 'BTCUSDT');
      expect(plan.decision, direction);
      expect(plan.entryLow, 100);
      expect(plan.entryHigh, 102);
      expect(plan.stopLoss, long ? 95 : 107);
      expect(plan.maximumChasePrice, long ? 103 : 99);
      expect(plan.takeProfits, [long ? 113 : 89]);
      expect(plan.targets.single.closePercentage, 100);
      final validation = const TradePlanValidator().validate(
        plan,
        tickSize: 0.1,
      );
      expect(validation.errors, isEmpty);
      expect(validation.warnings, isEmpty);
      expect(jsonDecode(plan.parsedJson), json);
    });
  }

  // Non-setup decisions need no empty risk/target objects to remain parseable.
  for (final decision in ['WAIT', 'NO_TRADE', 'DATA_INSUFFICIENT']) {
    test('$decision compact plan works without unused fields', () {
      final plan = TradePlan.fromResponse(
        jsonEncode({
          'request': {'symbol': 'BTCUSDT'},
          'decision': {'type': decision, 'summary': 'No active setup'},
          if (decision == 'WAIT')
            'entry_plan': {'entry_zone_low': 100, 'entry_zone_high': 102},
        }),
      )!;
      final validation = const TradePlanValidator().validate(
        plan,
        tickSize: 0.1,
      );
      expect(validation.isValid, true);
      expect(validation.canDrawWaitZone, decision == 'WAIT');
      expect(plan.isSetup, false);
      expect(plan.stopLoss, isNull);
      expect(plan.targets, isEmpty);
    });
  }
}
