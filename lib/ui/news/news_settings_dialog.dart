import 'package:fluent_ui/fluent_ui.dart';

import '../../models/trading_models.dart';
import '../../services/secure_key_store.dart';
import '../../utils/secret_mask.dart';

class NewsSettingsDialog extends StatefulWidget {
  const NewsSettingsDialog({
    super.key,
    required this.settings,
    required this.keyStatus,
    required this.onSave,
  });

  final NewsSettings settings;
  final ApiKeyStatus keyStatus;
  final Future<void> Function(NewsSettings settings, ApiKeyUpdates keys) onSave;

  @override
  State<NewsSettingsDialog> createState() => _NewsSettingsDialogState();
}

class _NewsSettingsDialogState extends State<NewsSettingsDialog> {
  late bool _useFinnhub;
  late bool _useBls;
  late bool _useBea;
  late bool _useFederalReserve;
  late final String? _finnhubMask;
  late final TextEditingController _finnhubKey;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _useFinnhub = widget.settings.useFinnhub;
    _useBls = widget.settings.useBls;
    _useBea = widget.settings.useBea;
    _useFederalReserve = widget.settings.useFederalReserve;
    _finnhubMask = createSecretMask(widget.keyStatus.hasFinnhubKey);
    _finnhubKey = TextEditingController(text: _finnhubMask);
  }

  @override
  void dispose() {
    _finnhubKey.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ContentDialog(
    title: const Text('Market News 设置'),
    content: SizedBox(
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ToggleSwitch(
            checked: _useFinnhub,
            content: const Text('Finnhub Market News'),
            onChanged: (value) => setState(() => _useFinnhub = value),
          ),
          if (_useFinnhub) ...[
            const SizedBox(height: 8),
            InfoLabel(
              label: 'Finnhub API Key',
              child: TextBox(
                controller: _finnhubKey,
                obscureText: true,
                placeholder: '输入新密钥以加密保存',
                onTap: _selectMask,
              ),
            ),
          ],
          const SizedBox(height: 12),
          const Text('官方数据源', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          ToggleSwitch(
            checked: _useBls,
            content: const Text('BLS'),
            onChanged: (value) => setState(() => _useBls = value),
          ),
          const SizedBox(height: 6),
          ToggleSwitch(
            checked: _useBea,
            content: const Text('BEA'),
            onChanged: (value) => setState(() => _useBea = value),
          ),
          const SizedBox(height: 6),
          ToggleSwitch(
            checked: _useFederalReserve,
            content: const Text('Federal Reserve'),
            onChanged: (value) => setState(() => _useFederalReserve = value),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: const TextStyle(color: Colors.errorPrimaryColor),
            ),
          ],
        ],
      ),
    ),
    actions: [
      Button(onPressed: () => Navigator.pop(context), child: const Text('取消')),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: Text(_saving ? '保存中…' : '保存'),
      ),
    ],
  );

  void _selectMask() {
    if (_finnhubMask == null || _finnhubKey.text != _finnhubMask) return;
    _finnhubKey.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _finnhubKey.text.length,
    );
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final key = _finnhubKey.text.trim();
      await widget.onSave(
        NewsSettings(
          useFinnhub: _useFinnhub,
          useBls: _useBls,
          useBea: _useBea,
          useFederalReserve: _useFederalReserve,
        ),
        ApiKeyUpdates(
          finnhubKey: key.isEmpty || key == _finnhubMask ? null : key,
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _error = '安全存储失败：$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
