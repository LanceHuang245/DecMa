import 'dart:async';

import 'package:decma/domain/models/app_settings.dart';
import 'package:decma/domain/models/candle.dart';
import 'package:decma/domain/models/trade_plan.dart';
import 'package:decma/data/services/bybit_service.dart';
import 'package:decma/data/services/storage/llm_settings_store.dart';
import 'package:decma/utils/network.dart';
import 'package:dio/dio.dart';
import 'package:decma/ui/chart/candle_chart.dart';
import 'package:decma/ui/chart/candle_chart_painter.dart';
import '../../fixtures/dashboard_agent_fixtures.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Model changes must survive reload without altering another connection.
  test('selecting a model persists only the active connection model', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    const active = LlmSettings(
      id: 'active',
      name: 'Active config',
      provider: LlmProvider.openAiResponses,
      endpoint: 'https://llm.test/v1',
      model: 'old-model',
    );
    const other = LlmSettings(
      id: 'other',
      name: 'Other config',
      provider: LlmProvider.anthropic,
      endpoint: 'https://other.test',
      model: 'other-model',
    );
    final controller = createDashboard(
      nodeAvailable: false,
      initialLlmConnections: LlmConnectionSettings(
        connections: const [active, other],
        activeConnectionId: active.id,
      ),
    );
    addTearDown(controller.dispose);
    await controller.selectLlmReasoningEffort('high');
    expect(
      (await LlmSettingsStore().readConnections()).active.reasoningEffort,
      'high',
    );
    await controller.selectLlmModel('new-model');
    expect(controller.llm.model, 'new-model');
    expect(controller.llm.reasoningEffort, isNull);
    await controller.selectLlmReasoningEffort('low');
    final saved = await LlmSettingsStore().readConnections();
    expect(saved.active.reasoningEffort, 'low');
    expect(saved.active.model, 'new-model');
    expect(saved.active.id, active.id);
    expect(saved.active.name, active.name);
    expect(saved.active.provider, active.provider);
    expect(saved.active.endpoint, active.endpoint);
    expect(saved.connections.last.toJson(), other.toJson());
    await controller.selectLlmReasoningEffort(null);
    expect(
      (await LlmSettingsStore().readConnections()).active.reasoningEffort,
      isNull,
    );
  });

  test('a stale symbol response cannot replace the current chart', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final bybit = _DelayedBybit();
    final controller = createDashboard(nodeAvailable: true, bybit: bybit);

    controller.selectSymbol('ETHUSDT');
    expect(controller.showChartLoading, isTrue);
    expect(controller.candles, isEmpty);

    controller.selectSymbol('XRPUSDT');
    expect(controller.activeSymbol, 'XRPUSDT');
    expect(controller.showChartLoading, isTrue);

    await _flushAsync();
    expect(bybit.wasCancelled('ETHUSDT'), isTrue);
    expect(controller.activeSymbol, 'XRPUSDT');
    expect(controller.candles, isEmpty);
    expect(controller.showChartLoading, isTrue);

    bybit.complete('XRPUSDT', 1);
    await _flushAsync();
    expect(controller.candles.single.close, 1);
    expect(controller.showChartLoading, isFalse);
    expect(controller.loadingChart, isFalse);

    controller.dispose();
  });

  test(
    'one-click analysis asks for current direction without any setup',
    () async {
      final controller = createDashboard(
        nodeAvailable: true,
        initialSymbol: 'ETHUSDT',
      );
      controller.quickAnalyze();
      await _flushAsync();
      expect(
        controller.promptController.text,
        contains('ETHUSDT 现在更适合做多、做空还是等待'),
      );
      expect(controller.promptController.text, isNot(contains('账户')));
      expect(controller.promptController.text, isNot(contains('手续费')));
      expect(controller.promptController.text, isNot(contains('激进')));
      controller.dispose();
    },
  );

  test('Nansen remains enabled when Node.js is unavailable', () {
    final controller = createDashboard(
      nodeAvailable: false,
      initialMcp: const McpSettings(
        useBybit: true,
        useNansen: true,
        useOpenWebSearch: true,
      ),
    );

    expect(controller.mcp.useBybit, isFalse);
    expect(controller.mcp.useNansen, isTrue);
    expect(controller.mcp.useOpenWebSearch, isFalse);

    controller.dispose();
  });

  testWidgets('WAIT renders its candidate zone but hides stop and targets', (
    tester,
  ) async {
    const plan = TradePlan(
      decision: 'WAIT',
      summary: 'Wait for a retest',
      parsedJson: '{}',
      entryLow: 100,
      entryHigh: 101,
      stopLoss: 98,
      targets: [TradeTarget(price: 105)],
    );
    await tester.pumpWidget(
      FluentApp(
        home: SizedBox(
          width: 800,
          height: 500,
          child: CandleChart(
            candles: [
              Candle(
                time: DateTime.utc(2026, 8, 10),
                open: 100,
                high: 101,
                low: 99,
                close: 100,
                volume: 1,
              ),
            ],
            plan: plan,
            showWaitZone: true,
          ),
        ),
      ),
    );

    final painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<PlanCandlePainter>()
        .single;
    expect(painter.plan(), same(plan));
    expect(find.text('开仓区：-'), findsNothing);
    expect(find.text('止损：-'), findsOneWidget);
    expect(find.text('止盈：-'), findsOneWidget);
  });
}

Future<void> _flushAsync() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class _DelayedBybit extends BybitService {
  final _requests = <String, Completer<List<Candle>>>{};

  @override
  Future<List<Candle>> fetchKlines({
    required String symbol,
    required String interval,
    int limit = 160,
    int? start,
    int? end,
    CancelToken? cancelToken,
  }) {
    final request = _requests[symbol] ??= Completer<List<Candle>>();
    cancelToken?.whenCancel.then((_) {
      _cancelled.add(symbol);
      if (!request.isCompleted) {
        request.completeError(
          const AppFailure(kind: AppFailureKind.cancelled, provider: 'Bybit'),
        );
      }
    });
    return request.future;
  }

  final _cancelled = <String>{};

  bool wasCancelled(String symbol) => _cancelled.contains(symbol);

  void complete(String symbol, double close) {
    _requests[symbol]!.complete([
      Candle(
        time: DateTime.utc(2026, 8, 10),
        open: close,
        high: close,
        low: close,
        close: close,
        volume: 1,
      ),
    ]);
  }
}
