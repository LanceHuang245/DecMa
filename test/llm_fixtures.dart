// Keep independently encoded SSE frames readable in the protocol fixtures.
// ignore_for_file: prefer_interpolation_to_compose_strings
import 'dart:convert';

import 'package:decma/models/trading_models.dart';

// Encode complete provider events without using the production converters.
String sse(Map<String, dynamic> event) => 'data: ${jsonEncode(event)}\n\n';

Map<String, dynamic> responseFixture(List<Map<String, dynamic>> output) => {
  'id': 'resp_1',
  'object': 'response',
  'created_at': 1,
  'status': 'completed',
  'model': 'test-model',
  'output': output,
};

const textOutput = {
  'type': 'message',
  'id': 'msg_1',
  'role': 'assistant',
  'status': 'completed',
  'content': [
    {'type': 'output_text', 'text': 'Hello world', 'annotations': []},
  ],
};

const toolOutput = {
  'type': 'function_call',
  'id': 'fc_1',
  'call_id': 'call_1',
  'name': 'get_price',
  'arguments': '{"symbol":"BTCUSDT"}',
  'status': 'completed',
};

const reasoningOutput = {
  'type': 'reasoning',
  'id': 'rs_1',
  'summary': [],
  'encrypted_content': 'opaque-reasoning',
};

// Emit a genuine text delta first and the final response only after a gate.
String firstTextEvent(LlmProvider provider) => switch (provider) {
  LlmProvider.anthropic =>
    sse({
          'type': 'message_start',
          'message': {
            'id': 'msg_1',
            'type': 'message',
            'role': 'assistant',
            'model': 'test-model',
            'content': [],
            'stop_reason': null,
            'stop_sequence': null,
            'usage': {'input_tokens': 1, 'output_tokens': 0},
          },
        }) +
        sse({
          'type': 'content_block_start',
          'index': 0,
          'content_block': {'type': 'text', 'text': ''},
        }) +
        sse({
          'type': 'content_block_delta',
          'index': 0,
          'delta': {'type': 'text_delta', 'text': 'Hello'},
        }),
  LlmProvider.openAiCompletions => sse({
    'id': 'chat_1',
    'object': 'chat.completion.chunk',
    'created': 1,
    'model': 'test-model',
    'choices': [
      {
        'index': 0,
        'delta': {'role': 'assistant', 'content': 'Hello'},
        'finish_reason': null,
      },
    ],
  }),
  _ => sse({
    'type': 'response.output_text.delta',
    'sequence_number': 1,
    'item_id': 'msg_1',
    'output_index': 0,
    'content_index': 0,
    'delta': 'Hello',
  }),
};

String lastTextEvents(LlmProvider provider) => switch (provider) {
  LlmProvider.anthropic =>
    sse({
          'type': 'content_block_delta',
          'index': 0,
          'delta': {'type': 'text_delta', 'text': ' world'},
        }) +
        sse({'type': 'content_block_stop', 'index': 0}) +
        sse({
          'type': 'message_delta',
          'delta': {'stop_reason': 'end_turn', 'stop_sequence': null},
          'usage': {'output_tokens': 2},
        }) +
        sse({'type': 'message_stop'}),
  LlmProvider.openAiCompletions =>
    sse({
          'id': 'chat_1',
          'object': 'chat.completion.chunk',
          'created': 1,
          'model': 'test-model',
          'choices': [
            {
              'index': 0,
              'delta': {'content': ' world'},
              'finish_reason': 'stop',
            },
          ],
        }) +
        'data: [DONE]\n\n',
  _ =>
    sse({
          'type': 'response.output_text.delta',
          'sequence_number': 2,
          'item_id': 'msg_1',
          'output_index': 0,
          'content_index': 0,
          'delta': ' world',
        }) +
        sse({
          'type': 'response.completed',
          'sequence_number': 3,
          'response': responseFixture([textOutput]),
        }),
};

// Request one function with a split argument payload on each provider wire.
String toolEvents(LlmProvider provider) {
  if (provider == LlmProvider.anthropic) {
    return sse({
          'type': 'message_start',
          'message': {
            'id': 'msg_tool',
            'type': 'message',
            'role': 'assistant',
            'model': 'test-model',
            'content': [],
            'stop_reason': null,
            'stop_sequence': null,
            'usage': {'input_tokens': 1, 'output_tokens': 0},
          },
        }) +
        sse({
          'type': 'content_block_start',
          'index': 0,
          'content_block': {
            'type': 'tool_use',
            'id': 'call_1',
            'name': 'get_price',
            'input': {},
          },
        }) +
        sse({
          'type': 'content_block_delta',
          'index': 0,
          'delta': {
            'type': 'input_json_delta',
            'partial_json': '{"symbol":"BTCUSDT"}',
          },
        }) +
        sse({'type': 'content_block_stop', 'index': 0}) +
        sse({
          'type': 'message_delta',
          'delta': {'stop_reason': 'tool_use', 'stop_sequence': null},
          'usage': {'output_tokens': 1},
        }) +
        sse({'type': 'message_stop'});
  }
  if (provider == LlmProvider.openAiCompletions) {
    return sse({
          'id': 'chat_tool',
          'object': 'chat.completion.chunk',
          'created': 1,
          'model': 'test-model',
          'choices': [
            {
              'index': 0,
              'finish_reason': 'tool_calls',
              'delta': {
                'role': 'assistant',
                'tool_calls': [
                  {
                    'index': 0,
                    'id': 'call_1',
                    'type': 'function',
                    'function': {
                      'name': 'get_price',
                      'arguments': '{"symbol":"BTCUSDT"}',
                    },
                  },
                ],
              },
            },
          ],
        }) +
        'data: [DONE]\n\n';
  }
  return sse({
    'type': 'response.completed',
    'sequence_number': 1,
    'response': responseFixture([reasoningOutput, toolOutput]),
  });
}
