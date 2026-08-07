import 'mcp_connection.dart';

class NansenMcp extends HttpMcpConnection {
  NansenMcp(String apiKey)
    : super(
        name: 'Nansen MCP',
        endpoint: 'https://mcp.nansen.ai/ra/mcp',
        headers: {'NANSEN-API-KEY': apiKey},
      );
}
