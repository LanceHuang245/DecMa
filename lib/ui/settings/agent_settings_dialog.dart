import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';

import '../../app_constants.dart';
import '../../domain/models/app_settings.dart';
import '../../data/services/openai_codex_oauth.dart';
import '../../data/services/storage/llm_settings_store.dart';
import '../../data/services/storage/secure_key_store.dart';
import '../../utils/display_formatters.dart';
import '../core/documentation_help_label.dart';
import 'llm_connection_editor.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../l10n/app_languages.dart';

// Coordinate one save while each editor owns its own draft/request state.
class AgentSettingsDialog extends StatefulWidget {
  const AgentSettingsDialog({
    super.key,
    required this.llm,
    required this.llmConnections,
    required this.mcp,
    required this.api,
    required this.keyStatus,
    required this.nodeAvailable,
    required this.onSave,
    this.codexAuth,
  });
  final LlmSettings llm;
  final LlmConnectionSettings llmConnections;
  final McpSettings mcp;
  final ApiSettings api;
  final ApiKeyStatus keyStatus;
  final bool nodeAvailable;
  final OpenAiCodexAuthService? codexAuth;
  final Future<void> Function(
    LlmConnectionSettings,
    McpSettings,
    ApiSettings,
    ApiKeyUpdates,
  )
  onSave;
  @override
  State<AgentSettingsDialog> createState() => _AgentSettingsDialogState();
}

class _AgentSettingsDialogState extends State<AgentSettingsDialog> {
  AppLocalizations get loc => AppLocalizations.of(context);
  final _llm = GlobalKey<LlmConnectionEditorState>();
  late bool _bybit = widget.nodeAvailable && widget.mcp.useBybit;
  late bool _nansen = widget.mcp.useNansen;
  late bool _search = widget.nodeAvailable && widget.mcp.useOpenWebSearch;
  late bool _coinalyze = widget.api.useCoinalyze;
  late final _bybitMask = createSecretMask(widget.keyStatus.hasBybitApiKey);
  late final _bybitSecretMask = createSecretMask(
    widget.keyStatus.hasBybitApiSecret,
  );
  late final _nansenMask = createSecretMask(widget.keyStatus.hasNansenKey);
  late final _coinalyzeMask = createSecretMask(
    widget.keyStatus.hasCoinalyzeKey,
  );
  late final _bybitKey = TextEditingController(text: _bybitMask);
  late final _bybitSecret = TextEditingController(text: _bybitSecretMask);
  late final _nansenKey = TextEditingController(text: _nansenMask);
  late final _coinalyzeKey = TextEditingController(text: _coinalyzeMask);
  bool _saving = false;
  String? _error;

