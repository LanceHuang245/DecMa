import 'package:fluent_ui/fluent_ui.dart';

import '../models/trading_models.dart';
import '../services/agent_service.dart';
import '../services/bybit_service.dart';
import 'candle_chart.dart';
import 'settings_dialog.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final _bybit = BybitService();
  final _agent = AgentService();
  final _symbol = TextEditingController(text: 'XRPUSDT');
  final _prompt = TextEditingController(text: '给我一个 XRP 的开仓方向与位置以及止盈、止损位置。');
  var _interval = '15';
  var _candles = <Candle>[];
  TradePlan? _plan;
  String? _result;
  String? _status;
  bool _loadingChart = false;
  bool _loadingAgent = false;
  LlmSettings _llm = LlmSettings(
    provider: LlmProvider.openAiResponses,
    endpoint: LlmProvider.openAiResponses.defaultEndpoint,
    apiKey: '',
    model: 'gpt-4.1',
  );
  McpSettings _mcp = const McpSettings(
    useBybit: true,
    useCoinglass: false,
    coinglassKey: '',
    useNansen: false,
    nansenKey: '',
    useOpenWebSearch: true,
  );

  @override
  void dispose() {
    _bybit.dispose();
    _agent.dispose();
    _symbol.dispose();
    _prompt.dispose();
    super.dispose();
  }

  String get _normalizedSymbol {
    final raw = _symbol.text.trim().toUpperCase().replaceAll(
      RegExp(r'\s+'),
      '',
    );
    return raw.endsWith('USDT') ? raw : '${raw}USDT';
  }

  Future<void> _loadChart() async {
    if (_loadingChart) return;
    setState(() {
      _loadingChart = true;
      _status = null;
    });
    try {
      final candles = await _bybit.fetchKlines(
        symbol: _normalizedSymbol,
        interval: _interval,
      );
      if (!mounted) return;
      setState(() => _candles = candles);
    } catch (error) {
      if (mounted) setState(() => _status = 'K 线加载失败：$error');
    } finally {
      if (mounted) setState(() => _loadingChart = false);
    }
  }

  Future<void> _runAgent() async {
    if (_loadingAgent) return;
    if (!_llm.isComplete) {
      setState(() => _status = '请先在设置中填写 LLM Endpoint、API Key 和 Model。');
      return;
    }
    if (_candles.isEmpty) await _loadChart();
    if (!mounted) return;
    setState(() {
      _loadingAgent = true;
      _status = 'Agent 正在调用数据 MCP 并分析市场…';
    });
    try {
      final answer = await _agent.run(
        prompt: _prompt.text.trim(),
        symbol: _normalizedSymbol,
        candles: _candles,
        llm: _llm,
        mcp: _mcp,
      );
      if (!mounted) return;
      setState(() {
        _result = answer.text;
        _plan = TradePlan.fromResponse(answer.text);
        _status = answer.warnings.isEmpty
            ? '分析完成。'
            : '分析完成；部分 MCP 不可用：${answer.warnings.join(' | ')}';
      });
    } catch (error) {
      if (mounted) setState(() => _status = 'Agent 请求失败：$error');
    } finally {
      if (mounted) setState(() => _loadingAgent = false);
    }
  }

  void _openSettings() {
    showDialog<void>(
      context: context,
      builder: (context) => AgentSettingsDialog(
        llm: _llm,
        mcp: _mcp,
        onSave: (llm, mcp) => setState(() {
          _llm = llm;
          _mcp = mcp;
          _status = '设置已保存到当前会话。';
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                const Text(
                  'DecMa',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
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
                width: 142,
                child: TextBox(
                  controller: _symbol,
                  placeholder: 'XRPUSDT',
                  onSubmitted: (_) => _loadChart(),
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
                  onChanged: (value) =>
                      setState(() => _interval = value ?? _interval),
                ),
              ),
              FilledButton(
                onPressed: _loadingChart ? null : _loadChart,
                child: Text(_loadingChart ? '加载中…' : '刷新 K 线'),
              ),
              Text('Bybit Linear · $_normalizedSymbol'),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: CandleChart(candles: _candles, plan: _plan),
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
          if (_status != null)
            Text(
              _status!,
              style: TextStyle(
                fontSize: 12,
                color: _status!.contains('失败')
                    ? Colors.errorPrimaryColor
                    : null,
              ),
            ),
          if (_plan != null) ...[const SizedBox(height: 8), _buildPlanCard()],
          const SizedBox(height: 8),
          Expanded(
            child: Card(
              backgroundColor: FluentTheme.of(
                context,
              ).resources.subtleFillColorSecondary,
              child: SingleChildScrollView(
                child: SelectableText(
                  _result ?? '配置模型后，输入问题并运行 Agent。结果中的 JSON 会自动标出开仓区、止损与止盈。',
                  style: const TextStyle(fontSize: 13, height: 1.4),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextBox(
            controller: _prompt,
            minLines: 3,
            maxLines: 5,
            placeholder: '例如：给我一个 XRP 的开仓方向与位置以及止盈、止损位置',
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _loadingAgent ? null : _runAgent,
            child: Text(_loadingAgent ? 'Agent 分析中…' : '运行 Agent'),
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
