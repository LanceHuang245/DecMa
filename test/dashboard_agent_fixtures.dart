import 'dart:async';

import 'package:decma/models/market_snapshot.dart';
import 'package:decma/models/news_event.dart';
import 'package:decma/models/trading_models.dart';
import 'package:decma/services/agent_service.dart';
import 'package:decma/services/analysis/feature_engine.dart';
import 'package:decma/services/bybit_service.dart';
import 'package:decma/services/secure_key_store.dart';
import 'package:decma/ui/dashboard/dashboard_controller.dart';
import 'package:decma/utils/network.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genkit/genkit.dart';

// Replace remote generation only; keep preparation and UI state real.
class StreamingAgent extends AgentService {
  final started = Completer<void>();
  final texts = <void Function(String)>[];
  final activities = <void Function(String)>[];
  final tokens = <CancellationToken?>[];
  final results = <Completer<AgentResult>>[];
  final previousAnalyses = <String?>[];
  final snapshots = <MarketSnapshot?>[];
  @override
  Future<AgentResult> run({
    required String prompt,
    required String symbol,
    required List<Candle> candles,
    required LlmSettings llm,
    required McpSettings mcp,
    required ApiSettings api,
    MarketSnapshot? marketSnapshot,
    MarketFeatures? marketFeatures,
    EventSnapshot? eventSnapshot,
    String? previousAnalysisContext,
    DateTime? previousAnalysisAt,
    void Function(String)? onActivity,
    void Function(String)? onText,
    CancellationToken? cancel,
  }) {
    texts.add(onText!);
    activities.add(onActivity!);
    tokens.add(cancel);
    previousAnalyses.add(previousAnalysisContext);
    snapshots.add(marketSnapshot);
    final result = Completer<AgentResult>();
    results.add(result);
    if (!started.isCompleted) started.complete();
    return cancellable(result.future, cancel?.whenCancelled);
  }
}

class _Keys extends SecureKeyStore {
  @override
  Future<void> update(ApiKeyUpdates updates) async {}
  @override
  Future<ApiKeyStatus> status({
    Iterable<String> llmConnectionIds = const ['default'],
  }) async =>
      const ApiKeyStatus(hasLlmKey: true, llmKeyConnectionIds: {'default'});
}

// Load through the actual settings entry point without background startup I/O.
Future<DashboardController> testController(
  AgentService agent, {
  BybitService? bybit,
}) async {
  addTearDown(agent.dispose);
  final exchange = bybit ?? AnalysisBybit();
  addTearDown(exchange.dispose);
  final connections = LlmConnectionSettings(
    connections: const [
      LlmSettings(
        provider: LlmProvider.openAiResponses,
        endpoint: 'https://llm.test/v1',
        model: 'test-model',
      ),
    ],
    activeConnectionId: 'default',
  );
  const mcp = McpSettings(
    useBybit: false,
    useNansen: false,
    useOpenWebSearch: false,
  );
  const api = ApiSettings(useCoinalyze: false);
  final controller = DashboardController(
    nodeAvailable: false,
    agent: agent,
    bybit: exchange,
    keyStore: _Keys(),
    initialLlmConnections: connections,
  );
  await controller.saveSettings(connections, mcp, api, const ApiKeyUpdates());
  return controller;
}

Future<void> flushAgentCallbacks() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

// Stall only preparation so cancellation exercises the dashboard's real state.
class SlowChartBybit extends BybitService {
  final started = Completer<void>();
  final result = Completer<List<Candle>>();
  CancelToken? token;
  @override
  Future<List<String>> fetchLinearSymbols({CancelToken? cancelToken}) async => [
    'BTCUSDT',
  ];
  @override
  Future<List<Candle>> fetchKlines({
    required String symbol,
    required String interval,
    int limit = 160,
    int? start,
    int? end,
    CancelToken? cancelToken,
  }) {
    token = cancelToken;
    if (!started.isCompleted) started.complete();
    return Future.any([
      result.future,
      cancelToken!.whenCancel.then<List<Candle>>(
        (_) => throw const AppFailure(kind: AppFailureKind.cancelled),
      ),
    ]);
  }
}

// Supply valid bounded exchange data for the real deterministic analysis pipeline.
class AnalysisBybit extends BybitService {
  @override
  Future<List<String>> fetchLinearSymbols({CancelToken? cancelToken}) async => [
    'BTCUSDT',
  ];
  @override
  Future<InstrumentSnapshot> fetchInstrument(
    String symbol, {
    CancelToken? cancelToken,
  }) async => InstrumentSnapshot(
    symbol: symbol,
    contractType: 'LinearPerpetual',
    status: 'Trading',
    tickSize: 0.1,
    quantityStep: 0.001,
    minimumOrderQuantity: 0.001,
    maximumOrderQuantity: 100,
    minimumNotionalValue: 5,
    fundingIntervalMinutes: 480,
    observedAt: DateTime.now().toUtc(),
  );
  @override
  Future<TickerSnapshot> fetchTicker(
    String symbol, {
    CancelToken? cancelToken,
  }) async => TickerSnapshot(
    symbol: symbol,
    lastPrice: 100,
    markPrice: 100,
    indexPrice: 100,
    bestBid: 99.9,
    bestAsk: 100.1,
    openInterest: 1000,
    fundingRate: 0.0001,
    observedAt: DateTime.now().toUtc(),
  );
  @override
  Future<List<Candle>> fetchKlines({
    required String symbol,
    required String interval,
    int limit = 160,
    int? start,
    int? end,
    CancelToken? cancelToken,
  }) async => List.generate(
    60,
    (i) => Candle(
      time: DateTime.now().toUtc().subtract(
        Duration(minutes: int.parse(interval) * (60 - i)),
      ),
      open: 100,
      high: 101,
      low: 99,
      close: 100,
      volume: 10,
    ),
  );
}
