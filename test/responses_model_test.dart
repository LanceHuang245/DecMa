import 'dart:convert';

import 'package:decma/models/trading_models.dart';
import 'package:decma/utils/network.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'llm_fixtures.dart';
import 'agent_fixtures.dart';

const _settings = LlmSettings(
  provider: LlmProvider.openAiCodex,
  endpoint: 'https://llm.test/v1/responses',
  model: 'test-model',
);

void main() {
  // Some Codex gateways put items only in done events, not in the terminal body.
  test(
    'Codex replays ordered done items when completed output is omitted',
    () async {
      final bodies = <Map<String, dynamic>>[];
      final client = MockClient.streaming((request, bytes) async {
        bodies.add(
          jsonDecode(utf8.decode(await bytes.toBytes()))
              as Map<String, dynamic>,
        );
        expect(request.url.path, '/v1/responses');
        final events = bodies.length == 1
            ? sse({
                    'type': 'response.output_item.done',
                    'sequence_number': 1,
                    'output_index': 1,
                    'item': toolOutput,
                  }) +
                  sse({
                    'type': 'response.output_item.done',
                    'sequence_number': 2,
                    'output_index': 0,
                    'item': reasoningOutput,
                  }) +
                  sse({
                    'type': 'response.completed',
                    'sequence_number': 3,
                    'response': responseFixture([]),
                  })
            : firstTextEvent(_settings.provider) +
                  lastTextEvents(_settings.provider);
        return http.StreamedResponse(
          Stream.value(utf8.encode(events)),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });
      try {
        final text = await generateReply(
          client: client,
          settings: _settings,
          apiKey: 'key',
          accountId: 'account-1',
          input: 'Price?',
          tools: [priceTool()],
        );
        expect(text, 'Hello world');
        expect(bodies, hasLength(2));
        expect((bodies.last['input'] as List).sublist(1, 3), [
          reasoningOutput,
          toolOutput,
        ]);
      } finally {
        client.close();
      }
    },
  );

  // A successful terminal body can omit text already sent in output deltas.
  test(
    'completed Codex text deltas are retained when terminal output is empty',
    () async {
      final client = MockClient.streaming(
        (_, _) async => http.StreamedResponse(
          Stream.value(
            utf8.encode(
              firstTextEvent(_settings.provider) +
                  sse({
                    'type': 'response.completed',
                    'sequence_number': 2,
                    'response': responseFixture([]),
                  }),
            ),
          ),
          200,
          headers: {'content-type': 'text/event-stream'},
        ),
      );
      try {
        expect(
          await generateReply(
            client: client,
            settings: _settings,
            apiKey: 'key',
            accountId: 'account-1',
            input: 'Hi',
            tools: const [],
          ),
          'Hello',
        );
      } finally {
        client.close();
      }
    },
  );

  // Truncated streams must not turn a partial draft into a successful result.
  test(
    'Codex without a successful terminal event is an invalid response',
    () async {
      final client = MockClient.streaming(
        (_, _) async => http.StreamedResponse(
          Stream.value(utf8.encode(firstTextEvent(_settings.provider))),
          200,
          headers: {'content-type': 'text/event-stream'},
        ),
      );
      try {
        await expectLater(
          generateReply(
            client: client,
            settings: _settings,
            apiKey: 'key',
            accountId: 'account-1',
            input: 'Hi',
            tools: const [],
          ),
          throwsA(
            isA<AppFailure>().having(
              (e) => e.kind,
              'kind',
              AppFailureKind.invalidResponse,
            ),
          ),
        );
      } finally {
        client.close();
      }
    },
  );
}
