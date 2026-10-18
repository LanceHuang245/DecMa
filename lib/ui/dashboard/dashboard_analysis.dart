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
    trading.clear();
    _plan = null;
    _chartPlan = null;
    _showWaitZone = false;
    var symbol = _activeSymbol;
    MarketSnapshot? snapshot;
    await _agentUi.run((token, onText, onActivity) async {
      var resultAnnounced = false;
      final cancel = CancelToken();
      final unlink = token.onCancel(() => cancel.cancel());
      try {
        symbol = await cancellable(
          _resolveAnalysisSymbol(prompt, cancel),
          token.whenCancelled,
        );
        token.throwIfCancelled();
        final candles = await cancellable(
          _prepareAnalysisChart(symbol, cancel),
          token.whenCancelled,
        );
        token.throwIfCancelled();
        if (candles.isEmpty) {
          throw Exception('$symbol 没有可分析的 K 线。');
        }
        snapshot = await cancellable(
          _buildMarketSnapshot(symbol, cancel),
          token.whenCancelled,
        );
        token.throwIfCancelled();
        final features = _featureEngine.calculate(snapshot!);
        onActivity('• Deterministic Engine - 指标计算完成');
        await cancellable(
          _refreshTokenNews(symbol, requestCancel: cancel),
          token.whenCancelled,
        );
        token.throwIfCancelled();
        final events = await cancellable(
          _eventSnapshot(symbol, features),
          token.whenCancelled,
        );
        token.throwIfCancelled();
        return await _agent.run(
          prompt: prompt,
          symbol: symbol,
          candles: candles,
          llm: _llm,
          mcp: _mcp,
          api: _api,
          marketSnapshot: snapshot,
          marketFeatures: features,
          eventSnapshot: events,
          previousAnalysisContext: _agentUi.lastAnalysis,
          previousAnalysisAt: _agentUi.lastAnalysisAt,
          cancel: token,
          onText: (text) {
            // Hide the machine payload while the readable answer is streaming.
            final fence = text.indexOf('```json');
            onText(fence < 0 ? text : text.substring(0, fence));
            // Log the hidden payload stage once, using the existing MCP activity UI.
            if (fence >= 0 && !resultAnnounced) {
              resultAnnounced = true;
              onActivity('• Result - 结果生成中…');
            }
          },
          onActivity: onActivity,
        );
      } finally {
        unlink();
      }
    }, finish: (answer) => _applyAnalysisResult(answer, symbol, snapshot));
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
  Future<String> _applyAnalysisResult(
    AgentResult answer,
    String symbol,
    MarketSnapshot? snapshot,
  ) async {
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
      notices.add('暂未获得完整价格计划，请以文字说明为准。');
    } else {
      notices.addAll(validation!.warnings);
      if (!validation.isValid) {
        notices.add('价格计划未通过校验，暂不使用这些价位。');
      }
    }
    if (!matchesResponse) notices.add('分析对象与 $symbol 不一致，请重新分析。');
    if (!matchesChart) {
      notices.add('当前图表已切换为 $_activeSymbol，未添加 $symbol 的图表标记。');
    }
    final canDisplay =
        plan != null && validation!.isValid && matchesResponse && matchesChart;
    _chartPlan = canDisplay ? plan : null;
    _plan = canDisplay && plan.isSetup ? plan : null;
    _showWaitZone = canDisplay && validation.canDrawWaitZone;
    if (canDisplay && snapshot != null) {
      await trading.accept(plan, snapshot);
      if (_isDisposed) return answer.text;
    }
    final visibleText = TradePlan.displayText(answer.text);
    return notices.isEmpty
        ? visibleText
        : '$visibleText\n\n> 数据源提示：${notices.join(' | ')}';
  }

  // One click asks the trading question; no account setup is needed.
  void _quickAnalyze() {
    promptController.text =
        '分析 $_activeSymbol 现在更适合做多、做空还是等待。'
        '请结合当前价格，直接说明现在能否入场；如果机会已经走完，说明应该等待什么条件。';
    _notify();
    unawaited(runAgent());
  }
}
