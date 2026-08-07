import 'dart:convert';

enum LlmProvider { anthropic, openAiResponses, openAiCompletions }

extension LlmProviderLabel on LlmProvider {
  String get label => switch (this) {
    LlmProvider.anthropic => 'Anthropic Messages',
    LlmProvider.openAiResponses => 'OpenAI Responses',
    LlmProvider.openAiCompletions => 'OpenAI Chat Completions',
  };

  String get defaultEndpoint => switch (this) {
    LlmProvider.anthropic => 'https://api.anthropic.com/v1/messages',
    LlmProvider.openAiResponses => 'https://api.openai.com/v1',
    LlmProvider.openAiCompletions => 'https://api.openai.com/v1',
  };
}

class LlmSettings {
  const LlmSettings({
    required this.provider,
    required this.endpoint,
    required this.apiKey,
    required this.model,
  });

  final LlmProvider provider;
  final String endpoint;
  final String apiKey;
  final String model;

  bool get isComplete =>
      endpoint.trim().isNotEmpty &&
      apiKey.trim().isNotEmpty &&
      model.trim().isNotEmpty;
}

class McpSettings {
  const McpSettings({
    required this.useBybit,
    required this.useCoinglass,
    required this.coinglassKey,
    required this.useNansen,
    required this.nansenKey,
    required this.useOpenWebSearch,
  });

  final bool useBybit;
  final bool useCoinglass;
  final String coinglassKey;
  final bool useNansen;
  final String nansenKey;
  final bool useOpenWebSearch;
}

class Candle {
  const Candle({
    required this.time,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
  });

  final DateTime time;
  final double open;
  final double high;
  final double low;
  final double close;
  final double volume;
}

class TradePlan {
  const TradePlan({
    required this.decision,
    required this.summary,
    this.entryLow,
    this.entryHigh,
    this.stopLoss,
    this.takeProfits = const [],
  });

  final String decision;
  final String summary;
  final double? entryLow;
  final double? entryHigh;
  final double? stopLoss;
  final List<double> takeProfits;

  bool get hasPriceLevels =>
      entryLow != null ||
      entryHigh != null ||
      stopLoss != null ||
      takeProfits.isNotEmpty;

  // Extract the schema required by sys_prompt.md while tolerating text before it.
  static TradePlan? fromResponse(String response) {
    final jsonText = _firstJsonObject(response);
    if (jsonText == null) return null;
    try {
      final data = jsonDecode(jsonText) as Map<String, dynamic>;
      final decision = _map(data['decision']);
      final entry = _map(data['entry_plan']);
      final risk = _map(data['risk_plan']);
      final takeProfits = (_list(data['take_profit_plan']))
          .map(_map)
          .map((item) => _number(item['price']))
          .whereType<double>()
          .toList();
      return TradePlan(
        decision: decision['type']?.toString() ?? 'UNKNOWN',
        summary: decision['summary']?.toString() ?? '',
        entryLow: _number(entry['entry_zone_low']),
        entryHigh: _number(entry['entry_zone_high']),
        stopLoss: _number(risk['stop_loss']),
        takeProfits: takeProfits,
      );
    } catch (_) {
      return null;
    }
  }

  static String? _firstJsonObject(String text) {
    final start = text.indexOf('{');
    if (start < 0) return null;
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
      if (depth == 0) return text.substring(start, index + 1);
    }
    return null;
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
