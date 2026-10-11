import 'package:decma/services/agent_tools.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genkit/genkit.dart';

void main() {
  // Exercise the real middleware against raw SDK output before model truncation.
  test(
    'a long MCP error is not counted as successful source evidence',
    () async {
      final tools = AgentTools();
      final request = ToolRequestPart(
        toolRequest: ToolRequest(
          ref: 'call_1',
          name: 'Bybit_MCP_getPrice',
          input: {},
        ),
      );
      final result = await tools.tool(
        request,
        ActionFnArg(),
        (_, _) async => ToolResult.response({
          'isError': true,
          'content': [
            {'type': 'text', 'text': 'x' * 30000},
          ],
        }),
      );
      expect(result.output.toString().length, lessThan(24100));
      expect(tools.attemptedSources, {'Bybit MCP'});
      expect(tools.completedSources, isEmpty);
      expect(tools.evidence, isEmpty);
    },
  );
}
