import 'mcp_connection.dart';

class CoinGlassMcp extends HttpMcpConnection {
  CoinGlassMcp(String apiKey)
    : super(
        name: 'CoinGlass MCP',
        endpoint: 'https://api-mcp.coinglass.com/mcp',
        headers: {'CG-API-KEY': apiKey},
      );
}
