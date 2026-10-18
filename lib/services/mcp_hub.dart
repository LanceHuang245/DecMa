import 'dart:async';
import 'dart:io';

import 'package:genkit/genkit.dart';
import 'package:dio/dio.dart';
import 'package:genkit_mcp/genkit_mcp.dart';
import 'package:schemantic/schemantic.dart';

import '../app_constants.dart';
import '../models/trading_models.dart';
import '../utils/dio_client.dart';
import '../utils/network.dart';

// Fixed backend configuration replaces constructor-only provider subclasses.
Map<String, McpServerConfig> mcpServerConfigs(
  McpSettings settings, {
  String? nansenKey,
}) => {
  if (settings.useBybit)
    'Bybit MCP': McpServerConfig(
      command: Platform.isWindows ? 'cmd' : 'npx',
      args: [
        if (Platform.isWindows) '/c',
        if (Platform.isWindows) 'npx',
        '-y',
        AppConstants.bybitMcpPackage,
      ],
      timeout: networkTimeout,
      environment: {
        ...Platform.environment,
        'BYBIT_API_KEY': '',
        'BYBIT_API_SECRET': '',
        'BYBIT_API_PRIVATE_KEY_PATH': '',
      },
    ),
  if (settings.useNansen && nansenKey?.isNotEmpty == true)
    'Nansen MCP': McpServerConfig(
      url: Uri.parse('https://mcp.nansen.ai/ra/mcp'),
      headers: {'NANSEN-API-KEY': nansenKey!},
      timeout: networkTimeout,
    ),
  if (settings.useOpenWebSearch)
    'OpenWebSearch MCP': McpServerConfig(
      command: Platform.isWindows ? 'cmd' : 'npx',
      args: [
        if (Platform.isWindows) '/c',
        if (Platform.isWindows) 'npx',
        '-y',
        AppConstants.openWebSearchMcpPackage,
      ],
      timeout: networkTimeout,
      environment: {
        ...Platform.environment,
        'MODE': 'stdio',
        'DEFAULT_SEARCH_ENGINE': 'duckduckgo',
      },
    ),
};

// Configure SDK clients directly; no protocol facade or per-server subclasses.
GenkitMcpClient createMcpClientFor(
  String name,
  McpServerConfig config, {
  Dio? dio,
}) => withDioClient(
  () => createMcpClient(
    McpClientOptions(
      name: AppConstants.appName,
      serverName: name,
      version: AppConstants.appVersion,
      rawToolResponses: true,
      mcpServer: config,
    ),
  ),
  dio: dio,
);

// Own connections, live tool discovery and the existing bounded bridge policy.
class McpHub {
  McpHub({this.dio});
  final Dio? dio;
  final _clients = <String, GenkitMcpClient>{};
  final _tools = <String, Map<String, dynamic>>{};
  final warnings = <String>[];
  McpSettings? _settings;
  String? _nansenKey;
  CancellationToken? _cancel;
  bool _connected = false;
  Future<void>? _closing;
  Set<String> get availableServers =>
      _tools.values.map((tool) => tool['server'] as String).toSet();

