import 'package:decma/models/trading_models.dart';
import 'package:decma/services/agent_prompts.dart';
import 'package:decma/services/analysis/trade_plan_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Missing personal costs must not become a blanket entry restriction.
  test('missing costs do not block direction or entry timing assessment', () {
    expect(
      analysisPrompt,
      contains('Missing costs alone must not block an entry-timing assessment'),
    );
    for (final obsoleteRule in [
      'Make net reward-risk validation an entry condition',
      'require cost validation before entry',
      'entry remains conditional on cost validation',
      'Explain unavailable exit allocation or net RR and the checks required',
    ]) {
      expect(analysisPrompt, isNot(contains(obsoleteRule)));
    }
  });

  test('unknown costs stay unavailable while verified risk vetoes remain', () {
    expect(analysisPrompt, contains('estimated_net_reward_risk = null'));
    expect(
      analysisPrompt,
      contains(
        'Net risk-reward is deterministically below the configured '
        'minimum using explicit cost inputs',
      ),
    );
    expect(
      analysisPrompt,
      contains('Do not turn missing costs into an entry trigger'),
    );
  });

  // Both directions remain structurally valid without a net reward-risk value.
  for (final isLong in [true, false]) {
    test('accepts ${isLong ? 'long' : 'short'} without net reward-risk', () {
      final plan = TradePlan.fromResponse('''
{"decision":{"type":"${isLong ? 'LONG_SETUP' : 'SHORT_SETUP'}","summary":"test"},"entry_plan":{"entry_zone_low":100,"entry_zone_high":101},"risk_plan":{"stop_loss":${isLong ? 98 : 103}},"take_profit_plan":[{"price":${isLong ? 107 : 94},"close_percentage":null,"gross_reward_risk":2.6,"estimated_net_reward_risk":null}]}
''')!;

      expect(plan.targets.single.estimatedNetRewardRisk, isNull);
      expect(const TradePlanValidator().validate(plan).isValid, isTrue);
    });
  }
}
