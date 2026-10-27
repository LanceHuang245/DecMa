import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_providers.dart';
import '../../data/services/node_runtime_service.dart';
import '../../utils/display_formatters.dart';
import '../chart/candle_chart_colors.dart';
import '../news/news_panel.dart';
import 'dashboard_agent_panel.dart';
import 'dashboard_chart_panel.dart';
import 'dashboard_controller.dart';
import '../../l10n/generated/app_localizations.dart';

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage>
    with AutomaticKeepAliveClientMixin {
  DashboardController get _controller => ref.read(dashboardControllerProvider);

  // Keep the chart, polling and conversation alive while Settings is shown.
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _controller.initialize();
    final nodeAvailable = ref.read(appInitialSettingsProvider).nodeAvailable;
    if (!nodeAvailable) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showNodeMissing());
    }
  }

  void _showNodeMissing() {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) {
        final loc = AppLocalizations.of(context);
        return ContentDialog(
          title: Text(loc.nodeMissingTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(loc.nodeMissingBody),
              const SizedBox(height: 10),
              HyperlinkButton(
                onPressed: NodeRuntimeService.openDownloadPage,
                child: Text(loc.openNodeSite),
              ),
            ],
          ),
          actions: [
            FilledButton(
              child: Text(loc.gotIt),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // Keep the page-scoped controller alive only while this page watches it.
    ref.watch(dashboardControllerProvider);
    return AnimatedBuilder(
      animation: _controller,
      child: AnimatedBuilder(
        animation: _controller.newsListenable,
        builder: (context, _) => NewsPanel(
          events: _controller.newsEvents,
          currentSymbol: _controller.activeSymbol,
          providerStatuses: _controller.newsProviderStatuses,
          isRefreshing: _controller.refreshingNews,
        ),
      ),
      builder: (context, newsPanel) {
        final latest = _controller.candles.isEmpty
            ? null
            : _controller.candles.last;
        return Padding(
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
                      '${formatMarketPrice(latest.close)} USD',
                      style: TextStyle(
                        color: candleColor(latest),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                // Keep market, news, and Agent as three independent desktop columns.
                child: Row(
                  children: [
                    Expanded(flex: 4, child: _chartPanel()),
                    const SizedBox(width: 12),
                    Expanded(flex: 2, child: newsPanel!),
                    const SizedBox(width: 12),
                    Expanded(flex: 3, child: _agentPanel()),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _chartPanel() => DashboardChartPanel(
    symbolController: _controller.symbolController,
    symbols: _controller.symbols,
    interval: _controller.interval,
    activeSymbol: _controller.activeSymbol,
    candles: _controller.candles,
    totalPrepended: _controller.totalPrependedCandles,
    plan: _controller.chartPlan,
    showWaitZone: _controller.showWaitZone,
    chartVersion: _controller.chartVersion,
    error: _controller.chartError,
    historyError: _controller.historyError,
    loading: _controller.showChartLoading,
    loadingChart: _controller.loadingChart,
    onSymbolSelected: _controller.selectSymbol,
    onIntervalChanged: _controller.selectInterval,
    onRetry: _controller.retryChart,
    onLoadMore: _controller.hasMoreHistory ? _controller.loadMoreHistory : null,
    loadingMore: _controller.loadingMore,
  );

  Widget _agentPanel() => DashboardAgentPanel(
    messages: _controller.conversation,
    scrollController: _controller.conversationScrollController,
    showScrollToBottom: _controller.showScrollToBottom,
    llm: _controller.llm,
    modelCatalogKey: ObjectKey(_controller.apiKeyStatus),
    loadModels: _controller.loadLlmModels,
    onModelChanged: _controller.selectLlmModel,
    onReasoningChanged: _controller.selectLlmReasoningEffort,
    loading: _controller.loadingAgent,
    promptController: _controller.promptController,
    onQuickAnalysis: (swing) => _controller.quickAnalyze(swing: swing),
    onSend: _controller.runAgent,
    onStop: _controller.stopAgent,
    onClear: _controller.clearAgentContext,
    onScrollToBottom: _controller.scrollConversationToBottom,
  );
}
