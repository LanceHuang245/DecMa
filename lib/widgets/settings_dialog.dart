import 'package:fluent_ui/fluent_ui.dart';

import '../models/trading_models.dart';

class AgentSettingsDialog extends StatefulWidget {
  const AgentSettingsDialog({
    super.key,
    required this.llm,
    required this.mcp,
    required this.onSave,
  });

  final LlmSettings llm;
  final McpSettings mcp;
  final void Function(LlmSettings llm, McpSettings mcp) onSave;

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

  @override
  void initState() {
    super.initState();
    _provider = widget.llm.provider;
    _useBybit = widget.mcp.useBybit;
    _useCoinglass = widget.mcp.useCoinglass;
    _useNansen = widget.mcp.useNansen;
    _useOpenWebSearch = widget.mcp.useOpenWebSearch;
    _endpoint = TextEditingController(text: widget.llm.endpoint);
    _apiKey = TextEditingController(text: widget.llm.apiKey);
    _model = TextEditingController(text: widget.llm.model);
    _coinglassKey = TextEditingController(text: widget.mcp.coinglassKey);
    _nansenKey = TextEditingController(text: widget.mcp.nansenKey);
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
                label: 'Endpoint（Anthropic 填完整 Messages URL；OpenAI 填 Base URL）',
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
                child: TextBox(controller: _apiKey, obscureText: true),
              ),
              const SizedBox(height: 20),
              const Text(
                '内置数据 MCP',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              const Text(
                '密钥仅保留在当前应用内存中，关闭应用即清除。Bybit 仅以无凭据模式启动。',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 10),
              ToggleSwitch(
                checked: _useBybit,
                content: const Text('Bybit MCP（需要本机 Node.js / npx）'),
                onChanged: (value) => setState(() => _useBybit = value),
              ),
              const SizedBox(height: 8),
              ToggleSwitch(
                checked: _useOpenWebSearch,
                content: const Text('OpenWebSearch MCP（需要本机 Node.js / npx）'),
                onChanged: (value) => setState(() => _useOpenWebSearch = value),
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
                  child: TextBox(controller: _coinglassKey, obscureText: true),
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
                  child: TextBox(controller: _nansenKey, obscureText: true),
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
          child: const Text('保存'),
          onPressed: () {
            // Keep user secrets in memory only; no project file is written.
            widget.onSave(
              LlmSettings(
                provider: _provider,
                endpoint: _endpoint.text.trim(),
                apiKey: _apiKey.text.trim(),
                model: _model.text.trim(),
              ),
              McpSettings(
                useBybit: _useBybit,
                useCoinglass: _useCoinglass,
                coinglassKey: _coinglassKey.text.trim(),
                useNansen: _useNansen,
                nansenKey: _nansenKey.text.trim(),
                useOpenWebSearch: _useOpenWebSearch,
              ),
            );
            Navigator.pop(context);
          },
        ),
      ],
    );
  }
}
