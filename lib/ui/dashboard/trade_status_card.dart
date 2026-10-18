import 'package:fluent_ui/fluent_ui.dart';

import '../../services/analysis/trading_session.dart';
import '../../services/analysis/entry_assessment.dart';
import '../../utils/display_formatters.dart';

// Show the answer and next action, without asking users to understand risk settings.
class TradeStatusCard extends StatelessWidget {
  const TradeStatusCard({super.key, required this.session});
  final TradingSession session;

  @override
  Widget build(BuildContext context) {
    final plan = session.plan;
    if (plan == null) return const SizedBox.shrink();
    final side = switch (plan.decision) {
      'LONG_SETUP' => '偏多',
      'SHORT_SETUP' => '偏空',
      _ => '等待',
    };
    final status = session.assessment;
    final action = switch (status?.state) {
      null => plan.isSetup ? '正在确认' : '暂不入场',
      EntryState.realized => '已经错过，不追价',
      EntryState.invalid => '原计划已失效',
      _ => status!.label,
    };
    return Card(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            status?.terminal == true
                ? '等待 · $action（此前$side）'
                : '$side · $action',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          if (session.currentPrice != null)
            Text('参考现价 ${formatMarketPrice(session.currentPrice!)}'),
          if (status != null) Text(status.reason),
          if (!session.checking && plan.isSetup && status?.terminal != true)
            Button(onPressed: session.recheck, child: const Text('刷新当前机会')),
        ],
      ),
    );
  }
}
