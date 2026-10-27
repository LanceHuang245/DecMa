import 'dart:convert';

class TradePlan {
  const TradePlan({
    required this.decision,
    required this.summary,
    required this.parsedJson,
    this.symbol,
    this.entryLow,
    this.entryHigh,
    this.stopLoss,
    this.takeProfits = const [],
  });

  final String decision;
  final String summary;
  final String parsedJson;
  final String? symbol;
  final double? entryLow;
  final double? entryHigh;
  final double? stopLoss;
  final List<double> takeProfits;

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
        if (decoded is! Map<String, dynamic>) continue;
        final data = decoded;
        final decision = data['decision'] as Map<String, dynamic>? ?? const {};
        if (decision.isEmpty) continue;
        final request = data['request'] as Map<String, dynamic>? ?? const {};
        final entry = data['entry_plan'] as Map<String, dynamic>? ?? const {};
        final risk = data['risk_plan'] as Map<String, dynamic>? ?? const {};
        final plan = TradePlan(
          decision: decision['type']?.toString() ?? 'UNKNOWN',
          summary: decision['summary']?.toString() ?? '',
          parsedJson: const JsonEncoder.withIndent('  ').convert(data),
          symbol: request['symbol']?.toString().toUpperCase(),
          entryLow: _number(entry['entry_zone_low']),
          entryHigh: _number(entry['entry_zone_high']),
          stopLoss: _number(risk['stop_loss']),
          takeProfits: (data['take_profits'] as List? ?? const [])
              .map(_number)
              .nonNulls
              .toList(),
        );
        final fence =
            RegExp(r'```[ \t]*(?:json)?\s*([\s\S]*?)```', caseSensitive: false)
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

  static double? _number(Object? value) => switch (value) {
    num value => value.toDouble(),
    String value => double.tryParse(value),
    _ => null,
  };
}
