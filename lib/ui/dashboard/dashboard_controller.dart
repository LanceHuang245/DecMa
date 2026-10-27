import 'dart:async';

import 'package:dio/dio.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../../domain/models/market_snapshot.dart';
import '../../domain/models/news_event.dart';
import '../../domain/models/app_settings.dart';
import '../../domain/models/llm_model_info.dart';
import '../../domain/models/candle.dart';
import '../../domain/models/trade_plan.dart';
import '../../data/services/agent_service.dart';
import '../../data/services/llm_model_catalog.dart';
import '../../domain/analysis/feature_engine.dart';
import 'trading_session.dart';
import '../../data/services/market_snapshot_service.dart';
import '../../domain/analysis/trade_plan_validator.dart';
import '../../data/services/bybit_service.dart';
import '../../data/services/storage/llm_settings_store.dart';
import '../../data/services/storage/secure_key_store.dart';
import '../../data/repositories/news_repository.dart';
import '../../utils/network.dart';
import '../chart/market_controller.dart';
import 'dashboard_agent.dart';
import '../news/news_controller.dart';
import '../../l10n/app_languages.dart';

export 'dashboard_agent.dart' show DashboardMessage, DashboardMessageKind;

// Analysis orchestration uses the dashboard's selected settings and plan state.
part 'dashboard_analysis.dart';

// Own dashboard state and resource lifetime independently of the page layout.
class DashboardController extends ChangeNotifier {
  DashboardController({
    required bool nodeAvailable,
    required BybitService bybit,
    required this.agent,
    required NewsRepository newsRepository,
    required SecureKeyStore keyStore,
    required this.settingsStore,
    LlmConnectionSettings? initialLlmConnections,
    McpSettings? initialMcp,
    ApiSettings? initialApi,
    NewsSettings? initialNews,
    String? initialSymbol,
  }) : _keyStore = keyStore,
       _marketSnapshots = MarketSnapshotService(bybit),
       trading = TradingSession(bybit) {
    final defaultLlm = LlmSettings(
      provider: LlmProvider.openAiResponses,
      endpoint: LlmProvider.openAiResponses.defaultEndpoint,
      model: 'gpt-4.1',
    );
    _llmConnections =
        initialLlmConnections ??
        LlmConnectionSettings(
          connections: [defaultLlm],
          activeConnectionId: defaultLlm.id,
        );
    _llm = _llmConnections.active;
    if (initialMcp != null) _mcp = initialMcp;
    if (initialApi != null) _api = initialApi;
    market = MarketController(
      bybit,
      symbol: initialSymbol?.trim().isNotEmpty == true
          ? initialSymbol!.trim().toUpperCase()
          : 'BTCUSDT',
    );
    if (!nodeAvailable) {
      _mcp = McpSettings(
        useBybit: false,
        useNansen: _mcp.useNansen,
        useOpenWebSearch: false,
      );
    }
    newsFeed = NewsController(
      newsRepository,
      keyStore,
      symbol: market.activeSymbol,
      settings:
          initialNews ??
          const NewsSettings(
            useFinnhub: false,
            useMarketaux: false,
            useBls: true,
            useBea: true,
            useFederalReserve: true,
            useWhiteHouse: true,
            useSec: true,
            useBbc: false,
          ),
    )..addListener(_onNewsChanged);
    market.addListener(_onMarketChanged);
    _agentUi.addListener(_notify);
    trading.addListener(_notify);
  }

