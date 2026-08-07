import 'dart:math';

import 'package:fluent_ui/fluent_ui.dart';

import '../models/trading_models.dart';
import '../services/secure_key_store.dart';

class AgentSettingsDialog extends StatefulWidget {
  const AgentSettingsDialog({
    super.key,
    required this.llm,
    required this.mcp,
    required this.keyStatus,
    required this.nodeAvailable,
    required this.onSave,
  });

  final LlmSettings llm;
  final McpSettings mcp;
  final ApiKeyStatus keyStatus;
  final bool nodeAvailable;
  final Future<void> Function(
    LlmSettings llm,
    McpSettings mcp,
    ApiKeyUpdates apiKeys,
  )
  onSave;

  @override
  State<AgentSettingsDialog> createState() => _AgentSettingsDialogState();
}

class _AgentSettingsDialogState extends State<AgentSettingsDialog> {
  late LlmProvider _provider;
  late bool _useBybit;
  late bool _useCoinglass;
  late bool _useNansen;
  late bool _useOpenWebSearch;
  late final TextEditingController _endpoint;
  late final TextEditingController _apiKey;
  late final TextEditingController _model;
  late final TextEditingController _coinglassKey;
  late final TextEditingController _nansenKey;
  late final String? _llmMask;
  late final String? _coinglassMask;
  late final String? _nansenMask;
  bool _saving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _provider = widget.llm.provider;
    _useBybit = widget.nodeAvailable && widget.mcp.useBybit;
    _useCoinglass = widget.mcp.useCoinglass;
    _useNansen = widget.mcp.useNansen;
    _useOpenWebSearch = widget.nodeAvailable && widget.mcp.useOpenWebSearch;
    _endpoint = TextEditingController(text: widget.llm.endpoint);
    _llmMask = _newMask(widget.keyStatus.hasLlmKey);
    _apiKey = TextEditingController(text: _llmMask);
    _model = TextEditingController(text: widget.llm.model);
    _coinglassMask = _newMask(widget.keyStatus.hasCoinGlassKey);
    _coinglassKey = TextEditingController(text: _coinglassMask);
    _nansenMask = _newMask(widget.keyStatus.hasNansenKey);
    _nansenKey = TextEditingController(text: _nansenMask);
  }

  @override
  void dispose() {
    _endpoint.dispose();
    _apiKey.dispose();
    _model.dispose();
    _coinglassKey.dispose();
    _nansenKey.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      title: const Text('Agent 设置'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'LLM 连接',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              InfoLabel(
                label: '接口类型',
                child: ComboBox<LlmProvider>(
                  value: _provider,
                  isExpanded: true,
                  items: [
                    for (final provider in LlmProvider.values)
                      ComboBoxItem(
                        value: provider,
                        child: Text(provider.label),
                      ),
                  ],
                  onChanged: (provider) {
                    if (provider == null) return;
                    setState(() {
                      if (_endpoint.text.trim() == _provider.defaultEndpoint) {
                        _endpoint.text = provider.defaultEndpoint;
                      }
                      _provider = provider;
                    });
                  },
                ),
              ),
              const SizedBox(height: 8),
              InfoLabel(
                label: 'Endpoint',
                child: TextBox(controller: _endpoint),
              ),
              const SizedBox(height: 8),
              InfoLabel(
                label: 'Model',
                child: TextBox(controller: _model),
              ),
              const SizedBox(height: 8),
              InfoLabel(
                label: 'LLM API Key',
                child: TextBox(
                  controller: _apiKey,
                  obscureText: true,
                  placeholder: '输入新密钥以加密保存',
                  onTap: () => _selectMask(_apiKey, _llmMask),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                '内置数据 MCP',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              const Text(
                'API Key 使用系统加密凭据存储。Bybit 仅以无凭据模式启动。',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 10),
              ToggleSwitch(
                checked: _useBybit,
                content: const Text('Bybit MCP'),
                onChanged: widget.nodeAvailable
                    ? (value) => setState(() => _useBybit = value)
                    : null,
              ),
              const SizedBox(height: 8),
              ToggleSwitch(
                checked: _useOpenWebSearch,
                content: const Text('OpenWebSearch MCP'),
                onChanged: widget.nodeAvailable
                    ? (value) => setState(() => _useOpenWebSearch = value)
                    : null,
              ),
              const SizedBox(height: 8),
              ToggleSwitch(
                checked: _useCoinglass,
                content: const Text('CoinGlass MCP'),
                onChanged: (value) => setState(() => _useCoinglass = value),
              ),
              if (_useCoinglass) ...[
                const SizedBox(height: 6),
                InfoLabel(
                  label: 'CoinGlass API Key',
                  child: TextBox(
                    controller: _coinglassKey,
                    obscureText: true,
                    placeholder: '输入新密钥以加密保存',
                    onTap: () => _selectMask(_coinglassKey, _coinglassMask),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              ToggleSwitch(
                checked: _useNansen,
                content: const Text('Nansen MCP'),
                onChanged: (value) => setState(() => _useNansen = value),
              ),
              if (_useNansen) ...[
                const SizedBox(height: 6),
                InfoLabel(
                  label: 'Nansen API Key',
                  child: TextBox(
                    controller: _nansenKey,
                    obscureText: true,
                    placeholder: '输入新密钥以加密保存',
                    onTap: () => _selectMask(_nansenKey, _nansenMask),
                  ),
                ),
              ],
              if (_saveError != null) ...[
                const SizedBox(height: 10),
                Text(
                  _saveError!,
                  style: const TextStyle(color: Colors.errorPrimaryColor),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        Button(
          child: const Text('取消'),
          onPressed: () => Navigator.pop(context),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? '保存中…' : '保存'),
        ),
      ],
    );
  }

  String? _newKey(TextEditingController controller, String? mask) {
    final value = controller.text.trim();
    return value.isEmpty || value == mask ? null : value;
  }

  void _selectMask(TextEditingController controller, String? mask) {
    if (mask == null || controller.text != mask) return;
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );
  }

  // The random text is only a visual mask and is never persisted as a key.
  String? _newMask(bool hasSavedKey) {
    if (!hasSavedKey) return null;
    const characters = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random.secure();
    return List.generate(
      24,
      (_) => characters[random.nextInt(characters.length)],
    ).join();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await widget.onSave(
        LlmSettings(
          provider: _provider,
          endpoint: _endpoint.text.trim(),
          model: _model.text.trim(),
        ),
        McpSettings(
          useBybit: _useBybit,
          useCoinglass: _useCoinglass,
          useNansen: _useNansen,
          useOpenWebSearch: _useOpenWebSearch,
        ),
        ApiKeyUpdates(
          llmKey: _newKey(_apiKey, _llmMask),
          coinGlassKey: _newKey(_coinglassKey, _coinglassMask),
          nansenKey: _newKey(_nansenKey, _nansenMask),
        ),
      );
      _apiKey.clear();
      _coinglassKey.clear();
      _nansenKey.clear();
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _saveError = '安全存储失败：$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
