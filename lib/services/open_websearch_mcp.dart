import 'dart:io';

import '../app_constants.dart';
import 'mcp_connection.dart';

class OpenWebSearchMcp extends StdioMcpConnection {
  OpenWebSearchMcp()
    : super(
        name: 'OpenWebSearch MCP',
        command: Platform.isWindows ? 'cmd' : 'npx',
        arguments: Platform.isWindows
            ? const ['/c', 'npx', '-y', AppConstants.openWebSearchMcpPackage]
            : const ['-y', AppConstants.openWebSearchMcpPackage],
        environment: _environment(),
      );

  // Configure the open-source server for its MCP stdio mode without an API key.
  static Map<String, String> _environment() =>
      Map<String, String>.from(Platform.environment)
        ..['MODE'] = 'stdio'
        ..['DEFAULT_SEARCH_ENGINE'] = 'duckduckgo';
}
