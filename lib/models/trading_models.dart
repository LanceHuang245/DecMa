import 'dart:convert';

enum LlmProvider { anthropic, openAiResponses, openAiCompletions, openAiCodex }

extension LlmProviderLabel on LlmProvider {
  String get label => switch (this) {
    LlmProvider.anthropic => 'Anthropic Messages',
    LlmProvider.openAiResponses => 'OpenAI Responses',
    LlmProvider.openAiCompletions => 'OpenAI Chat Completions',
    LlmProvider.openAiCodex => 'OpenAI Codex',
  };

  String get defaultEndpoint => switch (this) {
    LlmProvider.anthropic => 'https://api.anthropic.com',
    LlmProvider.openAiResponses => 'https://api.openai.com/v1',
    LlmProvider.openAiCompletions => 'https://api.openai.com/v1',
    LlmProvider.openAiCodex => 'https://chatgpt.com/backend-api/codex',
  };
}

class LlmSettings {
  const LlmSettings({
    required this.provider,
    required this.endpoint,
    required this.model,
  });

  final LlmProvider provider;
  final String endpoint;
  final String model;

  bool get isComplete => endpoint.trim().isNotEmpty && model.trim().isNotEmpty;
}

class McpSettings {
  const McpSettings({
    required this.useBybit,
    required this.useNansen,
    required this.useOpenWebSearch,
  });

  final bool useBybit;
  final bool useNansen;
  final bool useOpenWebSearch;
}

class ApiSettings {
  const ApiSettings({required this.useCoinalyze});

  final bool useCoinalyze;
}

class NewsSettings {
  const NewsSettings({
    required this.useFinnhub,
    required this.useBls,
    required this.useBea,
    required this.useFederalReserve,
  });

  final bool useFinnhub;
  final bool useBls;
  final bool useBea;
  final bool useFederalReserve;
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

  bool get hasPriceLevels =>
      entryLow != null ||
      entryHigh != null ||
      stopLoss != null ||
      takeProfits.isNotEmpty;

  // Select the final plan-shaped JSON object after the user-readable analysis.
  static TradePlan? fromResponse(String response) {
    for (final jsonText in _jsonObjects(response).toList().reversed) {
      try {
        final decoded = jsonDecode(jsonText);
        if (decoded is! Map) continue;
        final data = _map(decoded);
        final decision = _map(data['decision']);
        if (decision.isEmpty) continue;
        final request = _map(data['request']);
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
          parsedJson: const JsonEncoder.withIndent('  ').convert(data),
          symbol: request['symbol']?.toString().toUpperCase(),
          entryLow: _number(entry['entry_zone_low']),
          entryHigh: _number(entry['entry_zone_high']),
          stopLoss: _number(risk['stop_loss']),
          takeProfits: takeProfits,
        );
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  static Iterable<String> _jsonObjects(String text) sync* {
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
          yield text.substring(start, index + 1);
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
