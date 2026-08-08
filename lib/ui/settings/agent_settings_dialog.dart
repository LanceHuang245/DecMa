import 'dart:async';
import 'dart:math';

import 'package:fluent_ui/fluent_ui.dart';

import '../../models/trading_models.dart';
import '../../services/openai_codex_oauth.dart';
import '../../services/secure_key_store.dart';

class AgentSettingsDialog extends StatefulWidget {
  const AgentSettingsDialog({
    super.key,
    required this.llm,
    required this.mcp,
    required this.api,
    required this.keyStatus,
    required this.nodeAvailable,
    required this.onSave,
  });

  final LlmSettings llm;
  final McpSettings mcp;
  final ApiSettings api;
  final ApiKeyStatus keyStatus;
  final bool nodeAvailable;
  final Future<void> Function(
    LlmSettings llm,
    McpSettings mcp,
    ApiSettings api,
    ApiKeyUpdates apiKeys,
  )
  onSave;

  @override
  State<AgentSettingsDialog> createState() => _AgentSettingsDialogState();
}

class _AgentSettingsDialogState extends State<AgentSettingsDialog> {
  late LlmProvider _provider;
  late bool _useBybit;
  late bool _useNansen;
  late bool _useOpenWebSearch;
  late bool _useCoinalyze;
  late final TextEditingController _endpoint;
  late final TextEditingController _apiKey;
  late final TextEditingController _model;
  late final TextEditingController _nansenKey;
  late final TextEditingController _coinalyzeKey;
  late final String? _llmMask;
  late final String? _nansenMask;
  late final String? _coinalyzeMask;
  late final OpenAiCodexAuthService _codexAuth;
  List<String> _codexModels = const [];
  bool _codexConnected = false;
  bool _codexLoading = false;
  String? _codexError;
  bool _saving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _provider = widget.llm.provider;
    _codexConnected = widget.keyStatus.hasCodexOAuth;
    _useBybit = widget.nodeAvailable && widget.mcp.useBybit;
    _useNansen = widget.mcp.useNansen;
    _useOpenWebSearch = widget.nodeAvailable && widget.mcp.useOpenWebSearch;
    _useCoinalyze = widget.api.useCoinalyze;
    _endpoint = TextEditingController(text: widget.llm.endpoint);
    _llmMask = _newMask(widget.keyStatus.hasLlmKey);
    _apiKey = TextEditingController(text: _llmMask);
    _model = TextEditingController(text: widget.llm.model);
    _nansenMask = _newMask(widget.keyStatus.hasNansenKey);
    _nansenKey = TextEditingController(text: _nansenMask);
    _coinalyzeMask = _newMask(widget.keyStatus.hasCoinalyzeKey);
    _coinalyzeKey = TextEditingController(text: _coinalyzeMask);
    _codexAuth = OpenAiCodexAuthService();
    if (_provider == LlmProvider.openAiCodex && _codexConnected) {
      unawaited(_loadCodexModels());
    }
  }

  @override
  void dispose() {
    _endpoint.dispose();
    _apiKey.dispose();
    _model.dispose();
    _nansenKey.dispose();
    _coinalyzeKey.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      title: const Text('Agent 设置'),
      // Override Fluent's 368 px dialog default so the two settings columns fit.
      constraints: const BoxConstraints(maxWidth: 1040),
      content: SizedBox(
        width: 960,
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
                    if (provider == LlmProvider.openAiCodex &&
                        _codexConnected) {
                      unawaited(_loadCodexModels());
                    }
                  },
                ),
              ),
              const SizedBox(height: 8),
              if (_provider == LlmProvider.openAiCodex)
                _buildCodexSettings()
              else ...[
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
              ],
              const SizedBox(height: 20),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'MCP',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 6),
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
                                ? (value) =>
                                      setState(() => _useOpenWebSearch = value)
                                : null,
                          ),
                          const SizedBox(height: 8),
                          ToggleSwitch(
                            checked: _useNansen,
                            content: const Text('Nansen MCP'),
                            onChanged: (value) =>
                                setState(() => _useNansen = value),
                          ),
                          if (_useNansen) ...[
                            const SizedBox(height: 6),
                            InfoLabel(
                              label: 'Nansen API Key',
                              child: TextBox(
                                controller: _nansenKey,
                                obscureText: true,
                                placeholder: '输入新密钥以加密保存',
                                onTap: () =>
                                    _selectMask(_nansenKey, _nansenMask),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 20),
                    Container(width: 1, color: Colors.grey),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'API',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 6),
                          ToggleSwitch(
                            checked: _useCoinalyze,
                            content: const Text('Coinalyze'),
                            onChanged: (value) =>
                                setState(() => _useCoinalyze = value),
                          ),
                          if (_useCoinalyze) ...[
                            const SizedBox(height: 6),
                            InfoLabel(
                              label: 'Coinalyze API Key',
                              child: TextBox(
                                controller: _coinalyzeKey,
                                obscureText: true,
                                placeholder: '输入新密钥以加密保存',
                                onTap: () =>
                                    _selectMask(_coinalyzeKey, _coinalyzeMask),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
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

  Widget _buildCodexSettings() {
    final models = {
      ..._codexModels,
      if (_model.text.trim().isNotEmpty) _model.text.trim(),
    }.toList()..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _codexConnected
                    ? '已登录 ChatGPT，使用 Codex 订阅额度。'
                    : '通过 ChatGPT 登录以使用 Codex。',
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: _codexLoading ? null : _signInToCodex,
              child: Text(
                _codexLoading
                    ? '正在连接…'
                    : _codexConnected
                    ? '重新登录'
                    : '登录 ChatGPT',
              ),
            ),
          ],
        ),
        if (_codexConnected) ...[
          const SizedBox(height: 8),
          InfoLabel(
            label: 'Model',
            child: ComboBox<String>(
              value: _model.text.trim().isEmpty ? null : _model.text.trim(),
              isExpanded: true,
              placeholder: const Text('正在获取可用模型'),
              items: [
                for (final model in models)
                  ComboBoxItem(value: model, child: Text(model)),
              ],
              onChanged: models.isEmpty
                  ? null
                  : (model) => setState(() => _model.text = model ?? ''),
            ),
          ),
        ],
        if (_codexError != null) ...[
          const SizedBox(height: 6),
          Text(
            _codexError!,
            style: const TextStyle(color: Colors.errorPrimaryColor),
          ),
        ],
      ],
    );
  }

  Future<void> _signInToCodex() async {
    setState(() {
      _codexLoading = true;
      _codexError = null;
    });
    try {
      final models = await _codexAuth.signIn();
      if (!mounted) return;
      setState(() {
        _codexConnected = true;
        _codexModels = models;
        _endpoint.text = LlmProvider.openAiCodex.defaultEndpoint;
        if (models.isNotEmpty && !models.contains(_model.text.trim())) {
          _model.text = models.first;
        }
      });
    } catch (error) {
      if (mounted) setState(() => _codexError = 'OpenAI Codex 登录失败：$error');
    } finally {
      if (mounted) setState(() => _codexLoading = false);
    }
  }

  Future<void> _loadCodexModels() async {
    if (_codexLoading) return;
    setState(() {
      _codexLoading = true;
      _codexError = null;
    });
    try {
      final models = await _codexAuth.fetchModels();
      if (mounted) {
        setState(() {
          _codexModels = models;
          if (models.isNotEmpty && !models.contains(_model.text.trim())) {
            _model.text = models.first;
          }
        });
      }
    } catch (_) {
      // A cached OAuth session can still be refreshed when the Agent runs.
    } finally {
      if (mounted) setState(() => _codexLoading = false);
    }
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
          useNansen: _useNansen,
          useOpenWebSearch: _useOpenWebSearch,
        ),
        ApiSettings(useCoinalyze: _useCoinalyze),
        ApiKeyUpdates(
          llmKey: _newKey(_apiKey, _llmMask),
          nansenKey: _newKey(_nansenKey, _nansenMask),
          coinalyzeKey: _newKey(_coinalyzeKey, _coinalyzeMask),
        ),
      );
      _apiKey.clear();
      _nansenKey.clear();
      _coinalyzeKey.clear();
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _saveError = '安全存储失败：$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
