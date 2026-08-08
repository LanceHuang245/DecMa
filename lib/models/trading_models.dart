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
    this.id = defaultId,
    this.name = defaultName,
    required this.provider,
    required this.endpoint,
    required this.model,
  });

  static const defaultId = 'default';
  static const defaultName = '默认连接';

  final String id;
  final String name;
  final LlmProvider provider;
  final String endpoint;
  final String model;

  bool get isComplete => endpoint.trim().isNotEmpty && model.trim().isNotEmpty;

  // Store only connection metadata here; credentials remain in secure storage.
  Map<String, String> toJson() => {
    'id': id,
    'name': name,
    'provider': provider.name,
    'endpoint': endpoint,
    'model': model,
  };

  static LlmSettings? fromJson(Object? value) {
    if (value is! Map) return null;
    String? string(String key) =>
        value[key] is String ? value[key] as String : null;
    final provider = LlmProvider.values.where(
      (item) => item.name == string('provider'),
    );
    final id = string('id');
    final name = string('name');
    final endpoint = string('endpoint');
    final model = string('model');
    if (provider.length != 1 ||
        id == null ||
        id.isEmpty ||
        name == null ||
        name.isEmpty ||
        endpoint == null ||
        model == null) {
      return null;
    }
    return LlmSettings(
      id: id,
      name: name,
      provider: provider.single,
      endpoint: endpoint,
      model: model,
    );
  }
}

class LlmConnectionSettings {
  const LlmConnectionSettings({
    required this.connections,
    required this.activeConnectionId,
  }) : assert(connections.length > 0);

  final List<LlmSettings> connections;
  final String activeConnectionId;

  LlmSettings get active => connections.firstWhere(
    (connection) => connection.id == activeConnectionId,
    orElse: () => connections.first,
  );
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
