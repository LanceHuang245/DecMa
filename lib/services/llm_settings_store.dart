import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/trading_models.dart';

class LlmSettingsStore {
  LlmSettingsStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const _connectionsKey = 'decma.llm.connections';
  static const _activeConnectionKey = 'decma.llm.active_connection';
  static const _lastViewedSymbolKey = 'decma.dashboard.last_viewed_symbol';
  static const _legacyProviderKey = 'decma.llm.provider';
  static const _legacyEndpointKey = 'decma.llm.endpoint';
  static const _legacyModelKey = 'decma.llm.model';
  static const _bybitMcpKey = 'decma.mcp.bybit';
  static const _nansenMcpKey = 'decma.mcp.nansen';
  static const _openWebSearchMcpKey = 'decma.mcp.open_web_search';
  static const _coinalyzeApiKey = 'decma.api.coinalyze';
  static const _finnhubNewsKey = 'decma.news.finnhub';
  static const _marketauxNewsKey = 'decma.news.marketaux';
  static const _blsNewsKey = 'decma.news.bls';
  static const _beaNewsKey = 'decma.news.bea';
  static const _federalReserveNewsKey = 'decma.news.federal_reserve';
  final SharedPreferencesAsync _preferences;

  Future<String?> readLastViewedSymbol() =>
      _preferences.getString(_lastViewedSymbolKey);

  Future<void> saveLastViewedSymbol(String symbol) =>
      _preferences.setString(_lastViewedSymbolKey, symbol.toUpperCase());

  Future<LlmConnectionSettings> readConnections() async {
    final saved = await _preferences.getString(_connectionsKey);
    if (saved != null) {
      try {
        final decoded = jsonDecode(saved);
        if (decoded is List) {
          final connections = decoded
              .map(LlmSettings.fromJson)
              .whereType<LlmSettings>()
              .toList();
          final activeId = await _preferences.getString(_activeConnectionKey);
          if (connections.isNotEmpty) {
            return LlmConnectionSettings(
              connections: connections,
              activeConnectionId:
                  connections.any((connection) => connection.id == activeId)
                  ? activeId!
                  : connections.first.id,
            );
          }
        }
      } catch (_) {
        // Fall back to the legacy single-connection settings below.
      }
    }

    final values = await Future.wait([
      _preferences.getString(_legacyProviderKey),
      _preferences.getString(_legacyEndpointKey),
      _preferences.getString(_legacyModelKey),
    ]);
    final providerName = values[0];
    final endpoint = values[1];
    final model = values[2];
    final provider = LlmProvider.values.where(
      (item) => item.name == providerName,
    );
    final connection = LlmSettings(
      id: LlmSettings.defaultId,
      name: LlmSettings.defaultName,
      provider: provider.length == 1
          ? provider.single
          : LlmProvider.openAiResponses,
      endpoint: endpoint ?? LlmProvider.openAiResponses.defaultEndpoint,
      model: model ?? 'gpt-4.1',
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
        _connectionsKey,
        jsonEncode(settings.connections.map((item) => item.toJson()).toList()),
      ),
      _preferences.setString(_activeConnectionKey, settings.active.id),
    ]);
  }

  // Persist MCP toggles separately from secure API keys.
  Future<McpSettings> readMcp() async {
    final values = await Future.wait([
      _preferences.getBool(_bybitMcpKey),
      _preferences.getBool(_nansenMcpKey),
      _preferences.getBool(_openWebSearchMcpKey),
    ]);
    return McpSettings(
      useBybit: values[0] ?? true,
      useNansen: values[1] ?? false,
      useOpenWebSearch: values[2] ?? true,
    );
  }

  Future<void> saveMcp(McpSettings settings) async {
    await Future.wait([
      _preferences.setBool(_bybitMcpKey, settings.useBybit),
      _preferences.setBool(_nansenMcpKey, settings.useNansen),
      _preferences.setBool(_openWebSearchMcpKey, settings.useOpenWebSearch),
    ]);
  }

  Future<ApiSettings> readApi() async => ApiSettings(
    useCoinalyze: await _preferences.getBool(_coinalyzeApiKey) ?? false,
  );

  Future<void> saveApi(ApiSettings settings) =>
      _preferences.setBool(_coinalyzeApiKey, settings.useCoinalyze);

  Future<NewsSettings> readNews() async {
    final values = await Future.wait([
      _preferences.getBool(_finnhubNewsKey),
      _preferences.getBool(_marketauxNewsKey),
      _preferences.getBool(_blsNewsKey),
      _preferences.getBool(_beaNewsKey),
      _preferences.getBool(_federalReserveNewsKey),
    ]);
    return NewsSettings(
      useFinnhub: values[0] ?? false,
      useMarketaux: values[1] ?? false,
      useBls: values[2] ?? true,
      useBea: values[3] ?? true,
      useFederalReserve: values[4] ?? true,
    );
  }

  Future<void> saveNews(NewsSettings settings) => Future.wait([
    _preferences.setBool(_finnhubNewsKey, settings.useFinnhub),
    _preferences.setBool(_marketauxNewsKey, settings.useMarketaux),
    _preferences.setBool(_blsNewsKey, settings.useBls),
    _preferences.setBool(_beaNewsKey, settings.useBea),
    _preferences.setBool(_federalReserveNewsKey, settings.useFederalReserve),
  ]).then((_) {});
}
