import 'package:decma/models/trading_models.dart';
import 'package:decma/services/agent_service.dart';
import 'package:decma/ui/dashboard/dashboard_agent_panel.dart';
import 'package:decma/ui/dashboard/dashboard_controller.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'dashboard_agent_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () => SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty(),
  );

  // Cancelling prep restores chart loading without starting remote generation.
  test('stopping chart preparation restores the chart loading state', () async {
    final agent = StreamingAgent();
    final bybit = SlowChartBybit();
    final controller = await testController(agent, bybit: bybit);
    controller.selectAgentMode(AgentMode.analysis);
    controller.promptController.text = 'Analyze BTCUSDT';
    final run = controller.runAgent();
    await bybit.started.future;
    expect(controller.showChartLoading, true);
    controller.stopAgent();
    await run;
    await flushAgentCallbacks();
    expect(bybit.token!.isCancelled, true);
    expect(controller.loadingAgent, false);
    expect(controller.showChartLoading, false);
    expect(controller.chartError, isNull);
    expect(agent.results, isEmpty);
    bybit.result.complete(const []);
    controller.dispose();
  });

  // Stream snapshots replace one message while retaining interleaved statuses.
  test(
    'streaming and source repair replace a draft while keeping activities',
    () async {
      final agent = StreamingAgent();
      final controller = await testController(agent);
      controller.promptController.text = 'Hi';
      final run = controller.runAgent();
      await agent.started.future;
      expect(controller.loadingAgent, true);
      agent.texts.single('First draft');
      expect(
        controller.conversation
            .where((m) => m.kind == DashboardMessageKind.agent)
            .single
            .text,
        'First draft',
      );
      agent.activities.single('• MCP - data');
      agent.texts.single('');
      agent.texts.single('Revised draft');
      agent.results.single.complete(
        const AgentResult(text: 'Final answer', warnings: []),
      );
      await run;
      expect(controller.loadingAgent, false);
      expect(
        controller.conversation
            .where((m) => m.kind == DashboardMessageKind.agent)
            .single
            .text,
        'Final answer',
      );
      expect(
        controller.conversation.any((m) => m.text == '• MCP - data'),
        true,
      );
      controller.dispose();
    },
  );

  // A stopped request cannot alter the subsequent run through late callbacks.
  test('stop preserves partial text and isolates the following run', () async {
    final agent = StreamingAgent();
    final controller = await testController(agent);
    controller.promptController.text = 'First';
    final first = controller.runAgent();
    await agent.started.future;
    agent.texts[0]('Partial');
    controller.stopAgent();
    await first;
    expect(agent.tokens[0]!.isCancelled, true);
    expect(controller.loadingAgent, false);
    expect(controller.conversation.last.text, contains('已停止生成'));
    expect(controller.conversation.last.text, contains('Partial'));
    expect(controller.plan, isNull);
    controller.clearAgentContext();
    controller.promptController.text = 'Second';
    final second = controller.runAgent();
    await flushAgentCallbacks();
    agent.texts[0]('late old text');
    agent.activities[0]('late old activity');
    agent.texts[1]('New answer');
    agent.results[1].complete(
      const AgentResult(text: 'New answer', warnings: []),
    );
    await second;
    expect(
      controller.conversation.any((m) => m.text.contains('late old')),
      false,
    );
    expect(controller.conversation.last.text, 'New answer');
    agent.results[0].complete(
      const AgentResult(text: 'old result', warnings: []),
    );
    controller.dispose();
  });

  // Page disposal cancels generation before late output can touch UI state.
  test('disposing the dashboard cancels active generation', () async {
    final agent = StreamingAgent();
    final controller = await testController(agent);
    controller.promptController.text = 'Hi';
    final run = controller.runAgent();
    await agent.started.future;
    controller.dispose();
    await run;
    expect(agent.tokens.single!.isCancelled, true);
    agent.texts.single('late disposed chunk');
    expect(
      controller.conversation.any((m) => m.text == 'late disposed chunk'),
      false,
    );
    agent.results.single.complete(const AgentResult(text: 'old', warnings: []));
  });

  // Verify the visible stop action is enabled throughout active generation.
  testWidgets('the generating panel exposes an enabled stop action', (
    tester,
  ) async {
    var stops = 0;
    final prompt = TextEditingController();
    final scroll = ScrollController();
    await tester.pumpWidget(
      FluentApp(
        home: SizedBox(
          width: 600,
          height: 500,
          child: DashboardAgentPanel(
            plan: null,
            messages: const [],
            scrollController: scroll,
            showScrollToBottom: false,
            mode: AgentMode.conversation,
            llm: const LlmSettings(
              provider: LlmProvider.openAiResponses,
              endpoint: 'https://llm.test/v1',
              model: 'test-model',
            ),
            loading: true,
            promptController: prompt,
            onModeChanged: (_) {},
            onQuickAnalysis: () {},
            onSend: () {},
            onStop: () => stops++,
            onClear: () {},
            onScrollToBottom: () {},
            onOpenSettings: () {},
          ),
        ),
      ),
    );
    await tester.tap(find.text('停止生成'));
    expect(stops, 1);
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpWidget(const SizedBox());
    prompt.dispose();
    scroll.dispose();
  });
}
