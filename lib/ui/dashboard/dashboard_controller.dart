import 'dart:async';

import 'package:dio/dio.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../../models/market_snapshot.dart';
import '../../models/news_event.dart';
import '../../models/trading_models.dart';
import '../../services/agent_service.dart';
import '../../services/analysis/feature_engine.dart';
import '../../services/analysis/trading_session.dart';
import '../../services/analysis/market_snapshot_service.dart';
import '../../services/analysis/trade_plan_validator.dart';
import '../../services/bybit_service.dart';
import '../../services/llm_settings_store.dart';
import '../../services/secure_key_store.dart';
import '../../services/news/event_selector.dart';
import '../../services/news/news_service.dart';
import '../../utils/network.dart';
import '../chart/candle_series.dart';
import 'dashboard_agent.dart';

export 'dashboard_agent.dart' show DashboardMessage, DashboardMessageKind;

// Keep shared private state in one library, with behavior grouped by purpose.
part 'dashboard_analysis.dart';
part 'dashboard_chart.dart';
part 'dashboard_news.dart';
part 'dashboard_settings.dart';

// Own dashboard state and resource lifetime independently of the page layout.
class DashboardController extends ChangeNotifier {
  DashboardController({
    required bool nodeAvailable,
    BybitService? bybit,
    AgentService? agent,
    NewsService? newsService,
    SecureKeyStore? keyStore,
    LlmSettingsStore? llmSettingsStore,
    LlmConnectionSettings? initialLlmConnections,
    McpSettings? initialMcp,
    ApiSettings? initialApi,
    NewsSettings? initialNews,
    String? initialSymbol,
  }) : _bybit = bybit ?? BybitService(),
       _ownsBybit = bybit == null,
       _ownsAgent = agent == null,
       _ownsNews = newsService == null {
    _agent = agent ?? AgentService();
    _newsService = newsService ?? NewsService();
    _keyStore = keyStore ?? SecureKeyStore();
    _llmSettingsStore = llmSettingsStore ?? LlmSettingsStore();
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
    if (initialNews != null) _news = initialNews;
    if (initialSymbol?.trim().isNotEmpty ?? false) {
      _activeSymbol = initialSymbol!.trim().toUpperCase();
      _symbol.text = _activeSymbol;
    }
    if (!nodeAvailable) {
      _mcp = McpSettings(
        useBybit: false,
        useNansen: _mcp.useNansen,
        useOpenWebSearch: false,
      );
    }
    _agentUi.addListener(_notify);
    trading.addListener(_notify);
  }

  late final trading = TradingSession(_bybit);

  // Store existing services, UI state, and independent request cancellation.
  final BybitService _bybit;
  final bool _ownsBybit;
  final bool _ownsAgent;
  final bool _ownsNews;
  final _agentUi = AgentConversationController();
  late final AgentService _agent;
  final _featureEngine = const FeatureEngine();
  final _tradePlanValidator = const TradePlanValidator();
  late final NewsService _newsService;
  final _eventSelector = const EventSelector();
  late final SecureKeyStore _keyStore;
  late final LlmSettingsStore _llmSettingsStore;
  final _symbol = TextEditingController(text: 'BTCUSDT');
  late final MarketSnapshotService _marketSnapshots = MarketSnapshotService(
    _bybit,
  );
  Timer? _chartRefreshTimer;
  Timer? _newsRefreshTimer;
  CancelToken? _symbolListCancelToken;
  CancelToken? _chartCancelToken;
  CancelToken? _historyCancelToken;
  CancelToken? _macroNewsCancelToken;
  CancelToken? _tokenNewsCancelToken;
  var _newsRefreshesInFlight = 0;
  final _newsNotifier = ChangeNotifier();
  int _newsRevision = 0;
  var _activeSymbol = 'BTCUSDT';
  var _interval = '15';
  final _candleSeries = CandleSeries();
  var _symbols = <String>[];
  var _newsEvents = <NewsEvent>[];
  TradePlan? _plan;
  TradePlan? _chartPlan;
  bool _showWaitZone = false;
  String? _chartError;
  String? _historyError;
  var _chartVersion = 0;
  var _chartLoadGeneration = 0;
  int? _loadingChartGeneration;
  bool _showChartLoading = false;
  bool _isDisposed = false;
  bool _loadingOlder = false;
  bool _hasMoreHistory = true;
  ApiKeyStatus _apiKeyStatus = const ApiKeyStatus();
  late LlmSettings _llm;
  late LlmConnectionSettings _llmConnections;
  McpSettings _mcp = const McpSettings(
    useBybit: true,
    useNansen: false,
    useOpenWebSearch: true,
  );
  ApiSettings _api = const ApiSettings(useCoinalyze: false);
  NewsSettings _news = const NewsSettings(
    useFinnhub: false,
    useMarketaux: false,
    useBls: true,
    useBea: true,
    useFederalReserve: true,
  );

