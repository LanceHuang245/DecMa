part of 'dashboard_controller.dart';

// Persist settings independently of chart and conversation lifecycle.
extension DashboardSettings on DashboardController {
  // Persist existing connection settings without changing credential storage.
  Future<void> _saveSettings(
    LlmConnectionSettings llmConnections,
    McpSettings mcp,
    ApiSettings api,
    ApiKeyUpdates apiKeys,
  ) async {
    await Future.wait([
      _llmSettingsStore.saveConnections(llmConnections),
      _llmSettingsStore.saveMcp(mcp),
      _llmSettingsStore.saveApi(api),
    ]);
    await _keyStore.update(apiKeys);
    final status = await _keyStore.status(
      llmConnectionIds: llmConnections.connections.map((item) => item.id),
    );
    if (_isDisposed) return;
    _llmConnections = llmConnections;
    _llm = llmConnections.active;
    _mcp = mcp;
    _api = api;
    _apiKeyStatus = status;
    _notify();
  }

  Future<void> _saveNewsSettings(
    NewsSettings settings,
    ApiKeyUpdates apiKeys,
  ) async {
    await Future.wait([
      _llmSettingsStore.saveNews(settings),
      _keyStore.update(apiKeys),
    ]);
    final status = await _keyStore.status(
      llmConnectionIds: _llmConnections.connections.map((item) => item.id),
    );
    if (_isDisposed) return;
    _news = settings;
    _apiKeyStatus = status;
    _notify();
    unawaited(_refreshNews());
    unawaited(_refreshTokenNews(_activeSymbol));
  }

  Future<void> _loadApiKeyStatus() async {
    final status = await _keyStore.status(
      llmConnectionIds: _llmConnections.connections.map((item) => item.id),
    );
    if (_isDisposed) return;
    _apiKeyStatus = status;
    _notify();
  }
}
