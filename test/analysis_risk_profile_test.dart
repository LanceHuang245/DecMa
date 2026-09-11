import 'package:decma/models/analysis_risk_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses explicit USDT risk and holding window', () {
    final profile = AnalysisRiskProfile.parse(
      accountEquity: '1,000 USDT',
      maximumLoss: '20 USDT',
      plannedPosition: '500 USDT',
      tradeWindow: '3 小时',
      expectedSlippage: '0.05%',
      safetyBuffer: '0.1%',
      minimumNetRewardRisk: '1.5',
      maximumEffectiveLeverage: '3x',
    );
    expect(profile.accountEquity, 1000);
    expect(profile.riskCash, 20);
    expect(profile.holdingPeriod, const Duration(hours: 3));
    expect(profile.plannedPosition?.notionalUsdt, 500);
    expect(profile.expectedSlippageRate, 0.0005);
    expect(profile.minimumNetRewardRisk, 1.5);
  });

  test('does not guess ambiguous units', () {
    final profile = AnalysisRiskProfile.parse(
      accountEquity: '1000',
      maximumLoss: '2',
      plannedPosition: '10',
      tradeWindow: 'soon',
      expectedSlippage: '',
      safetyBuffer: '',
      minimumNetRewardRisk: '',
      maximumEffectiveLeverage: '',
    );
    expect(profile.riskCash, isNull);
    expect(profile.plannedPosition, isNull);
    expect(profile.warnings, isNotEmpty);
  });
}
