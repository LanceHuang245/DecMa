import 'package:fluent_ui/fluent_ui.dart';

import 'trading_session.dart';
import '../../domain/analysis/entry_assessment.dart';
import '../../domain/analysis/feature_engine.dart';
import '../../utils/display_formatters.dart';

// Show the answer and next action, without asking users to understand risk settings.
class TradeStatusCard extends StatelessWidget {
  const TradeStatusCard({super.key, required this.session}) : _dialog = false;
  const TradeStatusCard._dialog({required this.session}) : _dialog = true;
  final TradingSession session;
  final bool _dialog;

  String _value(double? value) => value?.toStringAsFixed(1) ?? '暂无';
  DateTime _expiry(TradingSession session) {
    final limit = session.createdAt!.add(
      Duration(minutes: session.plan!.conditions.timeframeMinutes * 3),
    );
    final explicit = session.plan!.conditions.expiresAt;
    return explicit != null && explicit.isBefore(limit) ? explicit : limit;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) => _build(context),
  );

  // Keep the summary compact; the dialog observes the same live session.
  Widget _build(BuildContext context) {
    final plan = session.plan;
    if (plan == null) {
      return _dialog
          ? ContentDialog(
              title: const Text('开仓详情'),
              content: const Text('当前计划已清除'),
              actions: [
                Button(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('关闭'),
                ),
              ],
            )
          : const SizedBox.shrink();
    }
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
    final trigger = switch (plan.conditions.triggerType) {
      'CLOSE_ABOVE' => '收盘站上指定价格',
      'CLOSE_BELOW' => '收盘跌破指定价格',
      'BREAKOUT_RETEST' => '突破后另一根 K 线回踩守住',
      'TOUCH_ZONE_AND_CLOSE_INSIDE' => '触及区间边界后收回区间',
      'VOLUME_ABOVE_MULTIPLE' => '价格方向与放量共同确认',
      _ => '等待确认',
    };
    final title = Text(
      status?.terminal == true ? '等待 · $action（此前$side）' : '$side · $action',
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
    );
    final canRefresh =
        !session.checking && plan.isSetup && status?.terminal != true;
    final refresh = Button(
      onPressed: session.recheck,
      child: const Text('刷新当前机会'),
    );
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_dialog && session.currentPrice != null)
          Text('参考现价 ${formatMarketPrice(session.currentPrice!)}'),
        if (status != null) Text(status.reason),
        if (plan.isSetup &&
            status?.terminal != true &&
            plan.entryLow != null &&
            plan.entryHigh != null &&
            plan.stopLoss != null &&
            plan.targets.isNotEmpty) ...[
          Text(
            '开仓区 ${formatMarketPrice(plan.entryLow!)}–${formatMarketPrice(plan.entryHigh!)} · 止损 ${formatMarketPrice(plan.stopLoss!)}',
          ),
          Text('TP1 ${formatMarketPrice(plan.targets.first.price)}'),
          if (_dialog) ...[
            Text('有效期至 ${_expiry(session).toLocal()}'),
            if (session.referenceEntry case final reference?) ...[
              Text(
                '参考入场 ${formatMarketPrice(reference.price)} · 净盈亏比 ${reference.netRewardRisk.toStringAsFixed(2)}:1',
              ),
              Text('成本后追价边界 ${formatMarketPrice(reference.maximumPrice)}'),
              const Text('按公共 Taker 费率和 3 小时资金费情景估算；未估计仓位冲击'),
            ],
            const SizedBox(height: 12),
            Text(
              '触发：$trigger · ${plan.conditions.timeframeMinutes} 分钟 · 价格 ${plan.conditions.triggerPrice ?? '区间边界'}',
            ),
            Text(
              '失效价 ${plan.conditions.cancellationPrice ?? plan.stopLoss} · 止损参考 ${plan.conditions.stopReference}',
            ),
            for (final entry
                in (session.features?.timeframes ??
                        const <String, TimeframeFeatures>{})
                    .entries)
              Text(
                '${entry.key}: RSI ${_value(entry.value.rsi14)} · ADX ${_value(entry.value.details['adx14'])} · K/D/J ${_value(entry.value.details['kdj_k9'])}/${_value(entry.value.details['kdj_d3'])}/${_value(entry.value.details['kdj_j3'])}',
              ),
            if (session.features != null)
              Text('指标快照 ${session.features!.calculatedAt.toLocal()}'),
          ],
        ],
        if (_dialog && status != null) Text('复核时间 ${status.at.toLocal()}'),
      ],
    );
    if (_dialog) {
      return ContentDialog(
        title: title,
        content: SingleChildScrollView(child: content),
        actions: [
          if (canRefresh) refresh,
          Button(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      );
    }
    return Card(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          title,
          content,
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Button(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => TradeStatusCard._dialog(session: session),
                ),
                child: const Text('查看详情'),
              ),
              if (canRefresh) refresh,
            ],
          ),
        ],
      ),
    );
  }
}