  final TradingSession trading;
  late final MarketController market;
  late final NewsController newsFeed;
  final AgentService agent;
  final LlmSettingsStore settingsStore;
  final SecureKeyStore _keyStore;
  final MarketSnapshotService _marketSnapshots;
  final _agentUi = AgentConversationController();
  final _featureEngine = const FeatureEngine();
  final _tradePlanValidator = const TradePlanValidator();
  TradePlan? _plan, _chartPlan;
  bool _showWaitZone = false, _isDisposed = false;
  ApiKeyStatus _apiKeyStatus = const ApiKeyStatus();
  late LlmSettings _llm;
  late LlmConnectionSettings _llmConnections;
  McpSettings _mcp = const McpSettings(
    useBybit: true,
    useNansen: false,
    useOpenWebSearch: true,
  );
  ApiSettings _api = const ApiSettings(useCoinalyze: false);
  // Expose the same page-facing state as before the streaming migration.
  TextEditingController get symbolController => market.symbolController;
  TextEditingController get promptController => _agentUi.prompt;
  ScrollController get conversationScrollController => _agentUi.scroll;
  String get activeSymbol => market.activeSymbol;
  String get interval => market.interval;
  List<Candle> get candles => market.candles;
  int get totalPrependedCandles => market.totalPrepended;
  List<String> get symbols => market.symbols;
  List<NewsEvent> get newsEvents => newsFeed.events;
  Listenable get newsListenable => newsFeed;
  Map<String, NewsProviderStatus> get newsProviderStatuses => newsFeed.statuses;
  TradePlan? get plan => _plan;
  TradePlan? get chartPlan =>
      trading.assessment?.terminal == true ? null : _chartPlan;
  bool get showWaitZone => _showWaitZone;
  List<DashboardMessage> get conversation => _agentUi.messages;
  String? get chartError => market.error;
  String? get historyError => market.historyError;
  int get chartVersion => market.version;
  bool get loadingChart => market.loading;
  bool get showChartLoading => market.showLoading;
  bool get loadingAgent => _agentUi.loading;
  bool get loadingMore => market.loadingMore;
  bool get hasMoreHistory => market.hasMore;
  bool get showScrollToBottom => _agentUi.showScrollToBottom;
  ApiKeyStatus get apiKeyStatus => _apiKeyStatus;
  LlmSettings get llm => _llm;
  LlmConnectionSettings get llmConnections => _llmConnections;
  McpSettings get mcp => _mcp;
  ApiSettings get api => _api;
  NewsSettings get news => newsFeed.settings;
  bool get refreshingNews => newsFeed.refreshing;

  // Delegate conversation controls to the object that owns their state.
  void stopAgent() {
    _agentUi.stop();
    _clearPlan();
    _notify();
  }

  void scrollConversationToBottom() => _agentUi.scrollToBottom();
  // Expose instance methods so callers do not depend on extension imports.
  Future<void> runAgent() => _runAgent();
  void quickAnalyze({bool swing = false}) => _quickAnalyze(swing: swing);
  Future<void> loadMoreHistory() => market.loadMore();
  void retryChart() => market.retry();
  void selectSymbol(String symbol) => market.selectSymbol(symbol);
  void selectInterval(String interval) {
    if (interval == market.interval) return;
    _clearPlan();
    market.selectInterval(interval);
  }

  void _recordActivity(String activity) => _agentUi.recordActivity(activity);
  void clearAgentContext() {
    if (loadingAgent) return;
    _clearPlan();
    _agentUi.clear();
  }

  // Start independent background feeds without tying them to an Agent run.
  void initialize() {
    unawaited(_loadApiKeyStatus());
    market.initialize();
    newsFeed.initialize();
  }

  // Never notify listeners or apply cancelled requests after page disposal.
  void _notify() {
    if (!_isDisposed) notifyListeners();
  }

  void _onNewsChanged() {
    // Revoke only new, relevant and officially confirmed critical event risks.
    final created = trading.createdAt;
    if (created != null && trading.plan != null) {
      final asset = trading.plan!.symbol?.replaceFirst(RegExp(r'USDT$'), '');
      final event = newsFeed.events
          .where(
            (e) =>
                e.importance == NewsImportance.critical &&
                e.verificationStatus ==
                    NewsVerificationStatus.primarySourceConfirmed &&
                e.publishedAt.isAfter(created) &&
                !e.publishedAt.isAfter(DateTime.now().toUtc()) &&
                (e.scope != NewsScope.assetSpecific ||
                    e.directAssets.contains(asset)),
          )
          .firstOrNull;
      if (event != null) {
        trading.cancel(appL10n.majorEventCancel(event.headline));
      }
    }
  }

