import '../../models/trading_models.dart';
import 'risk_engine.dart';

class TradePlanValidation {
  const TradePlanValidation({
    required this.errors,
    required this.warnings,
    this.canDrawWaitZone = false,
  });

  final List<String> errors;
  final List<String> warnings;
  final bool canDrawWaitZone;

  bool get isValid => errors.isEmpty;
}

class TradePlanValidator {
  const TradePlanValidator([this._riskEngine = const RiskEngine()]);

  static const _allowedDecisions = {
    'LONG_SETUP',
    'SHORT_SETUP',
    'WAIT',
    'NO_TRADE',
    'DATA_INSUFFICIENT',
  };
  final RiskEngine _riskEngine;

  // Reject plans that would draw directionally impossible price levels.
  TradePlanValidation validate(TradePlan plan, {double? tickSize}) {
    final errors = <String>[];
    final warnings = <String>[];
    if (!_allowedDecisions.contains(plan.decision)) {
      errors.add('未知决策类型 ${plan.decision}');
      return TradePlanValidation(errors: errors, warnings: warnings);
    }
    if (!plan.isSetup) {
      final canDrawWaitZone =
          plan.decision == 'WAIT' && _validWaitZone(plan, tickSize);
      final hasOtherLevels =
          plan.stopLoss != null ||
          plan.maximumChasePrice != null ||
          plan.takeProfits.isNotEmpty;
      if (plan.decision == 'WAIT' && plan.hasPriceLevels && !canDrawWaitZone) {
        warnings.add('候选等待区无效，价格标记已忽略');
      } else if (canDrawWaitZone && hasOtherLevels) {
        warnings.add('WAIT 仅保留候选等待区，其他价格标记已忽略');
      } else if (plan.decision != 'WAIT' && plan.hasPriceLevels) {
        warnings.add('非交易 Setup 的价格标记已忽略');
      }
      return TradePlanValidation(
        errors: errors,
        warnings: warnings,
        canDrawWaitZone: canDrawWaitZone,
      );
    }

    final low = plan.entryLow;
    final high = plan.entryHigh;
    final stop = plan.stopLoss;
    if (low == null || high == null || stop == null) {
      errors.add('交易 Setup 缺少完整开仓区或止损');
      return TradePlanValidation(errors: errors, warnings: warnings);
    }
    final prices = [
      low,
      high,
      stop,
      ...plan.takeProfits,
      ?plan.maximumChasePrice,
    ];
    if (prices.any((price) => !price.isFinite || price <= 0)) {
      errors.add('价格必须为正数且有限');
    }
    if (low > high) errors.add('开仓区下限高于上限');
    if (plan.targets.isEmpty) errors.add('交易 Setup 缺少止盈目标');

    final direction = plan.decision == 'LONG_SETUP'
        ? TradeDirection.long
        : TradeDirection.short;
    if (direction == TradeDirection.long) {
      if (stop >= low) errors.add('多头止损必须低于开仓区');
      if (plan.targets.any((target) => target.price <= high)) {
        errors.add('多头止盈必须高于开仓区');
      }
      if (!_strictlyOrdered(plan.takeProfits, ascending: true)) {
        errors.add('多头止盈必须按价格升序排列');
      }
      if (plan.maximumChasePrice case final chase? when chase < high) {
        errors.add('多头最大追价不能低于开仓区上限');
      }
    } else {
      if (stop <= high) errors.add('空头止损必须高于开仓区');
      if (plan.targets.any((target) => target.price >= low)) {
        errors.add('空头止盈必须低于开仓区');
      }
      if (!_strictlyOrdered(plan.takeProfits, ascending: false)) {
        errors.add('空头止盈必须按价格降序排列');
      }
      if (plan.maximumChasePrice case final chase? when chase > low) {
        errors.add('空头最大追价不能高于开仓区下限');
      }
    }

    _validatePercentages(plan, errors);
    if (tickSize != null) {
      if (prices.any((price) => !_riskEngine.isTickAligned(price, tickSize))) {
        errors.add('价格不符合合约 Tick Size');
      }
    }
    if (errors.isEmpty) {
      _compareRewardRisk(plan, direction, warnings);
    }
    return TradePlanValidation(errors: errors, warnings: warnings);
  }

  bool _validWaitZone(TradePlan plan, double? tickSize) {
    final low = plan.entryLow;
    final high = plan.entryHigh;
    if (low == null || high == null) return false;
    if (!low.isFinite ||
        !high.isFinite ||
        low <= 0 ||
        high <= 0 ||
        low > high) {
      return false;
    }
    return tickSize == null ||
        (_riskEngine.isTickAligned(low, tickSize) &&
            _riskEngine.isTickAligned(high, tickSize));
  }

  void _validatePercentages(TradePlan plan, List<String> errors) {
    final percentages = plan.targets
        .map((target) => target.closePercentage)
        .whereType<double>()
        .toList();
    if (percentages.isEmpty) return;
    if (percentages.length != plan.targets.length ||
        percentages.any((value) => value <= 0 || value > 100)) {
      errors.add('止盈比例必须全部存在且位于 0–100');
      return;
    }
    final total = percentages.reduce((left, right) => left + right);
    if ((total - 100).abs() > 0.5) errors.add('止盈比例合计必须为 100%');
  }

  void _compareRewardRisk(
    TradePlan plan,
    TradeDirection direction,
    List<String> warnings,
  ) {
    final entry = (plan.entryLow! + plan.entryHigh!) / 2;
    for (final target in plan.targets) {
      final metrics = _riskEngine.calculate(
        direction: direction,
        entry: entry,
        stop: plan.stopLoss!,
        target: target.price,
      );
      final declared = target.grossRewardRisk;
      if (metrics == null || declared == null) continue;
      final tolerance = 0.15 > metrics.grossRewardRisk * 0.1
          ? 0.15
          : metrics.grossRewardRisk * 0.1;
      if ((declared - metrics.grossRewardRisk).abs() > tolerance) {
        warnings.add('止盈 ${target.price} 的 Gross RR 与确定性计算不一致');
      }
      final net = target.estimatedNetRewardRisk;
      if (net != null && net > declared) {
        warnings.add('止盈 ${target.price} 的 Net RR 高于 Gross RR');
      }
    }
  }

  bool _strictlyOrdered(List<double> values, {required bool ascending}) {
    for (var index = 1; index < values.length; index++) {
      if (ascending
          ? values[index] <= values[index - 1]
          : values[index] >= values[index - 1]) {
        return false;
      }
    }
    return true;
  }
}
