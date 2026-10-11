import 'dart:async';

import 'package:dio/dio.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../../services/openai_codex_oauth.dart';
import '../../utils/network.dart';

// Own OAuth/catalog requests separately from the connection being edited.
class CodexSettings extends StatefulWidget {
  const CodexSettings({
    super.key,
    required this.connected,
    required this.model,
    required this.onConnected,
    this.auth,
  });
  final bool connected;
  final TextEditingController model;
  final VoidCallback onConnected;
  final OpenAiCodexAuthService? auth;
  @override
  State<CodexSettings> createState() => _CodexSettingsState();
}

class _CodexSettingsState extends State<CodexSettings> {
  late final _auth = widget.auth ?? OpenAiCodexAuthService();
  late bool _connected = widget.connected;
  final _cancel = CancelToken();
  List<String> _models = const [];
  bool _loading = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    if (_connected) unawaited(_load());
  }

  // Removing this keyed widget prevents catalog results touching a new editor.
  Future<void> _load({bool signIn = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final models = signIn
          ? await _auth.signIn(cancelToken: _cancel)
          : await _auth.fetchModels(cancelToken: _cancel);
      if (!mounted || _cancel.isCancelled) return;
      setState(() {
        _models = models;
        if (signIn) _connected = true;
        if (models.isNotEmpty && !models.contains(widget.model.text.trim())) {
          widget.model.text = models.first;
        }
      });
      if (signIn) widget.onConnected();
    } catch (error) {
      if (mounted && !_cancel.isCancelled && !isRequestCancelled(error)) {
        setState(
          () => _error = 'OpenAI Codex ${signIn ? '登录' : '模型获取'}失败：$error',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Preserve sign-in, refresh and model selection controls without shared async state.
  @override
  Widget build(BuildContext context) {
    final models = {
      ..._models,
      if (widget.model.text.trim().isNotEmpty) widget.model.text.trim(),
    }.toList()..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _connected
                    ? '已登录 ChatGPT，使用 Codex 订阅额度。'
                    : '通过 ChatGPT 登录以使用 Codex。',
              ),
            ),
            if (_connected) ...[
              Button(
                onPressed: _loading ? null : _load,
                child: const Text('重新获取模型列表'),
              ),
              const SizedBox(width: 12),
            ],
            FilledButton(
              onPressed: _loading ? null : () => _load(signIn: true),
              child: Text(
                _loading
                    ? '正在连接…'
                    : _connected
                    ? '重新登录'
                    : '登录 ChatGPT',
              ),
            ),
          ],
        ),
        if (_connected) ...[
          const SizedBox(height: 8),
          InfoLabel(
            label: 'Model',
            child: ComboBox<String>(
              value: widget.model.text.trim().isEmpty
                  ? null
                  : widget.model.text.trim(),
              isExpanded: true,
              placeholder: const Text('正在获取可用模型'),
              items: [
                for (final model in models)
                  ComboBoxItem(value: model, child: Text(model)),
              ],
              onChanged: models.isEmpty
                  ? null
                  : (model) => setState(() => widget.model.text = model ?? ''),
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 6),
          Text(
            _error!,
            style: const TextStyle(color: Colors.errorPrimaryColor),
          ),
        ],
      ],
    );
  }

  // Cancel network and localhost callback work before disposing the editor.
  @override
  void dispose() {
    _cancel.cancel();
    if (widget.auth == null) _auth.dispose();
    super.dispose();
  }
}
