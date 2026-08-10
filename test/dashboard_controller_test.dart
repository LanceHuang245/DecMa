import 'dart:async';

import 'package:decma/models/trading_models.dart';
import 'package:decma/services/agent_service.dart';
import 'package:decma/services/bybit_service.dart';
import 'package:decma/utils/network.dart';
import 'package:dio/dio.dart';
import 'package:decma/ui/chart/candle_chart.dart';
import 'package:decma/ui/chart/candle_chart_painter.dart';
import 'package:decma/ui/dashboard/dashboard_controller.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a stale symbol response cannot replace the current chart', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final bybit = _DelayedBybit();
    final controller = DashboardController(nodeAvailable: true, bybit: bybit);

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

  test('quick analysis sends the confirmed form request', () async {
    final controller = DashboardController(
      nodeAvailable: true,
      initialSymbol: 'ETHUSDT',
    );

    controller.quickAnalyze(
      analysisPlan: '激进',
      tradeWindow: '3 小时',
      accountBalance: '1,000 USDT',
      maxLoss: '20 USDT',
      plannedPosition: '500 USDT',
      currentPosition: '无',
      currentPositionSize: '99',
      currentPositionEntryPrice: '88,888',
    );
    await _flushAsync();

    expect(controller.agentMode, AgentMode.analysis);
    expect(controller.loadingAgent, isFalse);
    expect(controller.conversation, hasLength(1));
    expect(
      controller.promptController.text,
      '''请分析 ETHUSDT 的短线开仓机会。本次交易需在3 小时内完成。

账户资金：1,000 USDT
单笔最大可接受亏损：20 USDT
计划开仓数量：500 USDT
当前持仓：无
当前持仓数量：0
当前持仓均价：0

请同时评估 LONG 和 SHORT，并给出当前更优的开仓方向、等待入场区、入场触发条件、最大追价位置、止损位置、分批止盈位置以及风险收益比。

数据采集要求：FULL_SOURCE_ENRICHMENT。在输出方向结论前，按顺序对已启用且适用于本合约的 Bybit MCP、Coinalyze API 和 Nansen MCP 分别完成有界的数据查询。Harness Market Snapshot 不能替代 Bybit MCP 的补充确认，MCP 工具发现也不算实际取数。若某来源未启用、不支持当前资产或调用失败，必须明确说明，并继续使用其余有效数据完成分析；不得仅因辅助来源缺失而输出 DATA_INSUFFICIENT。

激进方案要求：只要核心行情数据有效、存在方向性结构优势，并且能够定义入场触发、结构止损和候选目标，就必须在 LONG_SETUP 和 SHORT_SETUP 中选择更优的条件式方案。OI 历史、清算、多空比、CVD、完整订单流、广泛新闻覆盖或尚未到触发点的执行数据缺失时，只能降低置信度、缩小建议仓位并加入入场前复核，不得仅因此输出 WAIT、NO_TRADE 或 DATA_INSUFFICIENT。若核心行情无效、方向大致均衡、无法定义有效止损，或已验证的净风险收益比不合格，仍可输出相应的 WAIT、NO_TRADE 或 DATA_INSUFFICIENT。

如果我填写的计划仓位超过上述单笔风险限制，请根据止损距离给出更合理的最大仓位建议。
''',
    );

    controller.dispose();
  });

  test('Nansen remains enabled when Node.js is unavailable', () {
    final controller = DashboardController(
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
        .whereType<CandlePainter>()
        .single;
    expect(painter.plan, same(plan));
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
