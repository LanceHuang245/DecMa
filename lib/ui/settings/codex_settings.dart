import 'package:dio/dio.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../../data/services/openai_codex_oauth.dart';
import '../../utils/network.dart';

// Own OAuth requests separately from the connection being edited.
class CodexSettings extends StatefulWidget {
  const CodexSettings({
    super.key,
    required this.connected,
    required this.onConnected,
    this.auth,
  });
  final bool connected;
  final VoidCallback onConnected;
  final OpenAiCodexAuthService? auth;
  @override
  State<CodexSettings> createState() => _CodexSettingsState();
}

class _CodexSettingsState extends State<CodexSettings> {
  late final _auth = widget.auth ?? OpenAiCodexAuthService();
  late bool _connected = widget.connected;
  final _cancel = CancelToken();
  bool _loading = false;
  String? _error;

  // Login stays in settings; model catalogs are loaded by the home selector.
  Future<void> _signIn() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _auth.signIn(cancelToken: _cancel);
      if (!mounted || _cancel.isCancelled) return;
      setState(() => _connected = true);
      widget.onConnected();
    } catch (error) {
      if (mounted && !_cancel.isCancelled && !isRequestCancelled(error)) {
        setState(() => _error = 'OpenAI Codex 登录失败：$error');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
            FilledButton(
              onPressed: _loading ? null : _signIn,
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
