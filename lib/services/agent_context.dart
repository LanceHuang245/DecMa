import 'dart:convert';

import '../models/market_snapshot.dart';
import '../models/news_event.dart';
import '../models/trading_models.dart';
import 'analysis/feature_engine.dart';

// Keep source status formatting next to the prompt context that consumes it.
Map<String, String> agentSourceAvailability({
  required McpSettings mcp,
  required ApiSettings api,
  required Set<String> servers,
  required bool hasSnapshot,
  required bool hasCoinalyze,
  required bool hasBybitKey,
  required bool hasBybitSecret,
  required bool hasFeeRates,
}) => {
  'bybit_rest_harness': hasSnapshot ? 'READY' : 'UNAVAILABLE',
  'bybit_mcp': !mcp.useBybit
      ? 'DISABLED'
      : servers.contains('Bybit MCP')
      ? 'AVAILABLE'
      : 'UNAVAILABLE',
  'bybit_account_fee_rate': !mcp.useBybit
      ? 'DISABLED'
      : hasBybitKey != hasBybitSecret
      ? 'INCOMPLETE'
      : !hasBybitKey
      ? 'NOT_CONFIGURED'
      : hasFeeRates
      ? 'READY'
      : 'UNAVAILABLE',
  'coinalyze_api': !api.useCoinalyze
      ? 'DISABLED'
      : hasCoinalyze
      ? 'AVAILABLE'
      : 'UNAVAILABLE',
  'nansen_mcp': !mcp.useNansen
      ? 'DISABLED'
      : servers.contains('Nansen MCP')
      ? 'AVAILABLE'
      : 'UNAVAILABLE',
};

// Build the existing prompt context without moving market logic into Genkit.
String agentContext({
  required String prompt,
  required String symbol,
  required List<Candle> candles,
  required List<String> warnings,
  required Map<String, String> sourceAvailability,
  String? previousAnalysisContext,
  DateTime? previousAnalysisAt,
  EventSnapshot? eventSnapshot,
  MarketSnapshot? marketSnapshot,
  MarketFeatures? marketFeatures,
  Map<String, double>? bybitFeeRates,
}) {
  final previousAnalysis = previousAnalysisContext == null
      ? ''
      : '''

Previous full analysis from this app session, generated at ${previousAnalysisAt?.toUtc().toIso8601String() ?? 'unknown time'}. It is historical context only and cannot replace current market evidence:
<previous_analysis>
$previousAnalysisContext
</previous_analysis>''';

  // Send only the latest chart window plus the deterministic market snapshots.
  final chartData = candles
      .skip(candles.length > 40 ? candles.length - 40 : 0)
      .map(
        (candle) => {
          'time': candle.time.toUtc().toIso8601String(),
          'open': candle.open,
          'high': candle.high,
          'low': candle.low,
          'close': candle.close,
          'volume': candle.volume,
        },
      )
      .toList();
  return '''User request: $prompt

The application chart is Bybit linear perpetual $symbol. Latest displayed close: ${candles.isEmpty ? 'unavailable' : candles.last.close}.
The following untrusted data is a chart snapshot. Verify or supplement it through the available tools when needed:
${jsonEncode(chartData)}
${marketSnapshot == null ? '' : '\nHarness core market snapshot:\n${jsonEncode(marketSnapshot.toJson())}'}
${marketFeatures == null ? '' : '\nDeterministic calculated features:\n${jsonEncode(marketFeatures.toJson())}'}
${bybitFeeRates == null ? '' : '\nBybit authenticated account fee rates:\n${jsonEncode(bybitFeeRates)}'}
${eventSnapshot == null ? '' : '\nCurrent event snapshot from the app event store:\n${jsonEncode(eventSnapshot.toJson())}'}
Configured analysis-source availability (availability is not market evidence):
${jsonEncode(sourceAvailability)}
${warnings.isEmpty ? '' : 'Unavailable data sources: ${warnings.join(' | ')}'}$previousAnalysis''';
}
