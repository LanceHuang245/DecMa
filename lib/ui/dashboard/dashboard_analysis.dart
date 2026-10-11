part of 'dashboard_controller.dart';

// Keep deterministic preparation, risk validation, and quick-analysis formatting.
extension DashboardAnalysis on DashboardController {
  // Prepare chart data here; the conversation owns display, history and stopping.
  Future<void> _runAgent() async {
    if (loadingAgent || _isDisposed) return;
    final hasKey = _llm.provider == LlmProvider.openAiCodex
        ? _apiKeyStatus.hasCodexOAuth
        : _apiKeyStatus.hasLlmKeyFor(_llm.id);
    if (!_llm.isComplete || !hasKey) {
      _agentUi.addMessage(
        DashboardMessage.agent(
          _llm.provider == LlmProvider.openAiCodex
              ? '> 请先在设置中登录 OpenAI Codex 并选择模型。'
              : '> 请先在设置中填写 LLM Endpoint、Model 并保存 API Key。',
        ),
      );
      return;
    }
    final prompt = promptController.text.trim();
    final mode = agentMode;
    var symbol = _activeSymbol;
    MarketSnapshot? snapshot;
    await _agentUi.run(
      (token, onText, onActivity) async {
        final cancel = CancelToken();
        final unlink = token.onCancel(() => cancel.cancel());
        try {
          if (mode == AgentMode.analysis) {
            symbol = await cancellable(
              _resolveAnalysisSymbol(prompt, cancel),
              token.whenCancelled,
            );
          }
          token.throwIfCancelled();
          final candles = mode == AgentMode.analysis
              ? await cancellable(
                  _prepareAnalysisChart(symbol, cancel),
                  token.whenCancelled,
                )
              : const <Candle>[];
          token.throwIfCancelled();
          if (mode == AgentMode.analysis && candles.isEmpty) {
            throw Exception('$symbol 没有可分析的 K 线。');
          }
          snapshot = mode == AgentMode.analysis
              ? await cancellable(
                  _buildMarketSnapshot(symbol, cancel),
                  token.whenCancelled,
                )
              : null;
          token.throwIfCancelled();
          final features = snapshot == null
              ? null
              : _featureEngine.calculate(snapshot!);
          if (features != null) onActivity('• Deterministic Engine - 指标计算完成');
          if (mode == AgentMode.analysis) {
            await cancellable(
              _refreshTokenNews(symbol, requestCancel: cancel),
              token.whenCancelled,
            );
          }
          token.throwIfCancelled();
          final events = mode == AgentMode.analysis
              ? await cancellable(
                  _eventSnapshot(symbol, features!),
                  token.whenCancelled,
                )
              : null;
          token.throwIfCancelled();
          return await _agent.run(
            prompt: prompt,
            symbol: symbol,
            candles: candles,
            llm: _llm,
            mcp: _mcp,
            api: _api,
            mode: mode,
            marketSnapshot: snapshot,
            marketFeatures: features,
            eventSnapshot: events,
            previousAnalysisContext: _agentUi.lastAnalysis,
            previousAnalysisAt: _agentUi.lastAnalysisAt,
            previousConversationContext: _agentUi.conversationContext,
            cancel: token,
            onText: onText,
            onActivity: onActivity,
          );
        } finally {
          unlink();
        }
      },
      finish: (answer) => mode == AgentMode.analysis
          ? _applyAnalysisResult(answer, symbol, snapshot)
          : answer.text,
    );
  }

  Future<MarketSnapshot> _buildMarketSnapshot(
    String symbol,
    CancelToken cancel,
  ) async {
    _recordActivity('• Market Snapshot - 获取固定多周期行情');
    final snapshot = await _marketSnapshots.build(symbol, cancelToken: cancel);
    if (snapshot.instrument.status != 'Trading' ||
        snapshot.instrument.contractType != 'LinearPerpetual') {
      throw Exception('$symbol 合约状态或类型无效。');
    }
    return snapshot;
  }

  Future<EventSnapshot> _eventSnapshot(
    String symbol,
    MarketFeatures features,
  ) async {
    final snapshot = _eventSelector.select(events: _newsEvents, symbol: symbol);
    final fallback =
        snapshot.assetSpecificEvents.isEmpty || features.hasAbnormalShortTerm;
    return EventSnapshot(
      snapshotAsOf: snapshot.snapshotAsOf,
      upcomingCriticalEvents: snapshot.upcomingCriticalEvents,
      breakingEvents: snapshot.breakingEvents,
      assetSpecificEvents: snapshot.assetSpecificEvents,
      cryptoMarketEvents: snapshot.cryptoMarketEvents,
      macroEvents: snapshot.macroEvents,
      tokenNewsSearchQueries: fallback
          ? await _newsService.tokenNewsSearchQueries(symbol)
          : const [],
    );
  }

