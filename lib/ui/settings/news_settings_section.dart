import 'package:fluent_ui/fluent_ui.dart';

import '../../app_constants.dart';
import '../../domain/models/app_settings.dart';
import '../../data/services/storage/secure_key_store.dart';
import 'package:decma/utils/display_formatters.dart';
import '../core/documentation_help_label.dart';
import 'settings_rows.dart';
import '../../l10n/generated/app_localizations.dart';

// Edit news sources and keys in place; saving keeps the section open.
class NewsSettingsSection extends StatefulWidget {
  const NewsSettingsSection({
    super.key,
    required this.settings,
    required this.keyStatus,
    required this.onSave,
  });

  final NewsSettings settings;
  final ApiKeyStatus keyStatus;
  final Future<void> Function(NewsSettings settings, ApiKeyUpdates keys) onSave;

  @override
  State<NewsSettingsSection> createState() => _NewsSettingsSectionState();
}

class _NewsSettingsSectionState extends State<NewsSettingsSection> {
  AppLocalizations get loc => AppLocalizations.of(context);
  late bool _useFinnhub;
  late bool _useMarketaux;
  late bool _useBls;
  late bool _useBea;
  late bool _useFederalReserve;
  late bool _useWhiteHouse;
  late bool _useSec;
  late bool _useBbc;
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
    _useWhiteHouse = widget.settings.useWhiteHouse;
    _useSec = widget.settings.useSec;
    _useBbc = widget.settings.useBbc;
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

  // Windows 11 settings layout: grouped rows, name and description left, switch right.
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SettingsGroup(
        title: loc.newsApis,
        rows: [
          SettingsToggleRow(
            title: DocumentationHelpLabel(
              label: 'Finnhub',
              tooltip: loc.finnhubDocs,
              documentationUrl: AppConstants.finnhubDocumentationUrl,
            ),
            description: loc.finnhubDescription,
            value: _useFinnhub,
            onChanged: (value) => setState(() => _useFinnhub = value),
            details: _keyField('Finnhub API Key', _finnhubKey, _finnhubMask),
          ),
          SettingsToggleRow(
            title: DocumentationHelpLabel(
              label: 'Marketaux',
              tooltip: loc.marketauxDocs,
              documentationUrl: AppConstants.marketauxDocumentationUrl,
            ),
            description: loc.marketauxDescription,
            value: _useMarketaux,
            onChanged: (value) => setState(() => _useMarketaux = value),
            details: _keyField(
              'Marketaux API Key',
              _marketauxKey,
              _marketauxMask,
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      SettingsGroup(
        title: loc.officialSources,
        rows: [
          SettingsToggleRow(
            title: const Text('BLS'),
            description: 'U.S. Bureau of Labor Statistics',
            value: _useBls,
            onChanged: (value) => setState(() => _useBls = value),
          ),
          SettingsToggleRow(
            title: const Text('BEA'),
            description: 'U.S. Bureau of Economic Analysis',
            value: _useBea,
            onChanged: (value) => setState(() => _useBea = value),
          ),
          SettingsToggleRow(
            title: const Text('Federal Reserve'),
            description: 'Board of Governors of the Federal Reserve System',
            value: _useFederalReserve,
            onChanged: (value) => setState(() => _useFederalReserve = value),
          ),
          SettingsToggleRow(
            title: const Text('White House'),
            description: 'Presidential Actions',
            value: _useWhiteHouse,
            onChanged: (value) => setState(() => _useWhiteHouse = value),
          ),
          SettingsToggleRow(
            title: const Text('SEC'),
            description: 'U.S. Securities and Exchange Commission',
            value: _useSec,
            onChanged: (value) => setState(() => _useSec = value),
          ),
        ],
      ),
      const SizedBox(height: 16),
      SettingsGroup(
        title: loc.newsOutlets,
        rows: [
          SettingsToggleRow(
            title: const Text('BBC'),
            description: loc.bbcDescription,
            value: _useBbc,
            onChanged: (value) => setState(() => _useBbc = value),
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

  Widget _keyField(
    String label,
    TextEditingController controller,
    String? mask,
  ) => InfoLabel(
    label: label,
    child: TextBox(
      controller: controller,
      obscureText: true,
      placeholder: loc.encryptedKeyPlaceholder,
      onTap: () => _selectMask(controller, mask),
    ),
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
          useWhiteHouse: _useWhiteHouse,
          useSec: _useSec,
          useBbc: _useBbc,
        ),
        ApiKeyUpdates(
          finnhubKey: key.isEmpty || key == _finnhubMask ? null : key,
          marketauxKey: _savedKey(_marketauxKey, _marketauxMask),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = loc.secureStorageFailed(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _savedKey(TextEditingController controller, String? mask) {
    final value = controller.text.trim();
    return value.isEmpty || value == mask ? null : value;
  }
}