  // Discover enabled sources before analysis so availability is accurate.
  Future<List<Tool>> prepare(
    McpSettings settings, {
    String? nansenApiKey,
    CancellationToken? cancel,
  }) async {
    await close();
    _closing = null;
    warnings.clear();
    _settings = settings;
    _nansenKey = nansenApiKey;
    _cancel = cancel;
    if (settings.useNansen && (nansenApiKey?.isEmpty ?? true)) {
      warnings.add('Nansen MCP: API Key 未配置。');
    }
    await _ensureConnected(cancel);
    if (_tools.isEmpty) return const [];
    return [
      _bridgeTool(
        'decma_discover_mcp_tools',
        'Search the live tools exposed by the configured Bybit, Nansen, and OpenWebSearch MCP servers. Call this before calling an MCP tool.',
        {
          'query': {
            'type': 'string',
            'description':
                'Capability needed, such as kline, funding rate, smart money flows, crypto news, or official announcements.',
          },
        },
        ['query'],
      ),
      _bridgeTool(
        'decma_call_mcp_tool',
        'Call one MCP tool returned by decma_discover_mcp_tools with its exact schema-compliant arguments.',
        {
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
        ['tool_name', 'arguments'],
      ),
    ];
  }

  // Keep the two public model-facing names and schemas stable across migration.
  Tool _bridgeTool(
    String name,
    String description,
    Map<String, dynamic> properties,
    List<String> required,
  ) => Tool<Map<String, dynamic>, Object?>(
    name: name,
    description: '[DecMa MCP bridge] $description',
    inputSchema: SchemanticType.from(
      jsonSchema: {
        'type': 'object',
        'properties': properties,
        'required': required,
        'additionalProperties': false,
      },
      parse: (value) => Map<String, dynamic>.from(value as Map),
    ),
    fn: (arguments, ctx) async =>
        .response(await call(name, arguments, cancel: ctx.cancel)),
  );

  // Register each client before awaiting discovery so cancellation can close it.
  Future<void> _ensureConnected(CancellationToken? cancel) async {
    cancel?.throwIfCancelled();
    if (_connected) return;
    _connected = true;
    final settings = _settings;
    if (settings == null) return;
    for (final entry in mcpServerConfigs(
      settings,
      nansenKey: _nansenKey,
    ).entries) {
      cancel?.throwIfCancelled();
      final client = _clients[entry.key] = createMcpClientFor(
        entry.key,
        entry.value,
        dio: dio,
      );
      final unlink = cancel?.onCancel(() => unawaited(close()));
      try {
        await cancellable(client.ready(), cancel?.whenCancelled);
        // Publish a server's catalog only after all of its pages succeed.
        final catalog = <String, Map<String, dynamic>>{};
        String? cursor;
        do {
          final result = await cancellable(
            client.listTools(cursor: cursor),
            cancel?.whenCancelled,
          );
          cancel?.throwIfCancelled();
          for (final raw
              in (result['tools'] as List? ?? const []).whereType<Map>()) {
            final tool = Map<String, dynamic>.from(raw);
            if (!_allowed(entry.key, tool)) continue;
            final name =
                '${entry.key.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}_${tool['name'].toString().replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}';
            catalog[name] = {...tool, 'server': entry.key};
          }
          cursor = result['nextCursor'] as String?;
        } while (cursor?.isNotEmpty ?? false);
        _tools.addAll(catalog);
      } catch (error) {
        await client.close();
        cancel?.throwIfCancelled();
        _clients.remove(entry.key);
        warnings.add('${entry.key}: $error');
      } finally {
        unlink?.call();
      }
    }
  }

  // Preserve Bybit's explicitly public read-only tool filter.
  bool _allowed(String server, Map<String, dynamic> tool) {
    if (server != 'Bybit MCP') return true;
    final name = tool['name'].toString().toLowerCase();
    final description = tool['description']?.toString().toLowerCase() ?? '';
    return const ['get', 'query', 'search', 'list'].any(name.startsWith) &&
        const [
          'no authentication required',
          'no authentication needed',
          'public endpoint',
        ].any(description.contains) &&
        !const [
          'authentication is required',
          'authentication via',
          'requires api key',
          'requires an api key',
          'private endpoint',
        ].any(description.contains);
  }

  // Return raw MCP output to the evidence middleware, without JSON round trips.
  Future<Map<String, dynamic>> call(
    String name,
    Map<String, dynamic> arguments, {
    CancellationToken? cancel,
  }) async {
    cancel ??= _cancel;
    cancel?.throwIfCancelled();
    if (name == 'decma_discover_mcp_tools') {
      await _ensureConnected(cancel);
      cancel?.throwIfCancelled();
      return {'tools': _search(arguments['query']?.toString() ?? '')};
    }
    if (name == 'decma_call_mcp_tool') {
      name = arguments['tool_name']?.toString() ?? '';
      if (!_tools.containsKey(name)) {
        throw Exception('Choose a tool returned by decma_discover_mcp_tools.');
      }
      arguments = Map<String, dynamic>.from(
        arguments['arguments'] as Map? ?? const {},
      );
    }
    final tool = _tools[name];
    if (tool == null) throw Exception('Unknown MCP tool: $name');
    final unlink = cancel?.onCancel(() => unawaited(close()));
    try {
      return await cancellable(
        _clients[tool['server']]!.callTool(
          name: tool['name'] as String,
          arguments: arguments,
        ),
        cancel?.whenCancelled,
      );
    } finally {
      unlink?.call();
    }
  }

  // Return only the twelve most relevant schemas rather than all server tools.
  List<Map<String, dynamic>> _search(String query) {
    final terms = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    int score(Map<String, dynamic> tool) => terms
        .where(
          '${tool['server']} ${tool['name']} ${tool['description']}'
              .toLowerCase()
              .contains,
        )
        .length;
    final entries = _tools.entries.toList()
      ..sort((a, b) => score(b.value).compareTo(score(a.value)));
    return entries
        .take(12)
        .map(
          (entry) => {
            'function_name': entry.key,
            'server': entry.value['server'],
            'description': entry.value['description'],
            'input_schema': entry.value['inputSchema'],
          },
        )
        .toList();
  }

  // Every caller awaits the same close operation, including cancellation cleanup.
  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    await Future.wait(_clients.values.map((client) => client.close()));
    _clients.clear();
    _tools.clear();
    _settings = null;
    _nansenKey = null;
    _cancel = null;
    _connected = false;
  }
}
