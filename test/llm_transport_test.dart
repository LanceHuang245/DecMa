import 'dart:convert';

import 'package:decma/models/trading_models.dart';
import 'package:decma/services/llm_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'Codex rebuilds output from SSE items before continuing tool calls',
    () async {
      final requestBodies = <Map<String, dynamic>>[];
      final client = MockClient((request) async {
        requestBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response(
          requestBodies.length == 1 ? _toolCallStream : _textStream,
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });
      final transport = LlmTransport(client);

      final reply = await transport.complete(
        settings: LlmSettings(
          provider: LlmProvider.openAiCodex,
          endpoint: 'https://chatgpt.com/backend-api/codex',
          model: 'gpt-5.6-sol',
        ),
        apiKey: 'access-token',
        codexAccountId: 'account-id',
        system: 'system prompt',
        input: 'analyze BTC',
        tools: const [],
        maxToolRounds: 2,
        callTools: (calls) async => [
          for (final call in calls) LlmToolResult(call.id, '{"tools":[]}'),
        ],
      );

      expect(reply, 'final answer');
      expect(requestBodies, hasLength(2));
      expect(requestBodies[1].containsKey('previous_response_id'), isFalse);
      final input = requestBodies[1]['input'] as List<dynamic>;
      expect(
        input.any((item) => item is Map && item['type'] == 'function_call'),
        isTrue,
      );
      expect(
        input.any(
          (item) => item is Map && item['type'] == 'function_call_output',
        ),
        isTrue,
      );
    },
  );
}

const _toolCallStream = '''event: response.output_item.done
data: {"type":"response.output_item.done","output_index":0,"item":{"id":"fc_1","type":"function_call","status":"completed","arguments":"{\\"query\\":\\"ticker\\"}","call_id":"call_1","name":"discover"}}

event: response.completed
data: {"type":"response.completed","response":{"id":"resp_1","status":"completed","output":[]}}
''';

const _textStream = '''event: response.output_item.done
data: {"type":"response.output_item.done","output_index":0,"item":{"id":"msg_1","type":"message","status":"completed","role":"assistant","content":[{"type":"output_text","text":"final answer"}]}}

event: response.completed
data: {"type":"response.completed","response":{"id":"resp_2","status":"completed","output":[]}}
''';
