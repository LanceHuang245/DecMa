import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/trading_models.dart';
import 'mcp_types.dart';

class LlmToolCall {
  const LlmToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  final String id;
  final String name;
  final Map<String, dynamic> arguments;
}

class LlmToolResult {
  const LlmToolResult(this.id, this.output);

  final String id;
  final String output;
}

typedef LlmToolHandler =
    Future<List<LlmToolResult>> Function(List<LlmToolCall> calls);

// Translate one provider-neutral request into the configured LLM protocol.
class LlmTransport {
  LlmTransport(this._client);

  final http.Client _client;

  Future<String> complete({
    required LlmSettings settings,
    required String apiKey,
    required String system,
    required String input,
    required List<McpTool> tools,
    required int maxToolRounds,
    required LlmToolHandler callTools,
  }) => switch (settings.provider) {
    LlmProvider.anthropic => _runAnthropic(
      settings,
      apiKey,
      system,
      input,
      tools,
      maxToolRounds,
      callTools,
    ),
    LlmProvider.openAiResponses => _runOpenAiResponses(
      settings,
      apiKey,
      system,
      input,
      tools,
      maxToolRounds,
      callTools,
    ),
    LlmProvider.openAiCompletions => _runOpenAiCompletions(
      settings,
      apiKey,
      system,
      input,
      tools,
      maxToolRounds,
      callTools,
    ),
  };

  Future<String> _runAnthropic(
    LlmSettings settings,
    String apiKey,
    String system,
    String input,
    List<McpTool> tools,
    int maxToolRounds,
    LlmToolHandler callTools,
  ) async {
    final messages = <Map<String, dynamic>>[
      {'role': 'user', 'content': input},
    ];
    for (var turn = 0; turn < maxToolRounds; turn++) {
      final response = await _post(
        _anthropicUri(settings.endpoint),
        {'x-api-key': apiKey, 'anthropic-version': '2023-06-01'},
        {
          'model': settings.model.trim(),
          'max_tokens': 16384,
          'system': system,
          'messages': messages,
          if (tools.isNotEmpty)
            'tools': tools
                .map(
                  (tool) => {
                    'name': tool.functionName,
                    'description': '[${tool.serverName}] ${tool.description}',
                    'input_schema': tool.inputSchema,
                  },
                )
                .toList(),
        },
      );
      final content = List<Map<String, dynamic>>.from(
        (response['content'] as List? ?? const []).whereType<Map>().map(
          Map<String, dynamic>.from,
        ),
      );
      final calls = content
          .where((block) => block['type'] == 'tool_use')
          .map(
            (block) => LlmToolCall(
              id: block['id'].toString(),
              name: block['name'].toString(),
              arguments: _map(block['input']),
            ),
          )
          .toList();
      if (calls.isEmpty) return _anthropicText(content);
      messages.add({'role': 'assistant', 'content': content});
      messages.add({
        'role': 'user',
        'content': [
          for (final result in await callTools(calls))
            {
              'type': 'tool_result',
              'tool_use_id': result.id,
              'content': result.output,
            },
        ],
      });
    }
    throw Exception('Agent reached the maximum of $maxToolRounds tool rounds.');
  }

