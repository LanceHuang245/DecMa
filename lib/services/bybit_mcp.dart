import 'dart:io';

import 'mcp_connection.dart';

class BybitMcp extends StdioMcpConnection {
  BybitMcp()
    : super(
        name: 'Bybit MCP',
        command: Platform.isWindows ? 'cmd' : 'npx',
        arguments: Platform.isWindows
            ? const ['/c', 'npx', '-y', 'bybit-official-trading-server@latest']
            : const ['-y', 'bybit-official-trading-server@latest'],
        environment: _publicMarketEnvironment(),
      );

  // Remove inherited credentials so the official server can access public data only.
  static Map<String, String> _publicMarketEnvironment() =>
      Map<String, String>.from(Platform.environment)
        ..remove('BYBIT_API_KEY')
        ..remove('BYBIT_API_SECRET')
        ..remove('BYBIT_API_PRIVATE_KEY_PATH');
}
