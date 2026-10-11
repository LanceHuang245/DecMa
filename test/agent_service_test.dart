import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:decma/models/trading_models.dart';
import 'package:decma/services/agent_service.dart';
import 'package:decma/services/mcp_hub.dart';
import 'package:decma/services/secure_key_store.dart';
import 'package:decma/utils/network.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genkit/genkit.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schemantic/schemantic.dart';

import 'llm_fixtures.dart';
import 'agent_fixtures.dart';

const _settings = LlmSettings(
  provider: LlmProvider.openAiResponses,
  endpoint: 'https://llm.test/v1',
  model: 'test-model',
);
const _mcp = McpSettings(
  useBybit: true,
  useNansen: true,
  useOpenWebSearch: false,
);

void main() {
  // Stopping Codex also cancels an expired-token refresh before generation.
  test(
    'Codex credential refresh observes the run cancellation token',
    () async {
      final cancel = CancellationController();
      final adapter = _StalledHttp();
      final dio = Dio()..httpClientAdapter = adapter;
      final service = AgentService(keyStore: _Keys(), dio: dio);
      try {
        final work = service.run(
          prompt: 'Hi',
          symbol: 'BTCUSDT',
          candles: const [],
          llm: const LlmSettings(
            provider: LlmProvider.openAiCodex,
            endpoint: 'https://llm.test/v1',
            model: 'test-model',
          ),
          mcp: const McpSettings(
            useBybit: false,
            useNansen: false,
            useOpenWebSearch: false,
          ),
          api: const ApiSettings(useCoinalyze: false),
          mode: AgentMode.conversation,
          cancel: cancel.token,
        );
        final assertion = expectLater(
          work,
          throwsA(
            isA<AppFailure>().having(
              (e) => e.kind,
              'kind',
              AppFailureKind.cancelled,
            ),
          ),
        );
        await adapter.started.future;
        cancel.cancel();
        await assertion.timeout(const Duration(seconds: 2));
      } finally {
        adapter.response.complete(ResponseBody.fromString('{}', 200));
        service.dispose();
      }
    },
  );

  // A successful first-pass source must be carried into missing-source repair.
  test(
    'coverage repair reuses evidence and only accepts real successful data',
    () async {
      final bodies = <Map<String, dynamic>>[];
      final hub = _Hub();
      final client = MockClient.streaming((request, bytes) async {
        bodies.add(
          jsonDecode(utf8.decode(await bytes.toBytes()))
              as Map<String, dynamic>,
        );
        final step = bodies.length;
        final events = switch (step) {
          1 => _tool('Bybit_MCP_getPrice'),
          3 => _tool('Nansen_MCP_getFlows'),
          _ =>
            firstTextEvent(_settings.provider) +
                lastTextEvents(_settings.provider),
        };
        return http.StreamedResponse(
          Stream.value(utf8.encode(events)),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });
      final service = AgentService(
        mcpHub: hub,
        keyStore: _Keys(),
        dio: dioForClient(client),
      );
      try {
        final answer = await service.run(
          prompt: AgentService.fullSourceEnrichmentMarker,
          symbol: 'BTCUSDT',
          candles: const [],
          llm: _settings,
          mcp: _mcp,
          api: const ApiSettings(useCoinalyze: false),
          mode: AgentMode.analysis,
        );
        expect(answer.text, 'Hello world');
        expect(hub.calls, ['Bybit_MCP_getPrice', 'Nansen_MCP_getFlows']);
        final repairInput = jsonEncode(bodies[2]['input']);
        expect(repairInput, contains('prior_tool_evidence'));
        expect(repairInput, contains('123'));
        expect(answer.warnings.join(), contains('Nansen MCP'));
        expect(answer.warnings.join(), isNot(contains('Bybit MCP')));
        expect(hub.closed, true);
      } finally {
        service.dispose();
        client.close();
      }
    },
  );

  // Cancelling a revision must not silently return the earlier provisional draft.
  test(
    'cancellation during source repair does not fall back to success',
    () async {
      final cancel = CancellationController();
      var requests = 0;
      var passes = 0;
      final client = MockClient.streaming((request, bytes) async {
        requests++;
        return http.StreamedResponse(
          () async* {
            yield utf8.encode(firstTextEvent(_settings.provider));
            if (requests == 1) {
              yield utf8.encode(lastTextEvents(_settings.provider));
            } else {
              await cancel.token.whenCancelled;
            }
          }(),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });
      final service = AgentService(
        mcpHub: _Hub(),
        keyStore: _Keys(),
        dio: dioForClient(client),
      );
      try {
        await expectLater(
          service.run(
            prompt: AgentService.fullSourceEnrichmentMarker,
            symbol: 'BTCUSDT',
            candles: const [],
            llm: _settings,
            mcp: _mcp,
            api: const ApiSettings(useCoinalyze: false),
            mode: AgentMode.analysis,
            cancel: cancel.token,
            onText: (text) {
              if (text.isEmpty) passes++;
              if (passes == 2 && text == 'Hello') cancel.cancel();
            },
          ),
          throwsA(
            isA<AppFailure>().having(
              (e) => e.kind,
              'kind',
              AppFailureKind.cancelled,
            ),
          ),
        );
        expect(requests, 2);
      } finally {
        service.dispose();
        client.close();
      }
    },
  );
}

// Mock only remote MCP data and secure credentials; run the real Agent/Genkit.
class _Hub extends McpHub {
  final calls = <String>[];
  bool closed = false;
  @override
  Set<String> get availableServers => {'Bybit MCP', 'Nansen MCP'};
  @override
  Future<List<Tool>> prepare(
    McpSettings settings, {
    String? nansenApiKey,
    CancellationToken? cancel,
    bool eager = false,
  }) async => [
    for (final name in ['Bybit_MCP_getPrice', 'Nansen_MCP_getFlows'])
      Tool<Map<String, dynamic>, Object?>(
        name: name,
        description: 'Public data',
        inputSchema: SchemanticType.from(
          jsonSchema: {
            'type': 'object',
            'properties': {
              'symbol': {'type': 'string'},
            },
            'required': ['symbol'],
          },
          parse: (value) => Map<String, dynamic>.from(value as Map),
        ),
        fn: (input, ctx) async =>
            .response(await call(name, input, cancel: ctx.cancel)),
      ),
  ];
  @override
  Future<Map<String, dynamic>> call(
    String functionName,
    Map<String, dynamic> arguments, {
    CancellationToken? cancel,
  }) async {
    calls.add(functionName);
    return functionName.startsWith('Bybit')
        ? {
            'content': [
              {'type': 'text', 'text': '123'},
            ],
          }
        : {
            'isError': true,
            'content': [
              {'type': 'text', 'text': 'unavailable'},
            ],
          };
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

class _Keys extends SecureKeyStore {
  @override
  Future<CodexOAuthCredentials?> readCodexOAuth() async =>
      CodexOAuthCredentials(
        accessToken: 'expired',
        refreshToken: 'refresh',
        accountId: 'account-1',
        expiresAt: DateTime.utc(2000),
      );
  @override
  Future<String?> readLlmKey({
    String connectionId = LlmSettings.defaultId,
  }) async => 'key';
  @override
  Future<String?> readNansenKey() async => 'key';
  @override
  Future<String?> readBybitApiKey() async => null;
  @override
  Future<String?> readBybitApiSecret() async => null;
}

// Stall only the HTTP boundary so Dio itself must honor the supplied token.
class _StalledHttp implements HttpClientAdapter {
  final started = Completer<void>();
  final response = Completer<ResponseBody>();
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    started.complete();
    return response.future;
  }

  @override
  void close({bool force = false}) {}
}

// Emit a provider-level function request with literal arguments and stable IDs.
String _tool(String name) => sse({
  'type': 'response.completed',
  'sequence_number': 1,
  'response': responseFixture([
    {...toolOutput, 'name': name},
  ]),
});
