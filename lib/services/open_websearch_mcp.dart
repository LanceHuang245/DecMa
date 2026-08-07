import 'dart:io';

import 'mcp_connection.dart';

class OpenWebSearchMcp extends StdioMcpConnection {
  OpenWebSearchMcp()
    : super(
        name: 'OpenWebSearch MCP',
        command: 'npx',
        arguments: const ['-y', 'open-websearch@latest'],
        environment: _environment(),
      );

  // Configure the open-source server for its MCP stdio mode without an API key.
  static Map<String, String> _environment() =>
      Map<String, String>.from(Platform.environment)
        ..['MODE'] = 'stdio'
        ..['DEFAULT_SEARCH_ENGINE'] = 'duckduckgo';
}
