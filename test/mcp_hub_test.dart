import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:decma/models/trading_models.dart';
import 'package:decma/services/mcp_hub.dart';
import 'package:decma/utils/network.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genkit/genkit.dart';
import 'package:genkit_mcp/genkit_mcp.dart';

const _nansen = McpSettings(
  useBybit: false,
  useNansen: true,
  useOpenWebSearch: false,
);

void main() {
  // Explicit empty overrides prevent inherited account credentials reaching Bybit.
  test(
    'Bybit subprocess configuration overrides inherited account secrets',
    () {
      final config = mcpServerConfigs(
        const McpSettings(
          useBybit: true,
          useNansen: false,
          useOpenWebSearch: false,
        ),
      )['Bybit MCP']!;
      expect(config.environment!['BYBIT_API_KEY'], '');
      expect(config.environment!['BYBIT_API_SECRET'], '');
      expect(config.environment!['BYBIT_API_PRIVATE_KEY_PATH'], '');
    },
  );

  // A failed later page must not advertise tools whose client was already closed.
  test(
    'failed discovery does not leave a partially loaded server catalog',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final dio = _localDio(server.port);
      final hub = McpHub(dio: dio);
      final requests = server.listen((request) async {
        if (request.method != 'POST') {
          request.response.statusCode = 405;
          await request.response.close();
          return;
        }
        final message =
            jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        request.response.headers.contentType = ContentType.json;
        if (!message.containsKey('id')) {
          request.response.statusCode = 202;
        } else {
          final result = switch (message['method']) {
            'initialize' => {
              'protocolVersion': '2025-06-18',
              'capabilities': {'tools': {}},
              'serverInfo': {'name': 'test', 'version': '1.0.0'},
            },
            'tools/list' when message['params']?['cursor'] == null => {
              'tools': [
                {
                  'name': 'price',
                  'description': 'Public price',
                  'inputSchema': {'type': 'object', 'properties': {}},
                },
              ],
              'nextCursor': 'page-2',
            },
            _ => null,
          };
          request.response.write(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': message['id'],
              if (result != null)
                'result': result
              else
                'error': {'code': -32603, 'message': 'Discovery failed'},
            }),
          );
        }
        await request.response.close();
      });
      try {
        await hub.prepare(_nansen, nansenApiKey: 'key', eager: true);
        expect(hub.warnings, isNotEmpty);
        expect(hub.availableServers, isEmpty);
        expect(
          (await hub.call('decma_discover_mcp_tools', {'query': ''}))['tools'],
          isEmpty,
        );
      } finally {
        await hub.close();
        dio.close(force: true);
        await requests.cancel();
        await server.close(force: true);
      }
    },
  );
  // Exercise the actual SDK subprocess configuration and environment forwarding.
  test(
    'stdio SDK client invokes a tool with the configured environment',
    () async {
      final client = createMcpClientFor(
        'test',
        McpServerConfig(
          command: Platform.isWindows ? 'cmd' : 'dart',
          args: Platform.isWindows
              ? const ['/c', 'dart', 'test/fixtures/mcp_stdio.dart']
              : const ['test/fixtures/mcp_stdio.dart'],
          environment: const {'DECMA_MCP_TEST': 'child-value'},
        ),
      );
      try {
        await client.ready();
        expect(
          ((await client.listTools())['tools'] as List).single['name'],
          'price',
        );
        final result = await client.callTool(
          name: 'price',
          arguments: {'symbol': 'BTCUSDT'},
        );
        expect(jsonDecode(result['content'][0]['text'] as String), {
          'symbol': 'BTCUSDT',
          'price': 123,
          'environment': 'child-value',
        });
      } finally {
        await client.close();
      }
    },
  );

  // An awaiting discovery retains its token even after the hub is closed.
  test(
    'discovery cannot return success after cancellation and close',
    () async {
      final hub = McpHub();
      final cancel = CancellationController();
      await hub.prepare(
        const McpSettings(
          useBybit: false,
          useNansen: false,
          useOpenWebSearch: false,
        ),
        cancel: cancel.token,
      );
      final assertion = expectLater(
        hub.call('decma_discover_mcp_tools', {'query': 'price'}),
        throwsA(isA<CancelledException>()),
      );
      cancel.cancel();
      await hub.close();
      await assertion;
    },
  );

  // Redirect the production endpoint at the Dio boundary, not inside the hub.
  test('HTTP hub discovers every page and retains raw tool errors', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final dio = _localDio(server.port);
    final hub = McpHub(dio: dio);
    final methods = <String>[];
    final requests = server.listen((request) async {
      if (request.method != 'POST') {
        request.response.statusCode = 405;
        await request.response.close();
        return;
      }
      expect(request.headers.value('NANSEN-API-KEY'), 'test-key');
      final message =
          jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      methods.add(message['method'] as String);
      request.response.headers.contentType = ContentType.json;
      if (!message.containsKey('id')) {
        request.response.statusCode = 202;
      } else {
        final result = switch (message['method']) {
          'initialize' => {
            'protocolVersion': '2025-06-18',
            'capabilities': {'tools': {}},
            'serverInfo': {'name': 'test-server', 'version': '1.0.0'},
          },
          'tools/list' => {
            'tools': [
              {
                'name': message['params']?['cursor'] == null
                    ? 'price'
                    : 'funding',
                'description': 'Public data',
                'inputSchema': {'type': 'object', 'properties': {}},
              },
            ],
            if (message['params']?['cursor'] == null) 'nextCursor': 'page-2',
          },
          'tools/call' => {
            'isError': true,
            'content': [
              {'type': 'text', 'text': 'temporarily unavailable'},
            ],
            'structuredContent': {'source': 'test'},
          },
          _ => null,
        };
        request.response.write(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': message['id'],
            if (result != null)
              'result': result
            else
              'error': {'code': -32601, 'message': 'Method not found'},
          }),
        );
      }
      await request.response.close();
    });
    try {
      await hub.prepare(_nansen, nansenApiKey: 'test-key', eager: true);
      final discovery = await hub.call('decma_discover_mcp_tools', {
        'query': '',
      });
      expect((discovery['tools'] as List).map((t) => t['function_name']), [
        'Nansen_MCP_price',
        'Nansen_MCP_funding',
      ]);
      final result = await hub.call('decma_call_mcp_tool', {
        'tool_name': 'Nansen_MCP_price',
        'arguments': {},
      });
      expect(result['isError'], true);
      expect(result['content'], [
        {'type': 'text', 'text': 'temporarily unavailable'},
      ]);
      expect(result['structuredContent'], {'source': 'test'});
      expect(methods.where((m) => m == 'initialize'), hasLength(1));
      final closing = hub.close();
      expect(hub.close(), same(closing));
      await closing;
      expect(hub.availableServers, isEmpty);
    } finally {
      await hub.close();
      dio.close(force: true);
      await requests.cancel();
      await server.close(force: true);
    }
  });

  // Stopping during the handshake aborts the actual pending Dio connection.
  test(
    'HTTP initialization can be stopped without waiting for its timeout',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final started = Completer<void>();
      final requests = server.listen((_) {
        if (!started.isCompleted) started.complete();
      });
      final dio = _localDio(server.port);
      final hub = McpHub(dio: dio);
      final cancel = CancellationController();
      try {
        final assertion = expectLater(
          hub.prepare(
            _nansen,
            nansenApiKey: 'key',
            cancel: cancel.token,
            eager: true,
          ),
          throwsA(isA<CancelledException>()),
        );
        await started.future;
        cancel.cancel();
        await assertion.timeout(const Duration(seconds: 2));
      } finally {
        await hub.close();
        dio.close(force: true);
        await requests.cancel();
        await server.close(force: true);
      }
    },
  );
}

Dio _localDio(int port) => createDio()
  ..interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        options.path = 'http://127.0.0.1:$port/mcp';
        handler.next(options);
      },
    ),
  );
