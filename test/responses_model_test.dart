import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:decma/models/trading_models.dart';
import 'package:decma/utils/network.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genkit/genkit.dart';
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
  // Generic gateways use the same stateless replay as OpenAI and Codex.
  test(
    'Responses preserves every tool round without server-side state',
    () async {
      final bodies = <Map<String, dynamic>>[];
      final plainReasoning = {
        'type': 'reasoning',
        'id': 'rs_2',
        'summary': <Object>[],
        'content': [
          {'type': 'reasoning_text', 'text': 'Check the price again.'},
        ],
      };
      final secondCall = {...toolOutput, 'id': 'fc_2', 'call_id': 'call_2'};
      final client = MockClient.streaming((_, bytes) async {
        bodies.add(
          jsonDecode(utf8.decode(await bytes.toBytes()))
              as Map<String, dynamic>,
        );
        final events = bodies.length <= 2
            ? sse({
                'type': 'response.completed',
                'sequence_number': 1,
                'response': responseFixture(
                  bodies.length == 1
                      ? [reasoningOutput, toolOutput]
                      : [plainReasoning, secondCall],
                ),
              })
            : firstTextEvent(LlmProvider.openAiResponses) +
                  lastTextEvents(LlmProvider.openAiResponses);
        return http.StreamedResponse(
          Stream.value(utf8.encode(events)),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });
      try {
        expect(
          await generateReply(
            settings: testSettings(LlmProvider.openAiResponses),
            client: client,
            input: 'Price?',
            tools: [priceTool()],
          ),
          'Hello world',
        );
        expect(bodies, hasLength(3));
        for (final body in bodies) {
          expect(body['store'], false);
          expect(body['include'], ['reasoning.encrypted_content']);
          expect(body.containsKey('previous_response_id'), false);
        }
        final history = bodies.last['input'] as List;
        expect(history.first['role'], 'user');
        expect(
          (history.first['content'] as List).first['text'],
          contains('Price?'),
        );
        expect(history.skip(1).toList(), [
          reasoningOutput,
          toolOutput,
          {
            'type': 'function_call_output',
            'call_id': 'call_1',
            'output': '123',
          },
          plainReasoning,
          secondCall,
          {
            'type': 'function_call_output',
            'call_id': 'call_2',
            'output': '123',
          },
        ]);
      } finally {
        client.close();
      }
    },
  );

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
      var requests = 0;
      final client = MockClient.streaming((_, _) async {
        requests++;
        return http.StreamedResponse(
          Stream.value(utf8.encode(firstTextEvent(_settings.provider))),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });
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
        expect(requests, 3);
      } finally {
        client.close();
      }
    },
  );

  // Retrying one model turn must replace its draft and keep completed tool work.
  test(
    'Codex retries the failed turn without duplicate text or tools',
    () async {
      final bodies = <Map<String, dynamic>>[];
      final snapshots = <String>[];
      final activities = <String>[];
      var toolCalls = 0;
      final client = MockClient.streaming((_, bytes) async {
        bodies.add(
          jsonDecode(utf8.decode(await bytes.toBytes()))
              as Map<String, dynamic>,
        );
        final events = switch (bodies.length) {
          1 => toolEvents(_settings.provider),
          2 => firstTextEvent(_settings.provider),
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
      try {
        expect(
          await generateReply(
            settings: _settings,
            client: client,
            onText: snapshots.add,
            onActivity: activities.add,
            tools: [
              priceTool(
                call: (_, _) async {
                  toolCalls++;
                  return '123';
                },
              ),
            ],
          ),
          'Hello world',
        );
        expect(bodies, hasLength(3));
        expect(bodies[2], bodies[1]);
        expect(toolCalls, 1);
        expect(snapshots, isNot(contains('HelloHello')));
        expect(snapshots.last, 'Hello world');
        expect(activities.any((text) => text.contains('1/2')), true);
      } finally {
        client.close();
      }
    },
  );

  // A cancellation during backoff must not start another HTTP request.
  test('Codex cancellation interrupts retry backoff', () async {
    final cancel = CancellationController();
    final retry = Completer<void>();
    var requests = 0;
    final client = MockClient.streaming((_, _) async {
      requests++;
      return http.StreamedResponse(
        Stream.value(utf8.encode(firstTextEvent(_settings.provider))),
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    });
    try {
      final work = generateReply(
        settings: _settings,
        client: client,
        cancel: cancel.token,
        onActivity: (text) {
          if (text.contains('1/2')) retry.complete();
        },
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
      await retry.future.timeout(const Duration(seconds: 5));
      cancel.cancel();
      await assertion.timeout(const Duration(seconds: 1));
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(requests, 1);
    } finally {
      cancel.cancel();
      client.close();
    }
  });

  // Explicit terminal failures are not mistaken for retryable EOF.
  for (final type in ['failed', 'incomplete']) {
    test('Codex preserves $type reason without retrying', () async {
      var requests = 0;
      final client = MockClient.streaming((_, _) async {
        requests++;
        return http.StreamedResponse(
          Stream.value(
            utf8.encode(
              firstTextEvent(_settings.provider) +
                  sse({
                    'type': 'response.$type',
                    'sequence_number': 2,
                    'response': {
                      ...responseFixture([]),
                      'status': type,
                      if (type == 'failed')
                        'error': {
                          'code': 'invalid_prompt',
                          'message': 'Rejected prompt',
                        },
                      if (type == 'incomplete')
                        'incomplete_details': {'reason': 'max_output_tokens'},
                    },
                  }),
            ),
          ),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });
      try {
        await expectLater(
          generateReply(settings: _settings, client: client),
          throwsA(
            isA<AppFailure>().having(
              (e) => e.message,
              'reason',
              contains(
                type == 'failed' ? 'invalid_prompt' : 'max_output_tokens',
              ),
            ),
          ),
        );
        expect(requests, 1);
      } finally {
        client.close();
      }
    });
  }

  // Only transient HTTP failures may consume the retry budget.
  for (final status in [400, 401, 429, 503]) {
    test('Codex handles HTTP $status with bounded retries', () async {
      var requests = 0;
      final client = MockClient.streaming((_, _) async {
        requests++;
        return requests == 1
            ? http.StreamedResponse(
                Stream.value(
                  utf8.encode(
                    '{"error":{"message":"Request failed","type":"api_error"}}',
                  ),
                ),
                status,
                headers: {'content-type': 'application/json'},
              )
            : http.StreamedResponse(
                Stream.value(
                  utf8.encode(
                    firstTextEvent(_settings.provider) +
                        lastTextEvents(_settings.provider),
                  ),
                ),
                200,
                headers: {'content-type': 'text/event-stream'},
              );
      });
      try {
        final work = generateReply(settings: _settings, client: client);
        if (status == 429 || status == 503) {
          expect(await work, 'Hello world');
          expect(requests, 2);
        } else {
          await expectLater(
            work,
            throwsA(
              isA<AppFailure>().having(
                (e) => e.kind,
                'kind',
                status == 401
                    ? AppFailureKind.authentication
                    : AppFailureKind.invalidResponse,
              ),
            ),
          );
          expect(requests, 1);
        }
      } finally {
        client.close();
      }
    });
  }

  // A done tool item is still unsafe without a successful response terminal.
  test('Codex does not execute tool output from a truncated attempt', () async {
    var requests = 0;
    var toolCalls = 0;
    final client = MockClient.streaming((_, _) async {
      requests++;
      return http.StreamedResponse(
        Stream.value(
          utf8.encode(
            requests == 1
                ? sse({
                    'type': 'response.output_item.done',
                    'sequence_number': 1,
                    'output_index': 0,
                    'item': toolOutput,
                  })
                : firstTextEvent(_settings.provider) +
                      lastTextEvents(_settings.provider),
          ),
        ),
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    });
    try {
      expect(
        await generateReply(
          settings: _settings,
          client: client,
          tools: [
            priceTool(
              call: (_, _) async {
                toolCalls++;
                return '123';
              },
            ),
          ],
        ),
        'Hello world',
      );
      expect(requests, 2);
      expect(toolCalls, 0);
    } finally {
      client.close();
    }
  });

  // An explicit error frame must not disappear behind a generic EOF message.
  test('Codex preserves error events without blind retries', () async {
    var requests = 0;
    final client = MockClient.streaming((_, _) async {
      requests++;
      return http.StreamedResponse(
        Stream.value(
          utf8.encode(
            sse({
              'type': 'error',
              'code': 'invalid_request',
              'message': 'Unsupported input',
            }),
          ),
        ),
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    });
    try {
      await expectLater(
        generateReply(settings: _settings, client: client),
        throwsA(
          isA<AppFailure>().having(
            (e) => e.message,
            'reason',
            contains('invalid_request'),
          ),
        ),
      );
      expect(requests, 1);
    } finally {
      client.close();
    }
  });

  // Body-stream transport errors can escape Dio/SDK exception wrappers.
  test('Codex retries a connection reset after partial text', () async {
    var requests = 0;
    final snapshots = <String>[];
    final client = MockClient.streaming((_, _) async {
      requests++;
      return http.StreamedResponse(
        () async* {
          yield utf8.encode(firstTextEvent(_settings.provider));
          if (requests == 1) throw const SocketException('Connection reset');
          yield utf8.encode(lastTextEvents(_settings.provider));
        }(),
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    });
    try {
      expect(
        await generateReply(
          settings: _settings,
          client: client,
          onText: snapshots.add,
        ),
        'Hello world',
      );
      expect(requests, 2);
      expect(snapshots, isNot(contains('HelloHello')));
    } finally {
      client.close();
    }
  });

  // Malformed frames must not be silently dropped or treated as normal EOF.
  test('Codex reports malformed SSE JSON without retrying', () async {
    var requests = 0;
    final client = MockClient.streaming((_, _) async {
      requests++;
      return http.StreamedResponse(
        Stream.value(
          utf8.encode(
            '${firstTextEvent(_settings.provider)}data: {broken json}\n\n'
            '${lastTextEvents(_settings.provider)}',
          ),
        ),
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    });
    try {
      await expectLater(
        generateReply(settings: _settings, client: client),
        throwsA(
          isA<AppFailure>().having(
            (e) => e.message,
            'reason',
            contains('解析失败'),
          ),
        ),
      );
      expect(requests, 1);
    } finally {
      client.close();
    }
  });
}
