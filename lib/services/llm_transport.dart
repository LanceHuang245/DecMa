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
    String? codexAccountId,
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
    LlmProvider.openAiCodex => _runOpenAiCodex(
      settings,
      apiKey,
      codexAccountId,
      system,
      input,
      tools,
      maxToolRounds,
      callTools,
    ),
  };

  Future<String> _runOpenAiCodex(
    LlmSettings settings,
    String accessToken,
    String? accountId,
    String system,
    String input,
    List<McpTool> tools,
    int maxToolRounds,
    LlmToolHandler callTools,
  ) {
    if (accountId == null || accountId.isEmpty) {
      throw Exception('OpenAI Codex OAuth 缺少 ChatGPT account ID，请重新登录。');
    }
    return _runOpenAiResponses(
      settings,
      accessToken,
      system,
      input,
      tools,
      maxToolRounds,
      callTools,
      extraHeaders: {
        'ChatGPT-Account-Id': accountId,
        'OpenAI-Beta': 'responses=experimental',
        'originator': 'codex_cli_rs',
        'Accept': 'text/event-stream',
      },
      store: false,
      codex: true,
      stream: true,
    );
  }

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
    LlmToolHandler callTools, {
    Map<String, String> extraHeaders = const {},
    bool? store,
    bool codex = false,
    bool stream = false,
  }) async {
    final codexInput = <Map<String, dynamic>>[];
    if (codex) codexInput.addAll(_codexInput(input));
    var response = await _post(
      _openAiUri(settings.endpoint, 'responses'),
      {'Authorization': 'Bearer $apiKey', ...extraHeaders},
      {
        'model': settings.model.trim(),
        'instructions': system,
        'input': codex ? codexInput : input,
        'store': ?store,
        if (stream) 'stream': true,
        if (tools.isNotEmpty)
          'tools': tools
              .map(
                (tool) => {'type': 'function', ...tool.toFunctionDefinition()},
              )
              .toList(),
      },
      stream: stream,
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
      if (codex) {
        // Codex continues with the prior output items instead of a response ID.
        codexInput.addAll(_list(response['output']).map(_map));
        codexInput.addAll(
          results.map(
            (result) => {
              'type': 'function_call_output',
              'call_id': result.id,
              'output': result.output,
            },
          ),
        );
      }
      response = await _post(
        _openAiUri(settings.endpoint, 'responses'),
        {'Authorization': 'Bearer $apiKey', ...extraHeaders},
        {
          'model': settings.model.trim(),
          'instructions': system,
          if (!codex) 'previous_response_id': response['id'],
          'input': codex
              ? codexInput
              : [
                  for (final result in results)
                    {
                      'type': 'function_call_output',
                      'call_id': result.id,
                      'output': result.output,
                    },
                ],
          'store': ?store,
          if (stream) 'stream': true,
          // Keep function definitions available for any follow-up tool round.
          if (tools.isNotEmpty)
            'tools': tools
                .map(
                  (tool) => {
                    'type': 'function',
                    ...tool.toFunctionDefinition(),
                  },
                )
                .toList(),
        },
        stream: stream,
      );
    }
    throw Exception('Agent reached the maximum of $maxToolRounds tool rounds.');
  }

  Future<Map<String, dynamic>> _post(
    Uri uri,
    Map<String, String> headers,
    Map<String, dynamic> body, {
    bool stream = false,
  }) async {
    // Log only the JSON body because API credentials are sent through headers.
    final requestBody = jsonEncode(body);
    debugPrint('LLM request [POST $uri]:\n$requestBody');
    final request = http.Request('POST', uri)
      ..headers.addAll({'Content-Type': 'application/json', ...headers})
      ..body = requestBody;
    final response = await _client
        .send(request)
        .timeout(const Duration(minutes: 5));
    final responseBody = await response.stream.bytesToString().timeout(
      const Duration(minutes: 5),
    );
    debugPrint(
      'LLM response [${response.statusCode} ${response.reasonPhrase ?? ''}]:\n$responseBody',
    );
    if (response.statusCode >= 400) {
      final decoded = _tryJson(responseBody);
      throw Exception(
        decoded['error'] is Map
            ? _map(decoded['error'])['message']
            : decoded['error'] ??
                  'LLM request failed (${response.statusCode}).',
      );
    }
    return _decodedResponse(responseBody, stream: stream);
  }

  List<Map<String, dynamic>> _codexInput(String input) => [
    {
      'type': 'message',
      'role': 'user',
      'content': [
        {'type': 'input_text', 'text': input},
      ],
    },
  ];

  Map<String, dynamic> _decodedResponse(String body, {required bool stream}) {
    if (!stream) return _map(jsonDecode(body));
    try {
      final decoded = _map(jsonDecode(body));
      if (decoded.isNotEmpty) return decoded;
    } on FormatException {
      // Codex emits one JSON object per Server-Sent Event data line.
    }
    Map<String, dynamic>? completed;
    final textDeltas = StringBuffer();
    final completedTextParts = <String>[];
    final outputItems = <int, Map<String, dynamic>>{};
    for (final line in body.split(RegExp(r'\r?\n'))) {
      if (!line.startsWith('data:')) continue;
      final data = line.substring('data:'.length).trim();
      if (data.isEmpty || data == '[DONE]') continue;
      try {
        final event = _map(jsonDecode(data));
        if (event['type'] == 'response.output_text.delta' &&
            event['delta'] is String) {
          textDeltas.write(event['delta']);
        }
        if (event['type'] == 'response.output_text.done' &&
            event['text'] is String) {
          completedTextParts.add(event['text'] as String);
        }
        if (event['type'] == 'response.output_item.done' &&
            event['item'] is Map) {
          final index = event['output_index'];
          if (index is num) {
            outputItems[index.toInt()] = _map(event['item']);
          }
        }
        if (event['type'] == 'response.completed' && event['response'] is Map) {
          completed = _map(event['response']);
        }
      } on FormatException {
        continue;
      }
    }
    final streamedText = completedTextParts.isNotEmpty
        ? completedTextParts.join('\n')
        : textDeltas.toString();
    final streamedOutput = outputItems.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    if (completed != null) {
      if (_list(completed['output']).isEmpty && streamedOutput.isNotEmpty) {
        completed = {
          ...completed,
          'output': streamedOutput.map((entry) => entry.value).toList(),
        };
      }
      if (streamedText.isNotEmpty && _responsesText(completed).isEmpty) {
        return {...completed, 'output_text': streamedText};
      }
      return completed;
    }
    if (streamedText.isNotEmpty || streamedOutput.isNotEmpty) {
      return {
        if (streamedText.isNotEmpty) 'output_text': streamedText,
        if (streamedOutput.isNotEmpty)
          'output': streamedOutput.map((entry) => entry.value).toList(),
      };
    }
    throw const FormatException('Codex did not return a completed response.');
  }

  Map<String, dynamic> _tryJson(String body) {
    try {
      return _map(jsonDecode(body));
    } on FormatException {
      return const {};
    }
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
    final outputText = response['output_text'];
    if (outputText is String && outputText.isNotEmpty) {
      return outputText;
    }
    return _list(response['output'])
        .map(_map)
        .where((item) => item['type'] == 'message')
        .expand((item) => _list(item['content']))
        .map(_map)
        .where(
          (item) => item['type'] == 'output_text' || item['type'] == 'text',
        )
        .map((item) => item['text'].toString())
        .where((text) => text != 'null' && text.isNotEmpty)
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
