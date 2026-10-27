import 'package:fluent_ui/fluent_ui.dart';

import '../../app_constants.dart';
import '../../domain/models/app_settings.dart';
import '../../data/services/openai_codex_oauth.dart';
import '../../data/services/storage/secure_key_store.dart';
import '../../utils/display_formatters.dart';
import '../core/documentation_help_label.dart';
import 'llm_connection_editor.dart';
import 'settings_rows.dart';
import '../../l10n/generated/app_localizations.dart';

// Coordinate one save while each editor owns its own draft/request state.
class AgentSettingsSection extends StatefulWidget {
  const AgentSettingsSection({
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
  State<AgentSettingsSection> createState() => _AgentSettingsSectionState();
}

class _AgentSettingsSectionState extends State<AgentSettingsSection> {
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

  // Same grouped-row layout as the news settings.
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      LlmConnectionEditor(
        key: _llm,
        initial: widget.llm,
        connections: widget.llmConnections,
        keys: widget.keyStatus,
        codexAuth: widget.codexAuth,
      ),
      const SizedBox(height: 20),
      SettingsGroup(
        title: 'MCP',
        rows: [
          SettingsToggleRow(
            title: DocumentationHelpLabel(
              label: 'Bybit MCP',
              tooltip: loc.bybitDocs,
              documentationUrl: AppConstants.bybitAccountDocumentationUrl,
            ),
            description: loc.bybitMcpDescription,
            value: _bybit,
            onChanged: widget.nodeAvailable
                ? (value) => setState(() => _bybit = value)
                : null,
            details: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _secret(
                  'Bybit API Key (Optional)',
                  _bybitKey,
                  _bybitMask,
                  hint: loc.bybitHint,
                ),
                const SizedBox(height: 6),
                _secret(
                  'Bybit API Secret (Optional)',
                  _bybitSecret,
                  _bybitSecretMask,
                ),
              ],
            ),
          ),
          SettingsToggleRow(
            title: const Text('OpenWebSearch MCP'),
            description: loc.openWebSearchDescription,
            value: _search,
            onChanged: widget.nodeAvailable
                ? (value) => setState(() => _search = value)
                : null,
          ),
          SettingsToggleRow(
            title: DocumentationHelpLabel(
              label: 'Nansen MCP',
              tooltip: loc.nansenDocs,
              documentationUrl: AppConstants.nansenDocumentationUrl,
            ),
            description: loc.nansenDescription,
            value: _nansen,
            onChanged: (value) => setState(() => _nansen = value),
            details: _secret('Nansen API Key', _nansenKey, _nansenMask),
          ),
        ],
      ),
      const SizedBox(height: 16),
      SettingsGroup(
        title: 'API',
        rows: [
          SettingsToggleRow(
            title: DocumentationHelpLabel(
              label: 'Coinalyze',
              tooltip: loc.coinalyzeDocs,
              documentationUrl: AppConstants.coinalyzeDocumentationUrl,
            ),
            description: loc.coinalyzeDescription,
            value: _coinalyze,
            onChanged: (value) => setState(() => _coinalyze = value),
            details: _secret(
              'Coinalyze API Key',
              _coinalyzeKey,
              _coinalyzeMask,
            ),
          ),
        ],
      ),
      if (_error != null) ...[
        const SizedBox(height: 10),
        Text(_error!, style: const TextStyle(color: Colors.errorPrimaryColor)),
      ],
      const SizedBox(height: 12),
      Align(
        alignment: AlignmentDirectional.centerEnd,
        child: FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? loc.saving : loc.save),
        ),
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

  // Typed secrets stay in their fields after saving, matching what is stored.
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
