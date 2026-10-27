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
              ? appL10n.codexNotReady
              : appL10n.llmNotReady,
        ),
      );
      return;
    }
    final prompt = promptController.text.trim();
    trading.clear();
    _plan = null;
    _chartPlan = null;
    _showWaitZone = false;
    var symbol = market.activeSymbol;
    MarketSnapshot? snapshot;
    await _agentUi.run((token, onText, onActivity) async {
      var resultAnnounced = false;
      final cancel = CancelToken();
      final unlink = token.onCancel(() => cancel.cancel());
      try {
        symbol = await cancellable(
          market.resolveSymbol(prompt, cancel),
          token.whenCancelled,
        );
        token.throwIfCancelled();
        final candles = await cancellable(
          market.prepare(symbol, cancel),
          token.whenCancelled,
        );
        token.throwIfCancelled();
        if (candles.isEmpty) {
          throw Exception(appL10n.noCandlesToAnalyze(symbol));
        }
        snapshot = await cancellable(
          _buildMarketSnapshot(symbol, cancel),
          token.whenCancelled,
        );
        token.throwIfCancelled();
        final features = _featureEngine.calculate(snapshot!);
        onActivity(appL10n.activityIndicatorsDone);
        await cancellable(
          newsFeed.refreshToken(symbol, requestCancel: cancel),
          token.whenCancelled,
        );
        token.throwIfCancelled();
        final events = await cancellable(
          newsFeed.snapshot(symbol, abnormal: features.hasAbnormalShortTerm),
          token.whenCancelled,
        );
        token.throwIfCancelled();
        return await agent.run(
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
            // Tool turns and source repair start new segments, including JSON visibility.
            if (text.isEmpty) {
              resultAnnounced = false;
              onText('');
              return;
            }
            // Hide the machine payload while the readable answer is streaming.
            final fence = RegExp(
              r'```[ \t]*json\b',
              caseSensitive: false,
            ).firstMatch(text);
            final visible = fence == null
                ? text
                : text.substring(0, fence.start);
            if (visible.isNotEmpty) onText(visible);
            // Log the hidden payload stage once, using the existing MCP activity UI.
            if (fence != null && !resultAnnounced) {
              resultAnnounced = true;
              onActivity(appL10n.activityResultGenerating);
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
    _recordActivity(appL10n.activityMarketSnapshot);
    final snapshot = await _marketSnapshots.build(symbol, cancelToken: cancel);
    if (snapshot.instrument.status != 'Trading' ||
        snapshot.instrument.contractType != 'LinearPerpetual') {
      throw Exception(appL10n.invalidContract(symbol));
    }
    return snapshot;
  }

  // Never validate partial streamed JSON or draw a plan for a different contract.
  Future<String> _applyAnalysisResult(
    AgentResult answer,
    String symbol,
    MarketSnapshot? snapshot,
  ) async {
    final parsed = TradePlan.parseResponse(answer.text);
    final plan = parsed.plan;
    final notices = [...answer.warnings];
    final validation = plan == null
        ? null
        : _tradePlanValidator.validate(
            plan,
            tickSize: snapshot?.instrument.tickSize,
          );
    final matchesResponse = plan?.symbol == null || plan!.symbol == symbol;
    final matchesChart = market.activeSymbol == symbol;
    if (plan == null) {
      notices.add(appL10n.noticeNoPlan);
    } else {
      notices.addAll(validation!.warnings);
      if (!validation.isValid) {
        notices.add(appL10n.noticePlanRejected);
      }
    }
    if (!matchesResponse) notices.add(appL10n.noticeSymbolMismatch(symbol));
    if (!matchesChart) {
      notices.add(appL10n.noticeChartSwitched(market.activeSymbol, symbol));
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
    final visibleText = parsed.text;
    return notices.isEmpty
        ? visibleText
        : '$visibleText\n\n${appL10n.dataSourceNotice(notices.join(' | '))}';
  }

  // One click asks the trading question for the chosen holding horizon.
  void _quickAnalyze({bool swing = false}) {
    promptController.text = swing
        ? appL10n.swingAnalyzePrompt(market.activeSymbol)
        : appL10n.quickAnalyzePrompt(market.activeSymbol);
    _notify();
    unawaited(runAgent());
  }
}
