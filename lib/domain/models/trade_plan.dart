import 'dart:convert';

import 'plan_conditions.dart';

class TradeTarget {
  const TradeTarget({
    required this.price,
    this.closePercentage,
    this.grossRewardRisk,
    this.estimatedNetRewardRisk,
  });

  final double price;
  final double? closePercentage;
  final double? grossRewardRisk;
  final double? estimatedNetRewardRisk;
}

class TradePlan {
  const TradePlan({
    required this.decision,
    required this.summary,
    required this.parsedJson,
    this.symbol,
    this.entryLow,
    this.entryHigh,
    this.stopLoss,
    this.maximumChasePrice,
    this.targets = const [],
    this.conditions = const PlanConditions(),
  });

  final String decision;
  final String summary;
  final String parsedJson;
  final String? symbol;
  final double? entryLow;
  final double? entryHigh;
  final double? stopLoss;
  final double? maximumChasePrice;
  final List<TradeTarget> targets;
  final PlanConditions conditions;

  List<double> get takeProfits =>
      targets.map((target) => target.price).toList();

  bool get isSetup => decision == 'LONG_SETUP' || decision == 'SHORT_SETUP';

  bool get hasPriceLevels =>
      entryLow != null ||
      entryHigh != null ||
      stopLoss != null ||
      takeProfits.isNotEmpty;

  static TradePlan? fromResponse(String response) =>
      parseResponse(response).plan;

  static String displayText(String response) => parseResponse(response).text;

  // Parse once and retain the matching span for readable output.
  static ({TradePlan? plan, String text}) parseResponse(String response) {
    for (final jsonText in _jsonObjects(response).toList().reversed) {
      try {
        final decoded = jsonDecode(jsonText.raw);
        if (decoded is! Map) continue;
        final data = _map(decoded);
        final decision = _map(data['decision']);
        if (decision.isEmpty) continue;
        final request = _map(data['request']);
        final entry = _map(data['entry_plan']);
        final risk = _map(data['risk_plan']);
        final targets = (_list(data['take_profit_plan']))
            .map(_map)
            .where((item) => _number(item['price']) != null)
            .map(
              (item) => TradeTarget(
                price: _number(item['price'])!,
                closePercentage: _number(item['close_percentage']),
                grossRewardRisk: _number(item['gross_reward_risk']),
                estimatedNetRewardRisk: _number(
                  item['estimated_net_reward_risk'],
                ),
              ),
            )
            .toList();
        final plan = TradePlan(
          decision: decision['type']?.toString() ?? 'UNKNOWN',
          summary: decision['summary']?.toString() ?? '',
          parsedJson: const JsonEncoder.withIndent('  ').convert(data),
          symbol: request['symbol']?.toString().toUpperCase(),
          entryLow: _number(entry['entry_zone_low']),
          entryHigh: _number(entry['entry_zone_high']),
          stopLoss: _number(risk['stop_loss']),
          maximumChasePrice: _number(entry['maximum_chase_price']),
          targets: targets,
          conditions: PlanConditions.fromJson(_map(data['conditions'])),
        );
        final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```')
            .allMatches(response)
            .where(
              (m) =>
                  m.start <= jsonText.start &&
                  m.end >= jsonText.end &&
                  m.group(1)!.trim() == jsonText.raw.trim(),
            )
            .firstOrNull;
        final text = response
            .replaceRange(
              fence?.start ?? jsonText.start,
              fence?.end ?? jsonText.end,
              '',
            )
            .trim();
        return (plan: plan, text: text.isEmpty ? plan.summary : text);
      } catch (_) {
        continue;
      }
    }
    return (plan: null, text: response);
  }

  static Iterable<({String raw, int start, int end})> _jsonObjects(
    String text,
  ) sync* {
    for (var start = 0; start < text.length; start++) {
      if (text[start] != '{') continue;
      var depth = 0;
      var inString = false;
      var escaped = false;
      for (var index = start; index < text.length; index++) {
        final char = text[index];
        if (inString) {
          if (escaped) {
            escaped = false;
          } else if (char == r'\') {
            escaped = true;
          } else if (char == '"') {
            inString = false;
          }
          continue;
        }
        if (char == '"') inString = true;
        if (char == '{') depth++;
        if (char == '}') depth--;
        if (depth == 0) {
          yield (
            raw: text.substring(start, index + 1),
            start: start,
            end: index + 1,
          );
          break;
        }
      }
    }
  }

  static Map<String, dynamic> _map(Object? value) => value is Map
      ? value.map((key, value) => MapEntry(key.toString(), value))
      : const {};

  static List<Object?> _list(Object? value) => value is List ? value : const [];

  static double? _number(Object? value) => switch (value) {
    num value => value.toDouble(),
    String value => double.tryParse(value),
    _ => null,
  };
}
