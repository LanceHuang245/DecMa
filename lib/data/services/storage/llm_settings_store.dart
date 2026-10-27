import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../domain/models/app_settings.dart';
import 'storage_keys.dart';

class LlmSettingsStore {
  LlmSettingsStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  Future<String?> readLastViewedSymbol() =>
      _preferences.getString(StorageKeys.lastViewedSymbol);

  Future<void> saveLastViewedSymbol(String symbol) => _preferences.setString(
    StorageKeys.lastViewedSymbol,
    symbol.toUpperCase(),
  );

  Future<String?> readLocaleCode() =>
      _preferences.getString(StorageKeys.localeCode);

  Future<void> saveLocaleCode(String code) =>
      _preferences.setString(StorageKeys.localeCode, code);

  Future<String?> readThemeMode() =>
      _preferences.getString(StorageKeys.themeMode);

  Future<void> saveThemeMode(String mode) =>
      _preferences.setString(StorageKeys.themeMode, mode);

  Future<LlmConnectionSettings> readConnections() async {
    final saved = await _preferences.getString(StorageKeys.llmConnections);
    if (saved != null) {
      return LlmConnectionSettings(
        connections: (jsonDecode(saved) as List)
            .cast<Map<String, dynamic>>()
            .map(LlmSettings.fromJson)
            .toList(),
        activeConnectionId: (await _preferences.getString(
          StorageKeys.activeLlmConnection,
        ))!,
      );
    }

    final connection = LlmSettings(
      provider: LlmProvider.openAiResponses,
      endpoint: LlmProvider.openAiResponses.defaultEndpoint,
      model: 'gpt-4.1',
    );
    return LlmConnectionSettings(
      connections: [connection],
      activeConnectionId: connection.id,
    );
  }

  // Persist only non-secret connection metadata; API keys stay in secure storage.
  Future<void> saveConnections(LlmConnectionSettings settings) async {
    await Future.wait([
      _preferences.setString(
        StorageKeys.llmConnections,
        jsonEncode(settings.connections.map((item) => item.toJson()).toList()),
      ),
      _preferences.setString(
        StorageKeys.activeLlmConnection,
        settings.active.id,
      ),
    ]);
  }

  // Persist MCP toggles separately from secure API keys.
  Future<McpSettings> readMcp() async {
    final values = await Future.wait([
      _preferences.getBool(StorageKeys.bybitMcp),
      _preferences.getBool(StorageKeys.nansenMcp),
      _preferences.getBool(StorageKeys.openWebSearchMcp),
    ]);
    return McpSettings(
      useBybit: values[0] ?? true,
      useNansen: values[1] ?? false,
      useOpenWebSearch: values[2] ?? true,
    );
  }

  Future<void> saveMcp(McpSettings settings) async {
    await Future.wait([
      _preferences.setBool(StorageKeys.bybitMcp, settings.useBybit),
      _preferences.setBool(StorageKeys.nansenMcp, settings.useNansen),
      _preferences.setBool(
        StorageKeys.openWebSearchMcp,
        settings.useOpenWebSearch,
      ),
    ]);
  }

  Future<ApiSettings> readApi() async => ApiSettings(
    useCoinalyze: await _preferences.getBool(StorageKeys.coinalyzeApi) ?? false,
  );

  Future<void> saveApi(ApiSettings settings) =>
      _preferences.setBool(StorageKeys.coinalyzeApi, settings.useCoinalyze);

  Future<NewsSettings> readNews() async {
    final values = await Future.wait([
      _preferences.getBool(StorageKeys.finnhubNews),
      _preferences.getBool(StorageKeys.marketauxNews),
      _preferences.getBool(StorageKeys.blsNews),
      _preferences.getBool(StorageKeys.beaNews),
      _preferences.getBool(StorageKeys.federalReserveNews),
      _preferences.getBool(StorageKeys.whiteHouseNews),
      _preferences.getBool(StorageKeys.secNews),
      _preferences.getBool(StorageKeys.bbcNews),
    ]);
    return NewsSettings(
      useFinnhub: values[0] ?? false,
      useMarketaux: values[1] ?? false,
      useBls: values[2] ?? true,
      useBea: values[3] ?? true,
      useFederalReserve: values[4] ?? true,
      useWhiteHouse: values[5] ?? true,
      useSec: values[6] ?? true,
      useBbc: values[7] ?? false,
    );
  }

  Future<void> saveNews(NewsSettings settings) async {
    await Future.wait([
      _preferences.setBool(StorageKeys.finnhubNews, settings.useFinnhub),
      _preferences.setBool(StorageKeys.marketauxNews, settings.useMarketaux),
      _preferences.setBool(StorageKeys.blsNews, settings.useBls),
      _preferences.setBool(StorageKeys.beaNews, settings.useBea),
      _preferences.setBool(
        StorageKeys.federalReserveNews,
        settings.useFederalReserve,
      ),
      _preferences.setBool(StorageKeys.whiteHouseNews, settings.useWhiteHouse),
      _preferences.setBool(StorageKeys.secNews, settings.useSec),
      _preferences.setBool(StorageKeys.bbcNews, settings.useBbc),
    ]);
  }
}
