import 'dart:typed_data';

import 'package:decma/models/trading_models.dart';
import 'package:decma/services/agent_service.dart';
import 'package:decma/services/mcp_hub.dart';
import 'package:decma/services/secure_key_store.dart';
import 'package:dio/dio.dart';
import 'package:genkit/genkit.dart';
import 'package:http/http.dart' as http;
import 'package:schemantic/schemantic.dart';

// Keep existing wire fixtures while all production requests go through real Dio.
Dio dioForClient(http.Client client) =>
    Dio(BaseOptions(validateStatus: (_) => true))
      ..httpClientAdapter = _ClientAdapter(client);

class _ClientAdapter implements HttpClientAdapter {
  _ClientAdapter(this.client);
  final http.Client client;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? body,
    Future<void>? cancelFuture,
  ) async {
    final request = http.Request(
      options.method,
      options.uri,
    )..headers.addAll(options.headers.map((k, v) => MapEntry(k, v.toString())));
    if (body != null) {
      request.bodyBytes = await body.expand((bytes) => bytes).toList();
    }
    final response = await client.send(request);
    return ResponseBody(
      response.stream.map(Uint8List.fromList),
      response.statusCode,
      headers: response.headers.map((k, v) => MapEntry(k, [v])),
    );
  }

  @override
  void close({bool force = false}) {}
}

// Supply native tools at the remote boundary rather than mocking Agent logic.
class ToolHub extends McpHub {
  ToolHub(this.tools);
  final List<Tool> tools;
  @override
  Future<List<Tool>> prepare(
    McpSettings settings, {
    String? nansenApiKey,
    CancellationToken? cancel,
  }) async => tools;
}

class TestKeys extends SecureKeyStore {
  TestKeys({this.key = 'key', this.account = 'account-1'});
  final String key;
  final String account;
  @override
  Future<String?> readLlmKey({
    String connectionId = LlmSettings.defaultId,
  }) async => key;
  @override
  Future<CodexOAuthCredentials?> readCodexOAuth() async =>
      CodexOAuthCredentials(
        accessToken: key,
        refreshToken: 'refresh',
        accountId: account,
        expiresAt: DateTime.utc(2099),
      );
}

// Exercise the complete production Agent/Genkit/Dio path for each protocol.
Future<String> generateReply({
  required LlmSettings settings,
  http.Client? client,
  String apiKey = 'key',
  String accountId = 'account-1',
  String input = 'Hi',
  List<Tool> tools = const [],
  CancellationToken? cancel,
  void Function(String)? onText,
  void Function(String)? onActivity,
}) async {
  final dio = client == null ? null : dioForClient(client);
  final service = AgentService(
    dio: dio,
    keyStore: TestKeys(key: apiKey, account: accountId),
    mcpHub: ToolHub(tools),
  );
  try {
    return (await service.run(
      prompt: input,
      symbol: 'BTCUSDT',
      candles: const [],
      llm: settings,
      mcp: const McpSettings(
        useBybit: false,
        useNansen: false,
        useOpenWebSearch: false,
      ),
      api: const ApiSettings(useCoinalyze: false),
      cancel: cancel,
      onText: onText,
      onActivity: onActivity,
    )).text;
  } finally {
    service.dispose();
    dio?.close(force: true);
  }
}

// Use a real Genkit Tool; the application no longer creates tool-call DTOs.
Tool priceTool({
  Future<String> Function(
    Map<String, dynamic>,
    ToolFnArg<Map<String, dynamic>>,
  )?
  call,
}) => Tool<Map<String, dynamic>, String>(
  name: 'get_price',
  description: 'Get a public price',
  inputSchema: SchemanticType.from(
    jsonSchema: const {
      'type': 'object',
      'properties': {
        'symbol': {'type': 'string'},
      },
      'required': ['symbol'],
      'additionalProperties': false,
    },
    parse: (value) => Map<String, dynamic>.from(value as Map),
  ),
  fn: (input, ctx) async =>
      .response(call == null ? '123' : await call(input, ctx)),
);

LlmSettings testSettings(LlmProvider provider) => LlmSettings(
  provider: provider,
  endpoint: switch (provider) {
    LlmProvider.anthropic => 'https://llm.test/v1/messages',
    LlmProvider.openAiCompletions => 'https://llm.test/v1/chat/completions',
    _ => 'https://llm.test/v1/responses',
  },
  model: 'test-model',
);