  void _clearPlan() {
    trading.clear();
    _plan = _chartPlan = null;
    _showWaitZone = false;
  }

  void _onMarketChanged() {
    if (newsFeed.symbol != market.activeSymbol) {
      _clearPlan();
      newsFeed.selectSymbol(market.activeSymbol);
      unawaited(settingsStore.saveLastViewedSymbol(market.activeSymbol));
    }
    if (market.candles.isNotEmpty &&
        trading.plan?.symbol == market.activeSymbol) {
      trading.observe(market.candles.last.close);
    }
    _notify();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _agentUi.removeListener(_notify);
    _agentUi.dispose();
    trading.removeListener(_notify);
    trading.dispose();
    market.removeListener(_onMarketChanged);
    market.dispose();
    newsFeed.removeListener(_onNewsChanged);
    newsFeed.dispose();
    super.dispose();
  }

  Future<List<LlmModelInfo>> loadLlmModels(CancelToken cancel) =>
      fetchLlmModels(_llm, keys: _keyStore, cancelToken: cancel);

  Future<void> selectLlmReasoningEffort(String? effort) =>
      selectLlmModel(_llm.model, reasoningEffort: effort);

  // Keep the saved effort across model changes unless a new one is chosen.
  Future<void> selectLlmModel(String model, {String? reasoningEffort}) async {
    reasoningEffort ??= _llm.reasoningEffort;
    if (loadingAgent ||
        (model == _llm.model && reasoningEffort == _llm.reasoningEffort)) {
      return;
    }
    final selected = LlmSettings(
      id: _llm.id,
      name: _llm.name,
      provider: _llm.provider,
      endpoint: _llm.endpoint,
      model: model,
      reasoningEffort: reasoningEffort,
    );
    final connections = LlmConnectionSettings(
      connections: [
        for (final item in _llmConnections.connections)
          item.id == selected.id ? selected : item,
      ],
      activeConnectionId: selected.id,
    );
    await settingsStore.saveConnections(connections);
    if (_isDisposed) return;
    _llmConnections = connections;
    _llm = selected;
    _notify();
  }

  // Persist existing connection settings without changing credential storage.
  Future<void> saveSettings(
    LlmConnectionSettings llmConnections,
    McpSettings mcp,
    ApiSettings api,
    ApiKeyUpdates apiKeys,
  ) async {
    await Future.wait([
      settingsStore.saveConnections(llmConnections),
      settingsStore.saveMcp(mcp),
      settingsStore.saveApi(api),
    ]);
    await _keyStore.update(apiKeys);
    final status = await _keyStore.status(
      llmConnectionIds: llmConnections.connections.map((item) => item.id),
    );
    if (_isDisposed) return;
    _llmConnections = llmConnections;
    _llm = llmConnections.active;
    _mcp = mcp;
    _api = api;
    _apiKeyStatus = status;
    _notify();
  }

  Future<void> saveNewsSettings(
    NewsSettings settings,
    ApiKeyUpdates apiKeys,
  ) async {
    await Future.wait([
      settingsStore.saveNews(settings),
      _keyStore.update(apiKeys),
    ]);
    final status = await _keyStore.status(
      llmConnectionIds: _llmConnections.connections.map((item) => item.id),
    );
    if (_isDisposed) return;
    newsFeed.settings = settings;
    _apiKeyStatus = status;
    _notify();
    newsFeed.refresh();
  }

  Future<void> _loadApiKeyStatus() async {
    final status = await _keyStore.status(
      llmConnectionIds: _llmConnections.connections.map((item) => item.id),
    );
    if (_isDisposed) return;
    _apiKeyStatus = status;
    _notify();
  }
}
