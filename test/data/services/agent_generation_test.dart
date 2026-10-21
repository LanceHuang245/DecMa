import 'dart:async';
import 'dart:convert';

import 'package:decma/domain/models/app_settings.dart';
import 'package:decma/utils/network.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genkit/genkit.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../fixtures/agent_fixtures.dart';
import '../../fixtures/llm_fixtures.dart';

void main() {
  // Plugin content indexes must not merge earlier model turns into the final draft.
  test('Chat Completions separates tool turns from the final result', () async {
    var requests = 0;
    final snapshots = <String>[];
    final client = MockClient.streaming((_, _) async {
      requests++;
      return _response(
        firstTextEvent(LlmProvider.openAiCompletions) +
            (requests < 3
                ? toolEvents(LlmProvider.openAiCompletions)
                : lastTextEvents(LlmProvider.openAiCompletions)),
      );
    });
    try {
      expect(
        await generateReply(
          settings: testSettings(LlmProvider.openAiCompletions),
          client: client,
          tools: [priceTool()],
          onText: snapshots.add,
        ),
        'Hello world',
      );
      expect(snapshots, isNot(contains('HelloHello')));
      final segments = <String>[];
      for (final snapshot in snapshots) {
        if (snapshot.isEmpty) {
          segments.add('');
        } else {
          segments[segments.length - 1] = snapshot;
        }
      }
      expect(segments.where((text) => text.isNotEmpty), [
        'Hello',
        'Hello',
        'Hello world',
      ]);
    } finally {
      client.close();
    }
  });

  // Verify actual request routing, auth, incremental output and tool history.
  for (final provider in LlmProvider.values) {
    test('$provider emits text before the request completes', () async {
      final release = Completer<void>();
      final received = Completer<void>();
      final snapshots = <String>[];
      final client = MockClient.streaming((request, bytes) async {
        final body = jsonDecode(utf8.decode(await bytes.toBytes())) as Map;
        expect(body['stream'], true);
        expect(request.url.path, switch (provider) {
          LlmProvider.anthropic => '/v1/messages',
          LlmProvider.openAiCompletions => '/v1/chat/completions',
          _ => '/v1/responses',
        });
        expect(
          request.headers[provider == LlmProvider.anthropic
              ? 'x-api-key'
              : 'authorization'],
          provider == LlmProvider.anthropic ? 'test-key' : 'Bearer test-key',
        );
        if (provider == LlmProvider.openAiCodex) {
          expect(request.headers['chatgpt-account-id'], 'account-1');
        }
        if (provider == LlmProvider.openAiResponses ||
            provider == LlmProvider.openAiCodex) {
          expect(body['store'], false);
          expect(body['include'], ['reasoning.encrypted_content']);
          expect(body.containsKey('previous_response_id'), false);
        }
        return http.StreamedResponse(
          () async* {
            yield utf8.encode(firstTextEvent(provider));
            await release.future;
            yield utf8.encode(lastTextEvents(provider));
          }(),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });
      final work = generateReply(
        settings: testSettings(provider),
        client: client,
        apiKey: 'test-key',
        onText: (text) {
          snapshots.add(text);
          if (text == 'Hello' && !received.isCompleted) received.complete();
        },
      );
      try {
        await received.future.timeout(const Duration(seconds: 5));
        expect(snapshots, contains('Hello'));
      } finally {
        release.complete();
      }
      expect(await work, 'Hello world');
      expect(snapshots.last, 'Hello world');
      client.close();
    });

    test(
      '$provider continues with matching tool IDs and provider history',
      () async {
        final bodies = <Map<String, dynamic>>[];
        final client = MockClient.streaming((_, bytes) async {
          bodies.add(
            jsonDecode(utf8.decode(await bytes.toBytes()))
                as Map<String, dynamic>,
          );
          return _response(
            bodies.length == 1
                ? toolEvents(provider)
                : firstTextEvent(provider) + lastTextEvents(provider),
          );
        });
        try {
          expect(
            await generateReply(
              settings: testSettings(provider),
              client: client,
              tools: [
                priceTool(
                  call: (input, ctx) async {
                    expect(input, {'symbol': 'BTCUSDT'});
                    expect(ctx.toolRequest!.toolRequest.ref, 'call_1');
                    return '123';
                  },
                ),
              ],
            ),
            'Hello world',
          );
          expect(bodies, hasLength(2));
          expect(bodies.last['tools'], isNotEmpty);
          if (provider == LlmProvider.openAiResponses ||
              provider == LlmProvider.openAiCodex) {
            expect(bodies.last.containsKey('previous_response_id'), false);
            expect(bodies.last['input'], contains(equals(reasoningOutput)));
            expect(bodies.last['input'], contains(equals(toolOutput)));
            expect(
              bodies.last['input'],
              contains(
                equals({
                  'type': 'function_call_output',
                  'call_id': 'call_1',
                  'output': '123',
                }),
              ),
            );
          } else {
            expect(jsonEncode(bodies.last['messages']), contains('call_1'));
            expect(jsonEncode(bodies.last['messages']), contains('123'));
          }
        } finally {
          client.close();
        }
      },
    );

    test('$provider preserves authentication errors', () async {
      final client = MockClient(
        (_) async => http.Response(
          '{"type":"error","error":{"message":"Invalid key","type":"authentication_error"}}',
          401,
          headers: {'content-type': 'application/json'},
        ),
      );
      try {
        await expectLater(
          generateReply(settings: testSettings(provider), client: client),
          throwsA(
            isA<AppFailure>().having(
              (e) => e.kind,
              'kind',
              AppFailureKind.authentication,
            ),
          ),
        );
      } finally {
        client.close();
      }
    });

    test('$provider never exceeds the 24-turn budget', () async {
      var requests = 0;
      final client = MockClient.streaming((_, _) async {
        requests++;
        return _response(toolEvents(provider));
      });
      try {
        await expectLater(
          generateReply(
            settings: testSettings(provider),
            client: client,
            tools: [priceTool()],
          ),
          throwsA(isA<Exception>()),
        );
        expect(requests, 24);
      } finally {
        client.close();
      }
    });
  }

  // Stopping a native tool must not initiate another model request.
  test('cancellation during a tool stops the loop promptly', () async {
    final started = Completer<void>();
    final tool = Completer<String>();
    final cancel = CancellationController();
    var requests = 0;
    final client = MockClient.streaming((_, _) async {
      requests++;
      return _response(toolEvents(LlmProvider.openAiResponses));
    });
    final work = generateReply(
      settings: testSettings(LlmProvider.openAiResponses),
      client: client,
      cancel: cancel.token,
      tools: [
        priceTool(
          call: (_, _) {
            started.complete();
            return tool.future;
          },
        ),
      ],
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
    await started.future;
    cancel.cancel();
    await assertion.timeout(const Duration(seconds: 2));
    tool.complete('123');
    expect(requests, 1);
    client.close();
  });
}

http.StreamedResponse _response(String events) => http.StreamedResponse(
  Stream.value(utf8.encode(events)),
  200,
  headers: {'content-type': 'text/event-stream'},
);
