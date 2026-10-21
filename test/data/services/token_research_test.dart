import 'dart:convert';

import 'package:decma/data/repositories/asset_resolver.dart';
import 'package:decma/data/services/agent_service.dart';
import 'package:decma/data/services/token_research.dart';
import 'package:decma/domain/models/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genkit/genkit.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schemantic/schemantic.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../../fixtures/agent_fixtures.dart';
import '../../fixtures/llm_fixtures.dart';

const _url = 'https://ethereum.org';
const _summary = 'Ethereum: smart contracts; ETH pays execution fees.';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test(
    'background persists per asset for seven days; catalyst windows advance',
    () async {
      final now = DateTime.utc(2026, 10, 21, 12);
      final research = TokenResearch(assets: AssetResolver.memory());
      await research.save(
        'ETHUSDT',
        summary: _summary,
        sourceUrls: [_url],
        fetchedUrls: {_url},
        now: now,
      );
      final restored = TokenResearch(assets: AssetResolver.memory());
      final next = now.add(const Duration(days: 1));
      final context = await restored.context(
        'ethusdt',
        now: next,
        searchAvailable: true,
      );
      expect((context['background'] as Map)['summary'], _summary);
      expect((context['background'] as Map)['source_urls'], [_url]);
      expect(context['background_refresh_required'], false);
      expect(
        (context['search_queries'] as Map).containsKey('background'),
        false,
      );
      expect(
        context['recent_since'],
        next.subtract(const Duration(hours: 72)).toIso8601String(),
      );
      expect(
        context['upcoming_until'],
        next.add(const Duration(days: 7)).toIso8601String(),
      );
      expect(
        (await restored.context(
          'BTCUSDT',
          now: next,
          searchAvailable: true,
        ))['background'],
        null,
      );
      expect(
        (await restored.context(
          'ETHUSDT',
          now: now.add(const Duration(days: 7)),
          searchAvailable: true,
        ))['background_refresh_required'],
        true,
      );
    },
  );

  // Exercise the real bridge middleware, cache tool, persistence and next-run context.
  for (final fetchFails in [false, true]) {
    test(
      'Agent reuses existing web tools; failed fetch cannot seed cache, fails=$fetchFails',
      () async {
        final bodies = <Map<String, dynamic>>[];
        final hub = _WebHub(fetchFails: fetchFails);
        final research = TokenResearch(assets: AssetResolver.memory());
        final client = MockClient.streaming((_, bytes) async {
          bodies.add(
            jsonDecode(utf8.decode(await bytes.toBytes()))
                as Map<String, dynamic>,
          );
          final step = bodies.length;
          final events = step <= 3
              ? sse({
                  'type': 'response.completed',
                  'sequence_number': 1,
                  'response': responseFixture([
                    {
                      ...toolOutput,
                      'id': 'fc_$step',
                      'call_id': 'call_$step',
                      'name': step == 3
                          ? 'decma_cache_token_background'
                          : 'decma_call_mcp_tool',
                      'arguments': jsonEncode(
                        step == 3
                            ? {
                                'summary': _summary,
                                'source_urls': [_url],
                              }
                            : {
                                'tool_name': step == 1
                                    ? 'OpenWebSearch_MCP_search'
                                    : 'OpenWebSearch_MCP_fetchWebContent',
                                'arguments': step == 1
                                    ? {
                                        'query':
                                            'Ethereum ETH official token utility',
                                      }
                                    : {'url': _url},
                              },
                      ),
                    },
                  ]),
                })
              : firstTextEvent(LlmProvider.openAiResponses) +
                    lastTextEvents(LlmProvider.openAiResponses);
          return http.StreamedResponse(
            Stream.value(utf8.encode(events)),
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        });
        final service = AgentService(
          mcpHub: hub,
          keyStore: TestKeys(),
          tokenResearch: research,
          dio: dioForClient(client),
        );
        addTearDown(service.dispose);
        addTearDown(client.close);
        Future<String> analyze() async => (await service.run(
          prompt: 'Analyze entry',
          symbol: 'ETHUSDT',
          candles: const [],
          llm: testSettings(LlmProvider.openAiResponses),
          mcp: const McpSettings(
            useBybit: false,
            useNansen: false,
            useOpenWebSearch: true,
          ),
          api: const ApiSettings(useCoinalyze: false),
        )).text;
        expect(await analyze(), 'Hello world');
        expect(hub.calls, [
          'OpenWebSearch_MCP_search',
          'OpenWebSearch_MCP_fetchWebContent',
        ]);
        final cached = await research.context(
          'ETHUSDT',
          now: DateTime.now().toUtc(),
          searchAvailable: true,
        );
        expect(cached['background_refresh_required'], fetchFails);
        expect(await analyze(), 'Hello world');
        expect(
          jsonEncode(bodies.last['input']).contains(_summary),
          !fetchFails,
        );
      },
    );
  }
}

class _WebHub extends ToolHub {
  _WebHub({required this.fetchFails}) : super([]);
  final bool fetchFails;
  final calls = <String>[];
  @override
  Set<String> get availableServers => {'OpenWebSearch MCP'};

  @override
  Future<List<Tool>> prepare(
    McpSettings settings, {
    String? nansenApiKey,
    CancellationToken? cancel,
  }) async => [
    Tool<Map<String, dynamic>, Object?>(
      name: 'decma_call_mcp_tool',
      description: 'Existing MCP bridge',
      inputSchema: SchemanticType.from(
        jsonSchema: const {
          'type': 'object',
          'properties': {
            'tool_name': {'type': 'string'},
            'arguments': {'type': 'object'},
          },
          'required': ['tool_name', 'arguments'],
        },
        parse: (value) => Map<String, dynamic>.from(value as Map),
      ),
      fn: (input, ctx) async {
        calls.add(input['tool_name'] as String);
        final fetch = calls.last.endsWith('fetchWebContent');
        return .response({
          if (fetch && fetchFails) 'isError': true,
          'content': [
            {
              'type': 'text',
              'text': fetch
                  ? (fetchFails
                        ? 'Page unavailable'
                        : 'ETH is used to pay Ethereum transaction fees.')
                  : 'Official Ethereum documentation: $_url',
            },
          ],
        });
      },
    ),
  ];
}
