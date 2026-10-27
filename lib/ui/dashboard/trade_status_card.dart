import 'package:fluent_ui/fluent_ui.dart';

import 'trading_session.dart';
import '../../domain/analysis/entry_assessment.dart';
import '../../domain/analysis/feature_engine.dart';
import '../../utils/display_formatters.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../l10n/app_languages.dart';

// Show the answer and next action, without asking users to understand risk settings.
class TradeStatusCard extends StatelessWidget {
  const TradeStatusCard({super.key, required this.session}) : _dialog = false;
  const TradeStatusCard._dialog({required this.session}) : _dialog = true;
  final TradingSession session;
  final bool _dialog;

  String _value(double? value) => value?.toStringAsFixed(1) ?? appL10n.noValue;
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
    final loc = AppLocalizations.of(context);
    final plan = session.plan;
    if (plan == null) {
      return _dialog
          ? ContentDialog(
              title: Text(loc.entryDetails),
              content: Text(loc.planCleared),
              actions: [
                Button(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(loc.close),
                ),
              ],
            )
          : const SizedBox.shrink();
    }
    final side = switch (plan.decision) {
      'LONG_SETUP' => loc.biasLong,
      'SHORT_SETUP' => loc.biasShort,
      _ => loc.decisionWait,
    };
    final status = session.assessment;
    final action = switch (status?.state) {
      null => plan.isSetup ? loc.actionConfirming : loc.actionNoEntry,
      EntryState.realized => loc.actionMissed,
      EntryState.invalid => loc.actionInvalid,
      _ => status!.label,
    };
    final trigger = switch (plan.conditions.triggerType) {
      'CLOSE_ABOVE' => loc.triggerCloseAbove,
      'CLOSE_BELOW' => loc.triggerCloseBelow,
      'BREAKOUT_RETEST' => loc.triggerBreakoutRetest,
      'TOUCH_ZONE_AND_CLOSE_INSIDE' => loc.triggerTouchZone,
      'VOLUME_ABOVE_MULTIPLE' => loc.triggerVolume,
      _ => loc.entryUnverified,
    };
    final title = Text(
      status?.terminal == true
          ? loc.statusTerminal(action, side)
          : '$side · $action',
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
    );
    final canRefresh =
        !session.checking && plan.isSetup && status?.terminal != true;
    final refresh = Button(
      onPressed: session.recheck,
      child: Text(loc.refreshOpportunity),
    );
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_dialog && session.currentPrice != null)
          Text(loc.referencePrice(formatMarketPrice(session.currentPrice!))),
        if (status != null) Text(status.reason),
        if (plan.isSetup &&
            status?.terminal != true &&
            plan.entryLow != null &&
            plan.entryHigh != null &&
            plan.stopLoss != null &&
            plan.targets.isNotEmpty) ...[
          Text(
            loc.entrySummary(
              formatMarketPrice(plan.entryLow!),
              formatMarketPrice(plan.entryHigh!),
              formatMarketPrice(plan.stopLoss!),
            ),
          ),
          Text('TP1 ${formatMarketPrice(plan.targets.first.price)}'),
          if (_dialog) ...[
            Text(loc.validUntil(_expiry(session).toLocal())),
            if (session.referenceEntry case final reference?) ...[
              Text(
                loc.referenceEntry(
                  formatMarketPrice(reference.price),
                  reference.netRewardRisk.toStringAsFixed(2),
                ),
              ),
              Text(
                loc.chaseBoundary(formatMarketPrice(reference.maximumPrice)),
              ),
              Text(loc.costEstimateNote),
            ],
            const SizedBox(height: 12),
            Text(
              loc.triggerSummary(
                trigger,
                plan.conditions.timeframeMinutes,
                plan.conditions.triggerPrice ?? loc.zoneEdge,
              ),
            ),
            Text(
              loc.invalidationSummary(
                '${plan.conditions.cancellationPrice ?? plan.stopLoss}',
                plan.conditions.stopReference,
              ),
            ),
            for (final entry
                in (session.features?.timeframes ??
                        const <String, TimeframeFeatures>{})
                    .entries)
              Text(
                '${entry.key}: RSI ${_value(entry.value.rsi14)} · ADX ${_value(entry.value.details['adx14'])} · K/D/J ${_value(entry.value.details['kdj_k9'])}/${_value(entry.value.details['kdj_d3'])}/${_value(entry.value.details['kdj_j3'])}',
              ),
            if (session.features != null)
              Text(
                loc.featureSnapshot(session.features!.calculatedAt.toLocal()),
              ),
          ],
        ],
        if (_dialog && status != null)
          Text(loc.reviewedAt(status.at.toLocal())),
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
            child: Text(loc.close),
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
                child: Text(loc.viewDetails),
              ),
              if (canRefresh) refresh,
            ],
          ),
        ],
      ),
    );
  }
}