  // Expose the same page-facing state as before the streaming migration.
  TextEditingController get symbolController => _symbol;
  TextEditingController get promptController => _agentUi.prompt;
  ScrollController get conversationScrollController => _agentUi.scroll;
  String get activeSymbol => _activeSymbol;
  String get interval => _interval;
  List<Candle> get candles => _candleSeries.items;
  int get totalPrependedCandles => _candleSeries.totalPrepended;
  List<String> get symbols => _symbols;
  List<NewsEvent> get newsEvents => _newsEvents;
  Listenable get newsListenable => _newsNotifier;
  Map<String, NewsProviderStatus> get newsProviderStatuses =>
      _newsService.statuses;
  TradePlan? get plan => _plan;
  TradePlan? get chartPlan =>
      trading.assessment?.terminal == true ? null : _chartPlan;
  bool get showWaitZone => _showWaitZone;
  List<DashboardMessage> get conversation => _agentUi.messages;
  String? get chartError => _chartError;
  String? get historyError => _historyError;
  int get chartVersion => _chartVersion;
  bool get loadingChart => _loadingChartGeneration == _chartLoadGeneration;
  bool get showChartLoading => _showChartLoading;
  bool get loadingAgent => _agentUi.loading;
  bool get loadingMore => _loadingOlder;
  bool get hasMoreHistory => _candleSeries.isNotEmpty && _hasMoreHistory;
  bool get showScrollToBottom => _agentUi.showScrollToBottom;
  ApiKeyStatus get apiKeyStatus => _apiKeyStatus;
  LlmSettings get llm => _llm;
  LlmConnectionSettings get llmConnections => _llmConnections;
  McpSettings get mcp => _mcp;
  ApiSettings get api => _api;
  NewsSettings get news => _news;
  bool get refreshingNews => _newsRefreshesInFlight > 0;

  // Delegate conversation controls to the object that owns their state.
  void stopAgent() {
    _agentUi.stop();
    trading.clear();
    _plan = null;
    _chartPlan = null;
    _notify();
  }

  void scrollConversationToBottom() => _agentUi.scrollToBottom();
  // Preserve instance-method APIs while private parts organize chart preparation.
  Future<void> runAgent() => _runAgent();
  Future<void> loadMoreHistory() => _loadMoreHistory();
  void retryChart() => _retryChart();
  void selectSymbol(String symbol) => _selectSymbol(symbol);
  void selectInterval(String interval) => _selectInterval(interval);
  void quickAnalyze() => _quickAnalyze();
  void _recordActivity(String activity) => _agentUi.recordActivity(activity);
  void clearAgentContext() {
    if (loadingAgent) return;
    _plan = null;
    _chartPlan = null;
    _showWaitZone = false;
    _chartVersion++;
    _agentUi.clear();
    trading.clear();
  }

  // Start independent background feeds without tying them to an Agent run.
  void initialize() {
    unawaited(_loadApiKeyStatus());
    unawaited(_loadSymbols());
    unawaited(_loadCachedNews());
    _startChartRefresh();
    _startNewsRefresh();
  }

  Future<void> saveSettings(
    LlmConnectionSettings connections,
    McpSettings mcp,
    ApiSettings api,
    ApiKeyUpdates keys,
  ) => _saveSettings(connections, mcp, api, keys);

  Future<void> saveNewsSettings(NewsSettings settings, ApiKeyUpdates keys) =>
      _saveNewsSettings(settings, keys);

  // Never notify listeners or apply cancelled requests after page disposal.
  void _notify() {
    if (!_isDisposed) notifyListeners();
  }

  // Keep protected ChangeNotifier calls inside the owning controller class.
  void _notifyNews() {
    if (!_isDisposed) _newsNotifier.notifyListeners();
  }

  void _cancelRequest(CancelToken? token) {
    if (token != null && !token.isCancelled) token.cancel();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _agentUi.removeListener(_notify);
    _agentUi.dispose();
    trading.removeListener(_notify);
    trading.dispose();
    _chartRefreshTimer?.cancel();
    _newsRefreshTimer?.cancel();
    _cancelRequest(_symbolListCancelToken);
    _cancelRequest(_chartCancelToken);
    _cancelRequest(_historyCancelToken);
    _cancelRequest(_macroNewsCancelToken);
    _cancelRequest(_tokenNewsCancelToken);
    if (_ownsBybit) _bybit.dispose();
    if (_ownsAgent) _agent.dispose();
    if (_ownsNews) _newsService.dispose();
    _symbol.dispose();
    _newsNotifier.dispose();
    super.dispose();
  }
}
