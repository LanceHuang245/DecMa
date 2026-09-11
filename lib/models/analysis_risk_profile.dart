/// An explicit maximum loss expressed as either USDT cash or equity percentage.
class MoneyOrPercent {
  const MoneyOrPercent.cash(double this.cash) : rate = null;
  const MoneyOrPercent.rate(double this.rate) : cash = null;

  final double? cash;
  final double? rate;

  Map<String, Object?> toJson() => {'cash': cash, 'rate': rate};

  factory MoneyOrPercent.fromJson(Map<String, dynamic> json) {
    final cash = _number(json['cash']);
    final rate = _number(json['rate']);
    if (cash != null && cash > 0 && rate == null) {
      return MoneyOrPercent.cash(cash);
    }
    if (cash == null && rate != null && rate > 0) {
      return MoneyOrPercent.rate(rate);
    }
    throw FormatException('MoneyOrPercent requires one positive cash or rate.');
  }
}

/// A planned order size with a deliberately explicit unit.
class PlannedPosition {
  const PlannedPosition.notional(double this.notionalUsdt)
    : assetQuantity = null,
      asset = null;

  const PlannedPosition.quantity(double this.assetQuantity, String this.asset)
    : notionalUsdt = null;

  final double? notionalUsdt;
  final double? assetQuantity;
  final String? asset;

  Map<String, Object?> toJson() => {
    'notionalUsdt': notionalUsdt,
    'assetQuantity': assetQuantity,
    'asset': asset,
  };

  factory PlannedPosition.fromJson(Map<String, dynamic> json) {
    final notional = _number(json['notionalUsdt']);
    final quantity = _number(json['assetQuantity']);
    final asset = json['asset']?.toString().trim();
    if (notional != null &&
        notional > 0 &&
        quantity == null &&
        (asset == null || asset.isEmpty)) {
      return PlannedPosition.notional(notional);
    }
    if (json['notionalUsdt'] == null &&
        quantity != null &&
        quantity > 0 &&
        asset != null &&
        asset.isNotEmpty) {
      return PlannedPosition.quantity(quantity, asset);
    }
    throw FormatException(
      'PlannedPosition requires one positive explicit unit.',
    );
  }
}

/// Normalizes confirmed account-risk inputs without inferring missing units.
class AnalysisRiskProfile {
  AnalysisRiskProfile({
    required this.accountEquity,
    required this.riskCash,
    required this.holdingPeriod,
    required this.plannedPosition,
    required this.expectedSlippageRate,
    required this.safetyBufferRate,
    required this.minimumNetRewardRisk,
    required this.maximumEffectiveLeverage,
    required List<String> warnings,
    required this.rawAccountEquity,
    required this.rawMaximumLoss,
    required this.rawPlannedPosition,
    required this.rawTradeWindow,
    required this.rawExpectedSlippage,
    required this.rawSafetyBuffer,
    required this.rawMinimumNetRewardRisk,
    required this.rawMaximumEffectiveLeverage,
  }) : warnings = List.unmodifiable(warnings);

  final double? accountEquity;
  final double? riskCash;
  final Duration? holdingPeriod;
  final PlannedPosition? plannedPosition;
  final double? expectedSlippageRate;
  final double? safetyBufferRate;
  final double? minimumNetRewardRisk;
  final double? maximumEffectiveLeverage;
  final List<String> warnings;
  final String rawAccountEquity;
  final String rawMaximumLoss;
  final String rawPlannedPosition;
  final String rawTradeWindow;
  final String rawExpectedSlippage;
  final String rawSafetyBuffer;
  final String rawMinimumNetRewardRisk;
  final String rawMaximumEffectiveLeverage;

