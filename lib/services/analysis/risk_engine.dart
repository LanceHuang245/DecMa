enum TradeDirection { long, short }

class RiskMetrics {
  const RiskMetrics({
    required this.riskPerUnit,
    required this.rewardPerUnit,
    required this.grossRewardRisk,
    required this.estimatedCostPerUnit,
    required this.netRewardRisk,
  });

  final double riskPerUnit;
  final double rewardPerUnit;
  final double grossRewardRisk;
  final double estimatedCostPerUnit;
  final double netRewardRisk;
}

class RiskEngine {
  const RiskEngine();

  // Calculate price risk and reward from explicit inputs only.
  RiskMetrics? calculate({
    required TradeDirection direction,
    required double entry,
    required double stop,
    required double target,
    double openFeeRate = 0,
    double closeFeeRate = 0,
    double slippageRate = 0,
    double fundingRate = 0,
    double safetyBufferRate = 0,
  }) {
    if (![entry, stop, target].every((value) => value.isFinite && value > 0)) {
      return null;
    }
    final risk = direction == TradeDirection.long ? entry - stop : stop - entry;
    final reward = direction == TradeDirection.long
        ? target - entry
        : entry - target;
    if (risk <= 0 || reward <= 0) return null;
    final costRates = [
      openFeeRate,
      closeFeeRate,
      slippageRate * 2,
      fundingRate.abs(),
      safetyBufferRate,
    ];
    if (costRates.any((value) => !value.isFinite || value < 0)) return null;
    final cost = entry * costRates.reduce((left, right) => left + right);
    return RiskMetrics(
      riskPerUnit: risk,
      rewardPerUnit: reward,
      grossRewardRisk: reward / risk,
      estimatedCostPerUnit: cost,
      netRewardRisk: (reward - cost) / (risk + cost),
    );
  }

  // Size a position from cash risk without assuming account inputs.
  double? positionSize({
    required double riskCash,
    required double riskPerUnit,
    double estimatedCostPerUnit = 0,
  }) {
    final totalRisk = riskPerUnit + estimatedCostPerUnit;
    if (!riskCash.isFinite || riskCash <= 0 || totalRisk <= 0) return null;
    return riskCash / totalRisk;
  }

  double? effectiveLeverage({
    required double positionSize,
    required double entry,
    required double accountEquity,
  }) {
    if (!positionSize.isFinite ||
        !entry.isFinite ||
        !accountEquity.isFinite ||
        positionSize <= 0 ||
        entry <= 0 ||
        accountEquity <= 0) {
      return null;
    }
    return positionSize * entry / accountEquity;
  }

  bool isTickAligned(double price, double tickSize) {
    if (!price.isFinite || !tickSize.isFinite || tickSize <= 0) return false;
    final steps = price / tickSize;
    return (steps - steps.round()).abs() < 1e-7;
  }
}
