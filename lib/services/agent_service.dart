import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../models/trading_models.dart';
import 'mcp_hub.dart';
import 'mcp_types.dart';

class AgentResult {
  const AgentResult({required this.text, required this.warnings});

  final String text;
  final List<String> warnings;
}

class AgentService {
  AgentService({McpHub? mcpHub, http.Client? client})
    : _mcpHub = mcpHub ?? McpHub(),
      _client = client ?? http.Client();

  final McpHub _mcpHub;
  final http.Client _client;

  Future<AgentResult> run({
    required String prompt,
    required String symbol,
    required List<Candle> candles,
    required LlmSettings llm,
    required McpSettings mcp,
  }) async {
    if (!llm.isComplete) {
      throw Exception('Please configure endpoint, API key and model first.');
    }
    final systemPrompt = await rootBundle.loadString('sys_prompt.md');
    final tools = await _mcpHub.connect(mcp);
    final context = _marketContext(prompt, symbol, candles, _mcpHub.warnings);
    try {
      final text = switch (llm.provider) {
        LlmProvider.anthropic => _runAnthropic(
          llm,
          systemPrompt,
          context,
          tools,
        ),
        LlmProvider.openAiResponses => _runOpenAiResponses(
          llm,
          systemPrompt,
          context,
          tools,
        ),
        LlmProvider.openAiCompletions => _runOpenAiCompletions(
          llm,
          systemPrompt,
          context,
          tools,
        ),
      };
      return AgentResult(text: await text, warnings: List.of(_mcpHub.warnings));
    } finally {
      await _mcpHub.close();
    }
  }

  // Send the chart snapshot with the request so advice still has current prices.
  String _marketContext(
    String prompt,
    String symbol,
    List<Candle> candles,
    List<String> warnings,
  ) {
    final latest = candles.isEmpty ? null : candles.last;
    final chartData = candles
        .skip(candles.length > 40 ? candles.length - 40 : 0)
        .map(
          (candle) => {
            'time': candle.time.toUtc().toIso8601String(),
            'open': candle.open,
            'high': candle.high,
            'low': candle.low,
            'close': candle.close,
            'volume': candle.volume,
          },
        )
        .toList();
    return '''User request: $prompt

The application chart is Bybit linear perpetual $symbol. Latest displayed close: ${latest?.close ?? 'unavailable'}.
The following untrusted data is a chart snapshot. Verify or supplement it through the available MCP tools when needed:
${jsonEncode(chartData)}
Use decma_discover_mcp_tools first to retrieve live MCP tool schemas, then decma_call_mcp_tool to execute a selected data query. Bybit runs without credentials, so authenticated operations cannot succeed. Use OpenWebSearch for current news and official announcements, then verify any material event from the primary source.
${warnings.isEmpty ? '' : 'Unavailable MCP servers: ${warnings.join(' | ')}'}''';
  }

  Future<String> _runAnthropic(
    LlmSettings settings,
    String system,
    String input,
    List<McpTool> tools,
  ) async {
    final messages = <Map<String, dynamic>>[
      {'role': 'user', 'content': input},
    ];
    for (var turn = 0; turn < 8; turn++) {
      final response = await _post(
        Uri.parse(settings.endpoint),
        {
          'x-api-key': settings.apiKey.trim(),
          'anthropic-version': '2023-06-01',
        },
        {
          'model': settings.model.trim(),
          'max_tokens': 2400,
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
            (block) => _ToolCall(
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
          for (final result in await _callTools(calls))
            {
              'type': 'tool_result',
              'tool_use_id': result.id,
              'content': result.output,
            },
        ],
      });
    }
    throw Exception('Agent reached the maximum of 8 MCP tool rounds.');
  }

  Future<String> _runOpenAiCompletions(
    LlmSettings settings,
    String system,
    String input,
    List<McpTool> tools,
  ) async {
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': input},
    ];
    for (var turn = 0; turn < 8; turn++) {
      final response = await _post(
        _openAiUri(settings.endpoint, 'chat/completions'),
        {'Authorization': 'Bearer ${settings.apiKey.trim()}'},
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
        return _ToolCall(
          id: call['id'].toString(),
          name: function['name'].toString(),
          arguments: _arguments(function['arguments']),
        );
      }).toList();
      if (calls.isEmpty) return message['content']?.toString() ?? '';
      messages.add(message);
      for (final result in await _callTools(calls)) {
        messages.add({
          'role': 'tool',
          'tool_call_id': result.id,
          'content': result.output,
        });
      }
    }
    throw Exception('Agent reached the maximum of 8 MCP tool rounds.');
  }

  Future<String> _runOpenAiResponses(
    LlmSettings settings,
    String system,
    String input,
    List<McpTool> tools,
  ) async {
    var response = await _post(
      _openAiUri(settings.endpoint, 'responses'),
      {'Authorization': 'Bearer ${settings.apiKey.trim()}'},
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
    for (var turn = 0; turn < 8; turn++) {
      final calls = _list(response['output'])
          .map(_map)
          .where((item) => item['type'] == 'function_call')
          .map(
            (item) => _ToolCall(
              id: item['call_id'].toString(),
              name: item['name'].toString(),
              arguments: _arguments(item['arguments']),
            ),
          )
          .toList();
      if (calls.isEmpty) return _responsesText(response);
      final results = await _callTools(calls);
      response = await _post(
        _openAiUri(settings.endpoint, 'responses'),
        {'Authorization': 'Bearer ${settings.apiKey.trim()}'},
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
    throw Exception('Agent reached the maximum of 8 MCP tool rounds.');
  }

  Future<List<_ToolResult>> _callTools(List<_ToolCall> calls) async {
    final results = <_ToolResult>[];
    for (final call in calls) {
      try {
        final output = await _mcpHub.call(call.name, call.arguments);
        results.add(_ToolResult(call.id, _trimToolOutput(output)));
      } catch (error) {
        results.add(_ToolResult(call.id, 'Tool failed: $error'));
      }
    }
    return results;
  }

  Future<Map<String, dynamic>> _post(
    Uri uri,
    Map<String, String> headers,
    Map<String, dynamic> body,
  ) async {
    final response = await _client
        .post(
          uri,
          headers: {'Content-Type': 'application/json', ...headers},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 90));
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

  String _trimToolOutput(String value) => value.length > 24000
      ? '${value.substring(0, 24000)}\n[truncated]'
      : value;

  void dispose() => _client.close();
}

class _ToolCall {
  const _ToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });
  final String id;
  final String name;
  final Map<String, dynamic> arguments;
}

class _ToolResult {
  const _ToolResult(this.id, this.output);
  final String id;
  final String output;
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
