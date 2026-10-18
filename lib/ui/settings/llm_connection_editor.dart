import 'package:fluent_ui/fluent_ui.dart';

import '../../domain/models/app_settings.dart';
import '../../data/services/openai_codex_oauth.dart';
import '../../data/services/storage/secure_key_store.dart';
import '../../utils/display_formatters.dart';
import 'codex_settings.dart';

// Own the editable connection draft, leaving data-source settings to the dialog.
class LlmConnectionEditor extends StatefulWidget {
  const LlmConnectionEditor({
    super.key,
    required this.initial,
    required this.connections,
    required this.keys,
    this.codexAuth,
  });
  final LlmSettings initial;
  final LlmConnectionSettings connections;
  final ApiKeyStatus keys;
  final OpenAiCodexAuthService? codexAuth;
  @override
  State<LlmConnectionEditor> createState() => LlmConnectionEditorState();
}

class LlmConnectionEditorState extends State<LlmConnectionEditor> {
  late final List<LlmSettings> _connections = List.of(
    widget.connections.connections,
  );
  late String _id = widget.initial.id;
  late LlmProvider _provider = widget.initial.provider;
  late final _name = TextEditingController(text: widget.initial.name);
  late final _endpoint = TextEditingController(text: widget.initial.endpoint);
  late final _model = TextEditingController(text: widget.initial.model);
  late String? _mask = createSecretMask(widget.keys.hasLlmKeyFor(_id));
  late final _key = TextEditingController(text: _mask);
  late bool _codexConnected = widget.keys.hasCodexOAuth;

  // Validate and return the existing storage contract without another settings DTO.
  ({LlmConnectionSettings connections, String? apiKey}) readSettings() {
    final name = _name.text.trim();
    if (name.isEmpty) throw Exception('配置名称不能为空。');
    if (_connections.any((item) => item.id != _id && item.name == name)) {
      throw Exception('配置名称已存在。');
    }
    final connection = LlmSettings(
      id: _id,
      name: name,
      provider: _provider,
      endpoint: _endpoint.text.trim(),
      model: _model.text.trim(),
    );
    final key = _key.text.trim();
    return (
      connections: LlmConnectionSettings(
        connections: [
          for (final item in _connections) item.id == _id ? connection : item,
        ],
        activeConnectionId: _id,
      ),
      apiKey: key.isEmpty || key == _mask ? null : key,
    );
  }

  void clearSecret() => _key.clear();

  // Switching a connection replaces its draft and disposes its keyed OAuth view.
  void _select(String id) {
    final connection = _connections.firstWhere((item) => item.id == id);
    setState(() {
      _id = id;
      _provider = connection.provider;
      _name.text = connection.name;
      _endpoint.text = connection.endpoint;
      _model.text = connection.model;
      _mask = createSecretMask(widget.keys.hasLlmKeyFor(id));
      _key.text = _mask ?? '';
    });
  }

  void _create() {
    final connection = LlmSettings(
      id: 'connection-${DateTime.now().microsecondsSinceEpoch}',
      name: '新建配置',
      provider: LlmProvider.openAiResponses,
      endpoint: LlmProvider.openAiResponses.defaultEndpoint,
      model: 'gpt-4.1',
    );
    _connections.add(connection);
    _select(connection.id);
  }

  void _delete() {
    _connections.removeWhere((item) => item.id == _id);
    if (_connections.isEmpty) {
      _create();
    } else {
      _select(_connections.first.id);
    }
  }

  // Keep the original controls and default-endpoint behavior for all four providers.
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('LLM 连接', style: TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 10),
      Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: InfoLabel(
              label: '已保存的配置',
              child: ComboBox<String>(
                value: _id,
                isExpanded: true,
                items: [
                  for (final item in _connections)
                    ComboBoxItem(value: item.id, child: Text(item.name)),
                ],
                onChanged: (id) {
                  if (id != null && id != _id) _select(id);
                },
              ),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton(onPressed: _create, child: const Text('新建配置')),
          const SizedBox(width: 12),
          Button(onPressed: _delete, child: const Text('删除配置')),
        ],
      ),
      const SizedBox(height: 8),
      InfoLabel(
        label: '配置名称',
        child: TextBox(controller: _name),
      ),
      const SizedBox(height: 8),
      InfoLabel(
        label: '接口类型',
        child: ComboBox<LlmProvider>(
          value: _provider,
          isExpanded: true,
          items: [
            for (final provider in LlmProvider.values)
              ComboBoxItem(value: provider, child: Text(provider.label)),
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
      if (_provider == LlmProvider.openAiCodex)
        CodexSettings(
          key: ValueKey(_id),
          connected: _codexConnected,
          model: _model,
          auth: widget.codexAuth,
          onConnected: () => setState(() {
            _codexConnected = true;
            _endpoint.text = LlmProvider.openAiCodex.defaultEndpoint;
          }),
        )
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
            controller: _key,
            obscureText: true,
            placeholder: '输入新密钥以加密保存',
            onTap: () {
              if (_mask != null && _key.text == _mask) {
                _key.selection = TextSelection(
                  baseOffset: 0,
                  extentOffset: _key.text.length,
                );
              }
            },
          ),
        ),
      ],
    ],
  );

  // The editor owns only its text controllers; OAuth owns its own request lifetime.
  @override
  void dispose() {
    _name.dispose();
    _endpoint.dispose();
    _model.dispose();
    _key.dispose();
    super.dispose();
  }
}
