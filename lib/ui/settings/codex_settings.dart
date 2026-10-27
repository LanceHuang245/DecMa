import 'package:dio/dio.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../../data/services/openai_codex_oauth.dart';
import '../../utils/network.dart';
import '../../l10n/generated/app_localizations.dart';

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
        setState(
          () => _error = AppLocalizations.of(context).codexLoginFailed(error),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(_connected ? loc.codexSignedIn : loc.codexSignInHint),
            ),
            FilledButton(
              onPressed: _loading ? null : _signIn,
              child: Text(
                _loading
                    ? loc.connecting
                    : _connected
                    ? loc.signInAgain
                    : loc.signInChatGpt,
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
