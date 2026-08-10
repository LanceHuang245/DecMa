import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../models/trading_models.dart';
import '../../services/agent_service.dart';
import '../../utils/display_formatters.dart';
import 'dashboard_controller.dart';

class DashboardAgentPanel extends StatelessWidget {
  const DashboardAgentPanel({
    super.key,
    required this.plan,
    required this.messages,
    required this.scrollController,
    required this.showScrollToBottom,
    required this.mode,
    required this.llm,
    required this.loading,
    required this.promptController,
    required this.onModeChanged,
    required this.onQuickAnalysis,
    required this.onSend,
    required this.onClear,
    required this.onScrollToBottom,
    required this.onOpenSettings,
  });

  final TradePlan? plan;
  final List<DashboardMessage> messages;
  final ScrollController scrollController;
  final bool showScrollToBottom;
  final AgentMode mode;
  final LlmSettings llm;
  final bool loading;
  final TextEditingController promptController;
  final ValueChanged<AgentMode> onModeChanged;
  final VoidCallback onQuickAnalysis;
  final VoidCallback onSend;
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
          if (plan != null) ...[const SizedBox(height: 8), _PlanCard(plan!)],
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
                              ? _ActivityMessage(message)
                              : _ConversationMessage(message),
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
          Row(
            children: [
              ToggleButton(
                checked: mode == AgentMode.analysis,
                onChanged: loading
                    ? null
                    : (checked) {
                        if (checked) onModeChanged(AgentMode.analysis);
                      },
                child: const Text('分析'),
              ),
              const SizedBox(width: 4),
              ToggleButton(
                checked: mode == AgentMode.conversation,
                onChanged: loading
                    ? null
                    : (checked) {
                        if (checked) onModeChanged(AgentMode.conversation);
                      },
                child: const Text('对话'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Tooltip(
                    message: '${llm.provider.label} · ${llm.model}',
                    child: Text(
                      '${llm.provider.label} · ${llm.model}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 12,
                        color: resources.textFillColorSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Stack(
            children: [
              TextBox(
                controller: promptController,
                minLines: 3,
                maxLines: 5,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 46),
                placeholder: '请输入对话或分析请求',
              ),
              // Keep quick analysis available only when working in analysis mode.
              if (mode == AgentMode.analysis)
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
                  onPressed: loading ? null : onSend,
                  child: loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: ProgressRing(),
                        )
                      : const Text('发送'),
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

class _ConversationMessage extends StatelessWidget {
  const _ConversationMessage(this.message);

  final DashboardMessage message;

  @override
  Widget build(BuildContext context) {
    final resources = FluentTheme.of(context).resources;
    final isUser = message.isUser;
    // Use the surrounding Fluent colors for generated agent Markdown.
    final agentStyle = MarkdownStyleSheet(
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
}

class _ActivityMessage extends StatelessWidget {
  const _ActivityMessage(this.message);

  final DashboardMessage message;

  @override
  Widget build(BuildContext context) => Container(
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

class _PlanCard extends StatelessWidget {
  const _PlanCard(this.plan);

  final TradePlan plan;

  @override
  Widget build(BuildContext context) => Card(
    padding: const EdgeInsets.all(8),
    backgroundColor: FluentTheme.of(context).resources.subtleFillColorSecondary,
    child: Wrap(
      spacing: 12,
      runSpacing: 4,
      children: [
        Text(
          '决策：${plan.decision}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        if (plan.entryLow != null || plan.entryHigh != null)
          Text('开仓 ${_price(plan.entryLow)} – ${_price(plan.entryHigh)}'),
        if (plan.stopLoss != null) Text('SL ${_price(plan.stopLoss)}'),
        if (plan.takeProfits.isNotEmpty)
          Text('TP ${plan.takeProfits.map(_price).join(' / ')}'),
      ],
    ),
  );

  String _price(double? value) =>
      value == null ? '—' : formatMarketPrice(value);
}
