class McpTool {
  const McpTool({
    required this.functionName,
    required this.serverName,
    required this.name,
    required this.description,
    required this.inputSchema,
  });

  final String functionName;
  final String serverName;
  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;

  Map<String, dynamic> toFunctionDefinition() => {
    'name': functionName,
    'description': '[$serverName] $description',
    'parameters': inputSchema,
  };
}

abstract class McpConnection {
  String get name;
  Future<List<McpTool>> listTools();
  Future<String> call(String toolName, Map<String, dynamic> arguments);
  Future<void> close();
}

List<McpTool> toolsFromMcpResult(
  String serverName,
  Map<String, dynamic> result,
) {
  final tools = result['tools'];
  if (tools is! List) return const [];
  return tools.whereType<Map>().map((raw) {
    final tool = Map<String, dynamic>.from(raw);
    final name = tool['name'].toString();
    final schema = tool['inputSchema'];
    return McpTool(
      functionName:
          '${serverName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}_${name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}',
      serverName: serverName,
      name: name,
      description: tool['description']?.toString() ?? name,
      inputSchema: schema is Map<String, dynamic>
          ? schema
          : Map<String, dynamic>.from(schema as Map? ?? const {}),
    );
  }).toList();
}
