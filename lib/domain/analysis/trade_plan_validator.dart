import '../models/trade_plan.dart';
import 'risk_engine.dart';
import '../../l10n/app_languages.dart';

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
      errors.add(appL10n.planUnknownDecision(plan.decision));
      return TradePlanValidation(errors: errors, warnings: warnings);
    }
    if (!plan.isSetup) {
      final canDrawWaitZone = plan.decision == 'WAIT' && _validWaitZone(plan);
      final hasOtherLevels =
          plan.stopLoss != null ||
          plan.maximumChasePrice != null ||
          plan.takeProfits.isNotEmpty;
      if (plan.decision == 'WAIT' && plan.hasPriceLevels && !canDrawWaitZone) {
        warnings.add(appL10n.planInvalidWaitZone);
      } else if (canDrawWaitZone && hasOtherLevels) {
        warnings.add(appL10n.planWaitOnlyZone);
      } else if (plan.decision != 'WAIT' && plan.hasPriceLevels) {
        warnings.add(appL10n.planNonSetupIgnored);
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
      errors.add(appL10n.planSetupMissingEntry);
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
      errors.add(appL10n.planPricesInvalid);
    }
    if (low > high) errors.add(appL10n.planEntryInverted);
    if (plan.targets.isEmpty) errors.add(appL10n.planMissingTargets);
    if (plan.targets.length > 3) warnings.add(appL10n.planTooManyTargets);

    final direction = plan.decision == 'LONG_SETUP'
        ? TradeDirection.long
        : TradeDirection.short;
    if (direction == TradeDirection.long) {
      if (stop >= low) errors.add(appL10n.planLongStop);
      if (plan.targets.any((target) => target.price <= high)) {
        errors.add(appL10n.planLongTargets);
      }
      if (!_strictlyOrdered(plan.takeProfits, ascending: true)) {
        errors.add(appL10n.planLongTargetOrder);
      }
      if (plan.maximumChasePrice case final chase? when chase < high) {
        errors.add(appL10n.planLongChase);
      }
    } else {
      if (stop <= high) errors.add(appL10n.planShortStop);
      if (plan.targets.any((target) => target.price >= low)) {
        errors.add(appL10n.planShortTargets);
      }
      if (!_strictlyOrdered(plan.takeProfits, ascending: false)) {
        errors.add(appL10n.planShortTargetOrder);
      }
      if (plan.maximumChasePrice case final chase? when chase > low) {
        errors.add(appL10n.planShortChase);
      }
    }

    _validatePercentages(plan, warnings);
    if (tickSize != null) {
      if (prices.any((price) => !_riskEngine.isTickAligned(price, tickSize))) {
        warnings.add(appL10n.planTickMisaligned);
      }
    }
    if (errors.isEmpty) {
      _compareRewardRisk(plan, direction, warnings);
    }
    return TradePlanValidation(errors: errors, warnings: warnings);
  }

  bool _validWaitZone(TradePlan plan) {
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
    return true;
  }

  void _validatePercentages(TradePlan plan, List<String> warnings) {
    final percentages = plan.targets
        .map((target) => target.closePercentage)
        .whereType<double>()
        .toList();
    if (percentages.isEmpty) return;
    if (percentages.length != plan.targets.length ||
        percentages.any(
          (value) => !value.isFinite || value <= 0 || value > 100,
        )) {
      warnings.add(appL10n.planAllocationInvalid);
      return;
    }
    final total = percentages.reduce((left, right) => left + right);
    if ((total - 100).abs() > 0.5) warnings.add(appL10n.planAllocationTotal);
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
        warnings.add(appL10n.planGrossRrMismatch(target.price));
      }
      final net = target.estimatedNetRewardRisk;
      if (net != null && net > declared) {
        warnings.add(appL10n.planNetAboveGross(target.price));
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
