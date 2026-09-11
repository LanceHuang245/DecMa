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

  test('rejects malformed numeric grouping in every risk input', () {
    final profile = AnalysisRiskProfile.parse(
      accountEquity: '1,2 USDT',
      maximumLoss: '1,,,000 USDT',
      plannedPosition: '1,2 BTC',
      tradeWindow: '1,,,2 小时',
      expectedSlippage: '1,2%',
      safetyBuffer: '1,,,2%',
      minimumNetRewardRisk: '1,2',
      maximumEffectiveLeverage: '1,,,2x',
    );

    expect(profile.accountEquity, isNull);
    expect(profile.riskCash, isNull);
    expect(profile.plannedPosition, isNull);
    expect(profile.holdingPeriod, isNull);
    expect(profile.expectedSlippageRate, isNull);
    expect(profile.safetyBufferRate, isNull);
    expect(profile.minimumNetRewardRisk, isNull);
    expect(profile.maximumEffectiveLeverage, isNull);
  });

  test('rejects holding periods that round down to zero minutes', () {
    final profile = AnalysisRiskProfile.parse(
      accountEquity: '',
      maximumLoss: '',
      plannedPosition: '',
      tradeWindow: '0.1 分钟',
      expectedSlippage: '',
      safetyBuffer: '',
      minimumNetRewardRisk: '',
      maximumEffectiveLeverage: '',
    );

    expect(profile.holdingPeriod, isNull);
    expect(
      profile.warnings,
      contains('Trade window must be positive minutes or hours.'),
    );
  });

  test(
    'resolves percentage loss and parses asset quantity with optional rates',
    () {
      final profile = AnalysisRiskProfile.parse(
        accountEquity: '1,000 USDT',
        maximumLoss: '2%',
        plannedPosition: '0.25 BTC',
        tradeWindow: '90 分钟',
        expectedSlippage: '0.05%',
        safetyBuffer: '0.1%',
        minimumNetRewardRisk: '1.5',
        maximumEffectiveLeverage: '3x',
      );

      expect(profile.riskCash, 20);
      expect(profile.plannedPosition?.assetQuantity, 0.25);
      expect(profile.plannedPosition?.asset, 'BTC');
      expect(profile.expectedSlippageRate, 0.0005);
      expect(profile.safetyBufferRate, 0.001);
      expect(profile.minimumNetRewardRisk, 1.5);
      expect(profile.maximumEffectiveLeverage, 3);
    },
  );

  test('keeps warnings immutable and round-trips JSON', () {
    final originalWarnings = <String>['review'];
    final profile = AnalysisRiskProfile(
      accountEquity: 1000,
      riskCash: 20,
      holdingPeriod: const Duration(hours: 3),
      plannedPosition: const PlannedPosition.notional(500),
      expectedSlippageRate: 0.0005,
      safetyBufferRate: 0.001,
      minimumNetRewardRisk: 1.5,
      maximumEffectiveLeverage: 3,
      warnings: originalWarnings,
      rawAccountEquity: '1,000 USDT',
      rawMaximumLoss: '20 USDT',
      rawPlannedPosition: '500 USDT',
      rawTradeWindow: '3 小时',
      rawExpectedSlippage: '0.05%',
      rawSafetyBuffer: '0.1%',
      rawMinimumNetRewardRisk: '1.5',
      rawMaximumEffectiveLeverage: '3x',
    );
    originalWarnings.add('changed after construction');
    final restored = AnalysisRiskProfile.fromJson(
      Map<String, dynamic>.from(profile.toJson()),
    );

    expect(profile.warnings, ['review']);
    expect(() => profile.warnings.add('mutate'), throwsUnsupportedError);
    expect(restored.toJson(), profile.toJson());
    expect(() => restored.warnings.add('mutate'), throwsUnsupportedError);
  });

  test('rejects incomplete MoneyOrPercent and PlannedPosition JSON', () {
    expect(() => MoneyOrPercent.fromJson({}), throwsA(isA<FormatException>()));
    expect(() => PlannedPosition.fromJson({}), throwsA(isA<FormatException>()));
  });
}
