import 'package:fluent_ui/fluent_ui.dart';

import '../../models/trading_models.dart';
import '../../services/node_runtime_service.dart';
import '../chart/candle_chart_colors.dart';
import '../core/window_title_bar.dart';
import '../settings/agent_settings_dialog.dart';
import 'dashboard_agent_panel.dart';
import 'dashboard_chart_panel.dart';
import 'dashboard_controller.dart';

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
  late final DashboardController _controller;

  @override
  void initState() {
    super.initState();
    _controller = DashboardController(
      nodeAvailable: widget.nodeAvailable,
      initialLlm: widget.initialLlm,
      initialMcp: widget.initialMcp,
      initialApi: widget.initialApi,
    )..initialize();
    if (!widget.nodeAvailable) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showNodeMissing());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
              onPressed: NodeRuntimeService.openDownloadPage,
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
        llm: _controller.llm,
        mcp: _controller.mcp,
        api: _controller.api,
        keyStatus: _controller.apiKeyStatus,
        nodeAvailable: widget.nodeAvailable,
        onSave: _controller.saveSettings,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final latest = _controller.candles.isEmpty
            ? null
            : _controller.candles.last;
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
                            _controller.activeSymbol,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (latest != null) ...[
                            const SizedBox(width: 12),
                            Text(
                              '${_price(latest.close)} USD',
                              style: TextStyle(
                                color: candleColor(latest),
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          const Spacer(),
                          Button(
                            onPressed: _openSettings,
                            child: const Text('设置'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        // The 3:2 flex ratio implements the requested 60% / 40% desktop split.
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              flex: 3,
                              child: DashboardChartPanel(
                                symbolController: _controller.symbolController,
                                symbols: _controller.symbols,
                                interval: _controller.interval,
                                activeSymbol: _controller.activeSymbol,
                                candles: _controller.candles,
                                plan: _controller.plan,
                                chartVersion: _controller.chartVersion,
                                error: _controller.chartError,
                                loading: _controller.showChartLoading,
                                loadingChart: _controller.loadingChart,
                                onSymbolSelected: _controller.selectSymbol,
                                onIntervalChanged: _controller.selectInterval,
                                onRetry: _controller.retryChart,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: DashboardAgentPanel(
                                plan: _controller.plan,
                                messages: _controller.conversation,
                                scrollController:
                                    _controller.conversationScrollController,
                                showScrollToBottom:
                                    _controller.showScrollToBottom,
                                mode: _controller.agentMode,
                                llm: _controller.llm,
                                loading: _controller.loadingAgent,
                                promptController: _controller.promptController,
                                onModeChanged: _controller.selectAgentMode,
                                onQuickAnalysis: _controller.quickAnalyze,
                                onSend: _controller.runAgent,
                                onClear: _controller.clearAgentContext,
                                onScrollToBottom:
                                    _controller.scrollConversationToBottom,
                              ),
                            ),
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
      },
    );
  }

  // Use precision suitable for the displayed price range.
  String _price(double value) {
    if (value >= 1000) return value.toStringAsFixed(1);
    if (value >= 1) return value.toStringAsFixed(4);
    return value.toStringAsFixed(6);
  }
}
