import 'package:fluent_ui/fluent_ui.dart';

import '../../models/analysis_risk_profile.dart';

class QuickAnalysisDialog extends StatefulWidget {
  const QuickAnalysisDialog({
    super.key,
    required this.symbol,
    required this.onConfirm,
  });

  final String symbol;
  final void Function({
    required String analysisPlan,
    required AnalysisRiskProfile riskProfile,
    required String currentPosition,
    required String currentPositionSize,
    required String currentPositionEntryPrice,
  })
  onConfirm;

  @override
  State<QuickAnalysisDialog> createState() => _QuickAnalysisDialogState();
}

class _QuickAnalysisDialogState extends State<QuickAnalysisDialog> {
  var _analysisPlan = '标准';
  final _tradeWindow = TextEditingController();
  final _accountBalance = TextEditingController();
  final _maxLoss = TextEditingController();
  final _plannedPosition = TextEditingController();
  final _expectedSlippage = TextEditingController();
  final _safetyBuffer = TextEditingController();
  final _minimumNetRewardRisk = TextEditingController();
  final _maximumEffectiveLeverage = TextEditingController();
  final _currentPositionSize = TextEditingController();
  final _currentPositionEntryPrice = TextEditingController();
  var _currentPosition = '无';

  @override
  void dispose() {
    _tradeWindow.dispose();
    _accountBalance.dispose();
    _maxLoss.dispose();
    _plannedPosition.dispose();
    _expectedSlippage.dispose();
    _safetyBuffer.dispose();
    _minimumNetRewardRisk.dispose();
    _maximumEffectiveLeverage.dispose();
    _currentPositionSize.dispose();
    _currentPositionEntryPrice.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ContentDialog(
    title: Text('分析 ${widget.symbol}'),
    constraints: const BoxConstraints(maxWidth: 520),
    content: SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _analysisPlanField(),
            _field('交易完成时限', '例如：3 小时', _tradeWindow),
            _field('账户资金', '例如：1,000 USDT', _accountBalance),
            _field('单笔最大可接受亏损', '例如：20 USDT 或 2%', _maxLoss),
            _field('计划开仓数量', '币数量或 USDT 名义价值', _plannedPosition),
            Expander(
              header: const Text('可选执行风险参数'),
              content: Column(
                children: [
                  _field('预期单边滑点', '例如：0.05%', _expectedSlippage),
                  _field('安全缓冲', '例如：0.1%', _safetyBuffer),
                  _field('最低净风险收益比', '例如：1.5', _minimumNetRewardRisk),
                  _field('最大有效杠杆', '例如：3x', _maximumEffectiveLeverage),
                ],
              ),
            ),
            _positionField(),
            if (_currentPosition != '无') ...[
              _field('当前持仓数量', '例如：0.1', _currentPositionSize),
              _field('当前持仓均价', '例如：100,000', _currentPositionEntryPrice),
            ],
          ],
        ),
      ),
    ),
    actions: [
      Button(onPressed: () => Navigator.pop(context), child: const Text('取消')),
      FilledButton(onPressed: _confirm, child: const Text('确认分析')),
    ],
  );

  Widget _field(
    String label,
    String placeholder,
    TextEditingController controller,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        const SizedBox(height: 4),
        TextBox(controller: controller, placeholder: placeholder),
      ],
    ),
  );

  Widget _analysisPlanField() => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('分析方案'),
        const SizedBox(height: 4),
        ComboBox<String>(
          value: _analysisPlan,
          isExpanded: true,
          items: const [
            ComboBoxItem(value: '标准', child: Text('标准')),
            ComboBoxItem(value: '激进', child: Text('激进')),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() => _analysisPlan = value);
          },
        ),
      ],
    ),
  );

  Widget _positionField() => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('当前持仓'),
        const SizedBox(height: 4),
        ComboBox<String>(
          value: _currentPosition,
          isExpanded: true,
          items: const [
            ComboBoxItem(value: '无', child: Text('无')),
            ComboBoxItem(value: '多', child: Text('多')),
            ComboBoxItem(value: '空', child: Text('空')),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() {
              _currentPosition = value;
              if (value == '无') {
                // Clear hidden values so a later confirmation cannot reuse them.
                _currentPositionSize.clear();
                _currentPositionEntryPrice.clear();
              }
            });
          },
        ),
      ],
    ),
  );

  void _confirm() {
    // Normalize confirmed risk inputs once before handing them to analysis.
    final riskProfile = AnalysisRiskProfile.parse(
      accountEquity: _accountBalance.text,
      maximumLoss: _maxLoss.text,
      plannedPosition: _plannedPosition.text,
      tradeWindow: _tradeWindow.text,
      expectedSlippage: _expectedSlippage.text,
      safetyBuffer: _safetyBuffer.text,
      minimumNetRewardRisk: _minimumNetRewardRisk.text,
      maximumEffectiveLeverage: _maximumEffectiveLeverage.text,
    );
    widget.onConfirm(
      analysisPlan: _analysisPlan,
      riskProfile: riskProfile,
      currentPosition: _currentPosition,
      currentPositionSize: _currentPositionSize.text,
      currentPositionEntryPrice: _currentPositionEntryPrice.text,
    );
    Navigator.pop(context);
  }
}