  Future<String> _runOpenAiCompletions(
    LlmSettings settings,
    String apiKey,
    String system,
    String input,
    List<McpTool> tools,
    int maxToolRounds,
    LlmToolHandler callTools,
  ) async {
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': input},
    ];
    for (var turn = 0; turn < maxToolRounds; turn++) {
      final response = await _post(
        _openAiUri(settings.endpoint, 'chat/completions'),
        {'Authorization': 'Bearer $apiKey'},
        {
          'model': settings.model.trim(),
          'messages': messages,
          if (tools.isNotEmpty)
            'tools': tools
                .map(
                  (tool) => {
                    'type': 'function',
                    'function': tool.toFunctionDefinition(),
                  },
                )
                .toList(),
        },
      );
      final message = _map(
        _map((response['choices'] as List).first)['message'],
      );
      final calls = (_list(message['tool_calls'])).map(_map).map((call) {
        final function = _map(call['function']);
        return LlmToolCall(
          id: call['id'].toString(),
          name: function['name'].toString(),
          arguments: _arguments(function['arguments']),
        );
      }).toList();
      if (calls.isEmpty) return message['content']?.toString() ?? '';
      messages.add(message);
      for (final result in await callTools(calls)) {
        messages.add({
          'role': 'tool',
          'tool_call_id': result.id,
          'content': result.output,
        });
      }
    }
    throw Exception('Agent reached the maximum of $maxToolRounds tool rounds.');
  }

  Future<String> _runOpenAiResponses(
    LlmSettings settings,
    String apiKey,
    String system,
    String input,
    List<McpTool> tools,
    int maxToolRounds,
    LlmToolHandler callTools,
  ) async {
    var response = await _post(
      _openAiUri(settings.endpoint, 'responses'),
      {'Authorization': 'Bearer $apiKey'},
      {
        'model': settings.model.trim(),
        'instructions': system,
        'input': input,
        if (tools.isNotEmpty)
          'tools': tools
              .map(
                (tool) => {'type': 'function', ...tool.toFunctionDefinition()},
              )
              .toList(),
      },
    );
    for (var turn = 0; turn < maxToolRounds; turn++) {
      final calls = _list(response['output'])
          .map(_map)
          .where((item) => item['type'] == 'function_call')
          .map(
            (item) => LlmToolCall(
              id: item['call_id'].toString(),
              name: item['name'].toString(),
              arguments: _arguments(item['arguments']),
            ),
          )
          .toList();
      if (calls.isEmpty) return _responsesText(response);
      final results = await callTools(calls);
      response = await _post(
        _openAiUri(settings.endpoint, 'responses'),
        {'Authorization': 'Bearer $apiKey'},
        {
          'model': settings.model.trim(),
          'previous_response_id': response['id'],
          'input': [
            for (final result in results)
              {
                'type': 'function_call_output',
                'call_id': result.id,
                'output': result.output,
              },
          ],
        },
      );
    }
    throw Exception('Agent reached the maximum of $maxToolRounds tool rounds.');
  }

  Future<Map<String, dynamic>> _post(
    Uri uri,
    Map<String, String> headers,
    Map<String, dynamic> body,
  ) async {
    // Log only the JSON body because API credentials are sent through headers.
    final requestBody = jsonEncode(body);
    debugPrint('LLM request [POST $uri]:\n$requestBody');
    final response = await _client
        .post(
          uri,
          headers: {'Content-Type': 'application/json', ...headers},
          body: requestBody,
        )
        .timeout(const Duration(minutes: 5));
    debugPrint(
      'LLM response [${response.statusCode} ${response.reasonPhrase ?? ''}]:\n${response.body}',
    );
    final decoded = _map(jsonDecode(response.body));
    if (response.statusCode >= 400) {
      throw Exception(
        decoded['error'] is Map
            ? _map(decoded['error'])['message']
            : decoded['error'] ??
                  'LLM request failed (${response.statusCode}).',
      );
    }
    return decoded;
  }

  Uri _openAiUri(String endpoint, String path) {
    final base = endpoint.replaceFirst(RegExp(r'/+$'), '');
    return Uri.parse(base.endsWith('/$path') ? base : '$base/$path');
  }

  // Anthropic-compatible providers document a base URL, not the Messages path.
  Uri _anthropicUri(String endpoint) {
    final base = endpoint.replaceFirst(RegExp(r'/+$'), '');
    return Uri.parse(
      base.endsWith('/v1/messages') ? base : '$base/v1/messages',
    );
  }

  String _anthropicText(List<Map<String, dynamic>> content) => content
      .where((block) => block['type'] == 'text')
      .map((block) => block['text'].toString())
      .join('\n');

  String _responsesText(Map<String, dynamic> response) {
    if (response['output_text'] != null) {
      return response['output_text'].toString();
    }
    return _list(response['output'])
        .map(_map)
        .where((item) => item['type'] == 'message')
        .expand((item) => _list(item['content']))
        .map(_map)
        .where((item) => item['type'] == 'output_text')
        .map((item) => item['text'].toString())
        .join('\n');
  }
}

Map<String, dynamic> _map(Object? value) => value is Map
    ? value.map((key, value) => MapEntry(key.toString(), value))
    : const {};

List<Object?> _list(Object? value) => value is List ? value : const [];

Map<String, dynamic> _arguments(Object? value) {
  if (value is Map) return _map(value);
  if (value is! String || value.isEmpty) return const {};
  try {
    return _map(jsonDecode(value));
  } catch (_) {
    return const {};
  }
}
