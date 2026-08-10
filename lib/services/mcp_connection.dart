import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../app_constants.dart';
import '../utils/network.dart';
import 'mcp_types.dart';

class HttpMcpConnection implements McpConnection {
  HttpMcpConnection({
    required this.name,
    required this.endpoint,
    required this.headers,
    Dio? dio,
  }) : _dio = dio ?? createDio();

  @override
  final String name;
  final String endpoint;
  final Map<String, String> headers;
  final Dio _dio;
  int _nextId = 1;
  String? _sessionId;
  bool _initialized = false;

  @override
  Future<List<McpTool>> listTools() async {
    await _initialize();
    return toolsFromMcpResult(name, await _request('tools/list', {}));
  }

  @override
  Future<String> call(String toolName, Map<String, dynamic> arguments) async {
    await _initialize();
    final result = await _request('tools/call', {
      'name': toolName,
      'arguments': arguments,
    });
    return jsonEncode(result['content'] ?? result);
  }

  Future<void> _initialize() async {
    if (_initialized) return;
    await _request('initialize', {
      'protocolVersion': AppConstants.mcpProtocolVersion,
      'capabilities': {},
      'clientInfo': {
        'name': AppConstants.appName,
        'version': AppConstants.appVersion,
      },
    });
    await _notification('notifications/initialized');
    _initialized = true;
  }

  Future<Map<String, dynamic>> _request(
    String method,
    Map<String, dynamic> params,
  ) => _send({
    'jsonrpc': '2.0',
    'id': _nextId++,
    'method': method,
    'params': params,
  });

  Future<void> _notification(String method) async {
    await _send({'jsonrpc': '2.0', 'method': method, 'params': {}});
  }

  Future<Map<String, dynamic>> _send(Map<String, dynamic> request) async {
    final response = await runNetworkRequest(
      name,
      () => _dio.postUri<String>(
        Uri.parse(endpoint),
        data: jsonEncode(request),
        options: networkOptions(
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json, text/event-stream',
            ...headers,
            ...switch (_sessionId) {
              final sessionId? => {'Mcp-Session-Id': sessionId},
              null => const <String, String>{},
            },
          },
          contentType: 'application/json',
        ),
      ),
    );
    requireSuccessfulResponse(response, provider: name);
    _sessionId ??= response.headers.value('mcp-session-id');
    final body = response.data ?? '';
    if (body.trim().isEmpty) return const {};
    final decoded = _decodeJsonOrSse(body);
    if (decoded['error'] != null) {
      throw AppFailure(kind: AppFailureKind.upstream, provider: name);
    }
    final result = decoded['result'];
    return result is Map<String, dynamic>
        ? result
        : Map<String, dynamic>.from(result as Map? ?? const {});
  }

  Map<String, dynamic> _decodeJsonOrSse(String body) {
    try {
      // SSE events may start with an `event:` field before their JSON `data:`.
      final events = body
          .split(RegExp(r'\r?\n'))
          .map((line) => line.trimLeft())
          .where((line) => line.startsWith('data:'))
          .map((line) => line.substring(5).trim())
          .where((line) => line.isNotEmpty)
          .toList();
      if (events.isEmpty) {
        return Map<String, dynamic>.from(jsonDecode(body) as Map);
      }
      for (final event in events) {
        final decoded = jsonDecode(event);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      }
    } on FormatException {
      throw AppFailure(kind: AppFailureKind.invalidResponse, provider: name);
    }
    throw AppFailure(kind: AppFailureKind.invalidResponse, provider: name);
  }

  @override
  Future<void> close() async => _dio.close(force: true);
}

class StdioMcpConnection implements McpConnection {
  StdioMcpConnection({
    required this.name,
    required this.command,
    required this.arguments,
    this.environment,
  });

  @override
  final String name;
  final String command;
  final List<String> arguments;
  final Map<String, String>? environment;
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};
  Process? _process;
  int _nextId = 1;

  @override
  Future<List<McpTool>> listTools() async {
    await _initialize();
    return toolsFromMcpResult(name, await _request('tools/list', {}));
  }

  @override
  Future<String> call(String toolName, Map<String, dynamic> arguments) async {
    await _initialize();
    final result = await _request('tools/call', {
      'name': toolName,
      'arguments': arguments,
    });
    return jsonEncode(result['content'] ?? result);
  }

  Future<void> _initialize() async {
    if (_process != null) return;
    final process = await Process.start(
      command,
      arguments,
      environment: environment,
    );
    _process = process;
    // MCP stdio responses are line-delimited JSON-RPC messages.
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_receiveLine);
    process.stderr.drain();
    await _request('initialize', {
      'protocolVersion': AppConstants.mcpProtocolVersion,
      'capabilities': {},
      'clientInfo': {
        'name': AppConstants.appName,
        'version': AppConstants.appVersion,
      },
    });
    _notify('notifications/initialized');
  }

  void _receiveLine(String line) {
    try {
      final message = Map<String, dynamic>.from(jsonDecode(line) as Map);
      final id = message['id'];
      if (id is! int) return;
      final completer = _pending.remove(id);
      if (completer == null) return;
      if (message['error'] != null) {
        completer.completeError(Exception(message['error']));
      } else {
        final result = message['result'];
        completer.complete(
          result is Map<String, dynamic>
              ? result
              : Map<String, dynamic>.from(result as Map? ?? const {}),
        );
      }
    } catch (_) {
      // Non-JSON process output is ignored because it is not an MCP response.
    }
  }

  Future<Map<String, dynamic>> _request(
    String method,
    Map<String, dynamic> params,
  ) async {
    final process = _process;
    if (process == null) throw StateError('MCP process is not running.');
    final id = _nextId++;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    process.stdin.writeln(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': params,
      }),
    );
    await process.stdin.flush();
    return completer.future.timeout(const Duration(seconds: 30));
  }

  void _notify(String method) {
    _process?.stdin.writeln(
      jsonEncode({'jsonrpc': '2.0', 'method': method, 'params': {}}),
    );
  }

  @override
  Future<void> close() async {
    final process = _process;
    if (process == null) return;
    _process = null;
    await process.stdin.close();
    process.kill();
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(
          const ProcessException('mcp', [], 'MCP stopped'),
        );
      }
    }
    _pending.clear();
  }
}
