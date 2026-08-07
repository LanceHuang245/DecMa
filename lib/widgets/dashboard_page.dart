import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../models/trading_models.dart';
import '../services/agent_service.dart';
import '../services/bybit_service.dart';
import '../services/llm_settings_store.dart';
import '../services/node_runtime_service.dart';
import '../services/secure_key_store.dart';
import 'candle_chart.dart';
import 'settings_dialog.dart';
import 'window_title_bar.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
    required this.nodeAvailable,
    this.initialLlm,
    this.initialMcp,
    this.initialApi,
  });

  final bool nodeAvailable;
  final LlmSettings? initialLlm;
  final McpSettings? initialMcp;
  final ApiSettings? initialApi;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  static const _historyLimit = 1000;
  static const _conversationBottomThreshold = 24.0;
  final _bybit = BybitService();
  final _agent = AgentService();
  final _keyStore = SecureKeyStore();
  final _llmSettingsStore = LlmSettingsStore();
  final _symbol = TextEditingController(text: 'BTCUSDT');
  final _prompt = TextEditingController(text: '');
  // Track the visible chat viewport without interrupting a user reading history.
  final _conversationScrollController = ScrollController();
  Timer? _chartRefreshTimer;
  var _activeSymbol = 'BTCUSDT';
  var _interval = '15';
  var _candles = <Candle>[];
  var _symbols = <String>[];
  TradePlan? _plan;
  // Keep the chat transcript only for the active app session.
  final _conversation = <_ConversationMessage>[];
  String? _chartError;
  var _chartVersion = 0;
  bool _loadingChart = false;
  bool _showChartLoading = false;
  bool _loadingAgent = false;
  AgentMode _agentMode = AgentMode.analysis;
  bool _conversationWasAtBottom = true;
  bool _showScrollToBottom = false;
  ApiKeyStatus _apiKeyStatus = const ApiKeyStatus();
  late LlmSettings _llm;
  McpSettings _mcp = const McpSettings(
    useBybit: true,
    useNansen: false,
    useOpenWebSearch: true,
  );
  ApiSettings _api = const ApiSettings(useCoinalyze: false);

  @override
  void initState() {
    super.initState();
    _llm =
        widget.initialLlm ??
        LlmSettings(
          provider: LlmProvider.openAiResponses,
          endpoint: LlmProvider.openAiResponses.defaultEndpoint,
          model: 'gpt-4.1',
        );
    if (widget.initialMcp != null) _mcp = widget.initialMcp!;
    if (widget.initialApi != null) _api = widget.initialApi!;
    if (!widget.nodeAvailable) {
      _mcp = const McpSettings(
        useBybit: false,
        useNansen: false,
        useOpenWebSearch: false,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) => _showNodeMissing());
    }
    unawaited(_loadApiKeyStatus());
    unawaited(_loadSymbols());
    _conversationScrollController.addListener(_handleConversationScroll);
    _startChartRefresh();
  }

  @override
  void dispose() {
    _chartRefreshTimer?.cancel();
    _bybit.dispose();
    _agent.dispose();
    _symbol.dispose();
    _prompt.dispose();
    _conversationScrollController
      ..removeListener(_handleConversationScroll)
      ..dispose();
    super.dispose();
  }

  // Poll public Kline data once per second without allowing overlapping requests.
  void _startChartRefresh() {
    _chartRefreshTimer?.cancel();
    unawaited(_loadChart());
    _chartRefreshTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_loadChart(latestOnly: true)),
    );
  }

  Future<void> _loadSymbols() async {
    try {
      final symbols = await _bybit.fetchLinearSymbols();
      if (mounted) setState(() => _symbols = symbols);
    } catch (_) {
      // Kline polling still works when the optional symbol list cannot load.
    }
  }

  Future<void> _loadChart({bool latestOnly = false}) async {
    if (_loadingChart) return;
    final symbol = _activeSymbol;
    final interval = _interval;
    final hasCandles = _candles.isNotEmpty;
    setState(() {
      _loadingChart = true;
      if (!latestOnly) _showChartLoading = true;
    });
    try {
      final candles = await _bybit.fetchKlines(
        symbol: symbol,
        interval: interval,
        limit: latestOnly && hasCandles ? 2 : _historyLimit,
      );
      // Ignore a response for a symbol or timeframe the user has left behind.
      if (!mounted || symbol != _activeSymbol || interval != _interval) return;
      setState(() {
        _candles = latestOnly
            ? _mergeLatestCandles(hasCandles ? _candles : const [], candles)
            : candles;
        _chartError = null;
        if (!latestOnly) {
          _showChartLoading = false;
          _chartVersion++;
        }
      });
    } catch (error) {
      _chartRefreshTimer?.cancel();
      if (mounted) {
        setState(() {
          _chartError = 'K 线加载失败：$error';
          _showChartLoading = false;
        });
      }
    } finally {
      if (mounted) setState(() => _loadingChart = false);
    }
  }

  void _retryChart() {
    if (_loadingChart) return;
    setState(() => _chartError = null);
    _startChartRefresh();
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

  void _selectSymbol(String symbol) {
    setState(() {
      _activeSymbol = symbol.toUpperCase();
      _symbol.text = _activeSymbol;
      _plan = null;
      _chartError = null;
    });
    _startChartRefresh();
  }

  List<AutoSuggestBoxItem<String>> _sortSymbols(
    String text,
    List<AutoSuggestBoxItem<String>> items,
  ) {
    final query = text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (query.length < 2) return const [];
    final matches = items.where((item) {
      final symbol = item.value ?? '';
      return symbol.contains(query) || _isSubsequence(query, symbol);
    }).toList();
    matches.sort((left, right) {
      final leftSymbol = left.value ?? '';
      final rightSymbol = right.value ?? '';
      return _matchScore(
        query,
        leftSymbol,
      ).compareTo(_matchScore(query, rightSymbol));
    });
    return matches;
  }

  bool _isSubsequence(String query, String symbol) {
    var queryIndex = 0;
    for (final char in symbol.split('')) {
      if (queryIndex < query.length && char == query[queryIndex]) queryIndex++;
    }
    return queryIndex == query.length;
  }

  int _matchScore(String query, String symbol) => symbol.startsWith(query)
      ? 0
      : symbol.contains(query)
      ? 1
      : 2;

  Future<String> _resolveAnalysisSymbol(String prompt) async {
    if (_symbols.isEmpty) await _loadSymbols();
    return _requestedSymbol(prompt) ?? _activeSymbol;
  }

  // Switch and fetch before analysis so the chart snapshot matches the request.
  Future<List<Candle>> _prepareAnalysisChart(String symbol) async {
    if (symbol == _activeSymbol && _candles.isNotEmpty) return _candles;
    _chartRefreshTimer?.cancel();
    _recordActivity('• Chart - 加载 $symbol');
    setState(() {
      _activeSymbol = symbol;
      _symbol.text = symbol;
      _plan = null;
      _chartError = null;
      _showChartLoading = true;
    });
    try {
      final candles = await _bybit.fetchKlines(
        symbol: symbol,
        interval: _interval,
        limit: _historyLimit,
      );
      if (!mounted || _activeSymbol != symbol) return candles;
      setState(() {
        _candles = candles;
        _showChartLoading = false;
        _chartVersion++;
      });
      _startChartRefresh();
      return candles;
    } catch (error) {
      if (mounted && _activeSymbol == symbol) {
        setState(() {
          _chartError = 'K 线加载失败：$error';
          _showChartLoading = false;
        });
      }
      throw Exception('无法加载 $symbol 的 K 线：$error');
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

  Future<void> _runAgent() async {
    if (_loadingAgent) return;
    if (!_llm.isComplete || !_apiKeyStatus.hasLlmKey) {
      setState(
        () => _conversation.add(
          const _ConversationMessage.agent(
            '> 请先在设置中填写 LLM Endpoint、Model 并保存 API Key。',
          ),
        ),
      );
      _scheduleConversationScroll();
      return;
    }
    final prompt = _prompt.text.trim();
    final mode = _agentMode;
    setState(() {
      _loadingAgent = true;
      _conversation.add(_ConversationMessage.user(prompt));
      _conversation.add(
        _ConversationMessage.activity(
          mode == AgentMode.analysis
              ? '• Thinking - 分析中…'
              : '• Thinking - 回答中…',
        ),
      );
      _prompt.clear();
    });
    _scheduleConversationScroll();
    try {
      final analysisSymbol = mode == AgentMode.analysis
          ? await _resolveAnalysisSymbol(prompt)
          : _activeSymbol;
      final analysisCandles = mode == AgentMode.analysis
          ? await _prepareAnalysisChart(analysisSymbol)
          : const <Candle>[];
      if (!mounted) return;
      if (mode == AgentMode.analysis && analysisCandles.isEmpty) {
        throw Exception('$analysisSymbol 没有可分析的 K 线。');
      }
      final answer = await _agent.run(
        prompt: prompt,
        symbol: analysisSymbol,
        candles: analysisCandles,
        llm: _llm,
        mcp: _mcp,
        api: _api,
        mode: mode,
        onActivity: _recordActivity,
      );
      if (!mounted) return;
      setState(() {
        if (mode == AgentMode.analysis) {
          final plan = TradePlan.fromResponse(answer.text);
          final notices = [...answer.warnings];
          final matchesResponse =
              plan?.symbol == null || plan!.symbol == analysisSymbol;
          final matchesChart = _activeSymbol == analysisSymbol;
          if (!matchesResponse) {
            notices.add('结果 JSON 的币种与分析币种 $analysisSymbol 不一致，未添加图表标记。');
          }
          if (!matchesChart) {
            notices.add('当前图表已切换为 $_activeSymbol，未添加 $analysisSymbol 的图表标记。');
          }
          final displayText = notices.isEmpty
              ? answer.text
              : '${answer.text}\n\n> 数据源提示：${notices.join(' | ')}';
          _conversation.add(_ConversationMessage.agent(displayText));
          _plan = matchesResponse && matchesChart ? plan : null;
        } else {
          _conversation.add(_ConversationMessage.agent(answer.text));
        }
      });
      _scheduleConversationScroll();
    } catch (error) {
      if (mounted) {
        setState(
          () => _conversation.add(
            _ConversationMessage.agent('> Agent 请求失败：$error'),
          ),
        );
        _scheduleConversationScroll();
      }
    } finally {
      if (mounted) setState(() => _loadingAgent = false);
    }
  }

  void _recordActivity(String activity) {
    if (!mounted) return;
    setState(() => _conversation.add(_ConversationMessage.activity(activity)));
    _scheduleConversationScroll();
  }

  // Show a quick return control whenever the reader leaves the conversation end.
  void _handleConversationScroll() {
    if (!_conversationScrollController.hasClients) return;
    final position = _conversationScrollController.position;
    final isAtBottom =
        position.maxScrollExtent - position.pixels <=
        _conversationBottomThreshold;
    _conversationWasAtBottom = isAtBottom;
    final shouldShowButton = !isAtBottom && _conversation.isNotEmpty;
    if (!mounted || shouldShowButton == _showScrollToBottom) return;
    setState(() => _showScrollToBottom = shouldShowButton);
  }

  void _scheduleConversationScroll() {
    final shouldFollow = _conversationWasAtBottom;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_conversationScrollController.hasClients) return;
      if (shouldFollow) {
        unawaited(
          _conversationScrollController.animateTo(
            _conversationScrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
          ),
        );
      } else if (!_showScrollToBottom && _conversation.isNotEmpty) {
        setState(() => _showScrollToBottom = true);
      }
    });
  }

  void _scrollConversationToBottom() {
    if (!_conversationScrollController.hasClients) return;
    unawaited(
      _conversationScrollController.animateTo(
        _conversationScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      ),
    );
  }

  void _clearAgentContext() {
    if (_loadingAgent) return;
    setState(() {
      _conversation.clear();
      _plan = null;
      _prompt.clear();
      _conversationWasAtBottom = true;
      _showScrollToBottom = false;
      // Rebuild the chart so its hover and floating plan widgets reset too.
      _chartVersion++;
    });
  }

  void _showNodeMissing() {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) => ContentDialog(
        title: const Text('Nodejs 未检测到'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('未检测到Nodejs，部分功能有缺失。'),
            const SizedBox(height: 10),
            HyperlinkButton(
              onPressed: () async {
                await NodeRuntimeService.openDownloadPage();
              },
              child: const Text('前往 Nodejs 官网'),
            ),
          ],
        ),
        actions: [
          FilledButton(
            child: const Text('知道了'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  void _openSettings() {
    showDialog<void>(
      context: context,
      builder: (context) => AgentSettingsDialog(
        llm: _llm,
        mcp: _mcp,
        api: _api,
        keyStatus: _apiKeyStatus,
        nodeAvailable: widget.nodeAvailable,
        onSave: (llm, mcp, api, apiKeys) async {
          await Future.wait([
            _llmSettingsStore.save(llm),
            _llmSettingsStore.saveMcp(mcp),
            _llmSettingsStore.saveApi(api),
          ]);
          await _keyStore.update(apiKeys);
          final status = await _keyStore.status();
          if (!mounted) return;
          setState(() {
            _llm = llm;
            _mcp = mcp;
            _api = api;
            _apiKeyStatus = status;
          });
        },
      ),
    );
  }

  Future<void> _loadApiKeyStatus() async {
    final status = await _keyStore.status();
    if (mounted) setState(() => _apiKeyStatus = status);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          const WindowTitleBar(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Text(
                        _activeSymbol,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (_candles.isNotEmpty) ...[
                        const SizedBox(width: 12),
                        Text(
                          _price(_candles.last.close),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const Spacer(),
                      Button(onPressed: _openSettings, child: const Text('设置')),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    // The 3:2 flex ratio implements the requested 60% / 40% desktop split.
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: 3, child: _buildChartPanel(context)),
                        const SizedBox(width: 12),
                        Expanded(flex: 2, child: _buildAgentPanel(context)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartPanel(BuildContext context) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 210,
                child: AutoSuggestBox<String>(
                  controller: _symbol,
                  placeholder: '搜索代币，例如 BTC',
                  items: _symbols
                      .map(
                        (symbol) => AutoSuggestBoxItem<String>(
                          value: symbol,
                          label: symbol,
                        ),
                      )
                      .toList(),
                  sorter: _sortSymbols,
                  onSelected: (item) {
                    final symbol = item.value;
                    if (symbol != null) _selectSymbol(symbol);
                  },
                ),
              ),
              SizedBox(
                width: 92,
                child: ComboBox<String>(
                  value: _interval,
                  isExpanded: true,
                  items: const [
                    ComboBoxItem(value: '1', child: Text('1m')),
                    ComboBoxItem(value: '5', child: Text('5m')),
                    ComboBoxItem(value: '15', child: Text('15m')),
                    ComboBoxItem(value: '60', child: Text('1h')),
                    ComboBoxItem(value: '240', child: Text('4h')),
                    ComboBoxItem(value: 'D', child: Text('1D')),
                  ],
                  onChanged: (value) {
                    if (value == null || value == _interval) return;
                    setState(() => _interval = value);
                    _startChartRefresh();
                  },
                ),
              ),
              Text('Bybit Linear · $_activeSymbol · 1 秒自动刷新'),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: CandleChart(
              // Reset zoom only after a complete history load succeeds.
              key: ValueKey(_chartVersion),
              candles: _candles,
              plan: _plan,
              error: _chartError,
              loading: _showChartLoading,
              onRetry: _loadingChart ? null : _retryChart,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _legend(Colors.blue, '开仓区'),
              const SizedBox(width: 14),
              _legend(Colors.red, '止损'),
              const SizedBox(width: 14),
              _legend(Colors.green, '止盈'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAgentPanel(BuildContext context) {
    final resources = FluentTheme.of(context).resources;
    // Keep generated Markdown readable in Fluent light and dark themes.
    final resultStyle = MarkdownStyleSheet(
      p: TextStyle(
        fontSize: 13,
        height: 1.4,
        color: resources.textFillColorPrimary,
      ),
      h1: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: resources.textFillColorPrimary,
      ),
      h2: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: resources.textFillColorPrimary,
      ),
      h3: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: resources.textFillColorPrimary,
      ),
      code: TextStyle(
        fontFamily: 'monospace',
        color: resources.textFillColorPrimary,
      ),
      codeblockDecoration: BoxDecoration(
        color: resources.layerFillColorDefault,
        borderRadius: BorderRadius.circular(4),
      ),
      blockquote: TextStyle(color: resources.textFillColorSecondary),
    );
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Trading Agent',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          if (_plan != null) ...[const SizedBox(height: 8), _buildPlanCard()],
          const SizedBox(height: 8),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Card(
                  backgroundColor: FluentTheme.of(
                    context,
                  ).resources.subtleFillColorSecondary,
                  child: SingleChildScrollView(
                    controller: _conversationScrollController,
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final message in _conversation) ...[
                          message.isActivity
                              ? _buildActivityMessage(context, message)
                              : _buildConversationMessage(
                                  context,
                                  message,
                                  resultStyle,
                                ),
                          const SizedBox(height: 8),
                        ],
                      ],
                    ),
                  ),
                ),
                if (_showScrollToBottom)
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: Tooltip(
                      message: '滚动到底部',
                      child: SizedBox(
                        width: 36,
                        height: 36,
                        child: IconButton(
                          icon: const Icon(FluentIcons.chevron_down),
                          onPressed: _scrollConversationToBottom,
                          style: ButtonStyle(
                            backgroundColor: WidgetStatePropertyAll(
                              FluentTheme.of(context).accentColor,
                            ),
                            foregroundColor: const WidgetStatePropertyAll(
                              Colors.white,
                            ),
                            shape: const WidgetStatePropertyAll(CircleBorder()),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ToggleButton(
                checked: _agentMode == AgentMode.analysis,
                onChanged: _loadingAgent
                    ? null
                    : (checked) {
                        if (checked) {
                          setState(() => _agentMode = AgentMode.analysis);
                        }
                      },
                child: const Text('分析'),
              ),
              const SizedBox(width: 4),
              ToggleButton(
                checked: _agentMode == AgentMode.conversation,
                onChanged: _loadingAgent
                    ? null
                    : (checked) {
                        if (checked) {
                          setState(() => _agentMode = AgentMode.conversation);
                        }
                      },
                child: const Text('对话'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Stack(
            children: [
              TextBox(
                controller: _prompt,
                minLines: 3,
                maxLines: 5,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 46),
                placeholder: '请输入对话或分析请求',
              ),
              Positioned(
                right: 8,
                bottom: 8,
                child: Button(
                  onPressed: _loadingAgent
                      ? null
                      : () {
                          // Reuse the normal send path for identical validation.
                          setState(() {
                            _agentMode = AgentMode.analysis;
                            _prompt.text =
                                '给我一个 $_activeSymbol 的开仓方向与位置以及止盈、止损位置。';
                          });
                          unawaited(_runAgent());
                        },
                  child: const Text('分析当前合约'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _loadingAgent ? null : _runAgent,
                  child: _loadingAgent
                      ? const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: ProgressRing(),
                            ),
                          ],
                        )
                      : const Text('发送'),
                ),
              ),
              const SizedBox(width: 8),
              Button(
                onPressed: _loadingAgent ? null : _clearAgentContext,
                child: const Text('清空'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildConversationMessage(
    BuildContext context,
    _ConversationMessage message,
    MarkdownStyleSheet agentStyle,
  ) {
    final resources = FluentTheme.of(context).resources;
    final isUser = message.isUser;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isUser
            ? const Color(0x332B88D8)
            : resources.layerFillColorDefault,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            isUser ? 'User' : 'Agent',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isUser ? Colors.blue : resources.textFillColorSecondary,
            ),
          ),
          const SizedBox(height: 5),
          if (isUser)
            SelectableText(
              message.text,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: resources.textFillColorPrimary,
              ),
            )
          else
            MarkdownBody(
              data: message.text,
              selectable: true,
              styleSheet: agentStyle,
            ),
        ],
      ),
    );
  }

  // Keep tool status compact while placing it at its exact chat position.
  Widget _buildActivityMessage(
    BuildContext context,
    _ConversationMessage message,
  ) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FluentTheme.of(context).resources.layerFillColorDefault,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        message.text,
        style: TextStyle(
          fontSize: 12,
          color: FluentTheme.of(context).resources.textFillColorSecondary,
        ),
      ),
    );
  }

  Widget _buildPlanCard() => Card(
    padding: const EdgeInsets.all(8),
    backgroundColor: FluentTheme.of(context).resources.subtleFillColorSecondary,
    child: Wrap(
      spacing: 12,
      runSpacing: 4,
      children: [
        Text(
          '决策：${_plan!.decision}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        if (_plan!.entryLow != null || _plan!.entryHigh != null)
          Text('开仓 ${_price(_plan!.entryLow)} – ${_price(_plan!.entryHigh)}'),
        if (_plan!.stopLoss != null) Text('SL ${_price(_plan!.stopLoss)}'),
        if (_plan!.takeProfits.isNotEmpty)
          Text('TP ${_plan!.takeProfits.map(_price).join(' / ')}'),
      ],
    ),
  );

  Widget _legend(Color color, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 10, height: 10, color: color),
      const SizedBox(width: 4),
      Text(text, style: const TextStyle(fontSize: 12)),
    ],
  );

  String _price(double? value) => value == null
      ? '—'
      : value >= 1000
      ? value.toStringAsFixed(1)
      : value >= 1
      ? value.toStringAsFixed(4)
      : value.toStringAsFixed(6);
}

class _ConversationMessage {
  const _ConversationMessage.user(this.text)
    : isUser = true,
      isActivity = false;
  const _ConversationMessage.agent(this.text)
    : isUser = false,
      isActivity = false;
  const _ConversationMessage.activity(this.text)
    : isUser = false,
      isActivity = true;

  final String text;
  final bool isUser;
  final bool isActivity;
}
