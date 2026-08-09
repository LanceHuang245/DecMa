import 'dart:io';

import '../app_constants.dart';
import 'mcp_connection.dart';

class BybitMcp extends StdioMcpConnection {
  BybitMcp()
    : super(
        name: 'Bybit MCP',
        command: Platform.isWindows ? 'cmd' : 'npx',
        arguments: Platform.isWindows
            ? const ['/c', 'npx', '-y', AppConstants.bybitMcpPackage]
            : const ['-y', AppConstants.bybitMcpPackage],
        environment: _publicMarketEnvironment(),
      );

  // Remove inherited credentials so the official server can access public data only.
  static Map<String, String> _publicMarketEnvironment() =>
      Map<String, String>.from(Platform.environment)
        ..remove('BYBIT_API_KEY')
        ..remove('BYBIT_API_SECRET')
        ..remove('BYBIT_API_PRIVATE_KEY_PATH');
}