  // Reuse the existing two source columns, help links and masked-key behavior.
  @override
  Widget build(BuildContext context) => ContentDialog(
    title: Text(loc.agentSettings),
    constraints: const BoxConstraints(maxWidth: 1040),
    content: SizedBox(
      width: 960,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Switch the language immediately and remember it for the next launch.
            InfoLabel(
              label: loc.language,
              child: ComboBox<String>(
                value: localeCodeNotifier.value,
                items: [
                  for (final language in appLanguages)
                    ComboBoxItem(
                      value: language.code,
                      child: Text(language.name),
                    ),
                ],
                onChanged: (code) {
                  if (code == null) return;
                  localeCodeNotifier.value = code;
                  unawaited(LlmSettingsStore().saveLocaleCode(code));
                },
              ),
            ),
            const SizedBox(height: 20),
            LlmConnectionEditor(
              key: _llm,
              initial: widget.llm,
              connections: widget.llmConnections,
              keys: widget.keyStatus,
              codexAuth: widget.codexAuth,
            ),
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
                          checked: _bybit,
                          content: const Text('Bybit MCP'),
                          onChanged: widget.nodeAvailable
                              ? (value) => setState(() => _bybit = value)
                              : null,
                        ),
                        if (_bybit) ...[
                          const SizedBox(height: 8),
                          DocumentationHelpLabel(
                            label: loc.bybitAccountApi,
                            tooltip: loc.bybitDocs,
                            documentationUrl:
                                AppConstants.bybitAccountDocumentationUrl,
                          ),
                          const SizedBox(height: 6),
                          _secret(
                            'Bybit API Key',
                            _bybitKey,
                            _bybitMask,
                            hint: loc.bybitHint,
                          ),
                          const SizedBox(height: 6),
                          _secret(
                            'Bybit API Secret',
                            _bybitSecret,
                            _bybitSecretMask,
                          ),
                        ],
                        const SizedBox(height: 8),
                        ToggleSwitch(
                          checked: _search,
                          content: const Text('OpenWebSearch MCP'),
                          onChanged: widget.nodeAvailable
                              ? (value) => setState(() => _search = value)
                              : null,
                        ),
                        const SizedBox(height: 8),
                        ToggleSwitch(
                          checked: _nansen,
                          content: DocumentationHelpLabel(
                            label: 'Nansen MCP',
                            tooltip: loc.nansenDocs,
                            documentationUrl:
                                AppConstants.nansenDocumentationUrl,
                          ),
                          onChanged: (value) => setState(() => _nansen = value),
                        ),
                        if (_nansen) ...[
                          const SizedBox(height: 6),
                          _secret('Nansen API Key', _nansenKey, _nansenMask),
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
                          checked: _coinalyze,
                          content: DocumentationHelpLabel(
                            label: 'Coinalyze',
                            tooltip: loc.coinalyzeDocs,
                            documentationUrl:
                                AppConstants.coinalyzeDocumentationUrl,
                          ),
                          onChanged: (value) =>
                              setState(() => _coinalyze = value),
                        ),
                        if (_coinalyze) ...[
                          const SizedBox(height: 6),
                          _secret(
                            'Coinalyze API Key',
                            _coinalyzeKey,
                            _coinalyzeMask,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
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
    ),
    actions: [
      Button(onPressed: () => Navigator.pop(context), child: Text(loc.cancel)),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: Text(_saving ? loc.saving : loc.save),
      ),
    ],
  );

  // Mask values are placeholders and must never replace saved credentials.
  Widget _secret(
    String label,
    TextEditingController controller,
    String? mask, {
    String? hint,
  }) => InfoLabel(
    label: label,
    child: TextBox(
      controller: controller,
      obscureText: true,
      placeholder: hint ?? loc.encryptedKeyPlaceholder,
      onTap: () {
        if (mask != null && controller.text == mask) {
          controller.selection = TextSelection(
            baseOffset: 0,
            extentOffset: controller.text.length,
          );
        }
      },
    ),
  );
  String? _newKey(TextEditingController controller, String? mask) {
    final value = controller.text.trim();
    return value.isEmpty || value == mask ? null : value;
  }

  // Keep the original storage API and only clear live controllers after saving.
  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final llm = _llm.currentState!.readSettings();
      await widget.onSave(
        llm.connections,
        McpSettings(
          useBybit: _bybit,
          useNansen: _nansen,
          useOpenWebSearch: _search,
        ),
        ApiSettings(useCoinalyze: _coinalyze),
        ApiKeyUpdates(
          llmKey: llm.apiKey,
          llmConnectionId: llm.connections.active.id,
          bybitApiKey: _newKey(_bybitKey, _bybitMask),
          bybitApiSecret: _newKey(_bybitSecret, _bybitSecretMask),
          nansenKey: _newKey(_nansenKey, _nansenMask),
          coinalyzeKey: _newKey(_coinalyzeKey, _coinalyzeMask),
        ),
      );
      if (!mounted) return;
      _llm.currentState?.clearSecret();
      _bybitKey.clear();
      _bybitSecret.clear();
      _nansenKey.clear();
      _coinalyzeKey.clear();
      Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _error = loc.secureStorageFailed(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _bybitKey.dispose();
    _bybitSecret.dispose();
    _nansenKey.dispose();
    _coinalyzeKey.dispose();
    super.dispose();
  }
}
