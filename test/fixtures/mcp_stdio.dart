import 'dart:convert';
import 'dart:io';

// Serve a tiny real subprocess so the application's stdio configuration is tested.
Future<void> main() async {
  await for (final line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    final request = jsonDecode(line) as Map<String, dynamic>;
    if (!request.containsKey('id')) continue;
    final result = switch (request['method']) {
      'initialize' => {
        'protocolVersion': '2025-06-18',
        'capabilities': {'tools': {}},
        'serverInfo': {'name': 'stdio-fixture', 'version': '1.0.0'},
      },
      'tools/list' => {
        'tools': [
          {
            'name': 'price',
            'description': 'Public price',
            'inputSchema': {
              'type': 'object',
              'properties': {
                'symbol': {'type': 'string'},
              },
            },
          },
        ],
      },
      'tools/call' => {
        'content': [
          {
            'type': 'text',
            'text': jsonEncode({
              'symbol': request['params']['arguments']['symbol'],
              'price': 123,
              'environment': Platform.environment['DECMA_MCP_TEST'],
            }),
          },
        ],
      },
      _ => null,
    };
    stdout.writeln(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': request['id'],
        if (result != null)
          'result': result
        else
          'error': {'code': -32601, 'message': 'Method not found'},
      }),
    );
  }
}
