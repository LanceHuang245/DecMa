import 'package:fluent_ui/fluent_ui.dart';

import '../../models/trading_models.dart';
import '../chart/candle_chart.dart';

class DashboardChartPanel extends StatelessWidget {
  const DashboardChartPanel({
    super.key,
    required this.symbolController,
    required this.symbols,
    required this.interval,
    required this.activeSymbol,
    required this.candles,
    required this.plan,
    required this.showWaitZone,
    required this.chartVersion,
    required this.error,
    required this.loading,
    required this.loadingChart,
    required this.onSymbolSelected,
    required this.onIntervalChanged,
    required this.onRetry,
  });

  final TextEditingController symbolController;
  final List<String> symbols;
  final String interval;
  final String activeSymbol;
  final List<Candle> candles;
  final TradePlan? plan;
  final bool showWaitZone;
  final int chartVersion;
  final String? error;
  final bool loading;
  final bool loadingChart;
  final ValueChanged<String> onSymbolSelected;
  final ValueChanged<String> onIntervalChanged;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
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
                width: 210,
                child: AutoSuggestBox<String>(
                  controller: symbolController,
                  placeholder: '搜索代币，例如 BTC',
                  items: symbols
                      .map(
                        (symbol) => AutoSuggestBoxItem<String>(
                          value: symbol,
                          label: symbol,
                        ),
                      )
                      .toList(),
                  sorter: _sortSymbols,
                  onSelected: (item) {
                    final symbol = item.value;
                    if (symbol != null) onSymbolSelected(symbol);
                  },
                ),
              ),
              SizedBox(
                width: 92,
                child: ComboBox<String>(
                  value: interval,
                  isExpanded: true,
                  items: const [
                    ComboBoxItem(value: '1', child: Text('1m')),
                    ComboBoxItem(value: '5', child: Text('5m')),
                    ComboBoxItem(value: '15', child: Text('15m')),
                    ComboBoxItem(value: '60', child: Text('1h')),
                    ComboBoxItem(value: '240', child: Text('4h')),
                    ComboBoxItem(value: 'D', child: Text('1D')),
                  ],
                  onChanged: (value) {
                    if (value != null && value != interval) {
                      onIntervalChanged(value);
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: CandleChart(
              // Reset zoom only after a complete history load succeeds.
              key: ValueKey(chartVersion),
              candles: candles,
              plan: plan,
              showWaitZone: showWaitZone,
              error: error,
              loading: loading,
              onRetry: loadingChart ? null : onRetry,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _ChartLegend(color: Colors.blue, text: '开仓区'),
              const SizedBox(width: 14),
              _ChartLegend(color: Colors.red, text: '止损'),
              const SizedBox(width: 14),
              _ChartLegend(color: Colors.green, text: '止盈'),
            ],
          ),
        ],
      ),
    );
  }

  // Keep contract matching with the chart UI because it is presentation-only.
  static List<AutoSuggestBoxItem<String>> _sortSymbols(
    String text,
    List<AutoSuggestBoxItem<String>> items,
  ) {
    final query = text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (query.length < 2) return const [];
    final matches = items.where((item) {
      final symbol = item.value ?? '';
      return symbol.contains(query) || _isSubsequence(query, symbol);
    }).toList();
    matches.sort((left, right) {
      final leftSymbol = left.value ?? '';
      final rightSymbol = right.value ?? '';
      return _matchScore(
        query,
        leftSymbol,
      ).compareTo(_matchScore(query, rightSymbol));
    });
    return matches;
  }

  static bool _isSubsequence(String query, String symbol) {
    var queryIndex = 0;
    for (final char in symbol.split('')) {
      if (queryIndex < query.length && char == query[queryIndex]) queryIndex++;
    }
    return queryIndex == query.length;
  }

  static int _matchScore(String query, String symbol) =>
      symbol.startsWith(query)
      ? 0
      : symbol.contains(query)
      ? 1
      : 2;
}

class _ChartLegend extends StatelessWidget {
  const _ChartLegend({required this.color, required this.text});

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 10, height: 10, color: color),
      const SizedBox(width: 4),
      Text(text, style: const TextStyle(fontSize: 12)),
    ],
  );
}
