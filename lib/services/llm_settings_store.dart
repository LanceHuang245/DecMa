import 'package:shared_preferences/shared_preferences.dart';

import '../models/trading_models.dart';

class LlmSettingsStore {
  LlmSettingsStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const _providerKey = 'decma.llm.provider';
  static const _endpointKey = 'decma.llm.endpoint';
  static const _modelKey = 'decma.llm.model';
  static const _bybitMcpKey = 'decma.mcp.bybit';
  static const _coinGlassMcpKey = 'decma.mcp.coinglass';
  static const _nansenMcpKey = 'decma.mcp.nansen';
  static const _openWebSearchMcpKey = 'decma.mcp.open_web_search';
  final SharedPreferencesAsync _preferences;

  Future<LlmSettings?> read() async {
    final values = await Future.wait([
      _preferences.getString(_providerKey),
      _preferences.getString(_endpointKey),
      _preferences.getString(_modelKey),
    ]);
    final providerName = values[0];
    final endpoint = values[1];
    final model = values[2];
    final provider = LlmProvider.values.where(
      (item) => item.name == providerName,
    );
    if (provider.length != 1 || endpoint == null || model == null) return null;
    return LlmSettings(
      provider: provider.single,
      endpoint: endpoint,
      model: model,
    );
  }

  // Persist only non-secret connection settings; API keys stay in secure storage.
  Future<void> save(LlmSettings settings) async {
    await Future.wait([
      _preferences.setString(_providerKey, settings.provider.name),
      _preferences.setString(_endpointKey, settings.endpoint),
      _preferences.setString(_modelKey, settings.model),
    ]);
  }

  // Persist MCP toggles separately from secure API keys.
  Future<McpSettings> readMcp() async {
    final values = await Future.wait([
      _preferences.getBool(_bybitMcpKey),
      _preferences.getBool(_coinGlassMcpKey),
      _preferences.getBool(_nansenMcpKey),
      _preferences.getBool(_openWebSearchMcpKey),
    ]);
    return McpSettings(
      useBybit: values[0] ?? true,
      useCoinglass: values[1] ?? false,
      useNansen: values[2] ?? false,
      useOpenWebSearch: values[3] ?? true,
    );
  }

  Future<void> saveMcp(McpSettings settings) async {
    await Future.wait([
      _preferences.setBool(_bybitMcpKey, settings.useBybit),
      _preferences.setBool(_coinGlassMcpKey, settings.useCoinglass),
      _preferences.setBool(_nansenMcpKey, settings.useNansen),
      _preferences.setBool(_openWebSearchMcpKey, settings.useOpenWebSearch),
    ]);
  }
}
