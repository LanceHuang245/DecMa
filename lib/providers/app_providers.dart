import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../domain/models/app_settings.dart';
import '../data/services/agent_service.dart';
import '../data/services/bybit_service.dart';
import '../data/services/storage/llm_settings_store.dart';
import '../data/repositories/news_repository.dart';
import '../data/services/storage/secure_key_store.dart';
import '../ui/dashboard/dashboard_controller.dart';

part 'app_providers.g.dart';

/// Immutable bundle of values loaded once before the app starts.
class AppInitialSettings {
  const AppInitialSettings({
    required this.nodeAvailable,
    this.llmConnections,
    this.mcp,
    this.api,
    this.news,
    this.symbol,
  });

  final bool nodeAvailable;
  final LlmConnectionSettings? llmConnections;
  final McpSettings? mcp;
  final ApiSettings? api;
  final NewsSettings? news;
  final String? symbol;
}

/// Overridden at the app root with the startup-loaded values.
@Riverpod(keepAlive: true)
AppInitialSettings appInitialSettings(Ref ref) {
  throw UnimplementedError('overridden in main()');
}

@Riverpod(keepAlive: true)
BybitService bybitService(Ref ref) {
  final service = BybitService();
  ref.onDispose(service.dispose);
  return service;
}

@Riverpod(keepAlive: true)
AgentService agentService(Ref ref) {
  final service = AgentService(
    bybit: ref.watch(bybitServiceProvider),
    keyStore: ref.watch(secureKeyStoreProvider),
  );
  ref.onDispose(service.dispose);
  return service;
}

@Riverpod(keepAlive: true)
NewsRepository newsRepository(Ref ref) {
  final service = NewsRepository();
  ref.onDispose(service.dispose);
  return service;
}

@Riverpod(keepAlive: true)
SecureKeyStore secureKeyStore(Ref ref) => SecureKeyStore();

@Riverpod(keepAlive: true)
LlmSettingsStore llmSettingsStore(Ref ref) => LlmSettingsStore();

/// Owns the dashboard controller for the app lifetime and wires its services.
@riverpod
DashboardController dashboardController(Ref ref) {
  final initial = ref.watch(appInitialSettingsProvider);
  final controller = DashboardController(
    nodeAvailable: initial.nodeAvailable,
    bybit: ref.watch(bybitServiceProvider),
    agent: ref.watch(agentServiceProvider),
    newsRepository: ref.watch(newsRepositoryProvider),
    keyStore: ref.watch(secureKeyStoreProvider),
    settingsStore: ref.watch(llmSettingsStoreProvider),
    initialLlmConnections: initial.llmConnections,
    initialMcp: initial.mcp,
    initialApi: initial.api,
    initialNews: initial.news,
    initialSymbol: initial.symbol,
  );
  ref.onDispose(controller.dispose);
  return controller;
}
