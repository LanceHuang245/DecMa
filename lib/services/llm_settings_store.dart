import 'package:shared_preferences/shared_preferences.dart';

import '../models/trading_models.dart';

class LlmSettingsStore {
  LlmSettingsStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const _providerKey = 'decma.llm.provider';
  static const _endpointKey = 'decma.llm.endpoint';
  static const _modelKey = 'decma.llm.model';
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
}
