import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/trading_models.dart';
import '../services/agent_service.dart';
import '../services/bybit_service.dart';
import '../services/llm_settings_store.dart';
import '../services/news/news_service.dart';
import '../services/secure_key_store.dart';
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
BybitService bybitService(Ref ref) => BybitService();

@Riverpod(keepAlive: true)
AgentService agentService(Ref ref) => AgentService();

@Riverpod(keepAlive: true)
NewsService newsService(Ref ref) => NewsService();

@Riverpod(keepAlive: true)
SecureKeyStore secureKeyStore(Ref ref) => SecureKeyStore();

@Riverpod(keepAlive: true)
LlmSettingsStore llmSettingsStore(Ref ref) => LlmSettingsStore();

/// Owns the dashboard controller for the app lifetime and wires its services.
@Riverpod(keepAlive: true)
DashboardController dashboardController(Ref ref) {
  final initial = ref.watch(appInitialSettingsProvider);
  final controller = DashboardController(
    nodeAvailable: initial.nodeAvailable,
    bybit: ref.watch(bybitServiceProvider),
    agent: ref.watch(agentServiceProvider),
    newsService: ref.watch(newsServiceProvider),
    keyStore: ref.watch(secureKeyStoreProvider),
    llmSettingsStore: ref.watch(llmSettingsStoreProvider),
    initialLlmConnections: initial.llmConnections,
    initialMcp: initial.mcp,
    initialApi: initial.api,
    initialNews: initial.news,
    initialSymbol: initial.symbol,
  );
  ref.onDispose(controller.dispose);
  return controller;
}
