import 'package:dio/dio.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../../domain/models/app_settings.dart';
import '../../domain/models/llm_model_info.dart';
import '../../domain/models/trade_plan.dart';
import 'trading_session.dart';
import 'llm_model_selector.dart';
import 'dashboard_messages.dart';
import 'trade_status_card.dart';
import 'dashboard_controller.dart';

class DashboardAgentPanel extends StatelessWidget {
  const DashboardAgentPanel({
    super.key,
    required this.plan,
    this.trading,
    required this.messages,
    required this.scrollController,
    required this.showScrollToBottom,
    required this.llm,
    required this.modelCatalogKey,
    required this.loadModels,
    required this.onModelChanged,
    required this.onReasoningChanged,
    required this.loading,
    required this.promptController,
    required this.onQuickAnalysis,
    required this.onSend,
    required this.onStop,
    required this.onClear,
    required this.onScrollToBottom,
    required this.onOpenSettings,
  });

  final TradePlan? plan;
  final TradingSession? trading;
  final List<DashboardMessage> messages;
  final ScrollController scrollController;
  final bool showScrollToBottom;
  final LlmSettings llm;
  final Key modelCatalogKey;
  final Future<List<LlmModelInfo>> Function(CancelToken) loadModels;
  final Future<void> Function(String) onModelChanged;
  final Future<void> Function(String?) onReasoningChanged;
  final bool loading;
  final TextEditingController promptController;
  final VoidCallback onQuickAnalysis;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final VoidCallback onClear;
  final VoidCallback onScrollToBottom;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final resources = FluentTheme.of(context).resources;
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
              IconButton(
                icon: const Icon(FluentIcons.settings),
                onPressed: onOpenSettings,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (plan != null && trading == null) ...[
            const SizedBox(height: 8),
            PlanCard(plan!),
          ],
          if (trading != null) TradeStatusCard(session: trading!),
          const SizedBox(height: 8),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Card(
                  backgroundColor: resources.subtleFillColorSecondary,
                  child: SingleChildScrollView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final message in messages) ...[
                          message.isActivity
                              ? ActivityMessage(message)
                              : ConversationMessage(message),
                          const SizedBox(height: 8),
                        ],
                      ],
                    ),
                  ),
                ),
                if (showScrollToBottom)
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
                          onPressed: onScrollToBottom,
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
          LlmModelSelector(
            key: modelCatalogKey,
            llm: llm,
            loadModels: loadModels,
            onChanged: onModelChanged,
            onReasoningChanged: onReasoningChanged,
            enabled: !loading,
          ),
          const SizedBox(height: 8),
          Stack(
            children: [
              TextBox(
                controller: promptController,
                minLines: 3,
                maxLines: 5,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 46),
                placeholder: '输入代币或继续追问分析结果',
              ),
              Positioned(
                right: 8,
                bottom: 8,
                child: Button(
                  onPressed: loading ? null : onQuickAnalysis,
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
                  // Keep cancellation available throughout preparation and output.
                  onPressed: loading ? onStop : onSend,
                  child: Text(loading ? '停止生成' : '发送'),
                ),
              ),
              const SizedBox(width: 8),
              Button(
                onPressed: loading ? null : onClear,
                child: const Text('清空'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
