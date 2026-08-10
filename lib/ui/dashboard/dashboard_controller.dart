import 'dart:async';

import 'package:dio/dio.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../../models/market_snapshot.dart';
import '../../models/news_event.dart';
import '../../models/trading_models.dart';
import '../../services/agent_service.dart';
import '../../services/analysis/feature_engine.dart';
import '../../services/analysis/market_snapshot_service.dart';
import '../../services/analysis/trade_plan_validator.dart';
import '../../services/bybit_service.dart';
import '../../services/llm_settings_store.dart';
import '../../services/secure_key_store.dart';
import '../../services/news/event_selector.dart';
import '../../services/news/news_service.dart';
import '../../utils/network.dart';

enum DashboardMessageKind { user, agent, activity }

class DashboardMessage {
  const DashboardMessage.user(this.text) : kind = DashboardMessageKind.user;
  const DashboardMessage.agent(this.text) : kind = DashboardMessageKind.agent;
  const DashboardMessage.activity(this.text)
    : kind = DashboardMessageKind.activity;

  final String text;
  final DashboardMessageKind kind;

  bool get isUser => kind == DashboardMessageKind.user;
  bool get isActivity => kind == DashboardMessageKind.activity;
}

/// Owns Dashboard data, asynchronous work, and resources independently of layout.
class DashboardController extends ChangeNotifier {
  DashboardController({
    required bool nodeAvailable,
    BybitService? bybit,
    LlmConnectionSettings? initialLlmConnections,
    McpSettings? initialMcp,
    ApiSettings? initialApi,
    NewsSettings? initialNews,
    String? initialSymbol,
  }) : _bybit = bybit ?? BybitService() {
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
      _mcp = const McpSettings(
        useBybit: false,
        useNansen: false,
        useOpenWebSearch: false,
      );
    }
    _conversationScrollController.addListener(_handleConversationScroll);
  }

  static const _historyLimit = 1000;
  static const _conversationBottomThreshold = 24.0;

  final BybitService _bybit;
  final _agent = AgentService();
  final _featureEngine = const FeatureEngine();
  final _tradePlanValidator = const TradePlanValidator();
  final _newsService = NewsService();
  final _eventSelector = const EventSelector();
  final _keyStore = SecureKeyStore();
  final _llmSettingsStore = LlmSettingsStore();
  final _symbol = TextEditingController(text: 'BTCUSDT');
  final _prompt = TextEditingController();
  final _conversationScrollController = ScrollController();
  final _conversation = <DashboardMessage>[];
  late final MarketSnapshotService _marketSnapshots = MarketSnapshotService(
    _bybit,
  );
  Timer? _chartRefreshTimer;
  Timer? _newsRefreshTimer;
  CancelToken? _symbolListCancelToken;
  CancelToken? _chartCancelToken;
  CancelToken? _macroNewsCancelToken;
  CancelToken? _tokenNewsCancelToken;
  var _newsRefreshesInFlight = 0;
  var _activeSymbol = 'BTCUSDT';
  var _interval = '15';
  var _candles = <Candle>[];
  var _symbols = <String>[];
  var _newsEvents = <NewsEvent>[];
  TradePlan? _plan;
  TradePlan? _chartPlan;
  bool _showWaitZone = false;
  String? _lastAnalysisContext;
  DateTime? _lastAnalysisAt;
  String? _conversationContext;
  String? _chartError;
  var _chartVersion = 0;
  var _chartLoadGeneration = 0;
  int? _loadingChartGeneration;
  bool _showChartLoading = false;
  bool _loadingAgent = false;
  AgentMode _agentMode = AgentMode.analysis;
  bool _conversationWasAtBottom = true;
  bool _showScrollToBottom = false;
  bool _isDisposed = false;
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

  TextEditingController get symbolController => _symbol;
  TextEditingController get promptController => _prompt;
  ScrollController get conversationScrollController =>
      _conversationScrollController;
  String get activeSymbol => _activeSymbol;
  String get interval => _interval;
  List<Candle> get candles => _candles;
  List<String> get symbols => _symbols;
  List<NewsEvent> get newsEvents => _newsEvents;
  Map<String, NewsProviderStatus> get newsProviderStatuses =>
      _newsService.statuses;
  TradePlan? get plan => _plan;
  TradePlan? get chartPlan => _chartPlan;
  bool get showWaitZone => _showWaitZone;
  List<DashboardMessage> get conversation => _conversation;
  String? get chartError => _chartError;
  int get chartVersion => _chartVersion;
  bool get loadingChart => _loadingChartGeneration == _chartLoadGeneration;
  bool get showChartLoading => _showChartLoading;
  bool get loadingAgent => _loadingAgent;
  AgentMode get agentMode => _agentMode;
  bool get showScrollToBottom => _showScrollToBottom;
  ApiKeyStatus get apiKeyStatus => _apiKeyStatus;
  LlmSettings get llm => _llm;
  LlmConnectionSettings get llmConnections => _llmConnections;
  McpSettings get mcp => _mcp;
  ApiSettings get api => _api;
  NewsSettings get news => _news;
  bool get refreshingNews => _newsRefreshesInFlight > 0;

  void initialize() {
    unawaited(_loadApiKeyStatus());
    unawaited(_loadSymbols());
    unawaited(_loadCachedNews());
    _startChartRefresh();
    _startNewsRefresh();
  }

  // Poll public Kline data once per second without allowing overlapping requests.
  void _startChartRefresh({bool loadImmediately = true}) {
    _chartRefreshTimer?.cancel();
    if (loadImmediately) unawaited(_loadChart());
    _chartRefreshTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_loadChart(latestOnly: true)),
    );
  }

  // News polls independently, so a feed outage cannot interrupt chart polling.
  void _startNewsRefresh() {
    _newsRefreshTimer?.cancel();
    _refreshAllNews();
    _newsRefreshTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _refreshAllNews(),
    );
  }

  // Check all sources every minute; each provider keeps its own cache interval.
  void _refreshAllNews() {
    unawaited(_refreshNews());
    unawaited(_refreshTokenNews(_activeSymbol));
  }

  Future<void> _loadCachedNews() async {
    final events = await _newsService.readCached();
    if (_isDisposed) return;
    _newsEvents = events;
    _notify();
  }

  Future<void> _refreshNews() async {
    if (_isDisposed) return;
    _cancelRequest(_macroNewsCancelToken);
    final cancelToken = _macroNewsCancelToken = CancelToken();
    try {
      final events = await _newsService.refresh(
        settings: _news,
        finnhubApiKey: await _keyStore.readFinnhubKey(),
        onRefreshChanged: _handleNewsRefreshState,
        cancelToken: cancelToken,
      );
      if (_isDisposed) return;
      _newsEvents = events;
      _notify();
    } catch (error) {
      if (isRequestCancelled(error)) return;
      // Per-provider failures are represented by NewsService status entries.
    } finally {
      if (identical(_macroNewsCancelToken, cancelToken)) {
        _macroNewsCancelToken = null;
      }
    }
  }

  Future<void> _refreshTokenNews(String symbol) async {
    if (_isDisposed) return;
    _cancelRequest(_tokenNewsCancelToken);
    final cancelToken = _tokenNewsCancelToken = CancelToken();
    try {
      final events = await _newsService.refreshTokenNews(
        symbol: symbol,
        settings: _news,
        marketauxApiKey: await _keyStore.readMarketauxKey(),
        onRefreshChanged: _handleNewsRefreshState,
        cancelToken: cancelToken,
      );
      if (_isDisposed) return;
      _newsEvents = events;
      _notify();
    } catch (error) {
      if (isRequestCancelled(error)) return;
      // Marketaux failures stay isolated from chart and Agent work.
    } finally {
      if (identical(_tokenNewsCancelToken, cancelToken)) {
        _tokenNewsCancelToken = null;
      }
    }
  }

  void _handleNewsRefreshState(bool refreshing) {
    if (_isDisposed) return;
    _newsRefreshesInFlight += refreshing ? 1 : -1;
    _notify();
  }

  Future<void> _loadSymbols() async {
    final cancelToken = _symbolListCancelToken = CancelToken();
    try {
      final symbols = await _bybit.fetchLinearSymbols(cancelToken: cancelToken);
      if (_isDisposed) return;
      _symbols = symbols;
      _notify();
    } catch (error) {
      if (isRequestCancelled(error)) return;
      // Kline polling still works when the optional symbol list cannot load.
    } finally {
      if (identical(_symbolListCancelToken, cancelToken)) {
        _symbolListCancelToken = null;
      }
    }
  }

  Future<void> _loadChart({bool latestOnly = false}) async {
    if (_isDisposed) return;
    final generation = _chartLoadGeneration;
    if (_loadingChartGeneration == generation) return;
    final symbol = _activeSymbol;
    final interval = _interval;
    final hasCandles = _candles.isNotEmpty;
    final fullLoad = !latestOnly || !hasCandles;
    final cancelToken = _chartCancelToken = CancelToken();
    _loadingChartGeneration = generation;
    if (fullLoad) _showChartLoading = true;
    _notify();
    try {
      final candles = await _bybit.fetchKlines(
        symbol: symbol,
        interval: interval,
        limit: fullLoad ? _historyLimit : 2,
        cancelToken: cancelToken,
      );
      // A stale request must never update a newer chart selection.
      if (_isDisposed ||
          generation != _chartLoadGeneration ||
          symbol != _activeSymbol ||
          interval != _interval) {
        return;
      }
      _candles = fullLoad ? candles : _mergeLatestCandles(_candles, candles);
      _chartError = null;
      if (fullLoad) {
        _showChartLoading = false;
        _chartVersion++;
      }
      _notify();
    } catch (error) {
      if (isRequestCancelled(error)) return;
      if (_isDisposed ||
          generation != _chartLoadGeneration ||
          symbol != _activeSymbol ||
          interval != _interval) {
        return;
      }
      _chartRefreshTimer?.cancel();
      _chartError = 'K 线加载失败：$error';
      _showChartLoading = false;
      _notify();
    } finally {
      if (identical(_chartCancelToken, cancelToken)) {
        _chartCancelToken = null;
      }
      if (!_isDisposed && _loadingChartGeneration == generation) {
        _loadingChartGeneration = null;
        _notify();
      }
    }
  }

  // Preserve the 1000-candle viewport while replacing the still-forming candle.
  List<Candle> _mergeLatestCandles(List<Candle> history, List<Candle> latest) {
    final byTime = <int, Candle>{
      for (final candle in history) candle.time.millisecondsSinceEpoch: candle,
      for (final candle in latest) candle.time.millisecondsSinceEpoch: candle,
    };
    final merged = byTime.values.toList()
      ..sort((left, right) => left.time.compareTo(right.time));
    return merged.length > _historyLimit
        ? merged.sublist(merged.length - _historyLimit)
        : merged;
  }

  void retryChart() {
    if (loadingChart) return;
    _chartError = null;
    _showChartLoading = true;
    _notify();
    _startChartRefresh();
  }

  void selectSymbol(String symbol) {
    final normalized = symbol.toUpperCase();
    if (normalized == _activeSymbol) return;
    _activeSymbol = normalized;
    _symbol.text = _activeSymbol;
    _beginChartTransition();
    _notify();
    _startChartRefresh();
    unawaited(_llmSettingsStore.saveLastViewedSymbol(_activeSymbol));
    unawaited(_refreshTokenNews(_activeSymbol));
  }

  void selectInterval(String interval) {
    if (interval == _interval) return;
    _interval = interval;
    _beginChartTransition();
    _notify();
    _startChartRefresh();
  }

  // Invalidate in-flight requests and remove candles from the previous view.
  void _beginChartTransition() {
    _cancelRequest(_chartCancelToken);
    _chartCancelToken = null;
    _chartLoadGeneration++;
    _candles = const [];
    _plan = null;
    _chartPlan = null;
    _showWaitZone = false;
    _chartError = null;
    _showChartLoading = true;
  }

  Future<String> _resolveAnalysisSymbol(String prompt) async {
    if (_symbols.isEmpty) await _loadSymbols();
    return _requestedSymbol(prompt) ?? _activeSymbol;
  }

  Future<List<Candle>> _prepareAnalysisChart(String symbol) async {
    if (symbol == _activeSymbol && _candles.isNotEmpty) return _candles;
    _chartRefreshTimer?.cancel();
    _recordActivity('• Chart - 加载 $symbol');
    _activeSymbol = symbol;
    _symbol.text = symbol;
    unawaited(_llmSettingsStore.saveLastViewedSymbol(symbol));
    _beginChartTransition();
    final generation = _chartLoadGeneration;
    _loadingChartGeneration = generation;
    _notify();
    try {
      final candles = await _bybit.fetchKlines(
        symbol: symbol,
        interval: _interval,
        limit: _historyLimit,
      );
      if (_isDisposed ||
          generation != _chartLoadGeneration ||
          _activeSymbol != symbol) {
        return candles;
      }
      _candles = candles;
      _showChartLoading = false;
      _chartVersion++;
      _notify();
      _startChartRefresh(loadImmediately: false);
      return candles;
    } catch (error) {
      if (!_isDisposed &&
          generation == _chartLoadGeneration &&
          _activeSymbol == symbol) {
        _chartError = 'K 线加载失败：$error';
        _showChartLoading = false;
        _notify();
      }
      throw Exception('无法加载 $symbol 的 K 线：$error');
    } finally {
      if (!_isDisposed && _loadingChartGeneration == generation) {
        _loadingChartGeneration = null;
        _notify();
      }
    }
  }

  String? _requestedSymbol(String prompt) {
    if (_symbols.isEmpty) return null;
    final candidates = <String>{};
    final normalized = prompt.toUpperCase();
    void addCandidate(String value) {
      final symbol = value.endsWith('USDT') ? value : '${value}USDT';
      if (_symbols.contains(symbol)) candidates.add(symbol);
    }

    for (final match in RegExp(
      r'\b([A-Z0-9]{2,20})\s*(?:[/_-]\s*)?USDT\b',
    ).allMatches(normalized)) {
      addCandidate(match.group(1)!);
    }
    for (final match in RegExp(
      r'\b([A-Z0-9]{2,20})\b',
    ).allMatches(normalized)) {
      addCandidate(match.group(1)!);
    }
    return candidates.length == 1 ? candidates.single : null;
  }

  Future<void> runAgent() async {
    if (_loadingAgent || _isDisposed) return;
    final hasLlmCredentials = _llm.provider == LlmProvider.openAiCodex
        ? _apiKeyStatus.hasCodexOAuth
        : _apiKeyStatus.hasLlmKeyFor(_llm.id);
    if (!_llm.isComplete || !hasLlmCredentials) {
      _conversation.add(
        DashboardMessage.agent(
          _llm.provider == LlmProvider.openAiCodex
              ? '> 请先在设置中登录 OpenAI Codex 并选择模型。'
              : '> 请先在设置中填写 LLM Endpoint、Model 并保存 API Key。',
        ),
      );
      _notify();
      _scheduleConversationScroll();
      return;
    }
    final prompt = _prompt.text.trim();
    final mode = _agentMode;
    final previousConversationContext = _conversationContext;
    _loadingAgent = true;
    _conversation.add(DashboardMessage.user(prompt));
    _conversation.add(
      DashboardMessage.activity(
        mode == AgentMode.analysis ? '• Thinking - 分析中…' : '• Thinking - 回答中…',
      ),
    );
    _prompt.clear();
    _notify();
    _scheduleConversationScroll();
    try {
      final analysisSymbol = mode == AgentMode.analysis
          ? await _resolveAnalysisSymbol(prompt)
          : _activeSymbol;
      final analysisCandles = mode == AgentMode.analysis
          ? await _prepareAnalysisChart(analysisSymbol)
          : const <Candle>[];
      if (_isDisposed) return;
      if (mode == AgentMode.analysis && analysisCandles.isEmpty) {
        throw Exception('$analysisSymbol 没有可分析的 K 线。');
      }
      final marketSnapshot = mode == AgentMode.analysis
          ? await _buildMarketSnapshot(analysisSymbol)
          : null;
      final marketFeatures = marketSnapshot == null
          ? null
          : _featureEngine.calculate(marketSnapshot);
      if (marketFeatures != null) {
        _recordActivity('• Deterministic Engine - 指标计算完成');
      }
      if (mode == AgentMode.analysis) {
        await _refreshTokenNews(analysisSymbol);
      }
      final eventSnapshot = mode == AgentMode.analysis
          ? await _eventSnapshot(analysisSymbol, marketFeatures!)
          : null;
      final answer = await _agent.run(
        prompt: prompt,
        symbol: analysisSymbol,
        candles: analysisCandles,
        llm: _llm,
        mcp: _mcp,
        api: _api,
        mode: mode,
        marketSnapshot: marketSnapshot,
        marketFeatures: marketFeatures,
        eventSnapshot: eventSnapshot,
        previousAnalysisContext: _lastAnalysisContext,
        previousAnalysisAt: _lastAnalysisAt,
        previousConversationContext: previousConversationContext,
        onActivity: _recordActivity,
      );
      if (_isDisposed) return;
      if (mode == AgentMode.analysis) {
        final plan = TradePlan.fromResponse(answer.text);
        final notices = [...answer.warnings];
        final validation = plan == null
            ? null
            : _tradePlanValidator.validate(
                plan,
                tickSize: marketSnapshot?.instrument.tickSize,
              );
        final matchesResponse =
            plan?.symbol == null || plan!.symbol == analysisSymbol;
        final matchesChart = _activeSymbol == analysisSymbol;
        if (plan == null) {
          notices.add('结果中没有可解析的 TradePlan JSON，未添加图表标记。');
        } else {
          notices.addAll(validation!.warnings);
          if (!validation.isValid) {
            notices.add(
              'TradePlan 校验失败：${validation.errors.join('；')}，未添加图表标记。',
            );
          } else if (!plan.isSetup) {
            notices.add(
              validation.canDrawWaitZone
                  ? 'WAIT 不是交易 Setup，仅显示候选等待区。'
                  : '${plan.decision} 不是交易 Setup，未添加图表标记。',
            );
          }
        }
        if (!matchesResponse) {
          notices.add('结果 JSON 的币种与分析币种 $analysisSymbol 不一致，未添加图表标记。');
        }
        if (!matchesChart) {
          notices.add('当前图表已切换为 $_activeSymbol，未添加 $analysisSymbol 的图表标记。');
        }
        final displayText = notices.isEmpty
            ? answer.text
            : '${answer.text}\n\n> 数据源提示：${notices.join(' | ')}';
        _conversation.add(DashboardMessage.agent(displayText));
        final canDisplayPlan =
            plan != null &&
            validation!.isValid &&
            matchesResponse &&
            matchesChart;
        _chartPlan = canDisplayPlan ? plan : null;
        _plan = canDisplayPlan && plan.isSetup ? plan : null;
        _showWaitZone = canDisplayPlan && validation.canDrawWaitZone;
        _lastAnalysisContext =
            'User analysis request: $prompt\n\nAnalysis response:\n$displayText';
        _lastAnalysisAt = DateTime.now();
      } else {
        _conversation.add(DashboardMessage.agent(answer.text));
        final turn = 'User: $prompt\nAgent: ${answer.text}';
        _conversationContext = _conversationContext == null
            ? turn
            : '$_conversationContext\n\n$turn';
      }
      _notify();
      _scheduleConversationScroll();
    } catch (error) {
      if (_isDisposed) return;
      _conversation.add(DashboardMessage.agent('> Agent 请求失败：$error'));
      _notify();
      _scheduleConversationScroll();
    } finally {
      if (!_isDisposed) {
        _loadingAgent = false;
        _notify();
      }
    }
  }

  Future<MarketSnapshot> _buildMarketSnapshot(String symbol) async {
    _recordActivity('• Market Snapshot - 获取固定多周期行情');
    final snapshot = await _marketSnapshots.build(symbol);
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
    final needsCoverageFallback =
        snapshot.assetSpecificEvents.isEmpty || features.hasAbnormalShortTerm;
    return EventSnapshot(
      snapshotAsOf: snapshot.snapshotAsOf,
      upcomingCriticalEvents: snapshot.upcomingCriticalEvents,
      breakingEvents: snapshot.breakingEvents,
      assetSpecificEvents: snapshot.assetSpecificEvents,
      cryptoMarketEvents: snapshot.cryptoMarketEvents,
      macroEvents: snapshot.macroEvents,
      tokenNewsSearchQueries: needsCoverageFallback
          ? await _newsService.tokenNewsSearchQueries(symbol)
          : const [],
    );
  }

  void quickAnalyze({
    required String analysisPlan,
    required String tradeWindow,
    required String accountBalance,
    required String maxLoss,
    required String plannedPosition,
    required String currentPosition,
    required String currentPositionSize,
    required String currentPositionEntryPrice,
  }) {
    _agentMode = AgentMode.analysis;
    final hasPosition = currentPosition.trim() != '无';
    final aggressiveInstruction = analysisPlan == '激进'
        ? '''激进方案要求：不得输出 NO_TRADE 或 WAIT；必须在 LONG 和 SHORT 中选择一个方向，并给出可执行的入场、止损和止盈方案。若条件不足，选择风险更低的一侧，降低仓位并收紧止损。

'''
        : '';
    // Build and send the analysis request from the confirmed dialog values.
    _prompt.text =
        '''请分析 $_activeSymbol 的短线开仓机会。本次交易需在${_quickAnalysisValue(tradeWindow, '填写交易完成时限')}内完成。

账户资金：${_quickAnalysisValue(accountBalance, '填写 USDT')}
单笔最大可接受亏损：${_quickAnalysisValue(maxLoss, '填写 USDT 或 %')}
计划开仓数量：${_quickAnalysisValue(plannedPosition, '填写币数量或 USDT 名义价值')}
当前持仓：${_quickAnalysisValue(currentPosition, '无 / 多 / 空')}
当前持仓数量：${hasPosition ? _quickAnalysisValue(currentPositionSize, '无则填 0') : '0'}
当前持仓均价：${hasPosition ? _quickAnalysisValue(currentPositionEntryPrice, '无则填 0') : '0'}

请同时评估 LONG 和 SHORT，并给出当前更优的开仓方向、等待入场区、入场触发条件、最大追价位置、止损位置、分批止盈位置以及风险收益比。

$aggressiveInstruction如果我填写的计划仓位超过上述单笔风险限制，请根据止损距离给出更合理的最大仓位建议。
''';
    _notify();
    unawaited(runAgent());
  }

  String _quickAnalysisValue(String value, String placeholder) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? '{$placeholder}' : trimmed;
  }

  void selectAgentMode(AgentMode mode) {
    if (_loadingAgent) return;
    _agentMode = mode;
    _notify();
  }

  void _recordActivity(String activity) {
    if (_isDisposed) return;
    _conversation.add(DashboardMessage.activity(activity));
    _notify();
    _scheduleConversationScroll();
  }

  // Show a quick return control whenever the reader leaves the conversation end.
  void _handleConversationScroll() {
    if (_isDisposed || !_conversationScrollController.hasClients) return;
    final position = _conversationScrollController.position;
    final isAtBottom =
        position.maxScrollExtent - position.pixels <=
        _conversationBottomThreshold;
    _conversationWasAtBottom = isAtBottom;
    final shouldShowButton = !isAtBottom && _conversation.isNotEmpty;
    if (shouldShowButton == _showScrollToBottom) return;
    _showScrollToBottom = shouldShowButton;
    _notify();
  }

  void _scheduleConversationScroll() {
    final shouldFollow = _conversationWasAtBottom;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isDisposed || !_conversationScrollController.hasClients) return;
      if (shouldFollow) {
        unawaited(
          _conversationScrollController.animateTo(
            _conversationScrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
          ),
        );
      } else if (!_showScrollToBottom && _conversation.isNotEmpty) {
        _showScrollToBottom = true;
        _notify();
      }
    });
  }

  void scrollConversationToBottom() {
    if (!_conversationScrollController.hasClients) return;
    unawaited(
      _conversationScrollController.animateTo(
        _conversationScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      ),
    );
  }

  void clearAgentContext() {
    if (_loadingAgent) return;
    _conversation.clear();
    _plan = null;
    _chartPlan = null;
    _showWaitZone = false;
    _lastAnalysisContext = null;
    _lastAnalysisAt = null;
    _conversationContext = null;
    _prompt.clear();
    _conversationWasAtBottom = true;
    _showScrollToBottom = false;
    // Rebuild the chart so its hover and floating plan widgets reset too.
    _chartVersion++;
    _notify();
  }

  Future<void> saveSettings(
    LlmConnectionSettings llmConnections,
    McpSettings mcp,
    ApiSettings api,
    ApiKeyUpdates apiKeys,
  ) async {
    await Future.wait([
      _llmSettingsStore.saveConnections(llmConnections),
      _llmSettingsStore.saveMcp(mcp),
      _llmSettingsStore.saveApi(api),
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
      _llmSettingsStore.saveNews(settings),
      _keyStore.update(apiKeys),
    ]);
    final status = await _keyStore.status(
      llmConnectionIds: _llmConnections.connections.map((item) => item.id),
    );
    if (_isDisposed) return;
    _news = settings;
    _apiKeyStatus = status;
    _notify();
    unawaited(_refreshNews());
    unawaited(_refreshTokenNews(_activeSymbol));
  }

  Future<void> _loadApiKeyStatus() async {
    final status = await _keyStore.status(
      llmConnectionIds: _llmConnections.connections.map((item) => item.id),
    );
    if (_isDisposed) return;
    _apiKeyStatus = status;
    _notify();
  }

  void _notify() {
    if (!_isDisposed) notifyListeners();
  }

  // Cancel superseded Dio work before its result becomes stale or the page closes.
  void _cancelRequest(CancelToken? token) {
    if (token != null && !token.isCancelled) token.cancel();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _chartRefreshTimer?.cancel();
    _newsRefreshTimer?.cancel();
    _cancelRequest(_symbolListCancelToken);
    _cancelRequest(_chartCancelToken);
    _cancelRequest(_macroNewsCancelToken);
    _cancelRequest(_tokenNewsCancelToken);
    _bybit.dispose();
    _agent.dispose();
    _newsService.dispose();
    _symbol.dispose();
    _prompt.dispose();
    _conversationScrollController
      ..removeListener(_handleConversationScroll)
      ..dispose();
    super.dispose();
  }
}
