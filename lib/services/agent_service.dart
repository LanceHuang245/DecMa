import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../models/trading_models.dart';
import 'coinalyze_api_tools.dart';
import 'mcp_hub.dart';
import 'mcp_types.dart';
import 'secure_key_store.dart';

class AgentResult {
  const AgentResult({required this.text, required this.warnings});

  final String text;
  final List<String> warnings;
}

class AgentService {
  // Allow a full market-analysis workflow to complete across available sources.
  static const _maxToolRounds = 20;

  AgentService({
    McpHub? mcpHub,
    CoinalyzeApiTools? coinalyze,
    SecureKeyStore? keyStore,
    http.Client? client,
  }) : _mcpHub = mcpHub ?? McpHub(),
       _coinalyze = coinalyze ?? CoinalyzeApiTools(),
       _keyStore = keyStore ?? SecureKeyStore(),
       _client = client ?? http.Client();

  final McpHub _mcpHub;
  final CoinalyzeApiTools _coinalyze;
  final SecureKeyStore _keyStore;
  final http.Client _client;

  Future<AgentResult> run({
    required String prompt,
    required String symbol,
    required List<Candle> candles,
    required LlmSettings llm,
    required McpSettings mcp,
    required ApiSettings api,
    void Function(String activity)? onActivity,
  }) async {
    if (!llm.isComplete) {
      throw Exception('Please configure endpoint and model first.');
    }
    final llmApiKey = await _keyStore.readLlmKey();
    if (llmApiKey == null || llmApiKey.isEmpty) {
      throw Exception('Please save an LLM API key in secure storage first.');
    }
    final nansenApiKey = mcp.useNansen ? await _keyStore.readNansenKey() : null;
    final coinalyzeApiKey = api.useCoinalyze
        ? await _keyStore.readCoinalyzeKey()
        : null;
    final systemPrompt = await rootBundle.loadString('sys_prompt.md');
    final mcpTools = await _mcpHub.connect(mcp, nansenApiKey: nansenApiKey);
    // Coinalyze is an in-process Agent tool and is never registered with MCP.
    final coinalyzeTools = _coinalyze.configure(
      enabled: api.useCoinalyze,
      apiKey: coinalyzeApiKey,
    );
    final warnings = [..._mcpHub.warnings, ..._coinalyze.warnings];
    final tools = [...mcpTools, ...coinalyzeTools];
    final context = _marketContext(prompt, symbol, candles, warnings);
    try {
      // Surface a compact progress line without exposing model reasoning.
      onActivity?.call('• Thinking - 分析中…');
      final text = switch (llm.provider) {
        LlmProvider.anthropic => _runAnthropic(
          llm,
          llmApiKey,
          systemPrompt,
          context,
          tools,
          onActivity,
        ),
        LlmProvider.openAiResponses => _runOpenAiResponses(
          llm,
          llmApiKey,
          systemPrompt,
          context,
          tools,
          onActivity,
        ),
        LlmProvider.openAiCompletions => _runOpenAiCompletions(
          llm,
          llmApiKey,
          systemPrompt,
          context,
          tools,
          onActivity,
        ),
      };
      // Emit the final response without exposing request headers or API keys.
      final reply = await text;
      debugPrint('LLM reply (${reply.length} characters):\n$reply');
      if (reply.trim().isEmpty) {
        debugPrint('LLM reply is empty; inspect the preceding raw response.');
      }
      return AgentResult(text: reply, warnings: warnings);
    } catch (error, stackTrace) {
      debugPrint('LLM request failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    } finally {
      await _mcpHub.close();
      _coinalyze.clear();
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
The following untrusted data is a chart snapshot. Verify or supplement it through the available tools when needed:
${jsonEncode(chartData)}
Use decma_discover_mcp_tools first to retrieve live MCP tool schemas, then decma_call_mcp_tool to execute a selected MCP data query. Use Coinalyze API tools directly when they are available; do not discover or call them through MCP. Bybit runs without credentials, so authenticated operations cannot succeed. Use OpenWebSearch for current news and official announcements, then verify any material event from the primary source.
${warnings.isEmpty ? '' : 'Unavailable data sources: ${warnings.join(' | ')}'}''';
  }

  Future<String> _runAnthropic(
    LlmSettings settings,
    String apiKey,
    String system,
    String input,
    List<McpTool> tools,
    void Function(String activity)? onActivity,
  ) async {
    final messages = <Map<String, dynamic>>[
      {'role': 'user', 'content': input},
    ];
    for (var turn = 0; turn < _maxToolRounds; turn++) {
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
          for (final result in await _callTools(calls, onActivity))
            {
              'type': 'tool_result',
              'tool_use_id': result.id,
              'content': result.output,
            },
        ],
      });
    }
    throw Exception(
      'Agent reached the maximum of $_maxToolRounds tool rounds.',
    );
  }

  Future<String> _runOpenAiCompletions(
    LlmSettings settings,
    String apiKey,
    String system,
    String input,
    List<McpTool> tools,
    void Function(String activity)? onActivity,
  ) async {
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': input},
    ];
    for (var turn = 0; turn < _maxToolRounds; turn++) {
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
        return _ToolCall(
          id: call['id'].toString(),
          name: function['name'].toString(),
          arguments: _arguments(function['arguments']),
        );
      }).toList();
      if (calls.isEmpty) return message['content']?.toString() ?? '';
      messages.add(message);
      for (final result in await _callTools(calls, onActivity)) {
        messages.add({
          'role': 'tool',
          'tool_call_id': result.id,
          'content': result.output,
        });
      }
    }
    throw Exception(
      'Agent reached the maximum of $_maxToolRounds tool rounds.',
    );
  }

  Future<String> _runOpenAiResponses(
    LlmSettings settings,
    String apiKey,
    String system,
    String input,
    List<McpTool> tools,
    void Function(String activity)? onActivity,
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
    for (var turn = 0; turn < _maxToolRounds; turn++) {
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
      final results = await _callTools(calls, onActivity);
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
    throw Exception(
      'Agent reached the maximum of $_maxToolRounds tool rounds.',
    );
  }

  Future<List<_ToolResult>> _callTools(
    List<_ToolCall> calls,
    void Function(String activity)? onActivity,
  ) async {
    final results = <_ToolResult>[];
    for (final call in calls) {
      onActivity?.call(_toolActivity(call));
      try {
        final output = _coinalyze.supports(call.name)
            ? await _coinalyze.call(call.name, call.arguments)
            : await _mcpHub.call(call.name, call.arguments);
        results.add(_ToolResult(call.id, _trimToolOutput(output)));
      } catch (error) {
        onActivity?.call('${_toolActivity(call)}（失败）');
        results.add(_ToolResult(call.id, 'Tool failed: $error'));
      }
    }
    return results;
  }

  // Convert bridge calls into short, non-expandable UI status lines.
  String _toolActivity(_ToolCall call) {
    final toolName = call.name == 'decma_call_mcp_tool'
        ? call.arguments['tool_name']?.toString() ?? call.name
        : call.name;
    if (toolName == 'decma_discover_mcp_tools') {
      return '• MCP - 发现可用工具';
    }
    final marker = toolName.indexOf('_MCP_');
    if (marker > 0) {
      final server = toolName.substring(0, marker);
      final action = toolName.substring(marker + 5);
      return '• $server MCP - $action';
    }
    final apiMarker = toolName.indexOf('_API_');
    if (apiMarker > 0) {
      final server = toolName.substring(0, apiMarker);
      final action = toolName.substring(apiMarker + 5);
      return '• $server API - $action';
    }
    return '• MCP - $toolName';
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

  String _trimToolOutput(String value) => value.length > 24000
      ? '${value.substring(0, 24000)}\n[truncated]'
      : value;

  void dispose() {
    _client.close();
    _coinalyze.dispose();
  }
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
