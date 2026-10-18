import 'package:decma/services/agent_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'dashboard_agent_fixtures.dart';

const _plan =
    '{"request":{"symbol":"BTCUSDT"},"decision":{"type":"WAIT","summary":"Wait"},"entry_plan":{"entry_zone_low":100,"entry_zone_high":101}}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () => SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty(),
  );

  // Exercise the actual preparation/validator path, not just a conversation mock.
  test('a chart plan is applied only after finalized generation', () async {
    final agent = StreamingAgent();
    final controller = await testController(agent, bybit: AnalysisBybit());
    controller.promptController.text = 'Analyze BTCUSDT';
    final run = controller.runAgent();
    await agent.started.future;
    agent.texts.single('Wait\n```json\n{');
    agent.texts.single('Wait\n```json\n$_plan');
    expect(
      controller.conversation.where(
        (m) => m.isActivity && m.text == '• Result - 结果生成中…',
      ),
      hasLength(1),
    );
    expect(
      controller.conversation.where((m) => !m.isActivity).last.text.trim(),
      'Wait',
    );
    expect(controller.chartPlan, isNull);
    agent.results.single.complete(const AgentResult(text: _plan, warnings: []));
    await run;
    expect(controller.chartPlan?.decision, 'WAIT');
    expect(controller.showWaitZone, true);
    expect(controller.plan, isNull);
    controller.dispose();
  });

  // Follow-ups retain historical analysis while obtaining a fresh market snapshot.
  test('follow-ups reuse the last analysis with current market data', () async {
    final agent = StreamingAgent();
    final controller = await testController(agent);
    controller.promptController.text = 'Analyze BTCUSDT';
    final first = controller.runAgent();
    await agent.started.future;
    final originalSnapshot = agent.snapshots.single;
    expect(originalSnapshot, isNotNull);
    agent.results.single.complete(
      const AgentResult(text: 'Initial analysis\n$_plan', warnings: []),
    );
    await first;

    controller.promptController.text = 'Why should I wait?';
    final followUp = controller.runAgent();
    await flushAgentCallbacks();
    expect(agent.previousAnalyses.last, contains('Initial analysis'));
    expect(agent.snapshots.last, isNotNull);
    expect(agent.snapshots.last, isNot(same(originalSnapshot)));
    agent.results.last.complete(
      const AgentResult(text: 'Updated analysis\n$_plan', warnings: []),
    );
    await followUp;
    expect(controller.loadingAgent, isFalse);
    controller.dispose();
  });

  // Even parseable draft JSON must not be committed to chart or later context.
  test(
    'cancelled analysis cannot update the plan or remembered analysis',
    () async {
      final agent = StreamingAgent();
      final controller = await testController(agent, bybit: AnalysisBybit());
      controller.promptController.text = 'Analyze BTCUSDT';
      final run = controller.runAgent();
      await agent.started.future;
      agent.texts.single(_plan);
      controller.stopAgent();
      await run;
      expect(controller.chartPlan, isNull);
      expect(controller.showWaitZone, false);
      controller.promptController.text = 'Follow up';
      final next = controller.runAgent();
      await flushAgentCallbacks();
      expect(agent.previousAnalyses.last, isNull);
      agent.results.last.complete(
        const AgentResult(text: 'Reply', warnings: []),
      );
      await next;
      agent.results.first.complete(
        const AgentResult(text: _plan, warnings: []),
      );
      controller.dispose();
    },
  );
}