  /// Parses only supported, unit-labelled values so ambiguity stays unavailable.
  factory AnalysisRiskProfile.parse({
    required String accountEquity,
    required String maximumLoss,
    required String plannedPosition,
    required String tradeWindow,
    required String expectedSlippage,
    required String safetyBuffer,
    required String minimumNetRewardRisk,
    required String maximumEffectiveLeverage,
  }) {
    final warnings = <String>[];
    final equity = _positiveUsdt(accountEquity);
    final maximum = _moneyOrPercent(maximumLoss);
    final riskCash =
        maximum?.cash ??
        (equity != null && maximum?.rate != null
            ? equity * maximum!.rate!
            : null);
    if (accountEquity.trim().isNotEmpty && equity == null) {
      warnings.add('Account equity must be a positive USDT amount.');
    }
    if (maximumLoss.trim().isNotEmpty &&
        (maximum == null || riskCash == null)) {
      warnings.add(
        'Maximum loss must be a positive USDT amount or percentage of valid equity.',
      );
    }
    final position = _plannedPosition(plannedPosition);
    if (plannedPosition.trim().isNotEmpty && position == null) {
      warnings.add('Planned position requires an explicit USDT or asset unit.');
    }
    final holdingPeriod = _holdingPeriod(tradeWindow);
    if (tradeWindow.trim().isNotEmpty && holdingPeriod == null) {
      warnings.add('Trade window must be positive minutes or hours.');
    }
    final slippage = _nonNegativePercent(expectedSlippage);
    if (expectedSlippage.trim().isNotEmpty && slippage == null) {
      warnings.add('Expected slippage must be a non-negative percentage.');
    }
    final buffer = _nonNegativePercent(safetyBuffer);
    if (safetyBuffer.trim().isNotEmpty && buffer == null) {
      warnings.add('Safety buffer must be a non-negative percentage.');
    }
    final minimumRr = _positiveNumber(minimumNetRewardRisk);
    if (minimumNetRewardRisk.trim().isNotEmpty && minimumRr == null) {
      warnings.add('Minimum net reward-risk must be positive.');
    }
    final maximumLeverage = _positiveMultiplier(maximumEffectiveLeverage);
    if (maximumEffectiveLeverage.trim().isNotEmpty && maximumLeverage == null) {
      warnings.add('Maximum effective leverage must be a positive multiplier.');
    }
    return AnalysisRiskProfile(
      accountEquity: equity,
      riskCash: riskCash,
      holdingPeriod: holdingPeriod,
      plannedPosition: position,
      expectedSlippageRate: slippage,
      safetyBufferRate: buffer,
      minimumNetRewardRisk: minimumRr,
      maximumEffectiveLeverage: maximumLeverage,
      warnings: List.unmodifiable(warnings),
      rawAccountEquity: accountEquity,
      rawMaximumLoss: maximumLoss,
      rawPlannedPosition: plannedPosition,
      rawTradeWindow: tradeWindow,
      rawExpectedSlippage: expectedSlippage,
      rawSafetyBuffer: safetyBuffer,
      rawMinimumNetRewardRisk: minimumNetRewardRisk,
      rawMaximumEffectiveLeverage: maximumEffectiveLeverage,
    );
  }

  Map<String, Object?> toJson() => {
    'accountEquity': accountEquity,
    'riskCash': riskCash,
    'holdingPeriodMinutes': holdingPeriod?.inMinutes,
    'plannedPosition': plannedPosition?.toJson(),
    'expectedSlippageRate': expectedSlippageRate,
    'safetyBufferRate': safetyBufferRate,
    'minimumNetRewardRisk': minimumNetRewardRisk,
    'maximumEffectiveLeverage': maximumEffectiveLeverage,
    'warnings': warnings,
    'rawAccountEquity': rawAccountEquity,
    'rawMaximumLoss': rawMaximumLoss,
    'rawPlannedPosition': rawPlannedPosition,
    'rawTradeWindow': rawTradeWindow,
    'rawExpectedSlippage': rawExpectedSlippage,
    'rawSafetyBuffer': rawSafetyBuffer,
    'rawMinimumNetRewardRisk': rawMinimumNetRewardRisk,
    'rawMaximumEffectiveLeverage': rawMaximumEffectiveLeverage,
  };