  // Never validate partial streamed JSON or draw a plan for a different contract.
  String _applyAnalysisResult(
    AgentResult answer,
    String symbol,
    MarketSnapshot? snapshot,
  ) {
    final plan = TradePlan.fromResponse(answer.text);
    final notices = [...answer.warnings];
    final validation = plan == null
        ? null
        : _tradePlanValidator.validate(
            plan,
            tickSize: snapshot?.instrument.tickSize,
          );
    final matchesResponse = plan?.symbol == null || plan!.symbol == symbol;
    final matchesChart = _activeSymbol == symbol;
    if (plan == null) {
      notices.add('结果中没有可解析的 TradePlan JSON，未添加图表标记。');
    } else {
      notices.addAll(validation!.warnings);
      if (!validation.isValid) {
        notices.add('TradePlan 校验失败：${validation.errors.join('；')}，未添加图表标记。');
      } else if (!plan.isSetup) {
        notices.add(
          validation.canDrawWaitZone
              ? 'WAIT 不是交易 Setup，仅显示候选等待区。'
              : '${plan.decision} 不是交易 Setup，未添加图表标记。',
        );
      }
    }
    if (!matchesResponse) notices.add('结果 JSON 的币种与分析币种 $symbol 不一致，未添加图表标记。');
    if (!matchesChart) {
      notices.add('当前图表已切换为 $_activeSymbol，未添加 $symbol 的图表标记。');
    }
    final canDisplay =
        plan != null && validation!.isValid && matchesResponse && matchesChart;
    _chartPlan = canDisplay ? plan : null;
    _plan = canDisplay && plan.isSetup ? plan : null;
    _showWaitZone = canDisplay && validation.canDrawWaitZone;
    return notices.isEmpty
        ? answer.text
        : '${answer.text}\n\n> 数据源提示：${notices.join(' | ')}';
  }

  // Preserve the existing readable request and explicit unavailable risk fields.
  void _quickAnalyze({
    required String analysisPlan,
    required AnalysisRiskProfile riskProfile,
    required String currentPosition,
    required String currentPositionSize,
    required String currentPositionEntryPrice,
  }) {
    selectAgentMode(AgentMode.analysis);
    final hasPosition = currentPosition.trim() != '无';
    final aggressiveInstruction = analysisPlan == '激进'
        ? '''激进方案要求：只要核心行情数据有效、存在方向性结构优势，并且能够定义入场触发、结构止损和候选目标，就必须在 LONG_SETUP 和 SHORT_SETUP 中选择更优的条件式方案。OI 历史、清算、多空比、CVD、完整订单流、广泛新闻覆盖或尚未到触发点的执行数据缺失时，只能降低置信度、缩小建议仓位并加入入场前复核，不得仅因此输出 WAIT、NO_TRADE 或 DATA_INSUFFICIENT。若核心行情无效、方向大致均衡、无法定义有效止损，或已验证的净风险收益比不合格，仍可输出相应的 WAIT、NO_TRADE 或 DATA_INSUFFICIENT。

'''
        : '';
    promptController.text =
        '''请分析 $_activeSymbol 的开仓机会。本次交易需持有${_holdingPeriodText(riskProfile.holdingPeriod)}。

账户资金：${_usdtText(riskProfile.accountEquity)}
单笔最大可接受亏损：${_usdtText(riskProfile.riskCash)}
计划开仓数量：${_plannedPositionText(riskProfile.plannedPosition)}
预期单边滑点：${_percentText(riskProfile.expectedSlippageRate)}
安全缓冲：${_percentText(riskProfile.safetyBufferRate)}
最低净风险收益比：${_numberText(riskProfile.minimumNetRewardRisk)}
最大有效杠杆：${_leverageText(riskProfile.maximumEffectiveLeverage)}
当前持仓：${_currentPositionText(currentPosition)}
当前持仓数量：${hasPosition ? _currentPositionText(currentPositionSize) : '0'}
当前持仓均价：${hasPosition ? _currentPositionText(currentPositionEntryPrice) : '0'}

请同时评估 LONG 和 SHORT，并给出当前更优的开仓方向、等待入场区、入场触发条件、最大追价位置、止损位置、分批止盈位置以及风险收益比。

${AgentService.fullSourceEnrichmentMarker}在输出方向结论前，按顺序对已启用且适用于本合约的 Bybit MCP、Coinalyze API 和 Nansen MCP 分别完成有界的数据查询。Harness Market Snapshot 不能替代 Bybit MCP 的补充确认，MCP 工具发现也不算实际取数。若某来源未启用、不支持当前资产或调用失败，必须明确说明，并继续使用其余有效数据完成分析；不得仅因辅助来源缺失而输出 DATA_INSUFFICIENT。

$aggressiveInstruction如果我填写的计划仓位超过上述单笔风险限制，请根据止损距离给出更合理的最大仓位建议。
''';
    _notify();
    unawaited(runAgent());
  }

  // Reuse the existing risk text conversion rules without introducing DTOs.
  String _holdingPeriodText(Duration? value) {
    if (value == null) return '不可用';
    return value.inMinutes % 60 == 0
        ? '${value.inHours} 小时'
        : '${value.inMinutes} 分钟';
  }

  String _usdtText(double? value) =>
      value == null ? '不可用' : '${_numberText(value)} USDT';
  String _plannedPositionText(PlannedPosition? value) {
    if (value == null) return '不可用';
    if (value.notionalUsdt != null) return _usdtText(value.notionalUsdt);
    return '${_numberText(value.assetQuantity)} ${value.asset}';
  }

  String _percentText(double? value) =>
      value == null ? '不可用' : '${_numberText(value * 100)}%';
  String _leverageText(double? value) =>
      value == null ? '不可用' : '${_numberText(value)}x';
  String _numberText(double? value) => value == null
      ? '不可用'
      : value.toStringAsFixed(8).replaceFirst(RegExp(r'\.?0+$'), '');
  String _currentPositionText(String value) =>
      value.trim().isEmpty ? '不可用' : value.trim();
}
