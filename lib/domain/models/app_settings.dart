enum LlmProvider { anthropic, openAiResponses, openAiCompletions, openAiCodex }

extension LlmProviderLabel on LlmProvider {
  // Use protocol-level choices when a gateway omits per-model capabilities.
  List<String> get standardReasoningEfforts => const [
    'low',
    'medium',
    'high',
    'xhigh',
    'max',
  ];

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
    this.reasoningEffort = defaultReasoningEffort,
  });

  static const defaultId = 'default';
  static const defaultName = '默认连接';
  // Default to a balanced reasoning level instead of leaving it unset.
  static const defaultReasoningEffort = 'medium';

  final String id;
  final String name;
  final LlmProvider provider;
  final String endpoint;
  final String model;
  final String? reasoningEffort;

  bool get isComplete => endpoint.trim().isNotEmpty && model.trim().isNotEmpty;

  // Store only connection metadata here; credentials remain in secure storage.
  Map<String, String> toJson() => {
    'id': id,
    'name': name,
    'provider': provider.name,
    'endpoint': endpoint,
    'model': model,
    'reasoningEffort': ?reasoningEffort,
  };

  factory LlmSettings.fromJson(Map<String, dynamic> json) => LlmSettings(
    id: json['id'],
    name: json['name'],
    provider: LlmProvider.values.byName(json['provider']),
    endpoint: json['endpoint'],
    model: json['model'],
    reasoningEffort: json['reasoningEffort'] ?? defaultReasoningEffort,
  );
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
    required this.useMarketaux,
    required this.useBls,
    required this.useBea,
    required this.useFederalReserve,
  });

  final bool useFinnhub;
  final bool useMarketaux;
  final bool useBls;
  final bool useBea;
  final bool useFederalReserve;
}
