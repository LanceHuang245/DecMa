import 'package:fluent_ui/fluent_ui.dart';

import '../../app_constants.dart';
import '../../models/trading_models.dart';
import '../../services/secure_key_store.dart';
import 'package:decma/utils/display_formatters.dart';
import '../core/documentation_help_label.dart';

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
  late bool _useMarketaux;
  late bool _useBls;
  late bool _useBea;
  late bool _useFederalReserve;
  late final String? _finnhubMask;
  late final String? _marketauxMask;
  late final TextEditingController _finnhubKey;
  late final TextEditingController _marketauxKey;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _useFinnhub = widget.settings.useFinnhub;
    _useMarketaux = widget.settings.useMarketaux;
    _useBls = widget.settings.useBls;
    _useBea = widget.settings.useBea;
    _useFederalReserve = widget.settings.useFederalReserve;
    _finnhubMask = createSecretMask(widget.keyStatus.hasFinnhubKey);
    _marketauxMask = createSecretMask(widget.keyStatus.hasMarketauxKey);
    _finnhubKey = TextEditingController(text: _finnhubMask);
    _marketauxKey = TextEditingController(text: _marketauxMask);
  }

  @override
  void dispose() {
    _finnhubKey.dispose();
    _marketauxKey.dispose();
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
            content: const DocumentationHelpLabel(
              label: 'Finnhub Market News',
              tooltip: '查看 Finnhub Market News 文档',
              documentationUrl: AppConstants.finnhubDocumentationUrl,
            ),
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
                onTap: () => _selectMask(_finnhubKey, _finnhubMask),
              ),
            ),
          ],
          const SizedBox(height: 12),
          ToggleSwitch(
            checked: _useMarketaux,
            content: const DocumentationHelpLabel(
              label: 'Marketaux Token News',
              tooltip: '查看 Marketaux API 文档',
              documentationUrl: AppConstants.marketauxDocumentationUrl,
            ),
            onChanged: (value) => setState(() => _useMarketaux = value),
          ),
          if (_useMarketaux) ...[
            const SizedBox(height: 8),
            InfoLabel(
              label: 'Marketaux API Key',
              child: TextBox(
                controller: _marketauxKey,
                obscureText: true,
                placeholder: '输入新密钥以加密保存',
                onTap: () => _selectMask(_marketauxKey, _marketauxMask),
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

  void _selectMask(TextEditingController controller, String? mask) {
    if (mask == null || controller.text != mask) return;
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
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
          useMarketaux: _useMarketaux,
          useBls: _useBls,
          useBea: _useBea,
          useFederalReserve: _useFederalReserve,
        ),
        ApiKeyUpdates(
          finnhubKey: key.isEmpty || key == _finnhubMask ? null : key,
          marketauxKey: _savedKey(_marketauxKey, _marketauxMask),
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _error = '安全存储失败：$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _savedKey(TextEditingController controller, String? mask) {
    final value = controller.text.trim();
    return value.isEmpty || value == mask ? null : value;
  }
}