  factory AnalysisRiskProfile.fromJson(Map<String, dynamic> json) =>
      AnalysisRiskProfile(
        accountEquity: _number(json['accountEquity']),
        riskCash: _number(json['riskCash']),
        holdingPeriod: _number(json['holdingPeriodMinutes']) == null
            ? null
            : Duration(minutes: _number(json['holdingPeriodMinutes'])!.round()),
        plannedPosition: json['plannedPosition'] is Map
            ? PlannedPosition.fromJson(
                Map<String, dynamic>.from(json['plannedPosition'] as Map),
              )
            : null,
        expectedSlippageRate: _number(json['expectedSlippageRate']),
        safetyBufferRate: _number(json['safetyBufferRate']),
        minimumNetRewardRisk: _number(json['minimumNetRewardRisk']),
        maximumEffectiveLeverage: _number(json['maximumEffectiveLeverage']),
        warnings: (json['warnings'] as List? ?? const [])
            .map((warning) => warning.toString())
            .toList(growable: false),
        rawAccountEquity: json['rawAccountEquity']?.toString() ?? '',
        rawMaximumLoss: json['rawMaximumLoss']?.toString() ?? '',
        rawPlannedPosition: json['rawPlannedPosition']?.toString() ?? '',
        rawTradeWindow: json['rawTradeWindow']?.toString() ?? '',
        rawExpectedSlippage: json['rawExpectedSlippage']?.toString() ?? '',
        rawSafetyBuffer: json['rawSafetyBuffer']?.toString() ?? '',
        rawMinimumNetRewardRisk:
            json['rawMinimumNetRewardRisk']?.toString() ?? '',
        rawMaximumEffectiveLeverage:
            json['rawMaximumEffectiveLeverage']?.toString() ?? '',
      );
}

double? _positiveUsdt(String value) => _positiveAmount(value, 'USDT');

MoneyOrPercent? _moneyOrPercent(String value) {
  final cash = _positiveUsdt(value);
  if (cash != null) return MoneyOrPercent.cash(cash);
  final rate = _positivePercent(value);
  return rate == null ? null : MoneyOrPercent.rate(rate);
}

PlannedPosition? _plannedPosition(String value) {
  final notional = _positiveUsdt(value);
  if (notional != null) return PlannedPosition.notional(notional);
  final match = RegExp(
    r'^\s*(' + _numericSource + r')\s+([A-Za-z]{2,15})\s*$',
  ).firstMatch(value);
  final quantity = _number(match?.group(1));
  return quantity == null || quantity <= 0
      ? null
      : PlannedPosition.quantity(quantity, match!.group(2)!.toUpperCase());
}

Duration? _holdingPeriod(String value) {
  final match = RegExp(
    r'^\s*(' +
        _numericSource +
        r')\s*(分钟|分鐘|分|minutes?|mins?|小时|小時|时|時|hours?|hrs?)\s*$',
    caseSensitive: false,
  ).firstMatch(value);
  final amount = _number(match?.group(1));
  if (amount == null || amount <= 0) return null;
  final unit = match!.group(2)!.toLowerCase();
  final minutes =
      unit.contains('hour') ||
          unit.contains('hr') ||
          unit.contains('小') ||
          unit == '时' ||
          unit == '時'
      ? amount * 60
      : amount;
  final roundedMinutes = minutes.round();
  return roundedMinutes > 0 ? Duration(minutes: roundedMinutes) : null;
}

double? _nonNegativePercent(String value) => _percent(value, minimum: 0);

double? _positivePercent(String value) =>
    _percent(value, minimum: double.minPositive);

double? _percent(String value, {required double minimum}) {
  final match = RegExp(
    r'^\s*(' + _numericSource + r')\s*%\s*$',
  ).firstMatch(value);
  final percentage = _number(match?.group(1));
  return percentage == null || percentage < minimum ? null : percentage / 100;
}

double? _positiveMultiplier(String value) {
  final match = RegExp(
    r'^\s*(' + _numericSource + r')\s*x\s*$',
    caseSensitive: false,
  ).firstMatch(value);
  final multiplier = _number(match?.group(1));
  return multiplier == null || multiplier <= 0 ? null : multiplier;
}

double? _positiveNumber(String value) {
  final number = _number(value);
  return number == null || number <= 0 ? null : number;
}

double? _positiveAmount(String value, String unit) {
  final match = RegExp(
    r'^\s*(' + _numericSource + r')\s*' + unit + r'\s*$',
    caseSensitive: false,
  ).firstMatch(value);
  final amount = _number(match?.group(1));
  return amount == null || amount <= 0 ? null : amount;
}

// Validate grouping before removing separators so malformed amounts stay unavailable.
const _numericSource = r'(?:0|[1-9]\d{0,2}(?:,\d{3})+|[1-9]\d*)(?:\.\d+)?';
final _numericValue = RegExp(
  '^$_numericSource'
  r'$',
);

double? _number(Object? value) {
  if (value is num) return value.isFinite ? value.toDouble() : null;
  final text = value?.toString().trim();
  if (text == null || !_numericValue.hasMatch(text)) return null;
  return double.tryParse(text.replaceAll(',', ''));
}
