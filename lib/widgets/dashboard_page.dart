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
  });

  final bool nodeAvailable;
  final LlmSettings? initialLlm;
  final McpSettings? initialMcp;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  static const _historyLimit = 1000;
  final _bybit = BybitService();
  final _agent = AgentService();
  final _keyStore = SecureKeyStore();
  final _llmSettingsStore = LlmSettingsStore();
  final _symbol = TextEditingController(text: 'BTCUSDT');
  final _prompt = TextEditingController(text: '给我一个 BTC 的开仓方向与位置以及止盈、止损位置。');
  Timer? _chartRefreshTimer;
  var _activeSymbol = 'BTCUSDT';
  var _interval = '15';
  var _candles = <Candle>[];
  var _symbols = <String>[];
  TradePlan? _plan;
  String? _result;
  var _activities = <String>[];
  String? _chartError;
  var _chartVersion = 0;
  bool _loadingChart = false;
  bool _showChartLoading = false;
  bool _loadingAgent = false;
  ApiKeyStatus _apiKeyStatus = const ApiKeyStatus();
  late LlmSettings _llm;
  McpSettings _mcp = const McpSettings(
    useBybit: true,
    useNansen: false,
    useOpenWebSearch: true,
  );

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
    _startChartRefresh();
  }

  @override
  void dispose() {
    _chartRefreshTimer?.cancel();
    _bybit.dispose();
    _agent.dispose();
    _symbol.dispose();
    _prompt.dispose();
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
    setState(() {
      _loadingChart = true;
      if (!latestOnly) _showChartLoading = true;
    });
    try {
      final candles = await _bybit.fetchKlines(
        symbol: _activeSymbol,
        interval: _interval,
        limit: latestOnly && _candles.isNotEmpty ? 2 : _historyLimit,
      );
      if (!mounted) return;
      setState(() {
        _candles = latestOnly
            ? _mergeLatestCandles(_candles, candles)
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

  Future<void> _runAgent() async {
    if (_loadingAgent) return;
    if (!_llm.isComplete || !_apiKeyStatus.hasLlmKey) {
      setState(() => _result = '> 请先在设置中填写 LLM Endpoint、Model 并保存 API Key。');
      return;
    }
    final prompt = _prompt.text.trim();
    if (_candles.isEmpty) await _loadChart();
    if (!mounted) return;
    setState(() {
      _loadingAgent = true;
      _activities = ['• Thinking - 分析中…'];
      _prompt.clear();
    });
    try {
      final answer = await _agent.run(
        prompt: prompt,
        symbol: _activeSymbol,
        candles: _candles,
        llm: _llm,
        mcp: _mcp,
        onActivity: _recordActivity,
      );
      if (!mounted) return;
      setState(() {
        _result = answer.warnings.isEmpty
            ? answer.text
            : '${answer.text}\n\n> MCP 提示：${answer.warnings.join(' | ')}';
        _plan = TradePlan.fromResponse(answer.text);
      });
    } catch (error) {
      if (mounted) setState(() => _result = '> Agent 请求失败：$error');
    } finally {
      if (mounted) setState(() => _loadingAgent = false);
    }
  }

  void _recordActivity(String activity) {
    if (!mounted || _activities.contains(activity)) return;
    setState(() => _activities.add(activity));
  }

  void _clearAgentContext() {
    if (_loadingAgent) return;
    setState(() {
      _result = null;
      _activities = [];
      _plan = null;
      _prompt.clear();
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
        keyStatus: _apiKeyStatus,
        nodeAvailable: widget.nodeAvailable,
        onSave: (llm, mcp, apiKeys) async {
          await Future.wait([
            _llmSettingsStore.save(llm),
            _llmSettingsStore.saveMcp(mcp),
          ]);
          await _keyStore.update(apiKeys);
          final status = await _keyStore.status();
          if (!mounted) return;
          setState(() {
            _llm = llm;
            _mcp = mcp;
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
                      const Text(
                        'DecMa',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text('Crypto Perpetual Decision Agent'),
                      const Spacer(),
                      Flexible(
                        child: Text(
                          '${_llm.provider.label} · ${_llm.model}',
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                        ),
                      ),
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
              const Spacer(),
              if (_candles.isNotEmpty)
                Text('Last ${_price(_candles.last.close)}'),
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
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Trading Agent',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 6),
              Button(onPressed: _openSettings, child: const Text('设置')),
            ],
          ),
          const SizedBox(height: 8),
          if (_plan != null) ...[const SizedBox(height: 8), _buildPlanCard()],
          const SizedBox(height: 8),
          Expanded(
            child: Card(
              backgroundColor: FluentTheme.of(
                context,
              ).resources.subtleFillColorSecondary,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_activities.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: resources.layerFillColorDefault,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        // Activity lines are intentionally summaries, not expandable logs.
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final activity in _activities)
                              Text(
                                activity,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: resources.textFillColorSecondary,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    MarkdownBody(
                      data:
                          _result ??
                          (_activities.isEmpty ? 'Agent 分析结果将显示在这里。' : ''),
                      selectable: true,
                      styleSheet: resultStyle,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextBox(
            controller: _prompt,
            minLines: 3,
            maxLines: 5,
            placeholder: '例如：给我一个 BTC 的开仓方向与位置以及止盈、止损位置',
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
