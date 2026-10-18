import 'dart:async';
import 'dart:convert';

import 'package:decma/domain/models/app_settings.dart';
import 'package:decma/utils/network.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../fixtures/llm_fixtures.dart';
import '../../fixtures/agent_fixtures.dart';

void main() {
  // EOF before a native finish event must never commit a partial reply.
  for (final provider in [
    LlmProvider.anthropic,
    LlmProvider.openAiCompletions,
  ]) {
    // Complete-looking arguments are not permission to execute an unfinished turn.
    test('$provider does not execute tools before a terminal finish', () async {
      var calls = 0;
      final all = toolEvents(provider);
      final events = provider == LlmProvider.openAiCompletions
          ? all.replaceFirst(
              '"finish_reason":"tool_calls"',
              '"finish_reason":null',
            )
          : all.substring(0, all.indexOf('data: {"type":"message_delta"'));
      final client = MockClient.streaming(
        (_, _) async => http.StreamedResponse(
          Stream.value(utf8.encode(events)),
          200,
          headers: {'content-type': 'text/event-stream'},
        ),
      );
      try {
        await expectLater(
          generateReply(
            settings: testSettings(provider),
            client: client,
            tools: [
              priceTool(
                call: (_, _) async {
                  calls++;
                  return '123';
                },
              ),
            ],
          ),
          throwsA(
            isA<AppFailure>().having(
              (e) => e.kind,
              'kind',
              AppFailureKind.invalidResponse,
            ),
          ),
        );
        expect(calls, 0);
      } finally {
        client.close();
      }
    });
    test('$provider rejects a stream without its terminal event', () async {
      final client = MockClient.streaming(
        (_, _) async => http.StreamedResponse(
          Stream.value(utf8.encode(firstTextEvent(provider))),
          200,
          headers: {'content-type': 'text/event-stream'},
        ),
      );
      try {
        await expectLater(
          generateReply(
            client: client,
            settings: LlmSettings(
              provider: provider,
              endpoint:
                  'https://llm.test${provider == LlmProvider.anthropic ? '' : '/v1'}',
              model: 'test-model',
            ),
            apiKey: 'key',
            input: 'Hi',
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
    });
  }

  // Anthropic indexes content blocks, not separate assistant replies.
  test(
    'Anthropic retains previous text blocks before the terminal event',
    () async {
      final release = Completer<void>();
      final secondBlock = Completer<void>();
      final snapshots = <String>[];
      final client = MockClient.streaming(
        (_, _) async => http.StreamedResponse(
          () async* {
            yield utf8.encode(
              firstTextEvent(LlmProvider.anthropic) +
                  sse({'type': 'content_block_stop', 'index': 0}) +
                  sse({
                    'type': 'content_block_start',
                    'index': 1,
                    'content_block': {'type': 'text', 'text': ''},
                  }) +
                  sse({
                    'type': 'content_block_delta',
                    'index': 1,
                    'delta': {'type': 'text_delta', 'text': ' world'},
                  }),
            );
            await release.future;
            yield utf8.encode(
              sse({'type': 'content_block_stop', 'index': 1}) +
                  sse({
                    'type': 'message_delta',
                    'delta': {'stop_reason': 'end_turn', 'stop_sequence': null},
                    'usage': {'output_tokens': 2},
                  }) +
                  sse({'type': 'message_stop'}),
            );
          }(),
          200,
          headers: {'content-type': 'text/event-stream'},
        ),
      );
      final work = generateReply(
        client: client,
        settings: const LlmSettings(
          provider: LlmProvider.anthropic,
          endpoint: 'https://llm.test',
          model: 'test-model',
        ),
        apiKey: 'key',
        input: 'Hi',
        onText: (text) {
          snapshots.add(text);
          if (text.endsWith(' world') && !secondBlock.isCompleted) {
            secondBlock.complete();
          }
        },
      );
      try {
        await secondBlock.future.timeout(const Duration(seconds: 2));
        expect(snapshots.last, 'Hello world');
      } finally {
        release.complete();
        await work;
        client.close();
      }
    },
  );
}
