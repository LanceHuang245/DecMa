import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../domain/models/trade_plan.dart';
import '../../utils/display_formatters.dart';
import 'dashboard_controller.dart';

class ConversationMessage extends StatelessWidget {
  const ConversationMessage(this.message, {super.key});

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

class ActivityMessage extends StatelessWidget {
  const ActivityMessage(this.message, {super.key});

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

class PlanCard extends StatelessWidget {
  const PlanCard(this.plan, {super.key});

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
