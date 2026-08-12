import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../app_constants.dart';
import '../models/trading_models.dart';
import 'bybit_mcp.dart';
import 'mcp_types.dart';
import 'nansen_mcp.dart';
import 'open_websearch_mcp.dart';

class McpHub {
  static const _discoverTools = 'decma_discover_mcp_tools';
  static const _callTool = 'decma_call_mcp_tool';
  final Map<String, McpConnection> _connections = {};
  final Map<String, McpTool> _tools = {};
  final List<String> warnings = [];
  McpSettings? _settings;
  String? _nansenApiKey;
  bool _didConnect = false;

  Set<String> get availableServers =>
      _tools.values.map((tool) => tool.serverName).toSet();

  // Eagerly discover tools for the full market-analysis workflow.
  Future<List<McpTool>> connect(
    McpSettings settings, {
    String? nansenApiKey,
  }) async {
    await prepare(settings, nansenApiKey: nansenApiKey);
    if (kDebugMode) debugPrint('[MCP] Eager discovery starting.');
    await _ensureConnected();
    return _tools.isEmpty ? const [] : _bridgeTools;
  }

  // Defer remote schema discovery until a conversation model asks for data.
  Future<List<McpTool>> prepare(
    McpSettings settings, {
    String? nansenApiKey,
  }) async {
    await close();
    warnings.clear();
    _settings = settings;
    _nansenApiKey = nansenApiKey;
    if (settings.useNansen && (nansenApiKey == null || nansenApiKey.isEmpty)) {
      warnings.add('Nansen MCP: API Key 未配置。');
    }
    if (kDebugMode) {
      debugPrint(
        '[MCP] Bridge tools ready. Enabled: '
        'bybit=${settings.useBybit}, nansen=${settings.useNansen}, '
        'openWebSearch=${settings.useOpenWebSearch}',
      );
    }
    return _bridgeTools;
  }

  Future<void> _ensureConnected() async {
    if (_didConnect) return;
    _didConnect = true;
    final settings = _settings;
    if (settings == null) return;
    final connections = <McpConnection>[
      if (settings.useBybit) BybitMcp(),
      if (settings.useNansen &&
          _nansenApiKey != null &&
          _nansenApiKey!.isNotEmpty)
        NansenMcp(_nansenApiKey!),
      if (settings.useOpenWebSearch) OpenWebSearchMcp(),
    ];
    if (kDebugMode) {
      debugPrint(
        '[MCP] Connecting to ${connections.length} server(s): '
        '${connections.map((connection) => connection.name).join(', ')}',
      );
    }
    for (final connection in connections) {
      try {
        final allTools = await connection.listTools();
        final allowedTools = allTools
            .where((tool) => _isAllowedTool(connection, tool))
            .toList();
        _connections[connection.name] = connection;
        for (final tool in allowedTools) {
          _tools[tool.functionName] = tool;
        }
        if (kDebugMode) {
          final filteredCount = allTools.length - allowedTools.length;
          debugPrint(
            '[MCP] ${connection.name}: loaded ${allowedTools.length} tool(s)'
            '${filteredCount > 0 ? ' (filtered $filteredCount)' : ''}',
          );
          for (final tool in allowedTools) {
            debugPrint('[MCP]   - ${tool.name}');
          }
        }
      } catch (error) {
        warnings.add('${connection.name}: $error');
        if (kDebugMode) {
          debugPrint('[MCP] ${connection.name}: failed - $error');
        }
        await connection.close();
      }
    }
    if (kDebugMode) {
      debugPrint(
        '[MCP] Load complete: ${_tools.length} tool(s) from '
        '${_connections.length} server(s)',
      );
      if (warnings.isNotEmpty) {
        debugPrint('[MCP] Warnings: ${warnings.join('; ')}');
      }
    }
  }

  // Expose only explicitly public read operations from Bybit's mixed tool server.
  bool _isAllowedTool(McpConnection connection, McpTool tool) {
    if (connection.name != 'Bybit MCP') return true;
    final name = tool.name.toLowerCase();
    final description = tool.description.toLowerCase();
    final isReadOperation = const [
      'get',
      'query',
      'search',
      'list',
    ].any(name.startsWith);
    final isExplicitlyPublic =
        description.contains('no authentication required') ||
        description.contains('no authentication needed') ||
        description.contains('public endpoint');
    final requiresAuthentication =
        description.contains('authentication is required') ||
        description.contains('authentication via') ||
        description.contains('requires api key') ||
        description.contains('requires an api key') ||
        description.contains('private endpoint');
    return isReadOperation && isExplicitlyPublic && !requiresAuthentication;
  }

  Future<String> call(
    String functionName,
    Map<String, dynamic> arguments,
  ) async {
    if (functionName == _discoverTools) {
      await _ensureConnected();
      return jsonEncode({
        'tools': _search(arguments['query']?.toString() ?? ''),
      });
    }
    if (functionName == _callTool) {
      final toolName = arguments['tool_name']?.toString();
      if (toolName == null || !_tools.containsKey(toolName)) {
        throw Exception('Choose a tool returned by decma_discover_mcp_tools.');
      }
      final toolArguments = arguments['arguments'];
      return call(
        toolName,
        toolArguments is Map
            ? Map<String, dynamic>.from(toolArguments)
            : const {},
      );
    }
    final tool = _tools[functionName];
    if (tool == null) throw Exception('Unknown MCP tool: $functionName');
    return _connections[tool.serverName]!.call(tool.name, arguments);
  }

  // Return only relevant, live schemas so provider tool limits never depend on upstream tool counts.
  List<Map<String, dynamic>> _search(String query) {
    final terms = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((term) => term.isNotEmpty);
    final tools = _tools.values.toList()
      ..sort(
        (left, right) => _score(right, terms).compareTo(_score(left, terms)),
      );
    return tools
        .take(12)
        .map(
          (tool) => {
            'function_name': tool.functionName,
            'server': tool.serverName,
            'description': tool.description,
            'input_schema': tool.inputSchema,
          },
        )
        .toList();
  }

  int _score(McpTool tool, Iterable<String> terms) {
    // Include the server so source-specific discovery queries rank correctly.
    final source = '${tool.serverName} ${tool.name} ${tool.description}'
        .toLowerCase();
    return terms.where(source.contains).length;
  }

  static const _bridgeTools = [
    McpTool(
      functionName: _discoverTools,
      serverName: '${AppConstants.appName} MCP bridge',
      name: _discoverTools,
      description:
          'Search the live tools exposed by the configured Bybit, Nansen, and OpenWebSearch MCP servers. Call this before calling an MCP tool.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description':
                'Capability needed, such as kline, funding rate, smart money flows, crypto news, or official announcements.',
          },
        },
        'required': ['query'],
        'additionalProperties': false,
      },
    ),
    McpTool(
      functionName: _callTool,
      serverName: '${AppConstants.appName} MCP bridge',
      name: _callTool,
      description:
          'Call one MCP tool returned by decma_discover_mcp_tools with its exact schema-compliant arguments.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'tool_name': {
            'type': 'string',
            'description':
                'The function_name returned by decma_discover_mcp_tools.',
          },
          'arguments': {
            'type': 'object',
            'description': 'Arguments that satisfy the returned input_schema.',
            'additionalProperties': true,
          },
        },
        'required': ['tool_name', 'arguments'],
        'additionalProperties': false,
      },
    ),
  ];

  Future<void> close() async {
    await Future.wait(
      _connections.values.map((connection) => connection.close()),
    );
    _connections.clear();
    _tools.clear();
    _settings = null;
    _nansenApiKey = null;
    _didConnect = false;
  }
}
