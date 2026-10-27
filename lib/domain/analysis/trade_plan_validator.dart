import '../models/trade_plan.dart';
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
  const TradePlanValidator();

  static const _allowedDecisions = {
    'LONG_SETUP',
    'SHORT_SETUP',
    'WAIT',
    'NO_TRADE',
    'DATA_INSUFFICIENT',
  };

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
          plan.stopLoss != null || plan.takeProfits.isNotEmpty;
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
    final prices = [low, high, stop, ...plan.takeProfits];
    if (prices.any((price) => !price.isFinite || price <= 0)) {
      errors.add(appL10n.planPricesInvalid);
    }
    if (low > high) errors.add(appL10n.planEntryInverted);
    if (plan.takeProfits.isEmpty) errors.add(appL10n.planMissingTargets);
    if (plan.takeProfits.length > 3) warnings.add(appL10n.planTooManyTargets);

    if (plan.decision == 'LONG_SETUP') {
      if (stop >= low) errors.add(appL10n.planLongStop);
      if (plan.takeProfits.any((target) => target <= high)) {
        errors.add(appL10n.planLongTargets);
      }
      if (!_strictlyOrdered(plan.takeProfits, ascending: true)) {
        errors.add(appL10n.planLongTargetOrder);
      }
    } else {
      if (stop <= high) errors.add(appL10n.planShortStop);
      if (plan.takeProfits.any((target) => target >= low)) {
        errors.add(appL10n.planShortTargets);
      }
      if (!_strictlyOrdered(plan.takeProfits, ascending: false)) {
        errors.add(appL10n.planShortTargetOrder);
      }
    }

    // Prices off the contract's tick grid cannot be placed as orders.
    if (tickSize != null &&
        prices.any((price) {
          final steps = price / tickSize;
          return (steps - steps.round()).abs() >= 1e-7;
        })) {
      warnings.add(appL10n.planTickMisaligned);
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
